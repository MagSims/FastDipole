function spin_matrices_of_dim(; N::Int)
    if N == 0
        return fill(Hermitian(zeros(ComplexF64,0,0)), 3)
    end

    S = (N-1)/2 + 0im
    j = 1:N-1
    off = @. sqrt(2(S+1)*j - j*(j+1)) / 2 + 0im

    Sx = Hermitian(diagm(1 => off, -1 => off))
    Sy = Hermitian(diagm(1 => -im*off, -1 => +im*off))
    Sz = Hermitian(diagm(S .- (0:N-1)))
    return SVector(Sx, Sy, Sz)
end


"""
    spin_matrices(S)

Returns a triple of ``N×N``` spin matrices, where ``N = 2S+1``. These are the
generators of SU(2) in the spin-`S` representation.

If `S == Inf`, then the return values are abstract symbols denoting
infinite-dimensional matrices that commute. These can be useful for repeating
historical studies, or modeling micromagnetic systems. A technical discussion
appears in the Sunny documentation page: [Interaction Strength
Renormalization](@ref).

# Example
```julia
S = spin_matrices(3/2)
@assert S'*S ≈ (3/2)*(3/2+1)*I
@assert S[1]*S[2] - S[2]*S[1] ≈ im*S[3]

S = spin_matrices(Inf)
@assert S[1]*S[2] - S[2]*S[1] == 0
```

See also [`print_stevens_expansion`](@ref).
"""
function spin_matrices(S)
    S == Inf && return spin_vector_symbol
    isinteger(2S+1) || error("Spin `S` must be half-integer.")
    spin_matrices_of_dim(; N=Int(2S+1))
end

# The Stevens quadrupoles, O[2, q=2...-2]
function quadrupoles(S::T) where T
    𝒮ˣ, 𝒮ʸ, 𝒮ᶻ = S
    return SVector{5, T}(
        𝒮ˣ^2 - 𝒮ʸ^2,
        𝒮ᶻ*𝒮ˣ,
        -𝒮ˣ^2 - 𝒮ʸ^2 + 2*𝒮ᶻ^2,
        𝒮ᶻ*𝒮ʸ,
        2*𝒮ʸ*𝒮ˣ,
    )
end

# Gradient of Stevens quadrupoles with respect to spin components
function grad_quadrupoles(S::Vec3)
    𝒮ˣ, 𝒮ʸ, 𝒮ᶻ = S
    return SVector{5, Vec3}(
        Vec3(2𝒮ˣ, -2𝒮ʸ, 0),    # ∇ (𝒮ˣ^2 - 𝒮ʸ^2)
        Vec3(𝒮ᶻ, 0, 𝒮ˣ),       # ∇ (𝒮ᶻ*𝒮ˣ)
        Vec3(-2𝒮ˣ, -2𝒮ʸ, 2𝒮ᶻ), # ∇ (-𝒮ˣ^2 - 𝒮ʸ^2 + 2*𝒮ᶻ^2)
        Vec3(0, 𝒮ᶻ, 𝒮ʸ),       # ∇ (𝒮ᶻ*𝒮ʸ)
        Vec3(2𝒮ʸ, 2𝒮ˣ, 0),     # ∇ (2*𝒮ʸ*𝒮ˣ)
    )
end

# Returns ⟨Z|Sᵅ|Z⟩
@generated function expected_spin(Z::CVec{N}) where N
    S = spin_matrices_of_dim(; N)
    elems_x = SVector{N-1}(diag(S[1], 1))
    elems_z = SVector{N}(diag(S[3], 0))
    lo_ind = SVector{N-1}(1:N-1)
    hi_ind = SVector{N-1}(2:N)

    return quote
        $(Expr(:meta, :inline))
        c = Z[$lo_ind]' * ($elems_x .* Z[$hi_ind])
        nx = 2real(c)
        ny = 2imag(c)
        nz = real(Z' * ($elems_z .* Z))
        Vec3(nx, ny, nz)
    end
end

# Returns ⟨Z|Qᵅ|Z⟩ where Q = O[2, q=2...-2] are Stevens quadrupoles
function expected_quadrupole(Z::CVec{N}) where N
    return Vec5(real(Z'*Q*Z) for Q in stevens_matrices_of_dim(2; N))
end


# Find a ket (up to an irrelevant phase) that corresponds to a pure dipole.
# TODO, we can do this faster by using the exponential map of spin operators,
# expressed as a polynomial expansion,
# http://www.emis.de/journals/SIGMA/2014/084/
ket_from_dipole(_::Vec3, ::Val{0}) :: CVec{0} = zero(CVec{0})
function ket_from_dipole(dip::Vec3, ::Val{N}) :: CVec{N} where N
    S = spin_matrices_of_dim(; N)
    λs, vs = eigen(dip' * S)
    return CVec{N}(vs[:, argmax(real.(λs))])
end

# Applies the time-reversal operator to the coherent spin state |Z⟩, which
# effectively negates the expected spin dipole, ⟨Z|Sᵅ|Z⟩ → -⟨Z|Sᵅ|Z⟩.
flip_ket(_::CVec{0}) = CVec{0}()
function flip_ket(Z::CVec{N}) where N
    # Per Sakurai (3rd ed.), eq. 4.176, the time reversal operator has the
    # action T[Z] = exp(-i π Sʸ) conj(Z). In our selected basis, the operator
    # exp(-i π Sʸ) can be implemented by flipping the sign of half the
    # components and then reversing their order.
    parity = SVector{N}(1-2mod(i,2) for i=0:N-1)
    return reverse(parity .* conj(Z))
end


# Returns (Λ + dE/d⟨S⟩ ⋅ S) Z
@generated function mul_spin_matrices(Λ, dE_dS::Vec3, Z::CVec{N}) where N
    S = spin_matrices_of_dim(; N)
    out = map(1:N) do i
        out_i = map(1:N) do j
            terms = Any[:(Λ[$i,$j])]
            for α = 1:3
                S_αij = S[α][i,j]
                if !iszero(S_αij)
                    push!(terms, :(dE_dS[$α] * $S_αij))
                end
            end
            :(+($(terms...)) * Z[$j])
        end
        :(+($(out_i...)))
    end
    return :(CVec{$N}($(out...)))
end

# Returns (dE/d⟨Q⟩ ⋅ Q) Z, where Q = O[2, q=2...-2] are Stevens quadrupoles
function mul_quadrupole_matrices(dE_dQ::Vec5, Z::CVec{N}) where N
    Q = stevens_matrices_of_dim(2; N)
    acc = zero(CVec{N})
    for i in 1:5
        acc += dE_dQ[i] * (Q[i] * Z)
    end
    return acc
end
