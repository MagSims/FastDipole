"""
    SpinWaveTheoryKPM(sys::System; measure, regularization=1e-8, tol)

A variant of [`SpinWaveTheory`](@ref) that uses the kernel polynomial method
(KPM) to perform [`intensities`](@ref) calculations [1]. Instead of explicitly
diagonalizing the dynamical matrix, KPM approximates intensities using
polynomial expansion truncated at order ``M``. The reduces the computational
cost from ``𝒪(N^3)`` to ``𝒪(N M)``, which is favorable for large system sizes
``N``.

The polynomial order ``M`` will be determined from the line broadening kernel
and the specified error tolerance `tol`. Specifically, for each wavevector,
``M`` scales like the spectral bandwidth of excitations, divided by the energy
resolution of the broadening kernel, times the negative logarithm of `tol`.

Reasonable choices of the error tolerance `tol` are `1e-1` for a faster
calculation, or `1e-2` for a more accurate calculation.

References:

 1. H. Lane et al., Kernel Polynomial Method for Linear Spin Wave Theory (2023)
    [[arXiv:2312.08349v3](https://arxiv.org/abs/2312.08349)].
"""
struct SpinWaveTheoryKPM
    swt :: SpinWaveTheory
    tol :: Float64

    function SpinWaveTheoryKPM(sys::System; measure::Union{Nothing, MeasureSpec}, regularization=1e-8, tol)
        return new(SpinWaveTheory(sys; measure, regularization), tol)
    end
end


# Smooth approximation to a Heaviside step function. The original (and
# published) idea was to construct an effective convolution kernel that is
# smooth everywhere, avoiding the need for a Jackson kernel. In practice, it is
# difficult to adaptively determine the polynomial order M in a way that avoids
# visible Gibbs ringing, especially near Goldstone modes. The current version of
# this code instead leaves the Jackson kernel on at all times. This makes KPM
# easier to use but sacrifices some accuracy.
#=
function regularization_function(y)
    if y < 0
        return 0.0
    elseif 0 ≤ y ≤ 1
        return (4 - 3y) * y^3
    else
        return 1.0
    end
end
=#

function mul_Ĩ!(y, x)
    L = size(y, 2) ÷ 2
    view(y, :, 1:L)    .= .+view(x, :, 1:L)
    view(y, :, L+1:2L) .= .-view(x, :, L+1:2L)
end

function mul_A!(swt, y, x, qs_reshaped, γ)
    L = size(y, 2) ÷ 2
    mul_dynamical_matrix!(swt, y, x, qs_reshaped)
    view(y, :, 1:L)    .*= +1/γ
    view(y, :, L+1:2L) .*= -1/γ
end

function set_moments!(moments, measure, u, α)
    map!(moments, measure.corr_pairs) do (μ, ν)
        dot(view(u, μ, :), view(α, ν, :))
    end
end


