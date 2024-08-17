# Takes a list of q points, converts into SampledCorrelation.data indices and
# corresponding exact wave vectors, and eliminates repeated elements.
function pruned_wave_vector_info(sc::SampledCorrelations, qs)

    # Round to the nearest wavevector and wrapped index
    Ls = size(sc.samplebuf)[2:4]
    ms = map(qs) do q 
        round.(Int, Ls .* q)
    end
    idcs = map(ms) do m
        CartesianIndex{3}(map(i -> mod(m[i], Ls[i])+1, (1, 2, 3)))
    end

    # Convert to absolute units (for form factors)
    qabs_rounded = map(m -> sc.crystal.recipvecs * (m ./ sc.latsize), ms)

    # List of "starting" pointers i where idcs[i-1] != idcs[i]
    starts = findall(i -> i == 1 || idcs[i-1] != idcs[i], eachindex(idcs))

    # Length of each run of repeated values
    counts = starts[2:end] - starts[1:end-1]
    append!(counts, length(idcs) - starts[end] + 1)

    # Remove contiguous repetitions
    qabs = qabs_rounded[starts]
    idcs = idcs[starts]

    return (; qabs, idcs, counts)
end


# Crude slow way to find the energy axis index closest to some given energy.
function find_idx_of_nearest_fft_energy(ref, val)
    for i in axes(ref[1:end-1], 1)
        x1, x2 = ref[i], ref[i+1]
        if x1 <= val <= x2 
            if abs(x1 - val) < abs(x2 - val)
                return i
            else
                return i+1
            end
        end
    end
    # Deal with edge case arising due to FFT index ordering
    if ref[end] <= val <= 0.0
        if abs(ref[end] - val) <= abs(val)
            return length(ref)
        else
            return 1
        end
    end
    error("Value does not lie in bounds of reference list.")
end


# If the user specifies an energy list, round to the nearest available energies
# and give the corresponding indices into the raw data. This is fairly
# inefficient, though the cost is likely trivial next to the rest of the
# computation. Since this is an edge case (user typically expected to choose
# :available or :available_with_negative), not spending time on optimization
# now.
function rounded_energy_information(sc, energies)
    ωvals = available_energies(sc; negative_energies = true)
    energies_sorted = sort(energies)
    @assert all(x -> x ==true, energies .== energies_sorted) "Specified energies must be an ordered list."
    @assert minimum(energies) >= minimum(ωvals) && maximum(energies) <= maximum(ωvals) "Specified energies includes values for which there is no available data."
    ωidcs = map(val -> find_idx_of_nearest_fft_energy(ωvals, val), energies)
    return ωvals[ωidcs], ωidcs
end


# Documented under intensities function for LSWT.
function intensities(sc::SampledCorrelations, qpts; energies, kernel=nothing, formfactors=nothing, kT)
    if isnan(sc.Δω) && energies != :available
        error("`SampledCorrelations` only contains static information. No energy information is available.")
    end
    if !isnothing(kernel)
        error("Kernel post-processing not yet available for `SampledCorrelations`.")
    end

    # Determine energy information
    (ωs, ωidcs) = if energies == :available
        ωs = available_energies(sc; negative_energies=false)
        (ωs, axes(ωs, 1))
    elseif energies == :available_with_negative
        ωs = available_energies(sc; negative_energies=true)
        (ωs, axes(ωs, 1))
    else
        rounded_energy_information(sc, energies)
    end

    # Prepare memory and configuration variables for actual calculation
    qpts = Base.convert(AbstractQPoints, qpts)
    ff_atoms = propagate_form_factors_to_atoms(formfactors, sc.crystal)
    intensities = zeros(eltype(sc.measure), isnan(sc.Δω) ? 1 : length(ωs), length(qpts.qs)) # N.B.: Inefficient indexing order to mimic LSWT
    q_idx_info = pruned_wave_vector_info(sc, qpts.qs)
    crystal = !isnothing(sc.origin_crystal) ? sc.origin_crystal : sc.crystal
    NCorr  = Val{size(sc.data, 1)}()
    NAtoms = Val{size(sc.data, 2)}()

    # Intensities calculation
    intensities_rounded!(intensities, sc.data, sc.crystal, sc.measure, ff_atoms, q_idx_info, ωidcs, NCorr, NAtoms)

    # Post-processing steps that depend on whether instant or dynamic correlations.
    if !isnan(sc.Δω)
        # Convert time axis to a density.
        # TODO: Why not do this with the definition of the FFT normalization?
        n_all_ω = size(sc.samplebuf, 6)
        intensities ./= (n_all_ω * sc.Δω)

        # Apply classical-to-quantum correspondence factor if temperature given.
        if !isnothing(kT) 
            c2q = classical_to_quantum.(ωs, kT)
            for i in axes(intensities, 2)
                intensities[:,i] .*= c2q
            end
        end
    else
        # If temperature is given for a SampledCorrelations with only
        # instantaneous data, throw an error. 
        !isnothing(kT) && error("Given `SampledCorrelations` only contains instant correlation data. Temperature corrections only available with dynamical correlation info.")
    end

    intensities = reshape(intensities, length(ωs), size(qpts.qs)...)
    return if !isnan(sc.Δω)
        Intensities(crystal, qpts, collect(ωs), reshape(intensities, length(ωs), size(qpts.qs)...))
    else
        InstantIntensities(crystal, qpts, dropdims(intensities; dims=1))
    end
