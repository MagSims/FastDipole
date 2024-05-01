
function Ewald(sys::System{N}) where N
    (; crystal, latsize, units) = sys

    A = precompute_dipole_ewald(crystal, latsize, units.μ0)

    na = natoms(crystal)
    μ = zeros(Vec3, latsize..., na)
    ϕ = zeros(Vec3, latsize..., na)

    Ar = reshape(reinterpret(Float64, A), 3, 3, size(A)...) # dims: [α,β,cell,i,j]
    FA = FFTW.rfft(Ar, 3:5) # FFT on cell indices
    sz_rft = size(FA)[3:5]  # First FT dimension (dimension 3) will be ~ halved
    Fμ = zeros(ComplexF64, 3, sz_rft..., na)
    Fϕ = zeros(ComplexF64, 3, sz_rft..., na)

    mock_spins = zeros(3, latsize..., na)
    plan     = FFTW.plan_rfft(mock_spins, 2:4; flags=FFTW.MEASURE)
    ift_plan = FFTW.plan_irfft(Fμ, latsize[1], 2:4; flags=FFTW.MEASURE)

    return Ewald(A, μ, ϕ, FA, Fμ, Fϕ, plan, ift_plan)
end

# Ideally, this would clone all mutable state within Ewald. Note that `A`, `FA`
# are immutable data. A blocker is that FFTW plans cannot currently be copied,
# and it is not 100% clear whether they can be treated as immutable. For
# example, they cache inverse plans, which may possibly lead to data races in a
# multithreaded context. See discussion at
# https://github.com/JuliaMath/FFTW.jl/issues/261.
function clone_ewald(ewald::Ewald)
    error("Not supported")
    (; A, μ, ϕ, FA, Fμ, Fϕ, plan, ift_plan) = ewald
    return Ewald(A, copy(μ), copy(ϕ), FA, copy(Fμ), copy(Fϕ), copy(plan), copy(ift_plan))
end

# Tensor product of 3-vectors
(⊗)(a::Vec3,b::Vec3) = reshape(kron(a,b), 3, 3)


function precompute_dipole_ewald(cryst::Crystal, latsize::NTuple{3,Int}, μ0)
    precompute_dipole_ewald_aux(cryst, latsize, μ0, Vec3(0,0,0), cos, Val{Float64}())
end

