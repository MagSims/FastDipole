
"""
    BinningParameters(binstart,binend,binwidth;covectors = I(4))
    BinningParameters(binstart,binend;numbins,covectors = I(4))

Describes a 4D parallelepided histogram in a format compatible with experimental Inelasitic Neutron Scattering data.
See [`generate_mantid_script_from_binning_parameters`](@ref) to convert [`BinningParameters`](@ref) to a format understandable by the [Mantid software](https://www.mantidproject.org/), or [`load_nxs`](@ref) to load [`BinningParameters`](@ref) from a Mantid `.nxs` file.
 
The coordinates of the histogram axes are specified by multiplication 
of `(q,ω)` with each row of the `covectors` matrix, with `q` given in [R.L.U.].
Since the default `covectors` matrix is the identity matrix, the default axes are
`(qx,qy,qz,ω)` in absolute units.

The convention for the binning scheme is that:
- The left edge of the first bin starts at `binstart`
- The bin width is `binwidth`
- The last bin contains `binend`
- There are no "partial bins;" the last bin may contain values greater than `binend`. C.f. [`count_bins`](@ref).

A `value` can be binned by computing its bin index:

    coords = covectors * value
    bin_ix = 1 .+ floor.(Int64,(coords .- binstart) ./ binwidth)
"""
mutable struct BinningParameters
    binstart::MVector{4,Float64}
    binend::MVector{4,Float64}
    binwidth::MVector{4,Float64}
    covectors::MMatrix{4,4,Float64}
end
# TODO: Use the more efficient three-argument `div(a,b,RoundDown)` instead of `floor(a/b)`
# to implement binning. Both performance and correctness need to be checked.

function Base.show(io::IO, ::MIME"text/plain", params::BinningParameters)
    printstyled(io, "Binning Parameters\n"; bold=true, color=:underline)
    nbin = params.numbins
    for k = 1:4
        if nbin[k] == 1
            printstyled(io, "∫ Integrated"; bold=true)
        else
            printstyled(io, @sprintf("⊡ %5d bins",nbin[k]); bold=true)
        end
        bin_edges = axes_binedges(params)
        first_edges = map(x -> x[1],bin_edges)
        last_edges = map(x -> x[end],bin_edges)
        @printf(io," from %+.3f to %+.3f along [", first_edges[k], last_edges[k])
        axes_names = ["x","y","z","E"]
        inMiddle = false
        for j = 1:4
            if params.covectors[k,j] != 0.
                if(inMiddle)
                    print(io," ")
                end
                @printf(io,"%+.2f d%s",params.covectors[k,j],axes_names[j])
                inMiddle = true
            end
        end
        @printf(io,"] (Δ = %.3f)", params.binwidth[k]/norm(params.covectors[k,:]))
        println(io)
    end
end

Base.copy(p::BinningParameters) = BinningParameters(copy(p.binstart),copy(p.binend),copy(p.binwidth),copy(p.covectors))

# Support numbins as a (virtual) property, even though only the binwidth is stored
Base.getproperty(params::BinningParameters, sym::Symbol) = sym == :numbins ? count_bins(params.binstart,params.binend,params.binwidth) : getfield(params,sym)

function Base.setproperty!(params::BinningParameters, sym::Symbol, numbins)
    if sym == :numbins
        # *Ensure* that the last bin contains params.binend
        params.binwidth .= (params.binend .- params.binstart) ./ (numbins .- 0.5)
    else
        setfield!(params,sym,numbins)
    end
end

"""
    count_bins(binstart,binend,binwidth)

Returns the number of bins in the binning scheme implied by `binstart`, `binend`, and `binwidth`.
To count the bins in a [`BinningParameters`](@ref), use `params.numbins`.

This function defines how partial bins are handled, so it should be used preferentially over
computing the number of bins manually.
"""
count_bins(bin_start,bin_end,bin_width) = ceil.(Int64,(bin_end .- bin_start) ./ bin_width)

function BinningParameters(binstart,binend,binwidth;covectors = [1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1])
    return BinningParameters(binstart,binend,binwidth,covectors)
end

function BinningParameters(binstart,binend;numbins,kwargs...)
    params = BinningParameters(binstart,binend,[0.,0,0,0];kwargs...)
    params.numbins = numbins # Use the setproperty to do it correctly
    params
