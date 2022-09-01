""" Functions for computing and manipulating structure factors """

# TODO:
#  1. Many optimizations + clean-ups still possible in this file.
#       In particular, still a ton of allocations?

"""
    StructureFactor

Type responsible for computing and updating the static/dynamic structure factor
averaged across multiple spin configurations.

Note that the initial `sys` provided does _not_ enter the structure factor,
it is purely used to determine the size of various results.

The full dynamic structure factor is
``𝒮^{αβ}_{jk}(𝐪, ω) = ⟨M^α_j(𝐪, ω) M^β_k(𝐪, ω)^∗⟩``,
which is an array of shape `[3, 3, Q1, Q2, Q3, B, B, T]`
where `B = nbasis(sys.lattice)`, `Qi = max(1, bz_size_i * L_i)` and
`T = num_ωs`. By default, `bz_size=ones(d)`.

Indexing the `.sfactor` attribute at `(α, β, q1, q2, q3, j, k, w)`
gives ``𝒮^{αβ}_{jk}(𝐪, ω)`` at `𝐪 = q1 * 𝐛_1 + q2 * 𝐛_2 + q3 * 𝐛_3`, and
`ω = maxω * w / T`, where `𝐛_1, 𝐛_2, 𝐛_3` are the reciprocal lattice vectors
of the system supercell.

Allowed values for the `qi` indices lie in `-div(Qi, 2):div(Qi, 2, RoundUp)`, and allowed
 values for the `w` index lie in `0:T-1`.

The maximum frequency captured by the calculation is set with the keyword
`ω_max``. `ω_max`` must be set to a value equal to, or smaller than, 2π/Δt, where Δt is the 
time step chosen for the dynamics. If no value is given, `ω_max`` will be taken as 2π/Δt.
The total number of resolved frequencies is set with `num_ωs` (the number of spin
snapshots measured during dynamics). By default, `num_ωs=1`, and the static structure
factor is computed. 

Setting `reduce_basis` performs the phase-weighted sums over the basis/sublattice
indices, resulting in a size `[3, 3, Q1, Q2, Q3, T]` array.

Setting `dipole_factor` applies the dipole form factor, further reducing the
array to size `[Q1, Q2, Q3, T]`.
"""
struct StructureFactor{A1, A2}
    sfactor       :: A1
    _mag_ft       :: Array{ComplexF64, 6}                    # Buffer for FT of a mag trajectory
    _bz_buf       :: A2                                      # Buffer for phase summation / BZ repeating
    lattice       :: Lattice
    reduce_basis  :: Bool                                    # Flag setting basis summation
    dipole_factor :: Bool                                    # Flag setting dipole form factor
    bz_size       :: NTuple{3, Int}                          # Num of Brillouin zones along each axis
    Δt            :: Float64                                 # Timestep size in dynamics integrator
    meas_period   :: Int                                     # Num timesteps between saved snapshots 
    num_ωs        :: Int                                     # Total number of snapshots to FT
    integrator    :: Union{SphericalMidpoint, SchrodingerMidpoint}
    plan          :: FFTW.cFFTWPlan{ComplexF64, -1, true, 6, NTuple{4, Int64}}
end

Base.show(io::IO, sf::StructureFactor) = print(io, join(size(sf.sfactor), "x"),  " StructureFactor")
Base.summary(io::IO, sf::StructureFactor) = string("StructureFactor: ", summary(sf.sfactor))

function StructureFactor(sys::SpinSystem{N}; bz_size=(1,1,1), reduce_basis=true,
                         dipole_factor=false, Δt::Float64=0.01,
                         num_ωs::Int=100, ω_max=nothing,) where N

    if isnothing(ω_max)
        meas_period = 10
    else
        @assert π/Δt > ω_max "Maximum ω with chosen step size is $(π/Δt). Please choose smaller Δt or larger ω_max."
        meas_period = floor(Int, π/(Δt * ω_max))
    end
    nb = nbasis(sys.lattice)
    spat_size = size(sys)[1:3]
    q_size = map(s -> s == 0 ? 1 : s, bz_size .* spat_size)
    result_size = (3, q_size..., num_ωs)
    min_q_idx = -1 .* div.(q_size .- 1, 2)
    min_ω_idx = -1 .* div(num_ωs - 1, 2)

    spin_ft = zeros(ComplexF64, 3, spat_size..., nb, num_ωs)
    if reduce_basis
        bz_buf = zeros(ComplexF64, 3, q_size..., num_ωs)
        bz_buf = OffsetArray(bz_buf, Origin(1, min_q_idx..., min_ω_idx))
    else
        bz_buf = zeros(ComplexF64, 3, q_size..., nb, num_ωs)
        bz_buf = OffsetArray(bz_buf, Origin(1, min_q_idx..., 1, min_ω_idx  ))
    end

    if reduce_basis
        if dipole_factor
            sfactor = zeros(Float64, q_size..., num_ωs)
            sfactor = OffsetArray(sfactor, Origin(min_q_idx..., min_ω_idx))
        else
            sfactor = zeros(ComplexF64, 3, 3, q_size..., num_ωs)
            sfactor = OffsetArray(sfactor, Origin(1, 1, min_q_idx..., min_ω_idx))
        end
    else
        if dipole_factor
            sfactor = zeros(Float64, q_size..., nb, nb, num_ωs)
            sfactor = OffsetArray(sfactor, Origin(min_q_idx..., 1, 1, min_ω_idx))
        else
            sfactor = zeros(ComplexF64, 3, 3, q_size..., nb, nb, num_ωs)
            sfactor = OffsetArray(sfactor, Origin(1, 1, min_q_idx..., 1, 1, min_ω_idx))
        end
    end

    integrator_type = N == 0 ? SphericalMidpoint : SchrodingerMidpoint
    integrator = integrator_type(sys)
    plan = plan_spintraj_fft!(spin_ft)

    StructureFactor{typeof(sfactor), typeof(bz_buf)}(
        sfactor, spin_ft, bz_buf, sys.lattice, reduce_basis, dipole_factor,
        bz_size, Δt, meas_period, num_ωs, integrator, plan
    )
