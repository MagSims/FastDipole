###########################################################################
# Below are the implementations of the SU(N) linear spin-wave calculations #
###########################################################################

@inline δ(x, y) = ==(x, y) # my delta function


"""
    generate_ham_lswt!

Update the linear spin-wave Hamiltonian from the exchange interactions.
Note that `k̃` is a 3-vector, the units of k̃ᵢ is 2π/|ãᵢ|, where |ãᵢ| is the lattice constant of the **magnetic** lattice.
"""
function swt_hamiltonian!(swt::SpinWaveTheory, k̃ :: Vector{Float64}, Hmat::Matrix{ComplexF64})
    (; sys, s̃_mat, T̃_mat, Q̃_mat) = swt
    Hmat .= 0 # DD: must be zeroed out!
    Nm, Ns = length(sys.dipoles), sys.Ns[1] # number of magnetic atoms and dimension of Hilbert space
    Nf = sys.mode == :SUN ? Ns-1 : 1
    N  = Nf + 1
    L  = Nf * Nm
    @assert size(Hmat) == (2*L, 2*L)
    # scaling factor (=1) if in the fundamental representation
    M = sys.mode == :SUN ? 1 : (Ns-1)
    no_single_ion = isempty(swt.sys.interactions_union[1].aniso.matrep)

    # the "metric" of scalar biquad interaction. Here we are using the following identity:
    # (𝐒ᵢ⋅𝐒ⱼ)² = -(𝐒ᵢ⋅𝐒ⱼ)/2 + ∑ₐ (OᵢᵃOⱼᵃ)/2, a=4,…,8
    # where the definition of Oᵢᵃ is given in Appendix B of *Phys. Rev. B 104, 104409*
    # Note: this is only valid for the `:dipole` mode, for `:SUN` mode, we consider 
    # different implementations
    biquad_metric = 1/2 * diagm([-1, -1, -1, 1/M, 1/M, 1/M, 1/M, 1/M])

    for k̃ᵢ in k̃
        (k̃ᵢ < 0.0 || k̃ᵢ ≥ 1.0) && throw("k̃ outside [0, 1) range")
    end

    # block matrices of `Hmat`
    Hmat11 = zeros(ComplexF64, L, L)
    Hmat22 = zeros(ComplexF64, L, L)
    Hmat12 = zeros(ComplexF64, L, L)
    Hmat21 = zeros(ComplexF64, L, L)

    (; extfield, gs, units) = sys

    # external field, need to multiply the `M` factor
    for matom = 1:Nm
        effB = units.μB * (gs[1, 1, 1, matom]' * extfield[1, 1, 1, matom])
        site_tS = s̃_mat[:, :, :, matom]
        site_B_dot_tS  = - effB[1] * site_tS[:, :, 1] - effB[2] * site_tS[:, :, 2] - effB[3] * site_tS[:, :, 3]
        for m = 2:N
            for n = 2:N
                δmn = δ(m, n)
                Hmat[(matom-1)*Nf+m-1,   (matom-1)*Nf+n-1]   += 0.5 * M * (site_B_dot_tS[m, n] - δmn * site_B_dot_tS[1, 1])
                Hmat[(matom-1)*Nf+n-1+L, (matom-1)*Nf+m-1+L] += 0.5 * M * (site_B_dot_tS[m, n] - δmn * site_B_dot_tS[1, 1])
            end
        end
    end

    # pairexchange interactions
    for matom = 1:Nm
        ints = sys.interactions_union[matom]
        # Heisenberg exchange
        for (; isculled, bond, J) in ints.heisen
            isculled && break
            sub_i, sub_j, ΔRδ = bond.i, bond.j, bond.n

            tTi_μ = s̃_mat[:, :, :, sub_i]
            tTj_ν = s̃_mat[:, :, :, sub_j]
            phase  = exp(2im * π * dot(k̃, ΔRδ))
            cphase = conj(phase)
            sub_i_M1, sub_j_M1 = sub_i - 1, sub_j - 1

            for m = 2:N
                mM1 = m - 1
                T_μ_11 = conj(tTi_μ[1, 1, :])
                T_μ_m1 = conj(tTi_μ[m, 1, :])
                T_μ_1m = conj(tTi_μ[1, m, :])
                T_ν_11 = tTj_ν[1, 1, :]

                for n = 2:N
                    nM1 = n - 1
                    δmn = δ(m, n)
                    T_μ_mn, T_ν_mn = conj(tTi_μ[m, n, :]), tTj_ν[m, n, :]
                    T_ν_n1 = tTj_ν[n, 1, :]
                    T_ν_1n = tTj_ν[1, n, :]

                    c1 = J * dot(T_μ_mn - δmn * T_μ_11, T_ν_11)
                    c2 = J * dot(T_μ_11, T_ν_mn - δmn * T_ν_11)
                    c3 = J * dot(T_μ_m1, T_ν_1n)
                    c4 = J * dot(T_μ_1m, T_ν_n1)
                    c5 = J * dot(T_μ_m1, T_ν_n1)
                    c6 = J * dot(T_μ_1m, T_ν_1n)

                    Hmat11[sub_i_M1*Nf+mM1, sub_i_M1*Nf+nM1] += 0.5 * c1
                    Hmat11[sub_j_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c2
                    Hmat22[sub_i_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c1
                    Hmat22[sub_j_M1*Nf+nM1, sub_j_M1*Nf+mM1] += 0.5 * c2

                    Hmat11[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c3 * phase
                    Hmat22[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c3 * cphase
                    
                    Hmat22[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c4 * phase
                    Hmat11[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c4 * cphase

                    Hmat12[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c5 * phase
                    Hmat12[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c5 * cphase
                    Hmat21[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c6 * phase
                    Hmat21[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c6 * cphase
                end
            end
        end

        # Quadratic exchange
        for (; isculled, bond, J) in ints.exchange
            isculled && break
            sub_i, sub_j, ΔRδ = bond.i, bond.j, bond.n

            tTi_μ = s̃_mat[:, :, :, sub_i]
            tTj_ν = s̃_mat[:, :, :, sub_j]
            phase  = exp(2im * π * dot(k̃, ΔRδ))
            cphase = conj(phase)
            sub_i_M1, sub_j_M1 = sub_i - 1, sub_j - 1

            for m = 2:N
                mM1 = m - 1
                T_μ_11 = conj(tTi_μ[1, 1, :])
                T_μ_m1 = conj(tTi_μ[m, 1, :])
                T_μ_1m = conj(tTi_μ[1, m, :])
                T_ν_11 = tTj_ν[1, 1, :]

                for n = 2:N
                    nM1 = n - 1
                    δmn = δ(m, n)
                    T_μ_mn, T_ν_mn = conj(tTi_μ[m, n, :]), tTj_ν[m, n, :]
                    T_ν_n1 = tTj_ν[n, 1, :]
                    T_ν_1n = tTj_ν[1, n, :]

                    c1 = dot(T_μ_mn - δmn * T_μ_11, J, T_ν_11)
                    c2 = dot(T_μ_11, J, T_ν_mn - δmn * T_ν_11)
                    c3 = dot(T_μ_m1, J, T_ν_1n)
                    c4 = dot(T_μ_1m, J, T_ν_n1)
                    c5 = dot(T_μ_m1, J, T_ν_n1)
                    c6 = dot(T_μ_1m, J, T_ν_1n)

                    Hmat11[sub_i_M1*Nf+mM1, sub_i_M1*Nf+nM1] += 0.5 * c1
                    Hmat11[sub_j_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c2
                    Hmat22[sub_i_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c1
                    Hmat22[sub_j_M1*Nf+nM1, sub_j_M1*Nf+mM1] += 0.5 * c2

                    Hmat11[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c3 * phase
                    Hmat22[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c3 * cphase
                    
                    Hmat22[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c4 * phase
                    Hmat11[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c4 * cphase

                    Hmat12[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c5 * phase
                    Hmat12[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c5 * cphase
                    Hmat21[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c6 * phase
                    Hmat21[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c6 * cphase
                end
            end
        end

        for (; isculled, bond, J) in ints.biquad
            isculled && break
            sub_i, sub_j, ΔRδ = bond.i, bond.j, bond.n

            tTi_μ = zeros(ComplexF64, N, N, 8)
            tTj_ν = zeros(ComplexF64, N, N, 8)

            for i = 1:3
                tTi_μ[:, :, i] = s̃_mat[:, :, i, sub_i]
                tTj_ν[:, :, i] = s̃_mat[:, :, i, sub_j]
            end

            for i = 4:8
                tTi_μ[:, :, i] = Q̃_mat[:, :, i-3, sub_i]
                tTj_ν[:, :, i] = Q̃_mat[:, :, i-3, sub_j]
            end

            phase  = exp(2im * π * dot(k̃, ΔRδ))
            cphase = conj(phase)
            sub_i_M1, sub_j_M1 = sub_i - 1, sub_j - 1

            for m = 2:N
                mM1 = m - 1
                T_μ_11 = conj(tTi_μ[1, 1, :])
                T_μ_m1 = conj(tTi_μ[m, 1, :])
                T_μ_1m = conj(tTi_μ[1, m, :])
                T_ν_11 = tTj_ν[1, 1, :]

                for n = 2:N
                    nM1 = n - 1
                    δmn = δ(m, n)
                    T_μ_mn, T_ν_mn = conj(tTi_μ[m, n, :]), tTj_ν[m, n, :]
                    T_ν_n1 = tTj_ν[n, 1, :]
                    T_ν_1n = tTj_ν[1, n, :]
                    # now the biquad interactions are only supported in the :dipole mode,
                    # since for the dipole mode, we do not need to multiply the `M` factor
                    # we first divide and then multiply back to be consistent
                    c1 = J * dot(T_μ_mn - δmn * T_μ_11, biquad_metric, T_ν_11)
                    c2 = J * dot(T_μ_11, biquad_metric, T_ν_mn - δmn * T_ν_11)
                    c3 = J * dot(T_μ_m1, biquad_metric, T_ν_1n)
                    c4 = J * dot(T_μ_1m, biquad_metric, T_ν_n1)
                    c5 = J * dot(T_μ_m1, biquad_metric, T_ν_n1)
                    c6 = J * dot(T_μ_1m, biquad_metric, T_ν_1n)

                    Hmat11[sub_i_M1*Nf+mM1, sub_i_M1*Nf+nM1] += 0.5 * c1
                    Hmat11[sub_j_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c2
                    Hmat22[sub_i_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c1
                    Hmat22[sub_j_M1*Nf+nM1, sub_j_M1*Nf+mM1] += 0.5 * c2

                    Hmat11[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c3 * phase
                    Hmat22[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c3 * cphase
                    
                    Hmat22[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c4 * phase
                    Hmat11[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c4 * cphase

                    Hmat12[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c5 * phase
                    Hmat12[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c5 * cphase
                    Hmat21[sub_i_M1*Nf+mM1, sub_j_M1*Nf+nM1] += 0.5 * c6 * phase
                    Hmat21[sub_j_M1*Nf+nM1, sub_i_M1*Nf+mM1] += 0.5 * c6 * cphase
                end
            end
        end
    end

    Hmat[1:L, 1:L] += M * Hmat11
    Hmat[L+1:2*L, L+1:2*L] += M * Hmat22
    Hmat[1:L, L+1:2*L] += M * Hmat12
    Hmat[L+1:2*L, 1:L] += M * Hmat21

    # single-ion anisotropy. For :SUN and :dipole mode, we should not multiply the results by the factor `M`, because the single-ion anisotropy is written in the fundamental representation.
    if !no_single_ion
        for matom = 1:Nm
            @views site_aniso = T̃_mat[:, :, matom]
            for m = 2:N
                for n = 2:N
                    δmn = δ(m, n)
                    Hmat[(matom-1)*Nf+m-1,   (matom-1)*Nf+n-1]   += 0.5 * (site_aniso[m, n] - δmn * site_aniso[1, 1])
                    Hmat[(matom-1)*Nf+n-1+L, (matom-1)*Nf+m-1+L] += 0.5 * (site_aniso[m, n] - δmn * site_aniso[1, 1])
                end
            end
        end
    end

    # Hmat must be hermitian up to round-off errors
    if norm(Hmat-Hmat') > 1e-12
        println("norm(Hmat-Hmat')= ", norm(Hmat-Hmat'))
        throw("Hmat is not hermitian!")
    end
    
    # make Hmat exactly hermitian for cholesky decomposition.
    Hmat[:, :] = (0.5 + 0.0im) * (Hmat + Hmat')

    # add tiny part to the diagonal elements for cholesky decomposition.
    for ii = 1:2*L
        Hmat[ii, ii] += swt.energy_ϵ
    end
end

"""
    bogoliubov!

Bogoliubov transformation that diagonalizes a bosonic Hamiltonian. 
See Colpa JH. *Diagonalization of the quadratic boson hamiltonian* 
Physica A: Statistical Mechanics and its Applications, 1978 Sep 1;93(3-4):327-53.
"""
function bogoliubov!(disp, V, Hmat, energy_tol, mode_fast::Bool = false)
    @assert size(Hmat, 1) == size(Hmat, 2) "Hmat is not a square matrix"
    @assert size(Hmat, 1) % 2 == 0 "dimension of Hmat is not even"

    L = size(Hmat, 1) ÷ 2
    (length(disp) != L) && (resize!(disp, L))

    Σ = diagm([ones(ComplexF64, L); -ones(ComplexF64, L)])

    if (!mode_fast)
        eigval_check = eigen(Σ * Hmat).values
        @assert all(<(energy_tol), abs.(imag(eigval_check))) "Matrix contains complex eigenvalues with imaginary part larger than `energy_tol`= "*string(energy_tol)*"(`sw_fields.coherent_states` not a classical ground state of the Hamiltonian)"

        eigval_check = eigen(Hmat).values
        @assert all(>(1e-12), real(eigval_check)) "Matrix not positive definite (`sw_fields.coherent_states` not a classical ground state of the Hamiltonian)"
    end

    K = cholesky(Hmat).U
    @assert mode_fast || norm(K' * K - Hmat) < 1e-12 "Cholesky fails"

    T = K * Σ * K'
    eigval, U = eigen(Hermitian(T + T') / 2)

    @assert mode_fast || norm(U * U' - I) < 1e-10 "Orthonormality fails"

    # sort eigenvalues and eigenvectors
    eigval = real(eigval)
    # sort eigenvalues in descending order
    index  = sortperm(eigval, rev=true)
    eigval = eigval[index]
    U = U[:, index]
    for i = 1:2*L
        if (i ≤ L && eigval[i] < 0.0) || (i > L && eigval[i] > 0.0)
            error("Matrix not positive definite (`sw_fields.coherent_states` not a classical ground state of the Hamiltonian)")
        end
        pref = i ≤ L ? √(eigval[i]) : √(-eigval[i])
        U[:, i] .*= pref
    end

    for col = 1:2*L
        normalize!(U[:, col])
    end

    V[:] = K \ U

    if (!mode_fast)
        E_check = V' * Hmat * V
        [E_check[i, i] -= eigval[i] for i = 1:L]
        [E_check[i, i] += eigval[i] for i = L+1:2*L]
        @assert all(<(1e-8), abs.(E_check)) "Eigenvectors check fails (Bogoliubov matrix `V` are not normalized!)"
        @assert all(<(1e-6), abs.(V' * Σ * V - Σ)) "Para-renormalization check fails (Boson commutatition relations not preserved after the Bogoliubov transformation!)"
    end

    # The linear spin-wave dispersion also in descending order.
    return [disp[i] = 2.0 * eigval[i] for i = 1:L]

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

**Experimental**. Computes the spin excitation energy dispersion relations given a
[`SpinWaveTheory`](@ref) and an array of wave vectors `qs`. Each element ``q``
of `qs` must be a 3-vector in units of reciprocal lattice units. I.e., ``qᵢ`` is
given in ``2π/|aᵢ|`` with ``|aᵢ|`` the lattice constant of the chemical lattice.

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
    disp_buf = zeros(Float64, nmodes)
    disp = zeros(Float64, nmodes, length(qs)) 

    for (iq, q) in enumerate(qs)
        _, qmag = chemical_to_magnetic(swt, q)
        swt_hamiltonian!(swt, qmag, ℋ)
        bogoliubov!(disp_buf, Vbuf, ℋ, energy_tol)
        disp[:,iq] .= disp_buf
    end

    return reshape_dispersions(disp)
end


"""
    dssf(swt::SpinWaveTheory, qs)

**Experimental**. Given a [`SpinWaveTheory`](@ref) object, computes the dynamical spin structure
factor,

```math
    𝒮^{αβ}(𝐤, ω) = 1/(2πN)∫dt ∑_𝐫 \\exp[i(ωt - 𝐤⋅𝐫)] ⟨S^α(𝐫, t)S^β(0, 0)⟩,
```

using the result from linear spin-wave theory,

```math
    𝒮^{αβ}(𝐤, ω) = ∑_n |A_n^{αβ}(𝐤)|^2 δ[ω-ω_n(𝐤)].
```

`qs` is an array of wave vectors of arbitrary dimension. Each element ``q`` of
`qs` must be a 3-vector in reciprocal lattice units. I.e., ``q_i`` is given in
``2π/|a_i|`` with ``|a_i|`` the lattice constant of the chemical lattice.

The first indices of the returned array correspond to those of `qs`. A final
index, corresponding to mode, is added to these. Each entry of this array is a
tensor (3×3 matrix) corresponding to the indices ``α`` and ``β``.
"""
function dssf(swt::SpinWaveTheory, qs)
    (; sys, positions_chem, s̃_mat) = swt
    qs = Vec3.(qs)
    Nm, Ns = length(sys.dipoles), sys.Ns[1] # number of magnetic atoms and dimension of Hilbert space
    Nf = sys.mode == :SUN ? Ns-1 : 1
    N  = Nf + 1
    nmodes  = Nf * Nm 
    M = sys.mode == :SUN ? 1 : (Ns-1) # scaling factor (=1) if in the fundamental representation
    sqrt_M = √M
    sqrt_Nm_inv = 1.0 / √Nm

    # Preallocation
    Hmat = zeros(ComplexF64, 2*nmodes, 2*nmodes)
    Vmat = zeros(ComplexF64, 2*nmodes, 2*nmodes)
    disp = zeros(Float64, nmodes, size(qs)...)
    Avec_pref = zeros(ComplexF64, Nm)
    Sαβs = zeros(ComplexF64, 3, 3, nmodes, size(qs)...) 

    # Calculate DSSF 
    for qidx in CartesianIndices(qs)
        q = qs[qidx]
        _, qmag = chemical_to_magnetic(swt, q)

        swt_hamiltonian!(swt, qmag, Hmat)
        bogoliubov!(@view(disp[:,qidx]), Vmat, Hmat, swt.energy_tol)

        for site = 1:Nm
            # note that d is the chemical coordinates
            chemical_coor = positions_chem[site]
            phase = exp(-2im * π  * dot(q, chemical_coor))
            Avec_pref[site] = sqrt_Nm_inv * phase * sqrt_M
        end

        for band = 1:nmodes
            v = Vmat[:, band]
            Avec = zeros(ComplexF64, 3)
            for site = 1:Nm
                @views tS_μ = s̃_mat[:, :, :, site]
                for μ = 1:3
                    for α = 2:N
                        Avec[μ] += Avec_pref[site] * (tS_μ[α, 1, μ] * v[(site-1)*(N-1)+α-1+nmodes] + tS_μ[1, α, μ] * v[(site-1)*(N-1)+α-1])
                    end
                end
            end

            # DD: Generalize this based on list of arbitrary operators, optimize out symmetry, etc.
            Sαβs[1,1,band,qidx] = real(Avec[1] * conj(Avec[1]))
            Sαβs[1,2,band,qidx] = Avec[1] * conj(Avec[2])
            Sαβs[1,3,band,qidx] = Avec[1] * conj(Avec[3])
            Sαβs[2,2,band,qidx] = real(Avec[2] * conj(Avec[2]))
            Sαβs[2,3,band,qidx] = Avec[2] * conj(Avec[3])
            Sαβs[3,3,band,qidx] = real(Avec[3] * conj(Avec[3]))
            Sαβs[2,1,band,qidx] = conj(Sαβs[1,2,band,qidx]) 
            Sαβs[3,1,band,qidx] = conj(Sαβs[3,1,band,qidx]) 
            Sαβs[3,2,band,qidx] = conj(Sαβs[2,3,band,qidx]) 
        end
    end

    return reshape_dispersions(disp), reshape_correlations(Sαβs) 
end 


struct SpinWaveIntensityFormula{T}
    string_formula :: String
    calc_intensity :: Function
end

function Base.show(io::IO, formula::SpinWaveIntensityFormula{T}) where T
    print(io,"SpinWaveIntensityFormula{$T}")
end

function Base.show(io::IO, ::MIME"text/plain", formula::SpinWaveIntensityFormula{T}) where T
    printstyled(io, "Quantum Scattering Intensity Formula\n";bold=true, color=:underline)

    formula_lines = split(formula.string_formula,'\n')

    intensity_equals = "  Intensity(Q,ω) = ∑ᵢ δ(ω-ωᵢ) "
    println(io,"At any Q and for each band ωᵢ = εᵢ(Q), with S = S(Q,ωᵢ):")
    println(io)
    println(io,intensity_equals,formula_lines[1])
    for i = 2:length(formula_lines)
        precursor = repeat(' ', textwidth(intensity_equals))
        println(io,precursor,formula_lines[i])
    end
    println(io)
    println(io,"Intensity :: $(T) and dispersion reported for each band")
end


function intensity_formula(f::Function,swt::SpinWaveTheory,corr_ix::AbstractVector{Int64}; return_type = Float64, string_formula = "f(Q,ω,S{α,β}[ix_q,ix_ω])")
    (; sys, positions_chem, s̃_mat) = swt
    Nm, Ns = length(sys.dipoles), sys.Ns[1] # number of magnetic atoms and dimension of Hilbert space
    Nf = sys.mode == :SUN ? Ns-1 : 1
    N  = Nf + 1
    nmodes  = Nf * Nm 
    M = sys.mode == :SUN ? 1 : (Ns-1) # scaling factor (=1) if in the fundamental representation
    sqrt_M = √M
    sqrt_Nm_inv = 1.0 / √Nm

    # Preallocation
    Hmat = zeros(ComplexF64, 2*nmodes, 2*nmodes)
    Vmat = zeros(ComplexF64, 2*nmodes, 2*nmodes)
    Avec_pref = zeros(ComplexF64, Nm)
    disp = zeros(Float64, nmodes)
    intensity = zeros(Float64, nmodes)

    # Calculate DSSF 
    formula = function(swt::SpinWaveTheory,q::Vec3)
        _, qmag = chemical_to_magnetic(swt, q)

        swt_hamiltonian!(swt, qmag, Hmat)
        bogoliubov!(disp, Vmat, Hmat, swt.energy_tol)

        for site = 1:Nm
            # note that d is the chemical coordinates
            chemical_coor = positions_chem[site]
            phase = exp(-2im * π  * dot(q, chemical_coor))
            Avec_pref[site] = sqrt_Nm_inv * phase * sqrt_M
        end

        for band = 1:nmodes
            v = Vmat[:, band]
            Avec = zeros(ComplexF64, 3)
            for site = 1:Nm
                @views tS_μ = s̃_mat[:, :, :, site]
                for μ = 1:3
                    for α = 2:N
                        Avec[μ] += Avec_pref[site] * (tS_μ[α, 1, μ] * v[(site-1)*(N-1)+α-1+nmodes] + tS_μ[1, α, μ] * v[(site-1)*(N-1)+α-1])
                    end
                end
            end

            # DD: Generalize this based on list of arbitrary operators, optimize out symmetry, etc.
            Sαβ = Matrix{ComplexF64}(undef,3,3)
            Sαβ[1,1] = real(Avec[1] * conj(Avec[1]))
            Sαβ[1,2] = Avec[1] * conj(Avec[2])
            Sαβ[1,3] = Avec[1] * conj(Avec[3])
            Sαβ[2,2] = real(Avec[2] * conj(Avec[2]))
            Sαβ[2,3] = Avec[2] * conj(Avec[3])
            Sαβ[3,3] = real(Avec[3] * conj(Avec[3]))
            Sαβ[2,1] = conj(Sαβ[1,2]) 
            Sαβ[3,1] = conj(Sαβ[3,1]) 
            Sαβ[3,2] = conj(Sαβ[2,3])

            k = swt.recipvecs_chem * q
            intensity[band] = f(k,disp[band],Sαβ[corr_ix])
        end
        return disp, intensity
    end
    SpinWaveIntensityFormula{return_type}(string_formula,formula)
end


