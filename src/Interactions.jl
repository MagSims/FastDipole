"""Structs for defining various terms in a spin Hamiltonian.
"""

abstract type AbstractInteraction end      # Subtype this for user-facing interfaces
abstract type AbstractInteractionCPU end   # Subtype this for actual internal CPU implementations
abstract type AbstractInteractionGPU end   # Subtype this for actual internal GPU implementations
abstract type AbstractAnisotropy <: AbstractInteraction end


struct QuadraticInteraction <: AbstractInteraction
    J     :: Mat3
    bond  :: Bond
    label :: String
end

function Base.show(io::IO, mime::MIME"text/plain", int::QuadraticInteraction)
    b = repr(mime, int.bond)
    J = int.J
    if J ≈ -J'                             # Catch purely DM interactions
        x = J[2, 3]
        y = J[3, 1]
        z = J[1, 2]
        @printf io "dm_interaction([%.4g, %.4g, %.4g], %s)" x y z b
    elseif diagm(fill(J[1,1], 3)) ≈ J      # Catch Heisenberg interactions
        @printf io "heisenberg(%.4g, %s)" J[1,1] b
    elseif diagm(diag(J)) ≈ J              # Catch diagonal interactions
        @printf io "exchange(diagm([%.4g, %.4g, %.4g]), %s)" J[1,1] J[2,2] J[3,3] b
    else                                   # Rest -- general exchange interactions
        @printf io "exchange([%.4g %.4g %.4g; %.4g %.4g %.4g; %.4g %.4g %.4g], %s)" J[1,1] J[1,2] J[1,3] J[2,1] J[2,2] J[2,3] J[3,1] J[3,2] J[3,3] b
        # TODO: Figure out how to reenable this depending on context:
        # @printf io "exchange([%.4f %.4f %.4f\n"   J[1,1] J[1,2] J[1,3]
        # @printf io "          %.4f %.4f %.4f\n"   J[2,1] J[2,2] J[2,3]
        # @printf io "          %.4f %.4f %.4f],\n" J[3,1] J[3,2] J[3,3]
        # @printf io "    %s)" b
    end
end

"""
    SiteInfo(site::Int, N::Int, g::Mat3, κ::Float64)

Characterizes the degree of freedom located at a given `site` index with
 a spin magnitude `S` and g-tensor `g`. When provided to a `SpinSystem`,
 this information is automatically propagated to all symmetry-equivalent
 sites.
"""
@with_kw struct SiteInfo
    site :: Int                # Index of site
    N    :: Int     = 0        # N in SU(N)
    g    :: Mat3    = 2*I(3)   # Spin g-tensor
    κ    :: Float64 = 1.0      # Spin/Ket rescaling factor
end

SiteInfo(site::Int, N::Int, g::Number, κ=1.0) = SiteInfo(site, N, g*I(3), κ)

"""
    exchange(J, bond::Bond, label="Exchange")

Creates a quadratic interaction,

```math
    ∑_{⟨ij⟩} 𝐒_i^T J^{(ij)} 𝐒_j
```

where ``⟨ij⟩`` runs over all bonds (not doubly counted) that are symmetry
equivalent to `bond`. The ``3 × 3`` interaction matrix ``J^{(ij)}`` is the
covariant transformation of `J` appropriate for the bond ``⟨ij⟩``.
"""
function exchange(J, bond::Bond, label::String="Exchange")
    QuadraticInteraction(Mat3(J), bond, label)
end


"""
    heisenberg(J, bond::Bond, label::String="Heisen")

Creates a Heisenberg interaction
```math
    J ∑_{⟨ij⟩} 𝐒_i ⋅ 𝐒_j
```
where ``⟨ij⟩`` runs over all bonds symmetry equivalent to `bond`.
"""
heisenberg(J, bond::Bond, label::String="Heisen") = QuadraticInteraction(J*Mat3(I), bond, label)


"""
    dm_interaction(DMvec, bond::Bond, label::String="DMInt")

Creates a DM Interaction
```math
    ∑_{⟨ij⟩} 𝐃^{(ij)} ⋅ (𝐒_i × 𝐒_j)
```
where ``⟨ij⟩`` runs over all bonds symmetry equivalent to `bond`, and
``𝐃^{(ij)}`` is the covariant transformation of the DM pseudo-vector `DMvec`
appropriate for the bond ``⟨ij⟩``.
"""
function dm_interaction(DMvec, bond::Bond, label::String="DMInt")
    J = SA[     0.0   DMvec[3] -DMvec[2]
           -DMvec[3]       0.0  DMvec[1]
            DMvec[2] -DMvec[1]      0.0]
    QuadraticInteraction(J, bond, label)
