struct ClassicalIntensityFormula{T} <: IntensityFormula
    kT :: Float64
    formfactors
    string_formula :: String
    calc_intensity :: Function
end

function Base.show(io::IO, formula::ClassicalIntensityFormula{T}) where T
    print(io,"ClassicalIntensityFormula{$T}")
end

function Base.show(io::IO, ::MIME"text/plain", formula::ClassicalIntensityFormula{T}) where T
    printstyled(io, "Classical Scattering Intensity Formula\n";bold=true, color=:underline)

    formula_lines = split(formula.string_formula,'\n')

    intensity_equals = "  Intensity[ix_q,ix_ω] = "
    println(io,"At discrete scattering modes S = S[ix_q,ix_ω], use:")
    println(io)
    println(io,intensity_equals,formula_lines[1])
    for i = 2:length(formula_lines)
        precursor = repeat(' ', textwidth(intensity_equals))
        println(io,precursor,formula_lines[i])
    end
    println(io)

    if isnothing(formula.formfactors)
        printstyled(io, "No form factors specified\n";color=:yellow)
    else
        printstyled(io, "Form factors included in S ✓\n";color=:green)
    end
    if formula.kT == Inf
        printstyled(io, "No temperature correction";color=:yellow)
        print(io, " (kT = ∞)\n")
    else
        printstyled(io, "Temperature corrected (kT = $(formula.kT)) ✓\n";color = :green)
    end
    if T != Float64
        println(io,"Intensity :: $(T)")
    end
end

"""
    formula = intensity_formula(sc::SampledCorrelations)

Establish a formula for computing the intensity of the discrete scattering modes
`(q,ω)` using the correlation data ``𝒮^{αβ}(q,ω)`` stored in the
[`SampledCorrelations`](@ref). The `formula` returned from `intensity_formula`
can be passed to [`intensities_interpolated`](@ref) or
[`intensities_binned`](@ref).

    intensity_formula(sc,...; kT = Inf, formfactors = ...)

There are keyword arguments providing temperature and form factor corrections:

- `kT`: If a temperature is provided, the intensities will be rescaled by a
    temperature- and ω-dependent classical-to-quantum factor. `kT` should be
    specified when making comparisons with spin wave calculations or
    experimental data. If `kT` is not specified, infinite temperature (no
    correction) is assumed.
- `formfactors`: To apply form factor corrections, provide this keyword with a
    list of `FormFactor`s, one for each symmetry-distinct site in the crystal.
    The order of `FormFactor`s must correspond to the order of site symmetry
    classes, e.g., as they appear when printed in `display(crystal)`.
"""
function intensity_formula(f::Function, sc::SampledCorrelations, corr_ix::AbstractVector{Int64}; 
    kT = Inf, 
    formfactors = nothing, 
    return_type = Float64, 
    calculate_errors = false, 
    string_formula = "f(Q,ω,S{α,β}[ix_q,ix_ω])"
)
    # If temperature given, ensure it's greater than 0.0
    if kT != Inf
        if iszero(kT)
            error("`kT` must be greater than zero.")
        end
        # Only apply c2q factor if have dynamical correlations
        if isnan(sc.Δω)
            error("`kT`-dependent corrections not available when using correlation data generated with `instant_correlations`. Do not set `kT` keyword.")
        end
    end

    ωs_sc = available_energies(sc;negative_energies = true)

    ff_atoms = propagate_form_factors_to_atoms(formfactors, sc.crystal)
    NAtoms = Val(size(sc.data)[2])
    NCorr = Val(length(corr_ix))

    # Set the buffer and basis reduction function that will go into closure.
    # This is determined by whether or not the running variance will be
    # calculated.
    data_buffer = calculate_errors ? sc.variance : sc.data
    reduce_basis = calculate_errors ? error_basis_reduction : phase_averaged_elements
    # reduce_basis = phase_averaged_elements

    # Intensity is calculated at the discrete (ix_q,ix_ω) modes available to the system.
    # Additionally, for momentum transfers outside of the first BZ, the norm `q_absolute` of the
    # momentum transfer may be different than the one inferred from `ix_q`, so it needs
    # to be provided independently of `ix_q`.
    calc_intensity = function (sc::SampledCorrelations, q_absolute::Vec3, ix_q::CartesianIndex{3}, ix_ω::Int64)
        correlations = reduce_basis(view(data_buffer, corr_ix, :, :, ix_q, ix_ω), q_absolute, sc.crystal, ff_atoms, NCorr, NAtoms)

        # This is NaN if sc is instant_correlations
        ω = (typeof(ωs_sc) == Float64 && isnan(ωs_sc)) ? NaN : ωs_sc[ix_ω] 

        return f(q_absolute, ω, correlations) * classical_to_quantum(ω,kT)
    end
    ClassicalIntensityFormula{return_type}(kT, formfactors, string_formula, calc_intensity)
