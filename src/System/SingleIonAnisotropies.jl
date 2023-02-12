function empty_anisotropy(N)
    op = zero(𝒮[1])
    matrep = zeros(ComplexF64, N, N)
    clsrep = ClassicalStevensExpansion(
        0.0,
        zero(SVector{5, Float64}),
        zero(SVector{9, Float64}),
        zero(SVector{13, Float64}),
    )
    return SingleIonAnisotropy(op, matrep, clsrep)
end


function SingleIonAnisotropy(op; N)
    matrep = operator_to_matrix(op; N)

    S = (N-1)/2
    c = operator_to_classical_stevens_coefficients(op, S)
    all(iszero.(c[[1,3,5]])) || error("Odd-ordered dipole anisotropies not supported.")
    c2 = SVector{ 5}(c[2])
    c4 = SVector{ 9}(c[4])
    c6 = SVector{13}(c[6])
    kmax = max(!iszero(c2)*2, !iszero(c4)*4, !iszero(c6)*6)
    clsrep = ClassicalStevensExpansion(kmax, c2, c4, c6)

    return SingleIonAnisotropy(op, matrep, clsrep)
end


"""
    set_anisotropy!(sys::System, op, i::Int)

Set the single-ion anisotropy for the `i`th atom of every unit cell, as well as
all symmetry-equivalent atoms. The parameter `op` may be a polynomial in
symbolic spin operators `𝒮[α]`, or a linear combination of symbolic Stevens
operators `𝒪[k,q]`.

The characters `𝒮` and `𝒪` can be copy-pasted from this help message, or typed
at a Julia terminal using `\\scrS` or `\\scrO` followed by tab-autocomplete.

For systems restricted to dipoles, the anisotropy operators interactions will
automatically be renormalized to achieve maximum consistency with the more
variationally accurate SU(_N_) mode.

# Examples
```julia
# An easy axis anisotropy in the z-direction
set_anisotropy!(sys, -D*𝒮[3]^3, i)

# The unique quartic single-ion anisotropy for a site with cubic point group
# symmetry
set_anisotropy!(sys, 𝒪[4,0] + 5𝒪[4,4], i)

# An equivalent expression of this quartic anisotropy, up to a constant shift
set_anisotropy!(sys, 20*(𝒮[1]^4 + 𝒮[2]^4 + 𝒮[3]^4), i)
```

See also [`print_anisotropy_as_stevens`](@ref).
"""
function set_anisotropy!(sys::System{N}, op::DP.AbstractPolynomialLike, i::Int) where N
    if !is_homogeneous(sys)
        error("Use `set_anisotropy_at!` for inhomogeneous systems.")
    end
    ints = interactions(sys)

    iszero(op) && return 

    (1 <= i <= nbasis(sys.crystal)) || error("Atom index $i is out of range.")

    if !iszero(ints[i].aniso.op)
        println("Warning: Overriding anisotropy for atom $i.")
    end

    if !is_anisotropy_valid(sys.crystal, i, op)
        println("Symmetry-violating anisotropy: $op.")
        println("Use `print_site(crystal, $i)` for more information.")
        error("Invalid anisotropy.")
    end

    for (b′, op′) in zip(all_symmetry_related_anisotropies(sys.crystal, i, op)...)
        ints[b′].aniso = SingleIonAnisotropy(op′; N)
    end
end


"""
    set_anisotropy_at!(sys::System, op, idx::Site)

Sets the single-ion anisotropy operator `op` for a single [`Site`](@ref),
ignoring crystal symmetry.  The system must support inhomogeneous interactions
via [`to_inhomogeneous`](@ref).

See also [`set_anisotropy!`](@ref).
"""
function set_anisotropy_at!(sys::System{N}, op::DP.AbstractPolynomialLike, idx) where N
    is_homogeneous(sys) && error("Use `to_inhomogeneous` first.")
    ints = interactions_inhomog(sys)
    idx = convert_idx(idx)
    ints[idx].aniso = SingleIonAnisotropy(op; N)
end