end

"""
    integrate_axes!(params::BinningParameters; axes)
Integrate over one or more axes of the histogram by setting the number of bins
in that axis to 1. Examples:

    integrate_axes!(params; axes = [2,3])
    integrate_axes!(params; axes = 2)
"""
function integrate_axes!(params::BinningParameters;axes)
    for k in axes
        nbins = [params.numbins.data...]
        nbins[k] = 1
        params.numbins = SVector{4}(nbins)
    end
    return params
end

# Find an axis-aligned bounding box containing the histogram
function binning_parameters_aabb(params)
    (; binstart, binend, covectors) = params
    bin_edges = axes_binedges(params)
    first_edges = map(x -> x[1],bin_edges)
    last_edges = map(x -> x[end],bin_edges)
    bin_edges = [first_edges last_edges]
    this_corner = MVector{4,Float64}(undef)
    q_corners = MMatrix{4,16,Float64}(undef)
    for j = 1:16 # The sixteen corners of a 4-cube
        for k = 1:4 # The four axes
            this_corner[k] = bin_edges[k,1 + (j >> (k-1) & 1)]
        end
        q_corners[:,j] = covectors \ this_corner
    end
    lower_aabb_q = minimum(q_corners,dims=2)[1:3]
    upper_aabb_q = maximum(q_corners,dims=2)[1:3]
    return lower_aabb_q, upper_aabb_q
end

"""
If `params` expects to bin values `(k,ω)` in absolute units, then calling

    bin_rlu_as_absolute_units!(params::BinningParameters,[reciprocal lattice vectors])

will modifiy the `covectors` in `params` so that they will accept `(q,ω)` in Reciprocal Lattice Units (R.L.U.) instead.
Conversly, if `params` expects `(q,ω)` R.L.U., calling

    bin_absolute_units_as_rlu!(params::BinningParameters,[reciprocal lattice vectors])

will adjust `params` to instead accept `(k,ω)` absolute units.

The second argument may be a 3x3 matrix specifying the reciprocal lattice vectors, or a [`Crystal`](@ref).
"""
bin_absolute_units_as_rlu!, bin_rlu_as_absolute_units!

function bin_rlu_as_absolute_units!(params::BinningParameters,recip_vecs::AbstractMatrix)
    covectorsK = params.covectors

    # covectorsQ * q = covectorsK *  recip_vecs * q = covectorsK * k
    # covectorsQ     = covectorsK *  recip_vecs
    covectorsQ       = covectorsK * [recip_vecs [0;0;0]; [0 0 0] 1]
    params.covectors = MMatrix{4,4}(covectorsQ)
    params
end

# covectorsK * k = covectorsQ * inv(recip_vecs) * k = covectorsQ * q
# covectorsK     = covectorsQ * inv(recip_vecs)
bin_absolute_units_as_rlu!(params::BinningParameters,recip_vecs::AbstractMatrix) = bin_rlu_as_absolute_units!(params,inv(recip_vecs))

