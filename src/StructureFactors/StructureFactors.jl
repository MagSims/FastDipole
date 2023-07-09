struct StructureFactor{N}
    # 𝒮^{αβ}(q,ω) data and metadata
    data           :: Array{ComplexF64, 7}   # Raw SF data for 1st BZ (numcorrelations × natoms × natoms × latsize × energy)
    crystal        :: Crystal                # Crystal for interpretation of q indices in `data`
    origin_crystal :: Union{Nothing,Crystal} # Original user-specified crystal (if different from above)
    Δω             :: Float64                # Energy step size

    # Correlation info (αβ indices of 𝒮^{αβ}(q,ω))
    observables  :: Vector{LinearMap} # Operators corresponding to observables
    observable_ixs :: Dict{Symbol,Int64} # User-defined observable names
    correlations :: SortedDict{CartesianIndex{2}, Int64}  # (α, β) to save from 𝒮^{αβ}(q, ω)

    # Specs for sample generation and accumulation
    samplebuf    :: Array{ComplexF64, 6}  # New sample buffer
    fft!         :: FFTW.AbstractFFTs.Plan # Pre-planned FFT
    copybuf      :: Array{ComplexF64, 4}  # Copy cache for accumulating samples
    measperiod   :: Int                   # Steps to skip between saving observables (downsampling for dynamical calcs)
    apply_g      :: Bool                  # Whether to apply the g-factor
    integrator   :: ImplicitMidpoint      # Integrator for dissipationless trajectories (will likely move to add_sample!)
    nsamples     :: Array{Int64, 1}       # Number of accumulated samples (array so mutable)
    processtraj! :: Function              # Function to perform post-processing on sample trajectories
end

function Base.show(io::IO, ::MIME"text/plain", sf::StructureFactor)
    printstyled(io, "StructureFactor";bold=true, color=:underline)
    print(io," ($(Base.format_bytes(Base.summarysize(sf))))\n")
    print(io,"[")
    if size(sf.data)[7] == 1
        printstyled(io,"S(q)";bold=true)
    else
        printstyled(io,"S(q,ω)";bold=true)
        print(io," | nω = $(size(sf.data)[7])")
    end
    print(io," | $(sf.nsamples[1]) sample")
    (sf.nsamples[1] > 1) && print(io,"s")
    print(io,"]\n")
    print(io,"$(size(sf.data)[1]) correlations on $(sf.latsize) lattice:\n")

    # Reverse the dictionary
    observable_names = Dict(value => key for (key, value) in sf.observable_ixs)

    for i = 1:length(sf.observables)
        print(io,i == 1 ? "╔ " : i == length(sf.observables) ? "╚ " : "║ ")
        for j = 1:length(sf.observables)
            if i > j
                print(io,"⋅ ")
            elseif haskey(sf.correlations,CartesianIndex(i,j))
                print(io,"⬤ ")
            else
                print(io,"• ")
            end
        end
        print(io,observable_names[i])
        println(io)
    end
    printstyled(io,"")
end

Base.getproperty(sf::StructureFactor, sym::Symbol) = sym == :latsize ? size(sf.samplebuf)[2:4] : getfield(sf,sym)

"""
    merge!(sf::StructureFactor, others...)

Accumulate the samples in `others` (one or more `StructureFactors`) into `sf`.
"""
function merge!(sf::StructureFactor, others...)
    for sfnew in others
        nnew = sfnew.nsamples[1]
        ntotal = sf.nsamples[1] + nnew
        @. sf.data = sf.data + (sfnew.data - sf.data) * (nnew/ntotal)
        sf.nsamples[1] = ntotal
    end
end

# Finds the linear index according to sf.correlations of each correlation in corrs, where
# corrs is of the form [(:A,:B),(:B,:C),...] where :A,:B,:C are observable names.
function lookup_correlations(sf::StructureFactor,corrs; err_msg = αβ -> "Missing correlation $(αβ)")
    indices = Vector{Int64}(undef,length(corrs))
    for (i,(α,β)) in enumerate(corrs)
        αi = sf.observable_ixs[α]
        βi = sf.observable_ixs[β]
        # Make sure we're looking up the correlation with its properly sorted name
        αi,βi = minmax(αi,βi)
        idx = CartesianIndex(αi,βi)

        # Get index or fail with an error
        indices[i] = get!(() -> error(err_msg(αβ)),sf.correlations,idx)
    end
    indices
end

