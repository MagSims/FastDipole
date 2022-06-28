import Random

"""
Defines a collection of spins, as well as the Hamiltonian they interact under.
 This is the main type to interface with most of the package.
"""
struct SpinSystem{N}   
    lattice     :: Lattice                          # Definition of underlying lattice
    hamiltonian :: HamiltonianCPU                   # Contains all interactions present
    _dipoles    :: Array{Vec3, 4}                   # Holds dipole moments: Axes are [Basis, CellA, CellB, CellC]
    _coherents  :: Array{SVector{N, ComplexF64}, 4} # Coherent states
    site_infos  :: Vector{SiteInfo}                 # Characterization of each basis site
    S           :: NTuple{3, Matrix{ComplexF64}}
    rng         :: Random.AbstractRNG
end

@inline Base.size(sys::SpinSystem) = size(sys._coherents)
@inline nbasis(sys::SpinSystem) = nbasis(sys.lattice)
@inline eachcellindex(sys::SpinSystem) = eachcellindex(sys.lattice)

@inline _get_coherent_from_dipole(dip::Vec3, ::Val{0}) :: CVec{0} = CVec{0}(zeros(0))
@inline function _get_coherent_from_dipole(dip::Vec3, ::Val{N}) :: CVec{N} where {N} 
    S = gen_spin_ops(N) 
    λs, vs = eigen(dip⋅S)
    return CVec{N}(vs[:, argmax(real.(λs))])
end

struct DipoleView{N} <: AbstractArray{Vec3, 4}
    _dipoles    :: Array{Vec3, 4}
    _coherents  :: Array{SVector{N, ComplexF64}, 4}
end

Base.IndexStyle(::Type{DipoleView}) = IndexLinear()
Base.size(dv::DipoleView) = size(dv._dipoles)
Base.getindex(dv::DipoleView, i...) = getindex(dv._dipoles, i...)
function Base.setindex!(dv::DipoleView{N}, v::Vec3, i...) where N
    setindex!(dv._dipoles, v, i...)
    setindex!(dv._coherents, _get_coherent_from_dipole(v, Val(N)), i...)
end

DipoleView(sys::SpinSystem{N}) where {N} = DipoleView{N}(sys._dipoles, sys._coherents)

function init_from_dipoles!(sys::SpinSystem{N}, dipoles::Array{Vec3, 4}) where N
    dipole_view = DipoleView(sys)
    dipole_view .= dipoles
end

struct KetView{N} <: AbstractArray{CVec{N}, 4}
    _dipoles    :: Array{Vec3, 4}
    _coherents  :: Array{SVector{N, ComplexF64}, 4}
end

Base.IndexStyle(::Type{KetView}) = IndexLinear()
Base.size(kv::KetView) = size(kv._coherents)
Base.getindex(kv::KetView, i...) = getindex(kv._coherents, i...)
function Base.setindex!(kv::KetView{N}, Z::CVec{N}, i...) where N
    setindex!(kv._coherents, Z, i...)
    setindex!(kv._dipoles, expected_spin(Z), i...)
end

KetView(sys::SpinSystem{N}) where N = KetView{N}(sys._dipoles, sys._coherents)

function init_from_coherents!(sys::SpinSystem, coherents::Array{CVec{N}, 4}) where N
    ket_view = KetView(sys)
    ket_view .= coherents
end


@generated function expected_spin(Z::CVec{N}) where N
    S = gen_spin_ops(N)
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


function set_expected_spins!(sys::SpinSystem)
    (; _dipoles, _coherents) = sys
    for b in 1:size(_dipoles, 1)
        spin_rescaling = sys.site_infos[b].spin_rescaling
        for i in CartesianIndices(size(_dipoles)[2:end])
            _dipoles[b, i] = spin_rescaling * expected_spin(_coherents[b, i])
        end
    end
end

function set_expected_spins!(dipoles::Array{Vec3, 4}, coherents::Array{CVec{N}, 4}, sys::SpinSystem) where N
    for b in 1:size(dipoles, 1)
        spin_rescaling = sys.site_infos[b].spin_rescaling
        for i in CartesianIndices(size(dipoles)[2:end])
            dipoles[b, i] = spin_rescaling * expected_spin(coherents[b, i])
        end
    end
end


"""
    propagate_site_info(cryst::Crystal, site_infos::Vector{SiteInfo})

Given an incomplete list of site information, propagates spin magnitudes and
symmetry-transformed g-tensors to all symmetry-equivalent sites. If SiteInfo is
not provided for a site, sets N=0, spin_rescaling=1 and g=2 for that site. Throws an error if
two symmetry-equivalent sites are provided in `site_infos`.
"""
function _propagate_site_info(crystal::Crystal, site_infos::Vector{SiteInfo})
    # All sites not explicitly provided are by default N=0, g=2, spin_rescaling=1
    all_site_infos = [SiteInfo(i; N=0, g=2*I(3), spin_rescaling=1.0) for i in 1:nbasis(crystal)]

    maxN = length(site_infos) > 0 ? maximum(info->info.N, site_infos) : 0

    specified_atoms = Int[]
    for siteinfo in site_infos
        @unpack site, N, g, spin_rescaling = siteinfo
        if N != maxN
            @warn "Up-converting N=$N -> N=$maxN on site $(site)!"
        end
        (sym_bs, sym_gs) = all_symmetry_related_couplings(crystal, Bond(site, site, [0,0,0]), g)
        for (sym_b, sym_g) in zip(sym_bs, sym_gs)
            sym_atom = sym_b.i
            if sym_atom in specified_atoms
                # Perhaps this should only throw if two _conflicting_ SiteInfo are passed?
                # Then propagate_site_info can be the identity on an already-filled list.
                @error "Provided two `SiteInfo` which describe symmetry-equivalent sites!"
            else
                push!(specified_atoms, sym_atom)
            end

            all_site_infos[sym_atom] = SiteInfo(sym_atom; N = maxN, g = sym_g, spin_rescaling)
        end
    end

    return all_site_infos, maxN