bin_absolute_units_as_rlu!(params::BinningParameters,crystal::Crystal) = bin_absolute_units_as_rlu!(params,2π*inv(crystal.latvecs)')

bin_rlu_as_absolute_units!(params::BinningParameters,crystal::Crystal) = bin_absolute_units_as_rlu!(params,crystal.latvecs'/2π)

"""
    unit_resolution_binning_parameters(sc::SampledCorrelations)

Create [`BinningParameters`](@ref) which place one histogram bin centered at each possible `(q,ω)` scattering vector of the crystal.
This is the finest possible binning without creating bins with zero scattering vectors in them.

This function can be used without reference to a [`SampledCorrelations`](@ref) using an alternate syntax to manually specify the bin centers for the energy axis and the lattice size:

    unit_resolution_binning_parameters(ω_bincenters,latsize,[reciprocal lattice vectors])

The last argument may be a 3x3 matrix specifying the reciprocal lattice vectors, or a [`Crystal`](@ref).

Lastly, binning parameters for a single axis may be specifed by their bin centers:

    (binstart,binend,binwidth) = unit_resolution_binning_parameters(bincenters::Vector{Float64})
"""
function unit_resolution_binning_parameters(ωvals,latsize,args...)
    numbins = (latsize...,length(ωvals))
    # Bin centers should be at Sunny scattering vectors
    maxQ = 1 .- (1 ./ numbins)
    
    min_val = (0.,0.,0.,minimum(ωvals))
    max_val = (maxQ[1],maxQ[2],maxQ[3],maximum(ωvals))
    total_size = max_val .- min_val

    binwidth = total_size ./ (numbins .- 1)
    binstart = (0.,0.,0.,minimum(ωvals)) .- (binwidth ./ 2)
    binend = (maxQ[1],maxQ[2],maxQ[3],maximum(ωvals)) # bin end is well inside of last bin

    params = BinningParameters(binstart,binend,binwidth)

    # Special case for when there is only one bin in a direction
    for i = 1:4
        if numbins[i] == 1
            params.binwidth[i] = 1.
            params.binstart[i] = min_val[i] - (params.binwidth[i] ./ 2)
            params.binend[i] = min_val[i]
        end
    end
    params
end

unit_resolution_binning_parameters(sc::SampledCorrelations; negative_energies=false,kwargs...) = unit_resolution_binning_parameters(available_energies_including_zero(sc;negative_energies),sc.latsize,sc;kwargs...)

function unit_resolution_binning_parameters(ωvals::AbstractVector{Float64})
    if !all(abs.(diff(diff(ωvals))) .< 1e-12)
      @warn "Non-uniform bins will be re-spaced into uniform bins"
    end
    if length(ωvals) == 1
      error("Can not infer bin width given only one bin center")
    end
    ωbinwidth = (maximum(ωvals) - minimum(ωvals)) / (length(ωvals) - 1)
    ωstart = minimum(ωvals) - ωbinwidth / 2
    ωend = maximum(ωvals)

    return ωstart, ωend, ωbinwidth
end

"""
    slice_2D_binning_parameter(sc::SampledCorrelations, cut_from_q, cut_to_q, cut_bins::Int64, cut_width::Float64; plane_normal = [0,0,1],cut_height = cutwidth)

Creates [`BinningParameters`](@ref) which make a cut along one dimension of Q-space.
 
The x-axis of the resulting histogram consists of `cut_bins`-many bins ranging
from `cut_from_q` to `cut_to_q`. 
The width of the bins in the transverse direciton is controlled by `cut_width` and `cut_height`.

The binning in the transverse directions is defined in the following way, which sets their normalization and orthogonality properties:

    cut_covector = normalize(cut_to_q - cut_from_q)
    transverse_covector = normalize(plane_normal × cut_covector)
    cotransverse_covector = normalize(transverse_covector × cut_covector)

In other words, the axes are orthonormal with respect to the Euclidean metric.

If the cut is too narrow, there will be very few scattering vectors per bin, or
the number per bin will vary substantially along the cut.
If the output appears under-resolved, try increasing `cut_width`.

The four axes of the resulting histogram are:
  1. Along the cut
  2. Fist transverse Q direction
  3. Second transverse Q direction
  4. Energy

This function can be used without reference to a [`SampledCorrelations`](@ref) using this alternate syntax to manually specify the bin centers for the energy axis:

    slice_2D_binning_parameter(ω_bincenters, cut_from, cut_to,...)

where `ω_bincenters` specifies the energy axis, and both `cut_from` and `cut_to` are arbitrary covectors, in any units.
"""
function slice_2D_binning_parameters(ωvals::Vector{Float64},cut_from_q,cut_to_q,cut_bins::Int64,cut_width;plane_normal = [0,0,1],cut_height = cut_width)
    # This covector should measure progress along the cut in r.l.u.
    cut_covector = normalize(cut_to_q - cut_from_q)
    # These two covectors should be perpendicular to the cut, and to each other
    transverse_covector = normalize(plane_normal × cut_covector)
    cotransverse_covector = normalize(transverse_covector × cut_covector)

    start_x = cut_covector ⋅ cut_from_q
    end_x = cut_covector ⋅ cut_to_q

    transverse_center = transverse_covector ⋅ cut_from_q # Equal to using cut_to_q
    cotransverse_center = cotransverse_covector ⋅ cut_from_q

    ωstart, ωend, ωbinwidth = unit_resolution_binning_parameters(ωvals)
    xstart, xend, xbinwidth = unit_resolution_binning_parameters(range(start_x,end_x,length = cut_bins))

    binstart = [xstart,transverse_center - cut_width/2,cotransverse_center - cut_height/2,ωstart]
    binend = [xend,transverse_center,cotransverse_center,ωend]
    numbins = [cut_bins,1,1,length(ωvals)]
    covectors = [cut_covector... 0; transverse_covector... 0; cotransverse_covector... 0; 0 0 0 1]

    BinningParameters(binstart,binend;numbins = numbins, covectors = covectors)
end

function slice_2D_binning_parameters(sc::SampledCorrelations,cut_from_q,cut_to_q,args...;kwargs...)
    slice_2D_binning_parameters(available_energies_including_zero(sc),cut_from_q,cut_to_q,args...;kwargs...)
end

"""
    axes_bincenters(params::BinningParameters)

Returns tick marks which label the bins of the histogram described by [`BinningParameters`](@ref) by their bin centers.

The following alternative syntax can be used to compute bin centers for a single axis:

    axes_bincenters(binstart,binend,binwidth)
"""
function axes_bincenters(binstart,binend,binwidth)
    bincenters = Vector{AbstractRange{Float64}}(undef,0)
    for k = eachindex(binstart)
        first_center = binstart[k] .+ binwidth[k] ./ 2
        nbin = count_bins(binstart[k],binend[k],binwidth[k])
        push!(bincenters,range(first_center,step = binwidth[k],length = nbin))
    end
    bincenters
end
axes_bincenters(params::BinningParameters) = axes_bincenters(params.binstart,params.binend,params.binwidth)

function axes_binedges(binstart,binend,binwidth)
    binedges = Vector{AbstractRange{Float64}}(undef,0)
    for k = eachindex(binstart)
        nbin = count_bins(binstart[k],binend[k],binwidth[k])
        push!(binedges,range(binstart[k],step = binwidth[k],length = nbin + 1))
    end
    binedges
end
axes_binedges(params::BinningParameters) = axes_binedges(params.binstart,params.binend,params.binwidth)



"""
    reciprocal_space_path_bins(sc,qs,density,args...;kwargs...)

Takes a list of wave vectors, `qs` in R.L.U., and builds a series of histogram [`BinningParameters`](@ref)
whose first axis traces a path through the provided points.
The second and third axes are integrated over according to the `args` and `kwargs`,
which are passed through to [`slice_2D_binning_parameters`](@ref).

Also returned is a list of marker indices corresponding to the input points, and
a list of ranges giving the indices of each histogram `x`-axis within a concatenated histogram.
The `density` parameter is given in samples per reciprocal lattice unit (R.L.U.).
"""
function q_space_path_bins(ωvals,qs,density,args...;kwargs...)
    nPts = length(qs)
    params = []
    markers = []
    ranges = []
    total_bins_so_far = 0
    push!(markers, total_bins_so_far+1)
    for k = 1:(nPts-1)
        startPt = qs[k]
        endPt = qs[k+1]
        # Density is taken in R.L.U. since that's where the
        # scattering vectors are equally spaced!
        nBins = round(Int64,density * norm(endPt - startPt))
        # SQTODO: Automatic density that adjusts itself lower
        # if there are not enough (e.g. zero) counts in some bins

        param = slice_2D_binning_parameters(ωvals,startPt,endPt,nBins,args...;kwargs...)
        push!(params,param)
        push!(ranges, total_bins_so_far .+ (1:nBins))
        total_bins_so_far = total_bins_so_far + nBins
        push!(markers, total_bins_so_far+1)
    end
    return params, markers, ranges
end
q_space_path_bins(sc::SampledCorrelations, qs::Vector, density,args...;kwargs...) = q_space_path_bins(available_energies_including_zero(sc), qs, density,args...;kwargs...)

function available_energies_including_zero(x; kwargs...)
    ωs = available_energies(x;kwargs...)
    # Special case due to NaN definition of instant_correlations
    (length(ωs) == 1 && isnan(ωs[1])) ? [0.] : ωs
end