"""
    StructureFactor

An object holding ``𝒮(𝐪,ω)`` or ``𝒮(𝐪)`` data. Construct a `StructureFactor`
using [`DynamicStructureFactor`](@ref) or [`InstantStructureFactor`](@ref),
respectively.
"""
function StructureFactor(sys::System{N}; Δt, nω, measperiod,
                            apply_g = true, observables = nothing, correlations = nothing,
                            process_trajectory = :none) where {N}

    # Set up correlation functions (which matrix elements αβ to save from 𝒮^{αβ})
    if isnothing(observables)
        # Default observables are spin x,y,z
        # projections (SU(N) mode) or components (dipole mode)
        observable_ixs = Dict(:Sx => 1,:Sy => 2,:Sz => 3)
        if N == 0
            dipole_component(i) = FunctionMap{Float64}(s -> s[i],1,3)
            observables = dipole_component.([1,2,3])
        else
            # SQTODO: Make this use the more optimized expected_spin function
            # Doing this will also, by necessity, allow users to make the same
            # type of optimization for their vector-valued observables.
            observables = LinearMap{ComplexF64}.(spin_matrices(N))
        end
    else
        # If it was given as a list, preserve the user's preferred
        # ordering of observables
        if observables isa AbstractVector
            # If they are pairs (:A => [...]), use the names
            # and otherwise use alphabetical names
            if !isempty(observables) && observables[1] isa Pair
                observables = OrderedDict(observables)
            else
                dict = OrderedDict{Symbol,LinearMap}()
                for i = 1:length(observables)
                    dict[Symbol('A' + i - 1)] = observables[i]
                end
                observables = dict
            end
        end

        # If observables were provided as (:name => matrix) pairs,
        # reformat them to (:name => idx) and matrices[idx]
        observable_ixs = Dict{Symbol,Int64}()
        matrices = Vector{LinearMap}(undef,length(observables))
        for (i,name) in enumerate(keys(observables))
            next_available_ix = length(observable_ixs) + 1
            if haskey(observable_ixs,name)
                error("Repeated observable name $name not allowed.")
            end
            observable_ixs[name] = next_available_ix

            # Convert dense matrices to LinearMap
            if observables[name] isa Matrix
                matrices[i] = LinearMap(observables[name])
            else
                matrices[i] = observables[name]
            end
        end
        observables = matrices
    end

    # By default, include all correlations
    if isnothing(correlations)
        correlations = []
        for oi in keys(observable_ixs), oj in keys(observable_ixs)
            push!(correlations, (oi, oj))
        end
    elseif correlations isa AbstractVector{Tuple{Int64,Int64}}
        # If the user used numeric indices to describe the correlations,
        # we need to convert it to the names, so need to temporarily reverse
        # the dictionary.
        observable_names = Dict(value => key for (key, value) in observable_ixs)
        correlations = [(observable_names[i],observable_names[j]) for (i,j) in correlations]
    end

    # Construct look-up table for correlation matrix elements
    idxinfo = SortedDict{CartesianIndex{2},Int64}() # CartesianIndex's sort to fastest order
    for (α,β) in correlations
        αi = observable_ixs[α]
        βi = observable_ixs[β]
        # Because correlation matrix is symmetric, only save diagonal and upper triangular
        # by ensuring that all pairs are in sorted order
        αi,βi = minmax(αi,βi)
        idx = CartesianIndex(αi,βi)

        # Add this correlation to the list if it's not already listed
        get!(() -> length(idxinfo) + 1,idxinfo,idx)
    end
    correlations = idxinfo

    # Set up trajectory processing function (e.g., symmetrize)
    processtraj! = if process_trajectory == :none 
        no_processing
    elseif process_trajectory == :symmetrize
        symmetrize!
    elseif process_trajectory == :subtract_mean
        subtract_mean!
    else
        error("Unknown argument for `process_trajectory`")
    end

    # Preallocation
    na = natoms(sys.crystal)
    ncorr = length(correlations)
    samplebuf = zeros(ComplexF64, length(observables), sys.latsize..., na, nω) 
    copybuf = zeros(ComplexF64, sys.latsize..., nω) 
    data = zeros(ComplexF64, ncorr, na, na, sys.latsize..., nω)

    # Normalize FFT according to physical convention
    normalizationFactor = 1/(nω * √(prod(sys.latsize)))
    fft! = normalizationFactor * FFTW.plan_fft!(samplebuf, (2,3,4,6))

    # Other initialization
    nsamples = Int64[0]
    integrator = ImplicitMidpoint(Δt)
    Δω = nω == 1 ? 0.0 : 2π / (Δt*measperiod*nω)
    origin_crystal = !isnothing(sys.origin) ? sys.origin.crystal : nothing

    # Make Structure factor and add an initial sample
    sf = StructureFactor{N}(data, sys.crystal, origin_crystal, Δω,
                            observables, observable_ixs, correlations, samplebuf, fft!, copybuf, measperiod, apply_g, integrator,
                            nsamples, processtraj!)
    add_sample!(sf, sys; processtraj!)

    return sf
end