end


"""
    SpinSystem(crystal::Crystal, ints::Vector{<:AbstractInteraction}, latsize, site_infos::Vector{SiteInfo}=[];
               μB, μ0)

Construct a `SpinSystem` with spins of magnitude `S` residing on the lattice sites
 of a given `crystal`, interactions given by `ints`, and the number of unit cells along
 each lattice vector specified by `latsize`. Initialized to all spins pointing along
 the ``+𝐳̂`` direction. μB and μ0 set the Bohr magneton and vacuum permeability. By
 default, these are set so that the unit system is (meV, T, Å).
"""
function SpinSystem(crystal::Crystal, ints::Vector{<:AbstractInteraction}, latsize,
                    site_infos::Vector{SiteInfo}=SiteInfo[];
                    rng=nothing, μB=BOHR_MAGNETON, μ0=VACUUM_PERM)
    latsize = collect(Int64.(latsize))
    lattice = Lattice(crystal, latsize)

    (all_site_infos, N) = _propagate_site_info(crystal, site_infos)
    ℋ_CPU = HamiltonianCPU(ints, crystal, latsize, all_site_infos; μB, μ0)
    S = gen_spin_ops(N)

    # Initialize sites to all spins along +z
    sys_size = (nbasis(lattice), lattice.size...)
    up = SA[0.0, 0.0, 1.0]
    dipoles = fill(up, sys_size)
    coherents = fill(_get_coherent_from_dipole(up, Val(N)), sys_size)

    # Set up default RNG if none provided
    isnothing(rng) && (rng = Random.MersenneTwister())

    # Default unit system is (meV, K, Å, T)
    SpinSystem{N}(lattice, ℋ_CPU, dipoles, coherents, all_site_infos, S, rng)
end

function Base.show(io::IO, ::MIME"text/plain", sys::SpinSystem{N}) where {N}
    sys_type = N > 0 ? "SU($N)" : "Dipolar"
    printstyled(io, "Spin System [$sys_type]\n"; bold=true, color=:underline)
    sz = size(sys)
    println(io, "Basis $(sz[1]), Lattice dimensions $(sz[2:end])")
end

"""
    rand!(sys::SpinSystem)

Sets spins randomly sampled on the unit sphere.
"""
function Random.rand!(sys::SpinSystem{0})  
    dip_view = DipoleView(sys)
    dip_view .= randn(sys.rng, Vec3, size(dip_view))
    @. dip_view /= norm(dip_view)
    for b ∈ 1:nbasis(sys)
        dip_view[b,:,:,:] .*= sys.site_infos[b].spin_rescaling
    end
    nothing
end

function Random.rand!(sys::SpinSystem{N}) where N
    Zs = sys._coherents
    randn!(sys.rng, Zs)
    @. Zs /= norm(Zs)
    set_expected_spins!(sys)
    nothing
end



"""
    randflips!(sys::SpinSystem)

Sets spins randomly either aligned or anti-aligned
with their original direction.
"""
function randflips!(sys::SpinSystem{0}) 
    dip_view = DipoleView(sys)
    @. dip_view .*= rand(sys.rng, (-1, 1), size(dip_view))
end

@inline function flip_ket(Z::CVec{N}, S) where N
    exp(-im*π*S[2])*conj(Z)
end

function randflips!(sys::SpinSystem{N}) where N
    Z, S = sys._coherents, sys.S
    for i in eachindex(Z)
        rand([true, false]) && (Z[i] = flip_ket(Z[i], S))
    end
    set_expected_spins!(sys)
end

"""
    energy(sys::SpinSystem)

Computes the energy of the system under `sys.hamiltonian`.
"""
energy(sys::SpinSystem) = energy(sys._dipoles, sys._coherents, sys.hamiltonian)

"""
    field!(B::Array{Vec3}, sys::SpinSystem)

Updates B in-place to contain the local field at each site in the
system under `sys.hamiltonian`. The "local field" is defined as

``𝐁_i = -∇_{𝐬_i} ℋ / S_i``

with ``𝐬_i`` the unit-vector variable at site i, and ``S_i`` is
the magnitude of the associated spin.
"""
field!(B::Array{Vec3}, sys::SpinSystem{N}) where N = field!(B, sys._dipoles, sys.hamiltonian)

"""
    field(sys::SpinSystem)

Compute the local field B at each site of the system under
`sys.hamiltonian`.
"""
@inline function field(sys::SpinSystem{N}) where N
    B = zero(sys._dipoles)
    field!(B, sys)
    B
end