end

function intensities_rounded!(intensities, data, crystal, measure::MeasureSpec{Op, F, Ret}, ff_atoms, q_idx_info, ωidcs, ::Val{NCorr}, ::Val{NAtoms}) where {Op, F, Ret, NCorr, NAtoms}
    (; qabs, idcs, counts) = q_idx_info 
    qidx = 1
    for (qabs, idx, count) in zip(qabs, idcs, counts)
        prefactors = prefactors_for_phase_averaging(qabs, crystal, ff_atoms, Val(NCorr), Val(NAtoms))

        # Perform phase-averaging over all omega
        for (n, iω) in enumerate(ωidcs)
            elems = zero(MVector{NCorr,ComplexF64})
            for j in 1:NAtoms, i in 1:NAtoms
                elems .+= (prefactors[i] * conj(prefactors[j])) .* view(data, :, i, j, idx, iω)
            end
            val = measure.combiner(qabs, SVector{NCorr, ComplexF64}(elems))
            intensities[n, qidx] = val
        end

        # Copy for repeated q-values
        for idx in qidx+1:qidx+count-1, n in axes(ωidcs, 1)
            intensities[n, idx] = intensities[n, qidx]
        end

        qidx += count
    end
end


function intensities_instant(sc::SampledCorrelations, qpts; formfactors=nothing, kT)
    return if isnan(sc.Δω)
        if !isnothing(kT) 
            error("kT=nothing is required for a `SampledCorrelations` without dynamics")
        end
        intensities(sc, qpts; formfactors, kT, energies=:available)
    else
        res = intensities(sc, qpts; formfactors, kT, energies=:available_with_negative)
        data_new = dropdims(sum(res.data, dims=1), dims=1) * sc.Δω
        InstantIntensities(res.crystal, res.qpts, data_new)
    end
end


function classical_to_quantum(ω, kT)
    if ω > 0
        ω/(kT*(1 - exp(-ω/kT)))
    elseif iszero(ω)
        1.0
    else
        -ω*exp(ω/kT)/(kT*(1 - exp(ω/kT)))
    end
end


#=
"""
    broaden_energy(sc::SampledCorrelations, vals, kernel::Function; negative_energies=false)

Performs a real-space convolution along the energy axis of an array of
intensities. Assumes the format of the intensities array corresponds to what
would be returned by [`intensities_interpolated`](@ref). `kernel` must be a function that
takes two numbers: `kernel(ω, ω₀)`, where `ω` is a frequency, and `ω₀` is the
center frequency of the kernel. Sunny provides [`lorentzian`](@ref)
for the most common use case:

```
newvals = broaden_energy(sc, vals, (ω, ω₀) -> lorentzian06(fwhm=0.2)(ω-ω₀))
```
"""
function broaden_energy(sc::SampledCorrelations, is, kernel::Function; negative_energies=false)
    dims = size(is)
    ωvals = available_energies(sc; negative_energies)
    out = zero(is)
    for (ω₀i, ω₀) in enumerate(ωvals)
        for (ωi, ω) in enumerate(ωvals)
            for qi in CartesianIndices(dims[1:end-1])
                out[qi,ωi] += is[qi,ω₀i]*kernel(ω, ω₀)*sc.Δω
            end
        end
    end
    return out
end
=#