end

"""
    StructureFactor(snaps::Vector{SpinSystem}; kwargs...)

Construct a `StructureFactor` from a list of spin configurations.
All `SpinSystem`s should have the same underlying lattice -- for
all intents, they should be the "same" system only with different
spin configs. `kwargs` are passed onto the default `StructureFactor`
constructor.
"""
function StructureFactor(snaps::Vector{SpinSystem}; kwargs...)
    if length(snaps) == 0
        error("No snapshots provided, cannot construct StructureFactor")
    end
    sf = StructureFactor(snaps[1]; kwargs...)
    for snap in snaps
        update!(sf, snap)
    end
    sf
end

"""
    StructureFactor(snaps::Vector{Array{Vec3, 4}}, crystal; kwargs...)

Construct a `StructureFactor` from a list of spin configurations,
and a `Crystal` specifying the underlying lattice. `kwargs` are passed
onto the default `StructureFactor` constructor.
"""
function StructureFactor(snaps::Vector{Array{Vec3, 4}}, crystal; kwargs...)
    if length(snaps) == 0
        error("No snapshots provided, cannot construct StructureFactor")
    end
    sys = SpinSystem(crystal, Vector{Interaction}(), size(snaps[1])[1:3])
    sf = StructureFactor(sys; kwargs...)
    for snap in snaps
        sys._dipoles .= snap
        update!(sf, sys)
    end
    sf
end


"""
Updates `M` in-place to hold the magnetization vectors obtained by scaling `s`
 by the appropriate spin magnitudes and g-tensors in `site_infos`.
This function assumes `M` has a first index of length 3, which correspond
 to the magnetization components. (Rather than storing an Array{Vec3}).
"""
function _compute_mag!(M, sys::SpinSystem)
    for b in 1:nbasis(sys)
        gS = sys.site_infos[b].g 
        for idx in eachcellindex(sys)
            M[:, idx, b] .= gS * sys._dipoles[idx, b]
        end
    end
end

"""
    update!(sf::StructureFactor, sys::SpinSystem)

Accumulates a contribution to the dynamic structure factor from the spin
configuration currently in `sys`.
"""
function update!(sf::StructureFactor, sys::SpinSystem)
    (; sfactor, _mag_ft, _bz_buf) = sf
    (; reduce_basis, dipole_factor, bz_size) = sf

    # Evolve the spin state forward in time to form a trajectory
    # Save off the magnetic moments 𝐦_i(t) = g_i S_i 𝐬_i(t) into _mag_ft
    dynsys = deepcopy(sys)
    sf.integrator.sys = dynsys
    T_dim = ndims(_mag_ft)      # Assuming T_dim is "time dimension", which is last
    _compute_mag!(selectdim(_mag_ft, T_dim, 1), dynsys)
    for nsnap in 2:sf.num_ωs
        for _ in 1:sf.meas_period
            evolve!(sf.integrator, sf.Δt)
        end
        _compute_mag!(selectdim(_mag_ft, T_dim, nsnap), dynsys)
    end

    # Fourier transform the trajectory in space + time
    fft_spin_traj!(_mag_ft, plan=sf.plan)

    # Optionally sum over basis sites then accumulate the conjugate outer product into sfactor
    # Accumulate the conjugate outer product into sfactor, with optionally:
    #   1) Doing a phase-weighting sum to reduce the basis atom dimensions
    #   2) Applying the neutron dipole factor to reduce the spin component dimensions
    if reduce_basis
        phase_weight_basis!(_bz_buf, _mag_ft, sys.lattice)
        if dipole_factor
            accum_dipole_factor!(sfactor, _bz_buf, sys.lattice)
        else
            outerprod_conj!(sfactor, _bz_buf, 1)
        end
    else
        expand_bz!(_bz_buf, _mag_ft)
        if dipole_factor
            accum_dipole_factor_wbasis!(sfactor, _bz_buf, sys.lattice)
        else
            outerprod_conj!(sfactor, _bz_buf, (1, 5)) 
        end
    end
end

