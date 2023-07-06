function spherical_points_fibonacci(N) 
    golden = (1+√5)/2
    decimals(x) = x - floor(x)
    planar_fib_points(N) = [(decimals(n/golden), n/N) for n in 1:N]
    plane_to_sphere((x, y)) = (2π*x, acos(1-2y))
    spherical_to_cartesian((θ, ϕ)) = (cos(θ)*sin(ϕ), sin(θ)*sin(ϕ), cos(ϕ))

    return planar_fib_points(N) .|> plane_to_sphere .|> spherical_to_cartesian .|> Vec3
end

"""
    spherical_shell(sf::StructureFactor, radius, density)

Returns a set of wave vectors lying on a sphere of specified radius, where
`radius` is given in ``Å^{-1}``. `density` controls how many points to select
per ``Å^{-2}``. 

The points are generated by mapping a Fibonacci lattice onto a sphere. 
"""
function spherical_shell(sf::StructureFactor, radius, density)
    numpoints = round(Int, 4π*radius^2 * density)
    crystal = orig_crystal(sf) 
    C = inv(2π*inv(crystal.latvecs)') # Transformation for inverse angstroms to RLU
    return if numpoints == 0 
        [Vec3(0,0,0)]  # If radius too small, just return the 0 vector 
    else
        map(v->C*v, radius * spherical_points_fibonacci(numpoints))
    end
end

function powder_average(sf::StructureFactor, q_ias, mode, density; kwargs...)
    A = inv(inv(sf.crystal.latvecs)') # Transformation to convert from inverse angstroms to RLUs
    nω = length(ωs(sf))
    output = zeros(Float64, length(q_ias), nω) # generalize this so matches contract

    for (i, r) in enumerate(q_ias)
        area = 4π*r^2
        numpoints = round(Int, area*density)
        fibpoints = numpoints == 0 ? [Vec3(0,0,0)] :  r .* spherical_points_fibonacci(numpoints)
        qs = map(v->A*v, fibpoints)
        vals = intensities(sf, qs, mode; kwargs...)
        vals = sum(vals, dims=1) / size(vals, 1)
        output[i,:] .= vals[1,:]
    end

    return output
end

# Similar to `powder_average`, but the data is binned instead of interpolated.
# Also similar to `intensities_binned`, but the histogram x-axis is `|k|` in absolute units, which
# is a nonlinear function of `kx`,`ky`,`kz`. The y-axis is energy.
#
# Binning parameters are specified as tuples `(start,end,bin_width)`,
# e.g. `radial_binning_parameters = (0,6π,6π/55)`.
#
# Energy broadening is support in the same as `intensities_binned`.
function powder_averaged_bins(sf::StructureFactor, radial_binning_parameters, mode;
    ω_binning_parameters=unit_resolution_binning_parameters(ωs(sf)),
    integrated_kernel=nothing,
    bzsize=nothing,
    kT=nothing,
    formfactors=nothing,
)
    ωstart,ωend,ωbinwidth = ω_binning_parameters
    rstart,rend,rbinwidth = radial_binning_parameters

    ω_bin_count = count_bins(ω_binning_parameters...)
    r_bin_count = count_bins(radial_binning_parameters...)

    output_intensities = zeros(Float64,r_bin_count,ω_bin_count)
    output_counts = zeros(Float64,r_bin_count,ω_bin_count)
    ωvals = ωs(sf)
    recip_vecs = 2π*inv(sf.crystal.latvecs)'
    ffdata = prepare_form_factors(sf, formfactors)
    contractor = if mode == :perp
        DipoleFactor(sf)
    elseif typeof(mode) <: Tuple{Int, Int}
        Element(sf, mode)
    else
        Trace(sf)
    end

    # Loop over every scattering vector
    Ls = sf.latsize
    if isnothing(bzsize)
        bzsize = (1,1,1) .* ceil(Int64,rend/eigmin(recip_vecs))
    end
    for cell in CartesianIndices(Ls .* bzsize)
        base_cell = CartesianIndex(mod1.(cell.I,Ls)...)
        for (iω,ω) in enumerate(ωvals)
            # Compute intensity
            # [c.f. all_exact_wave_vectors, but we need `cell' index as well here]
            q = SVector((cell.I .- 1) ./ Ls) # q is in R.L.U.

            # Figure out which radial bin this scattering vector goes in
            # The spheres are surfaces of fixed |k|, with k in absolute units
            k = recip_vecs * q
            r_coordinate = norm(k) 

            # Check if the radius falls within the histogram
            rbin = 1 .+ floor.(Int64,(r_coordinate .- rstart) ./ rbinwidth)
            if rbin <= r_bin_count && rbin >= 1
                # If we are energy-broadening, then scattering vectors outside the histogram
                # in the energy direction need to be considered
                if isnothing(integrated_kernel) # `Delta-function energy' logic
                    # Check if the ω falls within the histogram
                    ωbin = 1 .+ floor.(Int64,(ω .- ωstart) ./ ωbinwidth)
                    if ωbin <= ω_bin_count && ωbin >= 1
                        NCorr, NAtoms = size(sf.data)[1:2]
                        intensity = calc_intensity(sf,k,base_cell,ω,iω,contractor, kT, ffdata, Val(NCorr), Val(NAtoms))
                        output_intensities[rbin,ωbin] += intensity
                        output_counts[rbin,ωbin] += 1
                    end
                else # `Energy broadening into bins' logic

                    # Calculate source scattering vector intensity only once
                    NCorr, NAtoms = size(sf.data)[1:2]
                    intensity = calc_intensity(sf,k,base_cell,ω,iω,contractor, kT, ffdata, Val(NCorr), Val(NAtoms))
                    # Broaden from the source scattering vector (k,ω) to
                    # each target bin (rbin,ωbin_other)
                    for ωbin_other = 1:ω_bin_count
                        # Start and end points of the target bin
                        a = ωstart + (ωbin_other - 1) * ωbinwidth
                        b = ωstart + ωbin_other * ωbinwidth

                        # P(ω picked up in bin [a,b]) = ∫ₐᵇ Kernel(ω' - ω) dω'
                        fraction_in_bin = integrated_kernel(b - ω) - integrated_kernel(a - ω)
                        output_intensities[rbin,ωbin_other] += fraction_in_bin * intensity
                        output_counts[rbin,ωbin_other] += fraction_in_bin
                    end
                end
            end
        end
    end
    return output_intensities, output_counts
end