end

"""
A custom intensity formula can be specifed by providing a function `intensity = f(q,ω,correlations)` and specifying which correlations it requires:

    intensity_formula(f,sc::SampledCorrelations, required_correlations; kwargs...)

The function is intended to be specified using `do` notation. For example, this custom formula sums the off-diagonal correlations:

    required = [(:Sx,:Sy),(:Sy,:Sz),(:Sx,:Sz)]
    intensity_formula(sc,required,return_type = ComplexF64) do k, ω, off_diagonal_correlations
        sum(off_diagonal_correlations)
    end

If your custom formula returns a type other than `Float64`, use the `return_type` keyword argument to flag this.
"""
function intensity_formula(f::Function,sc::SampledCorrelations,required_correlations; kwargs...)
    # SQTODO: This corr_ix may contain repeated correlations if the user does a silly
    # thing like [(:Sx,:Sy),(:Sy,:Sx)], and this can technically be optimized so it's
    # not computed twice
    corr_ix = lookup_correlations(sc,required_correlations)
    intensity_formula(f,sc,corr_ix;kwargs...)
end


function classical_to_quantum(ω, kT::Float64)
    if kT == Inf
        return 1.0
    end
    if ω > 0
        ω/(kT*(1 - exp(-ω/kT)))
    elseif iszero(ω)
        1.0
    else
        -ω*exp(ω/kT)/(kT*(1 - exp(ω/kT)))
    end
end

"""
    lorentzian(x, η) 

Returns ``η/(π(x^2 + η^2))``.
"""
lorentzian(x, η) = η/(π*(x^2 + η^2))
lorentzian(η) = x -> lorentzian(x,η)

"""
    integrated_lorentzian(η) 

Returns ``x \\mapsto atan(x/η)/π`` for use with [`intensities_binned`](@ref).
"""
integrated_lorentzian(η::Float64) = x -> atan(x/η)/π

"""
    broaden_energy(sc::SampledCorrelations, vals, kernel::Function; negative_energies=false)

Performs a real-space convolution along the energy axis of an array of
intensities. Assumes the format of the intensities array corresponds to what
would be returned by [`intensities_interpolated`](@ref). `kernel` must be a function that
takes two numbers: `kernel(ω, ω₀)`, where `ω` is a frequency, and `ω₀` is the
center frequency of the kernel. Sunny provides [`lorentzian`](@ref)
for the most common use case:

```
newvals = broaden_energy(sc, vals, (ω, ω₀) -> lorentzian(ω-ω₀, 0.2))
```
"""
function broaden_energy(sc::SampledCorrelations, is, kernel::Function; negative_energies=false)
    dims = size(is)
    ωvals = available_energies(sc; negative_energies)
    out = zero(is)
    for (ω₀i, ω₀) in enumerate(ωvals)
        for (ωi, ω) in enumerate(ωvals)
            for qi in CartesianIndices(dims[1:end-1])
                out[qi,ωi] += is[qi,ω₀i]*kernel(ω, ω₀)
            end
        end
    end
    return out
end