end

struct QuadraticAnisotropy <: AbstractAnisotropy
    mat   :: Mat3
    site  :: Int
    label :: String # Maybe remove
end

struct QuarticAnisotropy <: AbstractAnisotropy
    tens  :: Quad3
    site  :: Int
    label :: String # Maybe remove
end

struct SUNAnisotropy <: AbstractAnisotropy
    op    :: Matrix{ComplexF64}
    site  :: Int
    label :: String # Maybe remove
end

function Base.show(io::IO, mime::MIME"text/plain", aniso::QuadraticAnisotropy)
    @unpack J, site, label = aniso
    @assert J ≈ J'
    # Check if it is easy-axis or easy-plane
    λ, V = eigen(J)
    nonzero_λ = findall(x -> abs(x) > 1e-12, λ)
    if length(nonzero_λ) == 1
        i = nonzero_λ[1]
        dir = V[:, i]
        if count(<(0.0), dir) >= 2
            dir = -dir
        end
        name, D = λ[i] < 0 ? ("easy_axis", -λ[i]) : ("easy_plane", λ[i])
        @printf io "%s(%.4g, [%.4g, %.4g, %.4g], %d)" name D dir[1] dir[2] dir[3] site
    else
        @printf io "single_ion_anisotropy([%.4g %.4g %.4g; %.4g %.4g %.4g; %.4g %.4g %.4g], %d)" J[1,1] J[1,2] J[1,3] J[2,1] J[2,2] J[2,3] J[3,1] J[3,2] J[3,3] site
    end
end