# Precompute the pairwise interaction matrix A beween magnetic moments μ. For
# q_reshaped = 0, this yields the usual Ewald energy, E = μᵢ Aᵢⱼ μⱼ / 2. Nonzero
# q_reshaped is useful in spin wave theory. Physically, this amounts to a
# modification of the periodic boundary conditions, such that μ(q) can be
# incommensurate with the magnetic cell. In all cases, the energy is E = μᵢ(-q)
# Aᵢⱼ(-q) μⱼ(q) / 2 in Fourier space, where q should be interpreted as a Fourier
# transform of the cell offset.
#
# As an optimization, this function returns real values when q_reshaped is zero.
# Effectively, one can replace `exp(i (q+k)⋅r) → cos(k⋅r)` because the imaginary
# part cancels in the symmetric sum over ±k. Specifically, replace `cis(x) ≡
# exp(i x) = cos(x) + i sin(x)` with just `cos(x)` for efficiency. The parameter
# `T ∈ {Float64, ComplexF64}` controls the return type in a type-stable way. 
function precompute_dipole_ewald_aux(cryst::Crystal, latsize::NTuple{3,Int}, μ0, q_reshaped, cis, ::Val{T}) where T
    na = natoms(cryst)
    A = zeros(SMatrix{3, 3, T, 9}, latsize..., na, na)

    # Superlattice vectors and reciprocals for the full system volume
    sys_size = diagm(Vec3(latsize))
    latvecs = cryst.latvecs * sys_size
    recipvecs = sys_size \ cryst.recipvecs

    # Precalculate constants
    I₃ = Mat3(I)
    V = det(latvecs)
    L = cbrt(V)
    # Roughly balances the real and Fourier space costs. Note that σ = 1/(√2 λ)
    σ = L/3
    σ² = σ*σ
    σ³ = σ^3
    # Corresponding to c0=6 in Ewalder.jl. Should give ~13 digits of accuracy.
    rmax = 6√2 * σ
    kmax = 6√2 / σ

    nmax = map(eachcol(latvecs), eachcol(recipvecs)) do a, b
        round(Int, rmax / (a⋅normalize(b)) + 1e-6) + 1
    end
    mmax = map(eachcol(latvecs), eachcol(recipvecs)) do a, b
        round(Int, kmax / (b⋅normalize(a)) + 1e-6)
    end

    # nmax and mmax should be balanced here
    # println("nmax $nmax mmax $mmax")

    for cell in CartesianIndices(latsize), j in 1:na, i in 1:na
        acc = zero(eltype(A))
        cell_offset = Vec3(cell[1]-1, cell[2]-1, cell[3]-1)
        Δr = cryst.latvecs * (cell_offset + cryst.positions[j] - cryst.positions[i])

        #####################################################
        ## Real space part
        for n1 = -nmax[1]:nmax[1], n2 = -nmax[2]:nmax[2], n3 = -nmax[3]:nmax[3]
            n = Vec3(n1, n2, n3)
            rvec = Δr + latvecs * n
            r² = rvec⋅rvec
            if 0 < r² <= rmax*rmax
                r = √r²
                r³ = r²*r
                rhat = rvec/r
                erfc0 = erfc(r/(√2*σ))
                gauss0 = √(2/π) * (r/σ) * exp(-r²/2σ²)    
                phase = cis(2π * dot(q_reshaped, n))
                acc += phase * (μ0/4π) * ((I₃/r³) * (erfc0 + gauss0) - (3(rhat⊗rhat)/r³) * (erfc0 + (1+r²/3σ²) * gauss0))
            end
        end

        #####################################################
        ## Fourier space part
        for m1 = -mmax[1]:mmax[1], m2 = -mmax[2]:mmax[2], m3 = -mmax[3]:mmax[3]
            m = Vec3(m1, m2, m3)
            k = recipvecs * (m + q_reshaped - round.(q_reshaped))
            k² = k⋅k
            if 0 < k² <= kmax*kmax
                phase = cis(-k⋅Δr)
                acc += phase * (μ0/V) * (exp(-σ²*k²/2) / k²) * (k⊗k)
            end
        end

        #####################################################
        ## Remove self energies
        if iszero(Δr)
            acc += - μ0*I₃/(3(2π)^(3/2)*σ³)
        end

        # For sites site1=(cell1, i) and site2=(cell2, j) offset by an amount
        # (off = cell2-cell1), the pair-energy is (s1 ⋅ A[off, i, j] ⋅ s2).
        # Julia arrays start at one, so we index A using (cell = off .+ 1).
        A[cell, i, j] = acc
    end

    #=
    for j in 1:na, i in 1:na
        X = (A[1,1,1, i,j] + A[1,1,1, j,i]')/2
        A[1,1,1, i,j] = X
        A[1,1,1, j,i] = X'
    end
    =#
    
    return A
end


function ewald_energy(sys::System{N}) where N
    (; μ, FA, Fμ, plan) = sys.ewald
    latsize = size(sys.dipoles)[1:3]
    even_rft_size = latsize[1] % 2 == 0

    for site in eachsite(sys)
        μ[site] = magnetic_moment(sys, site)
    end

    E = 0.0
    mul!(Fμ, plan, reinterpret(reshape, Float64, μ))

    # rfft() is missing half the elements of the first Fourier transformed
    # dimension (here, dimension 2). Account for these missing values by scaling
    # the output by 2.
    if even_rft_size
        @views Fμ[:, 2:end-1, :, :, :] .*= √2
    else
        @views Fμ[:, 2:end, :, :, :] .*= √2
    end

    # In real space, E = μ (A ⋆ μ) / 2. In Fourier space, the convolution
    # becomes an ordinary product using Parseval's theorem.
    (_, m1, m2, m3, na) = size(Fμ)
    ms = CartesianIndices((m1, m2, m3))
    @inbounds for j in 1:na, i in 1:na, m in ms, α in 1:3, β in 1:3
        E += (1/2) * real(conj(Fμ[α, m, i]) * conj(FA[α, β, m, i, j]) * Fμ[β, m, j])
    end
    return E / prod(latsize)
end

# Use FFT to accumulate the entire field dE/ds for long-range dipole-dipole
# interactions
function accum_ewald_grad!(∇E, dipoles, sys::System{N}) where N
    (; ewald, units, gs) = sys
    (; μ, FA, Fμ, Fϕ, ϕ, plan, ift_plan) = ewald

    # Fourier transformed magnetic moments
    for site in eachsite(sys)
        μ[site] = units.μB * gs[site] * dipoles[site]
    end
    mul!(Fμ, plan, reinterpret(reshape, Float64, μ))

    # Calculate magneto-potential ϕ in Fourier space. Without @inbounds,
    # performance degrades by ~50%
    fill!(Fϕ, 0.0)
    (_, m1, m2, m3, na) = size(Fμ)
    ms = CartesianIndices((m1, m2, m3))
    @inbounds for j in 1:na, i in 1:na, m in ms, α in 1:3, β in 1:3
        Fϕ[α,m,i] += conj(FA[α,β,m,i,j]) * Fμ[β,m,j]
    end

    # Inverse Fourier transform to get ϕ in real space
    ϕr = reinterpret(reshape, Float64, ϕ)
    mul!(ϕr, ift_plan, Fϕ)
    
    for site in eachsite(sys)
        ∇E[site] += units.μB * (gs[site]' * ϕ[site])
    end
end

# Calculate the field dE/ds at site1 generated by a dipole at site2.
function ewald_pairwise_grad_at(sys::System{N}, site1, site2) where N
    (; gs, ewald, units) = sys
    latsize = size(ewald.ϕ)[1:3]
    cell_offset = mod.(Tuple(to_cell(site2)-to_cell(site1)), latsize)
    cell = CartesianIndex(cell_offset .+ (1,1,1))

    # The factor of 1/2 in the energy formula `E = μ (A ⋆ μ) / 2` disappears due
    # to quadratic appearance of μ = - μB g S.
    return units.μB^2 * gs[site1]' * ewald.A[cell, to_atom(site1), to_atom(site2)] * gs[site2] * sys.dipoles[site2]
end

# Calculate the field dE/ds at `site` generated by all `dipoles`.
function ewald_grad_at(sys::System{N}, site) where N
    acc = zero(Vec3)
    for site2 in eachsite(sys)
        acc += ewald_pairwise_grad_at(sys, site, site2)
    end
    return acc
end

# Calculate the change in dipole-dipole energy when the spin at `site` is
# updated to `s`
function ewald_energy_delta(sys::System{N}, site, s::Vec3) where N
    (; dipoles, ewald, units) = sys
    Δs = s - dipoles[site]
    Δμ = units.μB * (sys.gs[site] * Δs)
    i = to_atom(site)
    ∇E = ewald_grad_at(sys, site)
    return Δs⋅∇E + dot(Δμ, ewald.A[1, 1, 1, i, i], Δμ) / 2
end