"""
    zero!(sf::StructureFactor)

Zeros out the accumulated structure factor.
"""
function zero!(sf::StructureFactor)
    sf.sfactor .= 0
end

"""
    apply_dipole_factor(sf::StructureFactor) :: StructureFactor

Apply the neutron dipole factor to a dynamic structure factor.
"""
function apply_dipole_factor(sf::StructureFactor)
    if sf.dipole_factor == true
        return sf
    end

    dip_sfactor = apply_dipole_factor(sf.sfactor, sf.lattice)
    StructureFactor(
        dip_sfactor, copy(sf._mag_ft), copy(sf._bz_buf), sf.lattice,
        sf.reduce_basis, true, sf.bz_size, sf.Δt, sf.meas_period,
        sf.num_ωs, sf.integrator, sf.plan
    )
end

function apply_dipole_factor(struct_factor::OffsetArray{ComplexF64}, lattice::Lattice)
    recip = gen_reciprocal(lattice)

    num_ωs = size(spin_traj_ft)[end]
    min_ω = -1 .* div(num_ωs - 1, 2)
    max_ω = min_ω + num_ωs - 1
    result = zeros(Float64, axes(struct_factor)[3:end])
    for q_idx in CartesianIndices(axes(struct_factor)[3:5])
        q = recip.lat_vecs * Vec3(Tuple(q_idx) ./ lattice.size)
        q = q / (norm(q) + 1e-12)
        dip_factor = reshape(I(3) - q * q', 3, 3, 1)
        for ω in min_ω:max_ω  # Seems like this explicit loop can be avoided. Test alternatives.
            result[q_idx, ω] = real(dot(dip_factor, struct_factor[:, :, q_idx, ω]))
        end
    end
    return result
end

"""
    dynamic_structure_factor(sys, sampler; nsamples=10, Δt=0.01, meas_period=10,
                             num_ωs=100, bz_size, thermalize=10, reduce_basis=true,
                             verbose=false)

Measures the full dynamic structure factor tensor of a spin system, for the requested range
of 𝐪-space and range of frequencies ω. Returns ``𝒮^{αβ}(𝐪, ω) = ⟨S^α(𝐪, ω) S^β(𝐪, ω)^∗⟩``,
which is an array of shape `[3, 3, Q1, ..., Qd, T]`
where `Qi = max(1, bz_size_i * L_i)` and `T = num_ωs`. By default, `bz_size=ones(d)`.

Setting `reduce_basis=false` makes it so that the basis/sublattice indices are not
phase-weighted and summed over, making the shape of the result `[3, 3, B, B, Q1, ..., Qd, T]`
where `B = nbasis(sys)` is the number of basis sites in the unit cell.

`nsamples` sets the number of thermodynamic samples to measure and average
 across from `sampler`. `Δt` sets the integrator timestep during dynamics,
 and `meas_period` sets how often snapshots are recorded during dynamics. `num_ωs`
 sets the total number snapshots taken. The sampler is thermalized by sampling
 `thermalize` times before any measurements are made.

The maximum frequency sampled is `ωmax = 2π / (Δt * meas_period)`, and the frequency resolution
 is set by `num_ωs` (the number of spin snapshots measured during dynamics). However, beyond
 increasing the resolution, `num_ωs` will also make all frequencies become more accurate.

Indexing the result at `(α, β, q1, ..., qd, w)` gives ``S^{αβ}(𝐪, ω)`` at
    `𝐪 = q1 * a⃰ + q2 * b⃰ + q3 * c⃰`, and `ω = maxω * w / T`, where `a⃰, b⃰, c⃰`
    are the reciprocal lattice vectors of the system supercell.

Allowed values for the `qi` indices lie in `-div(Qi, 2):div(Qi, 2, RoundUp)`, and allowed
 values for the `w` index lie in `0:T-1`.

If you you would like the form factor to be applied to the resulting structure factor,
set the parameter `ff_elem` to the desired element, e.g. `ff_elem="Fe2"`.
For a list of the available ions and their names, see https://www.ill.eu/sites/ccsl/ffacts/ffachtml.html .
"""
function dynamic_structure_factor(
    sys::SpinSystem, sampler::S; nsamples::Int=10,
    thermalize::Int=10, bz_size=(1,1,1), reduce_basis::Bool=true,
    dipole_factor::Bool=false, Δt::Float64=0.01, num_ωs::Int=100,
    ff_elem=nothing, lande=false,
    ω_max=nothing, verbose::Bool=false
) where {S <: AbstractSampler}

    # The call to form_factor is made simply to test the validity of
    # ff_elem before starting calculations. The call will error if ff_elem is not valid.
    !isnothing(ff_elem) && form_factor([π,0,0], ff_elem, lande)
    
    sf  = StructureFactor(sys;
        Δt, num_ωs, ω_max, bz_size, reduce_basis, dipole_factor
    )

    if verbose
        println("Beginning thermalization...")
    end

    # Equilibrate the system by sampling from it `nsamples` times (discarding results)
    thermalize!(sampler, thermalize)

    if verbose
        println("Done thermalizing. Beginning measurements...")
    end

    progress = Progress(nsamples; dt=1.0, desc="Sample: ", enabled=verbose)
    for _ in 1:nsamples
        sample!(sampler)
        update!(sf, sys)
        next!(progress)
    end

    if !isnothing(ff_elem)
        apply_form_factor!(sf, ff_elem, lande)
    end

    return sf
end

"""
    static_structure_factor(sys, sampler; nsamples, Δt, meas_period, num_ωs
                                          bz_size, thermalize, verbose)

Measures the static structure factor tensor of a spin system, for the requested range
of 𝐪-space. Returns ``𝒮^{αβ}(𝐪) = ⟨S^α(𝐪) S^β(𝐪)^∗⟩``,
which is an array of shape `[3, 3, Q1, ..., Qd]` where `Qi = max(1, bz_size_i * L_i)`.
By default, `bz_size=ones(d)`.

`nsamples` sets the number of thermodynamic samples to measure and average
 across from `sampler`. `Δt` sets the integrator timestep during dynamics,
 and `meas_period` sets how many timesteps are performed between recording snapshots.
 `num_ωs` sets the total number snapshots taken. The sampler is thermalized by sampling
 `thermalize` times before any measurements are made.

Indexing the result at `(α, β, q1, ..., qd)` gives ``𝒮^{αβ}(𝐪)`` at
    `𝐪 = q1 * a⃰ + q2 * b⃰ + q3 * c⃰`, where `a⃰, b⃰, c⃰`
    are the reciprocal lattice vectors of the system supercell.

Allowed values for the `qi` indices lie in `-div(Qi, 2):div(Qi, 2, RoundUp)`.
"""
function static_structure_factor(sys::SpinSystem, sampler::S; kwargs...) where {S <: AbstractSampler}
    dynamic_structure_factor(sys, sampler; num_ωs=1, kwargs...)
end


#= Non-exposed internal functions below =#

"""
    plan_spintraj_fft(spin_traj::Array{Vec3})

Prepares an out-of-place FFT plan for a spin trajectory array of
size [D1, ..., Dd, B, T]
"""
function plan_spintraj_fft(spin_traj::Array{Vec3})
    spin_traj = _reinterpret_from_spin_array(spin_traj)
    return FFTW.plan_fft!(spin_traj, (2,3,4,6))  # After reinterpret, indices 2, 3, 4 and 6 correspond to a, b, c and time.
end

"""
    plan_spintraj_fft!(spin_traj::Array{ComplexF64})

Prepares an in-place FFT plan for a spin trajectory array of
size [3, D1, ..., Dd, B, T].
"""
function plan_spintraj_fft!(spin_traj::Array{ComplexF64})
    return FFTW.plan_fft!(spin_traj, (2,3,4,6))  #Indices 2, 3, 4 and 6 correspond to a, b, c and time.
end

"""
    fft_spin_traj!(res, spin_traj; plan=nothing)

In-place version of `fft_spin_traj`. `res` should be an `Array{ComplexF64}` of size
`[3, D1, ..., Dd, B, T]` to hold the result, matching the size `[D1, ..., Dd, B, T]`
of `spin_traj`.
"""
function fft_spin_traj!(res::Array{ComplexF64}, spin_traj::Array{Vec3};
                        plan::Union{Nothing, FFTW.cFFTWPlan}=nothing)
    @assert size(res) == tuplejoin(3, size(spin_traj)) "fft_spins size not compatible with spin_traj size"

    # Reinterpret array to add the spin dimension explicitly
    # Now of shape [3, D1, ..., Dd, B, T]
    spin_traj = _reinterpret_from_spin_array(spin_traj)

    # FFT along the spatial indices, and the time index
    if isnothing(plan)
        res .= spin_traj
        FFTW.fft!(res, (2,3,4,6))
    else
        mul!(res, plan, spin_traj)
    end    

    return res
end

function fft_spin_traj!(spin_traj::Array{ComplexF64};
                        plan::Union{Nothing, FFTW.cFFTWPlan}=nothing)
    if isnothing(plan)
        FFTW.fft!(spin_traj, (2,3,4,6))
    else
        spin_traj = plan * spin_traj
    end
end

"""
    fft_spin_traj(spin_traj; bz_size, plan=nothing)

Takes in a `spin_traj` array of spins (Vec3) of shape `[D1, ..., Dd, B, T]`,  
 with `D1 ... Dd` being the spatial dimensions, B the sublattice index,
 and `T` the time axis.
Computes and returns an array of the shape `[3, D1, ..., Dd, B, T]`,
 holding spatial and temporal fourier transforms ``S^α_b(𝐪, ω)``. The spatial
 fourier transforms are done periodically, but the temporal axis is
 internally zero-padded to avoid periodic contributions. *(Avoiding
 periodic artifacts not implemented yet)*
"""
function fft_spin_traj(spin_traj::Array{Vec3};
                       plan::Union{Nothing, FFTW.cFFTWPlan}=nothing)
    fft_spins = zeros(ComplexF64, 3, size(spin_traj)...)
    fft_spin_traj!(fft_spins, spin_traj; plan=plan)
end

""" 
    phase_weight_basis(spin_traj_ft, bz_size, lattice)

Combines the sublattices of `spin_traj_ft` with the appropriate phase factors, producing
 the quantity ``S^α(𝐪, ω)`` within the number of Brillouin zones requested by `bz_size`.
Specifically, computes:

``S^α(𝐪, ω) = ∑_b e^{-i𝐫_b ⋅ 𝐪} S^α_b(𝐪, ω)``

where ``b`` is the basis index and ``𝐫_b`` is the associated basis vector.
``S^α_b(𝐪, ω)`` is periodically repeated past the first Brillouin zone,
but the resulting ``S^α(𝐪, ω)`` will not necessarily be periodic.
"""
function phase_weight_basis(spin_traj_ft::Array{ComplexF64},
                            lattice::Lattice, bz_size=nothing)
    if isnothing(bz_size)
        bz_size = ones(ndims(lattice) - 1)
    end

    bz_size = convert(SVector{3, Int}, bz_size)                  # Number of Brilloin zones along each axis
    spat_size = lattice.size                                     # Spatial lengths of the system
    num_ωs = size(spin_traj_ft)[end]
    min_ω = -1 .* div(num_ωs - 1, 2)
    q_size = map(s -> s == 0 ? 1 : s, bz_size .* spat_size)      # Total number of q-points along each q-axis of result
    result_size = (3, q_size..., num_ωs)
    min_q_idx = -1 .* div.(q_size .- 1, 2)

    result = zeros(ComplexF64, result_size)
    result = OffsetArray(result, Origin(1, min_q_idx..., min_ω))
    phase_weight_basis!(result, spin_traj_ft, lattice)
end

"""
    phase_weight_basis!(res, spin_traj_ft, lattice)

Like `phase_weight_basis`, but in-place. Infers `bz_size` from `size(res)`.
"""
function phase_weight_basis!(res::OffsetArray{ComplexF64},
                             spin_traj_ft::Array{ComplexF64},
                             lattice::Lattice)
    # Check that spatial size of spin_traj_ft same as spatial size of lattice
    spat_size = size(lattice)[1:3]
    valid_size = size(spin_traj_ft)[2:4] == spat_size
    @assert valid_size "`size(spin_traj_ft)` not compatible with `lattice`"
    # Check that q_size is elementwise either an integer multiple of spat_size, or is 1.
    q_size = size(res)[2:4]
    valid_q_size = all(map((qs, ss) -> qs % ss == 0 || qs == 1, q_size, spat_size))
    @assert valid_q_size "`size(res)` not compatible with `size(spin_traj_ft)`"

    recip = gen_reciprocal(lattice)

    num_ωs = size(spin_traj_ft)[end]
    min_ω = -1 .* div(num_ωs - 1, 2)
    max_ω = min_ω + num_ωs - 1

    fill!(res, 0.0)
    for q_idx in CartesianIndices(axes(res)[2:4])
        q = recip.lat_vecs * Vec3(Tuple(q_idx) ./ lattice.size)
        wrap_q_idx = modc(q_idx, spat_size) + one(CartesianIndex{3})
        for (b_idx, b) in enumerate(lattice.basis_vecs)
            phase = exp(-im * (b ⋅ q))
            # Note: Lots of allocations here. Fix?
            # Warning: Cannot replace T with 1:end due to Julia issues with end and CartesianIndex
            @. res[:, q_idx, min_ω:-1] += @view(spin_traj_ft[:, wrap_q_idx, b_idx, max_ω+2:num_ωs]) * phase
            @. res[:, q_idx, 0:max_ω] += @view(spin_traj_ft[:, wrap_q_idx, b_idx, 1:max_ω+1]) * phase
        end
    end

    return res
end

# === Helper functions for outerprod_conj === #

# TODO: Bounds checking
""" Given `size`, compute a new size tuple where there is an extra `1` before each dim in `dims`.
"""
function _outersizeα(size, dims)
    if length(dims) == 0
        return size
    end

    newsize = tuplejoin(size[1:dims[1]-1], 1)
    for i in 2:length(dims)
        newsize = tuplejoin(newsize, size[dims[i-1]:dims[i]-1], 1)
    end
    tuplejoin(newsize, size[dims[end]:end])
end

""" Given `size`, compute a new size tuple where there is an extra `1` after each dim in `dims`.
"""
_outersizeβ(size, dims) = length(dims) == 0 ? size : _outersizeα(size, dims .+ 1)

# ========================================== #

"""
    outerprod_conj(S, [dims=1])

Computes the outer product along the selected dimensions, with a complex
conjugation on the second copy in the product.

I.e. given a complex array of size `[D1, ..., Di, ..., Dd]`, for each
dimension `i` in `dims` this will create a new axis of the same size to make an
array of size `[D1, ..., Di, Di, ..., Dd]` where the new axes are formed by
an outer product of the vectors of the original axes with a complex conjugation
on one copy.
"""
function outerprod_conj(S, dims=1)
    sizeα = _outersizeα(axes(S), dims)
    sizeβ = _outersizeβ(axes(S), dims)
    Sα = reshape(S, sizeα)
    Sβ = reshape(S, sizeβ)
    @. Sα * conj(Sβ)
end

"""
    outerprod_conj!(res, S, [dims=1])

Like `outerprod_conj`, but accumulates the result in-place into `res`.
"""
function outerprod_conj!(res, S, dims=1)
    sizeα = _outersizeα(axes(S), dims)
    sizeβ = _outersizeβ(axes(S), dims)
    Sα = reshape(S, sizeα)
    Sβ = reshape(S, sizeβ)
    @. res += Sα * conj(Sβ)
end

"""
    expand_bz!(res::OffsetArray, S::Array)

Copy S periodically into res, with the periodic boundaries set by the
spatial axes of S. Assumes that S is of shape [3, L1, L2, L3, B, T], and
that res is of shape [3, Q1, Q2, Q3, B, T], with all Qi >= Li.
"""
function expand_bz!(res::OffsetArray{ComplexF64}, S::Array{ComplexF64})
    spat_size = size(S)[2:4]
    num_ωs  = size(S, ndims(S))
    min_ω = -1 .* div(num_ωs - 1, 2)
    max_ω = min_ω + num_ωs - 1

    for ω in min_ω:max_ω 
        for q_idx in CartesianIndices(axes(res)[2:4])
            wrap_q_idx = modc(q_idx, spat_size) + CartesianIndex(1, 1, 1)
            ω_no_offset = ω < 0 ? ω + num_ωs : ω + 1
            res[:, q_idx, :, ω] = S[:, wrap_q_idx, :, ω_no_offset]
        end
    end
end

#= These two "accumulate with dipole factor" functions are so close that it seems
    like they should be joined, but I cannot think of a clever way to do so.
=#

"""
    accum_dipole_factor!(res, S, lattice)

Given complex `S` of size [3, Q1, ..., QD, T] and `res` of size [Q1, ..., QD, T],
accumulates the structure factor from `S` with the dipole factor applied into `res`.
"""
function accum_dipole_factor!(res, S, lattice::Lattice)
    recip = gen_reciprocal(lattice)
    for q_idx in CartesianIndices(axes(res)[1:3])
        q = recip.lat_vecs * Vec3(Tuple(q_idx) ./ lattice.size)
        q = q / (norm(q) + 1e-12)
        dip_factor = I(3) - q * q'

        for α in 1:3
            for β in 1:3
                dip_elem = dip_factor[α, β]
                @. res[q_idx, :] += dip_elem * real(S[α, q_idx, :] * conj(S[β, q_idx, :]))
            end
        end
    end
end

"""
    accum_dipole_factor_wbasis!(res, S, lattice)

Given complex `S` of size [3, Q1, ..., QD, B, T] and real `res` of size [Q1, ..., QD, B, B, T],
accumulates the structure factor from `S` with the dipole factor applied into `res`.
"""
function accum_dipole_factor_wbasis!(res, S, lattice::Lattice)
    recip = gen_reciprocal(lattice)
    nb = nbasis(lattice)
    Sα = reshape(S, _outersizeα(axes(S), 5))  # Size [3,..., 1, B, T] 
    Sβ = reshape(S, _outersizeβ(axes(S), 5))  # Size [3,..., B, 1, T] 

    for q_idx in CartesianIndices(axes(res)[1:3])
        q = recip.lat_vecs * Vec3(Tuple(q_idx) ./ lattice.size)
        q = q / (norm(q) + 1e-12)
        dip_factor = I(3) - q * q'

        for α in 1:3
            for β in 1:3
                dip_elem = dip_factor[α, β]
                @. res[q_idx, :, :, :] += dip_elem * real(Sα[α, q_idx, :, :, :] * Sβ[β, q_idx, :, :, :])
            end
        end
    end
end

#========== Form factor ==========#

""" 
    form_factor(q::Vector{Float64}, elem::String, lande::Bool=false)

Compute the form factors for a list of momentum space magnitudes `q`, measured
in inverse angstroms. The result is dependent on the magnetic ion species,
`elem`. By default, a first order form factor ``f`` is returned. If `lande=true`
is set, and `elem` is suitable, then a second order form factor ``F`` is
returned. The form factor accounts for the fact that the magnetic moments are
perfectly localized at a point, but instead have some spread.
        
It is traditional to define the form factors using a sum of Gaussian broadening
functions in the scalar variable ``s = q/4π``, where ``q`` can be interpreted as
the magnitude of momentum transfer.

The Neutron Data Booklet, 2nd ed., Sec. 2.5 Magnetic Form Factors, defines the
approximation

`` \\langle j_l(s) \\rangle = A e^{-as^2} + B e^{-bs^2} + Ce^{-cs^2} + D, ``

where coefficients ``A, B, C, D, a, b, c`` are obtained from semi-empirical
fits, depending on the orbital angular momentum index ``l = 0, 2``. For
transition metals, the form-factors are calculated using the Hartree-Fock
method. For rare-earth metals and ions, Dirac-Fock form is used for the
calculations.

A first approximation to the magnetic form factor is

``f(s) = \\langle j_0(s) \\rangle``

A second order correction is given by

``F(s) = \\frac{2-g}{g} \\langle j_2(s) \\rangle s^2 + f(s)``, where ``g`` is
the Landé g-factor.  

Digital tables are available at:

* https://www.ill.eu/sites/ccsl/ffacts/ffachtml.html

Additional references are:

 * Marshall W and Lovesey S W, Theory of thermal neutron scattering Chapter 6
   Oxford University Press (1971)
 * Clementi E and Roetti C,  Atomic Data and Nuclear Data Tables, 14 pp 177-478
   (1974)
 * Freeman A J and Descleaux J P, J. Magn. Mag. Mater., 12 pp 11-21 (1979)
 * Descleaux J P and Freeman A J, J. Magn. Mag. Mater., 8 pp 119-129 (1978) 
"""
function form_factor(q::AbstractArray{Float64}, elem::String, lande::Bool=false)
    # Lande g-factors
    g_dict = Dict{String,Float64}(
        "La3"=>0,
        "Ce3"=>6/7,
        "Pr3"=>4/5,
        "Nd3"=>8/11, 
        "Pm3"=>3/5,
        "Sm3"=>2/7,
        "Eu3"=>0,
        "Gd3"=>2, 
        "Tb3"=>3/2, 
        "Dy3"=>4/3, 
        "Ho3"=>5/4, 
        "Er3"=>6/5, 
        "Tm3"=>7/6, 
        "Yb3"=>8/7, 
        "Lu3"=>0, 
        "Ti3"=>4/5, 
        "V4"=>4/5, 
        "V3"=>2/3, 
        "V2"=>2/5, 
        "Cr3"=>2/5, 
        "Mn4"=>2/5, 
        "Cr2"=>0, 
        "Mn3"=>0, 
        "Mn2"=>2, 
        "Fe3"=>2, 
        "Fe2"=>3/2, 
        "Co3"=>3/2,
        "Co2"=>4/3,
        "Ni2"=>5/4,
        "Cu2"=>6/5,
        "Zn2"=>0
    )
    
    function calculate_form(elem, datafile, s)
        path = joinpath(joinpath(@__DIR__, "data"), datafile)
        lines = collect(eachline(path))
        matches = filter(line -> startswith(line, elem), lines)
        if isempty(matches)
            error("Invalid magnetic ion '$elem'.")
        end
        (A, a, B, b, C, c, D) = parse.(Float64, split(matches[1])[2:end])
        return @. A*exp(-a*s^2) + B*exp(-b*s^2) + C*exp(-c*s^2) + D
    end

    s = q/4π 
    form1 = calculate_form(elem, "form_factor_J0.dat", s)
    form2 = calculate_form(elem, "form_factor_J2.dat", s)

    if lande
        if !haskey(g_dict, elem)
            error("Landé g-factor correction not available for ion '$elem'.")
        end
        g = g_dict[elem]
        if iszero(g)
            error("Second order form factor is invalid for vanishing Landé g-factor.")
        end
        return @. ((2-g)/g) * (form2*s^2) + form1
    else
        return form1
    end
end


q_idcs(sf::StructureFactor) = sf.dipole_factor ? (1:3) : (3:5)

## Need to figure out nicer way of doing multiple slices, the index of which
## depend on the type of structure factor calculation. Probably can right some
## tuple-building function.

function apply_form_factor!(res::OffsetArray, sf::StructureFactor, elem::String, lande::Bool=false)
    axs = axes(sf.sfactor)[q_idcs(sf)]
    qs = [norm(2π .* i.I ./ sf.lattice.size) for i in CartesianIndices(axs)]
    ff = form_factor(qs, elem, lande) 

    @inbounds if sf.reduce_basis
        if sf.dipole_factor
            for i in CartesianIndices(axs)
                @. res[i, :] = @views sf.sfactor[i, :] * ff[i]
            end
        else
            for i in CartesianIndices(axs)
                @. res[:, :, i, :] = @views sf.sfactor[:, :, i, :] * ff[i]
            end
        end
    else
        if sf.dipole_factor
            for i in CartesianIndices(axs)
                @. res[i, :, :, :] = @views sf.sfactor[i, :, :, :] * ff[i]
            end
        else
            for i in CartesianIndices(axs)
                @. res[:, :, i, :, :, :] = @views sf.sfactor[:, :, i, :, :, :] * ff[i]
            end
        end
    end

    nothing
end

apply_form_factor!(sf::StructureFactor, elem::String, lande::Bool=false) = apply_form_factor!(sf.sfactor, sf, elem, lande)

@doc raw"""
    apply_form_factor(sf::StructureFactor, elem::String, lande::Bool=false)

Applies the form factor correction to the structure factor `sf`. See `form_fractor`
for more details.
"""
function apply_form_factor(sf::StructureFactor, elem::String, lande::Bool=false)
    res = similar(sf.sfactor)
    apply_form_factor!(res, sf, elem, lande)
    return res
end



#========== Structure factor slices ==========#

@doc raw"""
    q_labels(sf::StructureFactor)

Returns the coordinates in momentum space corresponding to the three
Q indices of the structure factor.
"""
function q_labels(sf::StructureFactor)
    axs = axes(sf.sfactor)[q_idcs(sf)]
    return [map(i -> 2π*i/sf.lattice.size[a], axs[a]) for a in 1:3]
end

@doc raw"""
    ω_labels(sf::StructureFactor)

Returns the energies corresponding to the indices of the ω index. Units will
will be the same as those used to specify the Hamiltonian parameters (meV by default).
"""
function ω_labels(sf::StructureFactor)
    (; meas_period, num_ωs, Δt) = sf
    Δω = 2π/(Δt*meas_period*num_ωs)
    return map(i -> Δω*i, axes(sf.sfactor)[end])
end


@doc raw"""
    slice(sf::StructureFactor, points::Vector;
        interp_method = BSpline(Linear(Periodic())),
        interp_scale = 1, return_idcs=false)

Returns a slice through the structure factor `sf`. The slice is generated
along a linear path successively connecting each point in `points`.
`points` must be a vector containing at least two points. For example: 
`points = [(0, 0, 0), (π, 0, 0), (π, π, 0)]`.

If `return_idcs` is set to `true`, the function will also return the indices
of the slice that correspond to each point of `points`.

If `interp_scale=1` and the paths are parallel to one of the reciprocal
lattice vectors (e.g., (0,0,0) -> (π,0,0)), or strictly diagonal
(e.g., (0,0,0) -> (π,π,0)), then no interpolation is performed. If
`interp_scale` is set to a value greater than 1, then the function will interpolate
linearly between data points. For example, setting `interp_scale` to `2`` will
result in a slice that contains twice as many points as could be drawn
for the structure factor without interpolation.

The interpolation method is linear by default but may be set to
any scheme provided by the Interpolations.jl package. Simply set
the keyword `interp_method` to the desired method.
"""
# Write for reduce_basis=true, dipole_factor=true case first
function sf_slice(sf::StructureFactor, points::Vector;
    interp_method = BSpline(Linear(Periodic())),
    interp_scale = 1, return_idcs=false,
)
    function wrap(val::Float64, bounds::Tuple{Float64, Float64})
        offset = bounds[1]
        bound′ = bounds[2] - offset 
        val′ = val - offset
        remainder = rem(val′, bound′)

        # Avoid artifical wrapping due to floating point arithmetic
        return  remainder < 1e-12 ? bounds[2] : remainder + offset
    end

    function path_points(p1::Vec3, p2::Vec3, densities, bounds; interp_scale=1)
        v = p2 - p1
        steps_coords = v .* densities # Convert continuous distances into number of discrete steps

        # In terms of a discrete path on cells, the minimal number of steps between two cells
        # is equal to the maximum of the differences between the respective coordinates.
        nsteps = (round(Int, maximum(abs.(steps_coords))) + 1) * interp_scale

        # Create linear series of points between boundaries
        v = v ./ (nsteps-1) 
        ps = [p1 + (k * v) for k in 0:nsteps-1]

        # Periodically wrap coordinates that exceed that contained in the SF
        return map(ps) do p
            (wrap(p[i], bounds[i]) for i in 1:3)
        end
    end

    @assert length(size(sf.sfactor)) == 4 "Currently can only take slices from structures factors with reduced basis and dipole_factors"
    sfdata = parent(sf.sfactor)
    points = Vec3.(points) # Convert to uniform type

    # Consolidate data necessary for the interpolation
    q_vals = q_labels(sf) 
    ωs = ω_labels(sf)
    dims = size(sfdata)[q_idcs(sf)]

    q_bounds = [(first(qs), last(qs)) for qs in q_vals] # Upper and lower bounds in momentum space (depends on number of BZs)
    q_dens = [dims[i]/(2bounds[2]) for (i, bounds) in enumerate(q_bounds)] # Discrete steps per unit distance in momentum space
    q_scales = [range(bounds..., length=dims[i]) for (i, bounds) in enumerate(q_bounds)] # Values for scaled interpolation
    ω_scale = range(first(ωs), last(ωs), length=length(ωs))

    # Create interpolant
    itp = interpolate(sfdata, interp_method)
    sitp = scale(itp, q_scales..., ω_scale)

    # Pull each partial slice (each leg of the cut) from interpolant
    slices = []
    for i in 1:length(points)-1
        ps = path_points(points[i], points[i+1], q_dens, q_bounds; interp_scale)
        slice = zeros(eltype(sf.sfactor), length(ps), length(ωs))
        for (i, p) in enumerate(ps)
            slice[i,:] = sitp(p..., ωs)
        end
        push!(slices, i > 1 ? slice[2:end,:] : slice) # Avoid repeated points
    end

    # Stitch slices together
    slice_dims = [size(slice, 1) for slice in slices]
    idcs = [1]
    for (i, dim) in enumerate(slice_dims[1:end])
        push!(idcs, idcs[i] + dim)
    end
    slice = OffsetArray(vcat(slices...), Origin(1, ωs.offsets[1] + 1))

    return_idcs && (return (; slice, idcs))
    return slice
end