"""
    single_ion_anisotropy(J, site, label="Anisotropy")

Creates a quadratic single-ion anisotropy,
```math
    ∑_i 𝐒_i^T J^{(i)} 𝐒_i
```
where ``i`` runs over all sublattices that are symmetry equivalent to `site`,
and ``J^{(i)}`` is the covariant transformation of the ``3 × 3`` anisotropy
matrix `J` appropriate for ``i``. Without loss of generality, we require that
`J` is symmetric.
"""
function quadratic_anisotropy(J, site::Int, label::String="Anisotropy")
    if !(J ≈ J')
        error("Single-ion anisotropy must be symmetric.")
    end
    QuadraticAnisotropy(Mat3(J), site, label)
end


"""
    easy_axis(D, n, site, label="EasyAxis")

Creates an easy axis anisotropy,
```math
    - D ∑_i (𝐧̂^{(i)}⋅𝐒_i)^2
```
where ``i`` runs over all sublattices that are symmetry equivalent to `site`,
``𝐧̂^{(i)}`` is the covariant transformation of the unit vector `n`, and ``D > 0``
is the interaction strength.
"""
function easy_axis(D, n, site::Int, label::String="EasyAxis")
    if D <= 0
        error("Parameter `D` must be nonnegative.")
    end
    if !(norm(n) ≈ 1)
        error("Parameter `n` must be a unit vector. Consider using `normalize(n)`.")
    end
    QuadraticAnisotropy(-D*Mat3(n*n'), site, label)
end


"""
    easy_plane(D, n, site, label="EasyPlane")

Creates an easy plane anisotropy,
```math
    + D ∑_i (𝐧̂^{(i)}⋅𝐒_i)^2
```
where ``i`` runs over all sublattices that are symmetry equivalent to `site`,
``𝐧̂^{(i)}`` is the covariant transformation of the unit vector `n`, and ``D > 0``
is the interaction strength.
"""
function easy_plane(D, n, site::Int, label::String="EasyAxis")
    if D <= 0
        error("Parameter `D` must be nonnegative.")
    end
    if !(norm(n) ≈ 1)
        error("Parameter `n` must be a unit vector. Consider using `normalize(n)`.")
    end
    QuadraticAnisotropy(+D*Mat3(n*n'), site, label)
end

"""
    quartic_anisotropy(J, site, label="QuarticAniso")

Creates a quartic anisotropy.
```math
    ∑_i ∑_{α, β, γ, δ ∈ \\{x, y, z\\}} J_{αβγδ} S_i^α S_i^β S_i^γ S_i^δ
```
"""
function quartic_anisotropy(J, site, label="QuarticAniso")
    # TODO: Basic symmetry checks?
    if (size(J) != (3, 3, 3, 3)) || !(eltype(J) <: Real)
        error("Parameter `tens` must be a 3x3x3x3 real tensor.")
    end
    QuarticAnisotropy(tens, site, label)
end

# N-dimensional irreducible matrix representation of 𝔰𝔲(2). Use this only
#  to give the user the ability to construct generalized anisotropy matrices.
# Internal code should implicitly use the action of these operators on
#  N-dimensional complex vectors.
function gen_spin_ops(N)
    s = (N-1)/2
    a = 1:N-1
    off = @. sqrt(2(s+1)*a - a*(a+1)) / 2

    Sx = diagm(1 => off, -1 => off)
    Sy = diagm(1 => -im*off, -1 => +im*off)
    Sz = diagm((N-1)/2 .- (0:N-1))
    return Sx, Sy, Sz
end

"""
    SUN_anisotropy(mat, site)
"""
function SUN_anisotropy(mat, site, label="SUNAniso")
    # TODO: Basic symmetry / validity checks?
    SUNAnisotropy(mat, site, label)
end

struct DipoleDipole <: AbstractInteraction
    extent   :: Int
    η        :: Float64
end

"""
    dipole_dipole(; extent::Int=4, η::Float64=0.5)

Includes long-range dipole-dipole interactions,

```math
    -(μ₀/4π) ∑_{⟨ij⟩}  (3 (𝐌_j⋅𝐫̂_{ij})(𝐌_i⋅𝐫̂_{ij}) - 𝐌_i⋅𝐌_j) / |𝐫_{ij}|^3
```

where the sum is over all pairs of spins (singly counted), including periodic
images, regularized using the Ewald summation convention. The magnetic moments
are ``𝐌_i = μ_B g 𝐒_i`` where ``g`` is the g-factor or g-tensor, and the spin
magnitude ``|𝐒_i|`` is typically a multiple of 1/2. The Bohr magneton ``μ_B``
and vacuum permeability ``μ_0`` are physical constants, with numerical values
determined by the unit system.

`extent` controls the number of periodic copies of the unit cell summed over in
the Ewald summation (higher is more accurate, but higher creation-time cost),
while `η` controls the direct/reciprocal-space tradeoff in the Ewald summation.
"""
dipole_dipole(; extent=4, η=0.5) = DipoleDipole(extent, η)

struct ExternalField <: AbstractInteraction
    B :: Vec3
end

"""
    external_field(B::Vec3)

Adds an external field ``𝐁`` with Zeeman coupling,

```math
    -∑_i 𝐁 ⋅ 𝐌_i.
```

The magnetic moments are ``𝐌_i = μ_B g 𝐒_i`` where ``g`` is the g-factor or
g-tensor, and the spin magnitude ``|𝐒_i|`` is typically a multiple of 1/2. The
Bohr magneton ``μ_B`` is a physical constant, with numerical value determined by
the unit system.
"""
external_field(B) = ExternalField(Vec3(B))

function Base.show(io::IO, ::MIME"text/plain", int::ExternalField)
    B = int.B
    @printf io "external_field([%.4g, %.4g, %.4g])" B[1] B[2] B[3]
end


#= Energy and field functions for "simple" interactions that aren't geometry-dependent.
   See Hamiltonian.jl for expectations on `_accum_neggrad!` functions.
=#

struct ExternalFieldCPU
    effBs :: Vector{Vec3}  # |S_b|gᵀB for each basis index b
end

function ExternalFieldCPU(ext_field::ExternalField, site_infos::Vector{SiteInfo}; μB=BOHR_MAGNETON)
    # As E = -∑_i 𝐁^T g 𝐒_i, we can precompute effB = g^T S B, so that
    #  we can compute E = -∑_i effB ⋅ 𝐬_i during simulation.
    # However, S_i may be basis-dependent, so we need to store an effB
    #  per sublattice.
    effBs = [μB * site.g' * site.S * ext_field.B for site in site_infos]
    ExternalFieldCPU(effBs)
end

function energy(spins::Array{Vec3, 4}, field::ExternalFieldCPU)
    E = 0.0
    for b in 1:size(spins, 1)
        effB = field.effBs[b]
        for s in selectdim(spins, 1, b)
            E += effB ⋅ s
        end
    end
    return -E
end

"Accumulates the negative local Hamiltonian gradient coming from the external field"
@inline function _accum_neggrad!(B::Array{Vec3, 4}, field::ExternalFieldCPU)
    for b in 1:size(B, 1)
        effB = field.effBs[b]
        for idx in CartesianIndices(size(B)[2:end])
            B[b, idx] = B[b, idx] + effB
        end
    end
end