function intensities!(data, swt_kpm::SpinWaveTheoryKPM, qpts; energies, kernel::AbstractBroadening, kT=0.0, verbose=false)
    qpts = convert(AbstractQPoints, qpts)

    (; swt, tol) = swt_kpm
    (; sys, measure) = swt
    cryst = orig_crystal(sys)

    isnothing(kernel.fwhm) && error("Cannot determine the kernel fwhm")

    @assert eltype(data) == eltype(measure)
    @assert size(data) == (length(energies), length(qpts.qs))

    Na = nsites(sys)
    Ncells = Na / natoms(cryst)
    Nf = nflavors(swt)
    L = Nf*Na
    n_lancozs_iters = 10
    Avec_pref = zeros(ComplexF64, Na) # initialize array of some prefactors

    Nobs = size(measure.observables, 1)
    Ncorr = length(measure.corr_pairs)
    corrbuf = zeros(ComplexF64, Ncorr)
    moments = ElasticArray{ComplexF64}(undef, Ncorr, 0)

    u = zeros(ComplexF64, Nobs, 2L)
    α0 = zeros(ComplexF64, Nobs, 2L)
    α1 = zeros(ComplexF64, Nobs, 2L)
    α2 = zeros(ComplexF64, Nobs, 2L)

    for (iq, q) in enumerate(qpts.qs)
        q_reshaped = to_reshaped_rlu(sys, q)
        q_global = cryst.recipvecs * q

        # Represent each local observable A(q) as a complex vector u(q) that
        # denotes a linear combination of HP bosons.

        for i in 1:Na
            r = sys.crystal.positions[i]
            ff = get_swt_formfactor(measure, 1, i)
            Avec_pref[i] = exp(2π*im * dot(q_reshaped, r))
            Avec_pref[i] *= compute_form_factor(ff, norm2(q_global))
        end

        if sys.mode == :SUN
            data_sun = swt.data::SWTDataSUN
            N = sys.Ns[1]
            for i in 1:Na, μ in 1:Nobs
                @views O = data_sun.observables_localized[μ, i]
                for f in 1:Nf
                    u[μ, f + (i-1)*Nf]     = Avec_pref[i] * O[f, N]
                    u[μ, f + (i-1)*Nf + L] = Avec_pref[i] * O[N, f]
                end
            end
        else
            @assert sys.mode in (:dipole, :dipole_large_s)
            data_dip = swt.data::SWTDataDipole
            for i in 1:Na
                sqrt_halfS = data_dip.sqrtS[i]/sqrt(2)
                for μ in 1:Nobs
                    O = data_dip.observables_localized[μ, i]
                    u[μ, i]   = Avec_pref[i] * sqrt_halfS * (O[1] + im*O[2])
                    u[μ, i+L] = Avec_pref[i] * sqrt_halfS * (O[1] - im*O[2])
                end
            end
        end

        # Bound eigenvalue magnitudes and determine order of polynomial
        # expansion

        lo, hi = eigbounds(swt, q_reshaped, n_lancozs_iters)
        γ = 1.1 * max(abs(lo), hi)
        factor = max(-3*log10(tol), 1)
        M = round(Int, factor * 2γ / kernel.fwhm)
        resize!(moments, Ncorr, M)

        if verbose
            println("Bounds=", (lo, hi), " M=", M)
        end

        # Perform Chebyshev recursion

        q_repeated = fill(q_reshaped, Nobs)
        mul_Ĩ!(α0, u)
        mul_A!(swt, α1, α0, q_repeated, γ)
        set_moments!(view(moments, :, 1), measure, u, α0)
        set_moments!(view(moments, :, 2), measure, u, α1)
        for m in 3:M
            mul_A!(swt, α2, α1, q_repeated, γ)
            @. α2 = 2*α2 - α0
            set_moments!(view(moments, :, m), measure, u, α2)
            (α0, α1, α2) = (α1, α2, α0)
        end

        # Transform Chebyshev moments to intensities for each ω

        buf = zeros(2M)
        plan = FFTW.plan_r2r!(buf, FFTW.REDFT10)

        for (iω, ω) in enumerate(energies)
            # Previously included factor `regularization_function(x / ωcut)`.
            f(x) = kernel(x, ω) * thermal_prefactor(x; kT)

            coefs = cheb_coefs!(M, f, (-γ, γ); buf, plan)
            apply_jackson_kernel!(coefs)
            for i in 1:Ncorr
                corrbuf[i] = dot(coefs, view(moments, i, :)) / Ncells
            end
            data[iω, iq] = measure.combiner(q_global, corrbuf)
        end
    end

    return Intensities(cryst, qpts, collect(energies), data)
end

function intensities(swt_kpm::SpinWaveTheoryKPM, qpts; energies, kernel::AbstractBroadening, kT=0.0, verbose=false)
    qpts = convert(AbstractQPoints, qpts)
    data = zeros(eltype(swt_kpm.swt.measure), length(energies), length(qpts.qs))
    return intensities!(data, swt_kpm, qpts; energies, kernel, kT, verbose)
end
