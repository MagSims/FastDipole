# Bogoliubov transformation that diagonalizes a bosonic Hamiltonian. See Colpa
# JH. *Diagonalization of the quadratic boson hamiltonian* Physica A:
# Statistical Mechanics and its Applications, 1978 Sep 1;93(3-4):327-53.
function mk_bogoliubov!(L)
    Σ = Diagonal(diagm([ones(ComplexF64, L); -ones(ComplexF64, L)]))
    buf = UpperTriangular(zeros(ComplexF64,2L,2L))

    function bogoliubov!(disp, V, H, energy_tol, mode_fast::Bool = false)
        @assert size(H, 1) == size(H, 2) "H is not a square matrix"
        @assert size(H, 1) % 2 == 0 "dimension of H is not even"
        @assert size(H, 1) ÷ 2 == L "dimension of H doesn't match $L"
        @assert length(disp) == L "length of dispersion doesn't match $L"

        if (!mode_fast)
            eigval_check = eigen(Σ * H).values
            @assert all(<(energy_tol), abs.(imag(eigval_check))) "Matrix contains complex eigenvalues with imaginary part larger than `energy_tol`= "*string(energy_tol)*"(`sw_fields.coherent_states` not a classical ground state of the Hamiltonian)"

            eigval_check = eigen(H).values
            @assert all(>(1e-12), real(eigval_check)) "Matrix not positive definite (`sw_fields.coherent_states` not a classical ground state of the Hamiltonian)"
        end
  
        K = if mode_fast
          cholesky!(H).U # Clobbers H
        else
          K = cholesky(H).U
          @assert norm(K' * K - H) < 1e-12 "Cholesky fails"
          K
        end

        # Compute eigenvalues of KΣK', sorted in descending order by real part
        eigval, U = if mode_fast
          mul!(buf,K,Σ)
          mul!(V,buf,K')
          # Hermitian only views the upper triangular, so no need
          # to explicitly symmetrize here
          T = Hermitian(V)
          eigen!(T;sortby = λ -> -real(λ)) # Clobbers
        else
          T = K * Σ * K'
          eigen(Hermitian(T + T') / 2;sortby = λ -> -real(λ))
        end

        @assert mode_fast || norm(U * U' - I) < 1e-10 "Orthonormality fails"

        for i = 1:2*L
            if (i ≤ L && eigval[i] < 0.0) || (i > L && eigval[i] > 0.0)
                error("Matrix not positive definite (`sw_fields.coherent_states` not a classical ground state of the Hamiltonian)")
            end
            pref = i ≤ L ? √(eigval[i]) : √(-eigval[i])
            view(U,:,i) .*= pref
        end

        V .= U
        ldiv!(K,V)

        if (!mode_fast)
            E_check = V' * H * V
            [E_check[i, i] -= eigval[i] for i = 1:L]
            [E_check[i, i] += eigval[i] for i = L+1:2*L]
            @assert all(<(1e-8), abs.(E_check)) "Eigenvectors check fails (Bogoliubov matrix `V` are not normalized!)"
            @assert all(<(1e-6), abs.(V' * Σ * V - Σ)) "Para-renormalization check fails (Boson commutatition relations not preserved after the Bogoliubov transformation!)"
        end

        # The linear spin-wave dispersion in descending order.
        for i in 1:L
            disp[i] = 2eigval[i]
        end
        return
    end
end


# DD: These two functions are a stopgap until data is treated differently in
# main calculations. Also, the final data layout will need to be iterated on. I
# am thinking the user should always be able to get some array with indices
# identical to the list of wave vectors. This could be achieved, for example, by
# having the output be an array with length equal to the number of modes. Each
# entry would then be an array with dimension equal to the array of wave
# vectors. The entries of this array would then depend on the request (an an
# energy, an intensity, an entire tensor stored as an SMatrix, etc.) 
# The key point is to make it as easy as possible to put the output
# in correspondence with the input for plotting, further processing, etc.
function reshape_correlations(corrs)
    qdims, nmodes = size(corrs)[4:end], size(corrs)[3]  # First two indices are are always tensor indices
    idxorder = collect(1:ndims(corrs))
    idxorder[3], idxorder[end] = idxorder[end], idxorder[3]
    corrs = permutedims(corrs, idxorder)
    return selectdim(reinterpret(SMatrix{3,3,ComplexF64,9}, reshape(corrs, 9, qdims...,nmodes) ), 1, 1)
end

function reshape_dispersions(disp)
    idxorder = collect(1:ndims(disp))
    idxorder[1], idxorder[end] = idxorder[end], idxorder[1]
    return permutedims(disp, idxorder)
end

"""
    dispersion(swt::SpinWaveTheory, qs)

Computes the spin excitation energy dispersion relations given a
[`SpinWaveTheory`](@ref) and an array of wave vectors `qs`. Each element ``q``
of `qs` must be a 3-vector in units of reciprocal lattice units. I.e., ``qᵢ`` is
given in ``2π/|aᵢ|`` with ``|aᵢ|`` the lattice constant of the original chemical
lattice.

The first indices of the returned array correspond to those of `qs`. A final
index, corresponding to mode, is added to these. Each entry of the array is an
energy.
"""
function dispersion(swt::SpinWaveTheory, qs)
    (; sys, energy_tol) = swt
    
    Nm, Ns = length(sys.dipoles), sys.Ns[1] # number of magnetic atoms and dimension of Hilbert space
    Nf = sys.mode == :SUN ? Ns-1 : 1
    nmodes  = Nf * Nm

    ℋ = zeros(ComplexF64, 2nmodes, 2nmodes)
    Vbuf = zeros(ComplexF64, 2nmodes, 2nmodes)
    disp = zeros(Float64, nmodes, length(qs))
    bogoliubov! = mk_bogoliubov!(nmodes)

    for (iq, q) in enumerate(qs)
        q_reshaped = to_reshaped_rlu(swt.sys, q)
        if sys.mode == :SUN
            swt_hamiltonian_SUN!(ℋ, swt, q_reshaped)
        else
            @assert sys.mode in (:dipole, :dipole_large_S)
            swt_hamiltonian_dipole!(ℋ, swt, q_reshaped)
        end
        bogoliubov!(view(disp,:,iq), Vbuf, ℋ, energy_tol)
    end

    return reshape_dispersions(disp)
end


"""
    dssf(swt::SpinWaveTheory, qs)

Given a [`SpinWaveTheory`](@ref) object, computes the dynamical spin structure
factor,

```math
    𝒮^{αβ}(𝐤, ω) = 1/(2πN)∫dt ∑_𝐫 \\exp[i(ωt - 𝐤⋅𝐫)] ⟨S^α(𝐫, t)S^β(0, 0)⟩,
```

using the result from linear spin-wave theory,

```math
    𝒮^{αβ}(𝐤, ω) = ∑_n |A_n^{αβ}(𝐤)|^2 δ[ω-ω_n(𝐤)].
```

`qs` is an array of wave vectors of arbitrary dimension. Each element ``q`` of
`qs` must be a 3-vector in reciprocal lattice units (RLU), i.e., in the basis of
reciprocal lattice vectors.

The first indices of the returned array correspond to those of `qs`. A final
index, corresponding to mode, is added to these. Each entry of this array is a
tensor (3×3 matrix) corresponding to the indices ``α`` and ``β``.
"""
function dssf(swt::SpinWaveTheory, qs)
    qs = Vec3.(qs)
    nmodes = num_bands(swt)

    disp = zeros(Float64, nmodes, size(qs)...)
    Sαβs = zeros(ComplexF64, 3, 3, nmodes, size(qs)...) 

    # dssf(...) doesn't do any contraction, temperature correction, etc.
    # It simply returns the full Sαβ correlation matrix
    formula = intensity_formula(swt, :full; kernel = delta_function_kernel)

    # Calculate DSSF 
    for qidx in CartesianIndices(qs)
        q = qs[qidx]
        band_structure = formula.calc_intensity(swt,q)
        for band = 1:nmodes
            disp[band,qidx] = band_structure.dispersion[band]
            Sαβs[:,:,band,qidx] .= band_structure.intensity[band]
        end
    end

    return reshape_dispersions(disp), reshape_correlations(Sαβs) 
end 


struct BandStructure{N,T}
  dispersion :: SVector{N,Float64}
  intensity :: SVector{N,T}
end

struct SpinWaveIntensityFormula{T}
    string_formula :: String
    kernel :: Union{Nothing,Function}
    calc_intensity :: Function
end

function Base.show(io::IO, ::SpinWaveIntensityFormula{T}) where T
    print(io,"SpinWaveIntensityFormula{$T}")
end

function Base.show(io::IO, ::MIME"text/plain", formula::SpinWaveIntensityFormula{T}) where T
    printstyled(io, "Quantum Scattering Intensity Formula\n"; bold=true, color=:underline)

    formula_lines = split(formula.string_formula, '\n')

    if isnothing(formula.kernel)
        println(io, "At any Q and for each band ωᵢ = εᵢ(Q), with S = S(Q,ωᵢ):\n")
        intensity_equals = "  Intensity(Q,ω) = ∑ᵢ δ(ω-ωᵢ) "
    else
        println(io, "At any (Q,ω), with S = S(Q,ωᵢ):\n")
        intensity_equals = "  Intensity(Q,ω) = ∑ᵢ Kernel(ω-ωᵢ) "
    end
    separator = '\n' * repeat(' ', textwidth(intensity_equals))
    println(io, intensity_equals, join(formula_lines, separator))
    println(io)
    if isnothing(formula.kernel)
        println(io,"BandStructure information (ωᵢ and intensity) reported for each band")
    else
        println(io,"Intensity(ω) reported")
    end
end

delta_function_kernel = nothing

"""
    formula = intensity_formula(swt::SpinWaveTheory; kernel = ...)

Establish a formula for computing the scattering intensity by diagonalizing
the hamiltonian ``H(q)`` using Linear Spin Wave Theory.

If `kernel = delta_function_kernel`, then the resulting formula can be used with
[`intensities_bands`](@ref).

If `kernel` is an energy broadening kernel function, then the resulting formula can be used with [`intensities_broadened`](@ref).
Energy broadening kernel functions can either be a function of `Δω` only, e.g.:

    kernel = Δω -> ...

or a function of both the energy transfer `ω` and of `Δω`, e.g.:

    kernel = (ω,Δω) -> ...

The integral of a properly normalized kernel function over all `Δω` is one.
"""
function intensity_formula(f::Function,swt::SpinWaveTheory,corr_ix::AbstractVector{Int64}; kernel::Union{Nothing,Function},
                           return_type=Float64, string_formula="f(Q,ω,S{α,β}[ix_q,ix_ω])", mode_fast=false,
                           formfactors=nothing)
    (; sys, data, observables) = swt
    Nm, Ns = length(sys.dipoles), sys.Ns[1] # number of magnetic atoms and dimension of Hilbert space
    S = (Ns-1) / 2
    nmodes = num_bands(swt)
    sqrt_Nm_inv = 1.0 / √Nm
    sqrt_halfS  = √(S/2)

    # Preallocation
    H = zeros(ComplexF64, 2*nmodes, 2*nmodes)
    V = zeros(ComplexF64, 2*nmodes, 2*nmodes)
    Avec_pref = zeros(ComplexF64, Nm)
    disp = zeros(Float64, nmodes)
    intensity = zeros(return_type, nmodes)
    bogoliubov! = mk_bogoliubov!(nmodes)

    # Expand formfactors for symmetry classes to formfactors for all atoms in
    # crystal
    ff_atoms = propagate_form_factors_to_atoms(formfactors, swt.sys.crystal)

    # Upgrade to 2-argument kernel if needed
    kernel_edep = if isnothing(kernel)
        nothing
    else
        try
            kernel(0.,0.)
            kernel
        catch MethodError
            (ω,Δω) -> kernel(Δω)
        end
    end

    # In Spin Wave Theory, the Hamiltonian depends on momentum transfer `q`.
    # At each `q`, the Hamiltonian is diagonalized one time, and then the
    # energy eigenvalues can be reused multiple times. To facilitate this,
    # `I_of_ω = calc_intensity(swt,q)` performs the diagonalization, and returns
    # the result either as:
    #
    #   Delta function kernel --> I_of_ω = (eigenvalue,intensity) pairs
    #
    #   OR
    #
    #   Smooth kernel --> I_of_ω = Intensity as a function of ω
    #
    calc_intensity = function(swt::SpinWaveTheory, q::Vec3)
        # This function, calc_intensity, is an internal function to be stored
        # inside a formula. The unit system for `q` that is passed to
        # formula.calc_intensity is an implementation detail that may vary
        # according to the "type" of a formula. In the present context, namely
        # LSWT formulas, `q` is given in RLU for the original crystal. This
        # convention must be consistent with the usage in various
        # `intensities_*` functions defined in LinearSpinWaveIntensities.jl.
        # Separately, the functions calc_intensity for formulas associated with
        # SampledCorrelations will receive `q_absolute` in absolute units.
        q_reshaped = to_reshaped_rlu(swt.sys, q)
        q_absolute = swt.sys.crystal.recipvecs * q_reshaped

        if sys.mode == :SUN
            swt_hamiltonian_SUN!(H, swt, q_reshaped)
        else
            @assert sys.mode in (:dipole, :dipole_large_S)
            swt_hamiltonian_dipole!(H, swt, q_reshaped)
        end
        bogoliubov!(disp, V, H, swt.energy_tol, mode_fast)

        for i = 1:Nm
            @assert Nm == natoms(sys.crystal)
            phase = exp(-2π*im * dot(q_reshaped, sys.crystal.positions[i]))
            Avec_pref[i] = sqrt_Nm_inv * phase

            # TODO: move form factor into `f`, then delete this rescaling
            Avec_pref[i] *= compute_form_factor(ff_atoms[i], q_absolute⋅q_absolute)
        end

        # Fill `intensity` array
        for band = 1:nmodes
            v = V[:, band]
            corrs = if sys.mode == :SUN
                Avec = zeros(ComplexF64, num_observables(observables))
                (; observable_operators) = data
                for i = 1:Nm
                    for μ = 1:num_observables(observables)
                        @views O = observable_operators[:, :, μ, i]
                        for α = 2:Ns
                            Avec[μ] += Avec_pref[i] * (O[α, 1] * v[(i-1)*(Ns-1)+α-1+nmodes] + O[1, α] * v[(i-1)*(Ns-1)+α-1])
                        end
                    end
                end
                corrs = Vector{ComplexF64}(undef,num_correlations(observables))
                for (ci,i) in observables.correlations
                    (α,β) = ci.I
                    corrs[i] = Avec[α] * conj(Avec[β])
                end
                corrs
            else
                @assert sys.mode in (:dipole, :dipole_large_S)
                Avec = zeros(ComplexF64, 3)
                (; R_mat) = data
                for i = 1:Nm
                    Vtmp = [v[i+nmodes] + v[i], im * (v[i+nmodes] - v[i]), 0.0]
                    Avec += Avec_pref[i] * sqrt_halfS * (R_mat[i] * Vtmp)
                end

                @assert observables.observable_ixs[:Sx] == 1
                @assert observables.observable_ixs[:Sy] == 2
                @assert observables.observable_ixs[:Sz] == 3
                corrs = Vector{ComplexF64}(undef,num_correlations(observables))
                for (ci,i) in observables.correlations
                    (α,β) = ci.I
                    corrs[i] = Avec[α] * conj(Avec[β])
                end
                corrs
            end

            intensity[band] = f(q_absolute, disp[band], corrs[corr_ix])
        end

        # Return the result of the diagonalization in an appropriate
        # format based on the kernel provided
        if isnothing(kernel)
            # Delta function kernel --> (eigenvalue,intensity) pairs

            # If there is no specified kernel, we are done: just return the
            # BandStructure
            return BandStructure{nmodes,return_type}(disp, intensity)
        else
            # Smooth kernel --> Intensity as a function of ω (or a list of ωs)
            return function(ω)
                is = Vector{return_type}(undef,length(ω))
                is .= sum(intensity' .* kernel_edep.(disp',ω .- disp'),dims=2)
                is
            end
        end
    end
    output_type = isnothing(kernel) ? BandStructure{nmodes,return_type} : return_type
    SpinWaveIntensityFormula{output_type}(string_formula,kernel_edep,calc_intensity)
end