# Evaluate a given linear combination of Stevens operators for classical spin s
function energy_and_gradient_for_classical_anisotropy(s::Vec3, clsrep::ClassicalStevensExpansion)
    (; kmax, c2, c4, c6) = clsrep

    E      = 0.0
    dE_dz  = 0.0
    dE_dJp = 0.0 + 0.0im

    kmax == 0 && @goto exit

    # Quadratic contributions

    X = s⋅s
    Jp¹ = s[1] + im*s[2]
    Jz¹ = s[3]
    Jp² = Jp¹*Jp¹
    Jz² = Jz¹*Jz¹

    A = (3Jz²-X, Jz¹, 1)
    dA_dz = (6Jz¹, 1)
    E +=        (c2[1]*real(Jp²)+c2[5]*imag(Jp²))A[3] +
                (c2[2]*real(Jp¹)+c2[4]*imag(Jp¹))A[2] +
                c2[3]*A[1]
    dE_dz +=    (c2[2]*real(Jp¹)+c2[4]*imag(Jp¹))dA_dz[2] +
                c2[3]*dA_dz[1]
    dE_dJp +=   (2/2)*(c2[1]*Jp¹-im*c2[5]*Jp¹)A[3] +
                (1/2)*(c2[2]    -im*c2[4]    )A[2]

    kmax == 2 && @goto exit

    # Quartic contributions

    X² = X*X
    Jp³ = Jp²*Jp¹
    Jz³ = Jz²*Jz¹
    Jp⁴ = Jp²*Jp²
    Jz⁴ = Jz²*Jz²

    A = (35Jz⁴ - (30X)Jz² + (3X²),
        7Jz³ - (3X)Jz¹,
        7Jz² - (X),
        Jz¹,
        1)
    dA_dz = (140Jz³ - (60X)Jz¹,
            21Jz² - 3X,
            14Jz¹,
            1)
    E +=        (c4[1]*real(Jp⁴)+c4[9]*imag(Jp⁴))A[5] +
                (c4[2]*real(Jp³)+c4[8]*imag(Jp³))A[4] +
                (c4[3]*real(Jp²)+c4[7]*imag(Jp²))A[3] +
                (c4[4]*real(Jp¹)+c4[6]*imag(Jp¹))A[2] +
                c4[5]*A[1]
    dE_dz +=    (c4[2]*real(Jp³)+c4[8]*imag(Jp³))dA_dz[4] +
                (c4[3]*real(Jp²)+c4[7]*imag(Jp²))dA_dz[3] +
                (c4[4]*real(Jp¹)+c4[6]*imag(Jp¹))dA_dz[2] +
                c4[5]*dA_dz[1]
    dE_dJp +=   (4/2)*(c4[1]*Jp³-im*c4[9]*Jp³)A[5] +
                (3/2)*(c4[2]*Jp²-im*c4[8]*Jp²)A[4] +
                (2/2)*(c4[3]*Jp¹-im*c4[7]*Jp¹)A[3] +
                (1/2)*(c4[4]    -im*c4[6]    )A[2]

    kmax == 4 && @goto exit

    # Hexic contributions

    X³ = X²*X
    Jp⁵ = Jp⁴*Jp¹
    Jz⁵ = Jz⁴*Jz¹
    Jp⁶ = Jp³*Jp³
    Jz⁶ = Jz³*Jz³

    A = (231Jz⁶ - (315X)Jz⁴ + (105X²)Jz² - (5X³),
        33Jz⁵ - (30X)Jz³ + (5X²)Jz¹,
        33Jz⁴ - (18X)Jz² + (X²),
        11Jz³ - (3X)Jz¹,
        11Jz² - (X),
        Jz¹,
        1)
    dA_dz = (1386Jz⁵ - (1260X)Jz³ + (210X²)Jz¹,
            165Jz⁴ - (90X)Jz² + 5X²,
            132Jz³ - (36X)Jz¹,
            33Jz² - 3X,
            22Jz¹,
            1)
    E +=        (c6[1]*real(Jp⁶)+c6[13]*imag(Jp⁶))A[7] +
                (c6[2]*real(Jp⁵)+c6[12]*imag(Jp⁵))A[6] +
                (c6[3]*real(Jp⁴)+c6[11]*imag(Jp⁴))A[5] +
                (c6[4]*real(Jp³)+c6[10]*imag(Jp³))A[4] +
                (c6[5]*real(Jp²)+c6[9] *imag(Jp²))A[3] +
                (c6[6]*real(Jp¹)+c6[8] *imag(Jp¹))A[2] +
                c6[7]*A[1]
    dE_dz +=    (c6[2]*real(Jp⁵)+c6[12]*imag(Jp⁵))dA_dz[6] +
                (c6[3]*real(Jp⁴)+c6[11]*imag(Jp⁴))dA_dz[5] +
                (c6[4]*real(Jp³)+c6[10]*imag(Jp³))dA_dz[4] +
                (c6[5]*real(Jp²)+c6[9] *imag(Jp²))dA_dz[3] +
                (c6[6]*real(Jp¹)+c6[8] *imag(Jp¹))dA_dz[2] +
                c6[7]*dA_dz[1]
    dE_dJp +=   (6/2)*(c6[1]*Jp⁵-im*c6[13]*Jp⁵)A[7] +
                (5/2)*(c6[2]*Jp⁴-im*c6[12]*Jp⁴)A[6] +
                (4/2)*(c6[3]*Jp³-im*c6[11]*Jp³)A[5] +
                (3/2)*(c6[4]*Jp²-im*c6[10]*Jp²)A[4] +
                (2/2)*(c6[5]*Jp¹-im*c6[9] *Jp¹)A[3] +
                (1/2)*(c6[6]    -im*c6[8]     )A[2]

    # Unpack gradient components

    @label exit
    dE_dx = +2real(dE_dJp)
    dE_dy = -2imag(dE_dJp)
    return (E, Vec3(dE_dx, dE_dy, dE_dz))
end