"""
    DynamicStructureFactor(sys::System; Δt, nω, ωmax, 
        process_trajectory=:none, observables=nothing, correlations=nothing) 

Creates a `StructureFactor` for calculating and storing ``𝒮(𝐪,ω)`` data. This
information will be obtained by running dynamical spin simulations on
equilibrium snapshots, and measuring pair-correlations. The ``𝒮(𝐪,ω)`` data
can be retrieved by calling [`intensities_interpolated`](@ref). Alternatively,
[`instant_intensities_interpolated`](@ref) will integrate out ``ω`` to obtain ``𝒮(𝐪)``,
optionally applying classical-to-quantum correction factors.
        
Prior to calling `DynamicStructureFactor`, ensure that `sys` represents a good
equilibrium sample. Additional sample data may be accumulated by calling
[`add_sample!`](@ref)`(sf, sys)` with newly equilibrated `sys` configurations.

Three keywords are required to specify the dynamics used for the trajectory
calculation.

- `Δt`: The time step used for calculating the trajectory from which dynamic
    spin-spin correlations are calculated. The trajectories are calculated with
    an [`ImplicitMidpoint`](@ref) integrator.
- `ωmax`: The maximum energy, ``ω``, that will be resolved.
- `nω`: The number of energy bins to calculated between 0 and `ωmax`.

Additional keyword options are the following:
- `process_trajectory`: Specifies a function that will be applied to the sample
    trajectory before correlation analysis. Current options are `:none` and
    `:symmetrize`. The latter will symmetrize the trajectory in time, which can
    be useful for removing Fourier artifacts that arise when calculating the
    correlations.
- `observables`: Allows the user to specify custom observables. The `observables`
    must be given as a list of complex `N×N` matrices or `LinearMap`s. It's
    recommended to name each observable, for example:
    `observables = [:A => a_observable_matrix, :B => b_map, ...]`.
    By default, Sunny uses the 3 components of the dipole, `:Sx`, `:Sy` and `:Sz`.
- `correlations`: Specify which correlation functions are calculated, i.e. which
    matrix elements ``αβ`` of ``𝒮^{αβ}(q,ω)`` are calculated and stored.
    Specified with a vector of tuples. By default Sunny records all auto- and
    cross-correlations generated by all `observables`.
    To retain only the xx and xy correlations, one would set
    `correlations=[(:Sx,:Sx), (:Sx,:Sy)]` or `correlations=[(1,1),(1,2)]`.
"""
function DynamicStructureFactor(sys::System; Δt, nω, ωmax, kwargs...) 
    nω = Int64(nω)
    @assert π/Δt > ωmax "Desired `ωmax` not possible with specified `Δt`. Choose smaller `Δt` value."
    measperiod = floor(Int, π/(Δt * ωmax))
    nω = 2nω-1  # Ensure there are nω _non-negative_ energies
    StructureFactor(sys; Δt, nω, measperiod, kwargs...)
end


"""
    InstantStructureFactor(sys::System; process_trajectory=:none,
                            observables=nothing, correlations=nothing) 

Creates a `StructureFactor` object for calculating and storing instantaneous
structure factor intensities ``𝒮(𝐪)``. This data will be calculated from the
spin-spin correlations of equilibrium snapshots, absent any dynamical
information. ``𝒮(𝐪)`` data can be retrieved by calling
[`instant_intensities_interpolated`](@ref).

_Important note_: When dealing with continuous (non-Ising) spins, consider
creating a full [`DynamicStructureFactor`](@ref) object instead of an
`InstantStructureFactor`. The former will provide full ``𝒮(𝐪,ω)`` data, from
which ``𝒮(𝐪)`` can be obtained by integrating out ``ω``. During this
integration step, Sunny can incorporate temperature- and ``ω``-dependent
classical-to-quantum correction factors to produce more accurate ``𝒮(𝐪)``
estimates. See [`instant_intensities_interpolated`](@ref) for more information.

Prior to calling `InstantStructureFactor`, ensure that `sys` represents a good
equilibrium sample. Additional sample data may be accumulated by calling
[`add_sample!`](@ref)`(sf, sys)` with newly equilibrated `sys` configurations.

The following optional keywords are available:

- `process_trajectory`: Specifies a function that will be applied to the sample
    trajectory before correlation analysis. Current options are `:none` and
    `:symmetrize`. The latter will symmetrize the trajectory in time, which can
    be useful for removing Fourier artifacts that arise when calculating the
    correlations.
- `observables`: Allows the user to specify custom observables. The `observables`
    must be given as a list of complex `N×N` matrices or `LinearMap`s. It's
    recommended to name each observable, for example:
    `observables = [:A => a_observable_matrix, :B => b_map, ...]`.
    By default, Sunny uses the 3 components of the dipole, `:Sx`, `:Sy` and `:Sz`.
- `correlations`: Specify which correlation functions are calculated, i.e. which
    matrix elements ``αβ`` of ``𝒮^{αβ}(q,ω)`` are calculated and stored.
    Specified with a vector of tuples. By default Sunny records all auto- and
    cross-correlations generated by all `observables`.
    To retain only the xx and xy correlations, one would set
    `correlations=[(:Sx,:Sx), (:Sx,:Sy)]` or `correlations=[(1,1),(1,2)]`.
"""
function InstantStructureFactor(sys::System; kwargs...)
    StructureFactor(sys; Δt=0.1, nω=1, measperiod=1, kwargs...)
end
