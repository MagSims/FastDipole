# Construct portion of Hamiltonian due to onsite terms (single-site anisotropy
# or external field).
function swt_onsite_coupling!(H, op, swt, atom)
    sys = swt.sys
    N = sys.Ns[1] 
    nflavors = N - 1 
    L = nflavors * natoms(sys.crystal)   
    newdims = (nflavors, natoms(sys.crystal), nflavors, natoms(sys.crystal))

    H11 = reshape(view(H, 1:L, 1:L), newdims)
    H22 = reshape(view(H, L+1:2L, L+1:2L), newdims)

    for m in 1:N-1
        for n in 1:N-1
            c = 0.5 * (op[m, n] - δ(m, n) * op[N, N])
            H11[m, atom, n, atom] += c
            H22[n, atom, m, atom] += c
        end
    end
end

# Adds contribution of a bilinear pair of operators Ai * Bj, where Ai is on site
# i, and Bj is on site j. Typically these will be generated by the sparse tensor
# decomposition stored in the `general` field of a `PairCoupling`.
function swt_pair_coupling!(H, Ai, Bj, swt, phase, bond)
    (; i, j) = bond
    sys = swt.sys
    N = sys.Ns[1] 
    nflavors = N - 1 
    L = nflavors * natoms(sys.crystal)   
    newdims = (nflavors, natoms(sys.crystal), nflavors, natoms(sys.crystal))

    H11 = reshape(view(H, 1:L, 1:L), newdims)
    H12 = reshape(view(H, 1:L, L+1:2L), newdims)
    H22 = reshape(view(H, L+1:2L, L+1:2L), newdims)

    for m in 1:N-1
        for n in 1:N-1
            c = 0.5 * (Ai[m,n] - δ(m,n)*Ai[N,N]) * (Bj[N,N])
            H11[m, i, n, i] += c
            H22[n, i, m, i] += c

            c = 0.5 * Ai[N,N] * (Bj[m,n] - δ(m,n)*Bj[N,N])
            H11[m, j, n, j] += c
            H22[n, j, m, j] += c

            c = 0.5 * Ai[m,N] * Bj[N,n]
            H11[m, i, n, j] += c * phase
            H22[n, j, m, i] += c * conj(phase)

            c = 0.5 * Ai[N,m] * Bj[n,N]
            H11[n, j, m, i] += c * conj(phase)
            H22[m, i, n, j] += c * phase
            
            c = 0.5 * Ai[m,N] * Bj[n,N]
            H12[m, i, n, j] += c * phase
            H12[n, j, m, i] += c * conj(phase)
        end
    end
end


# Set the dynamical quadratic Hamiltonian matrix in SU(N) mode. 
function swt_hamiltonian_SUN!(H, swt::SpinWaveTheory, q_reshaped::Vec3)
    (; sys, data) = swt
    (; zeeman_operators) = data

    N = sys.Ns[1]                       # Dimension of SU(N) coherent states
    nflavors = N - 1                    # Number of local boson flavors
    L = nflavors * natoms(sys.crystal)  # Number of quasiparticle bands
    @assert size(H) == (2L, 2L)

    # Clear the Hamiltonian
    H .= 0

    # Add single-site terms (single-site anisotropy and external field)
    # Couple percent speedup if this is removed and accumulated into onsite term
    # (not pursuing for now to maintain parallelism with dipole mode). 
    for atom in 1:natoms(sys.crystal)
        zeeman = view(zeeman_operators, :, :, atom)
        swt_onsite_coupling!(H, zeeman, swt, atom)
    end

    # Add pair interactions that use explicit bases
    for (atom, int) in enumerate(sys.interactions_union)

        # Set the onsite term
        swt_onsite_coupling!(H, int.onsite, swt, atom)

        for coupling in int.pair
            # Extract information common to bond
            (; isculled, bond) = coupling
            isculled && break

            phase = exp(2π*im * dot(q_reshaped, bond.n)) # Phase associated with periodic wrapping
            for (A, B) in coupling.general.data 
                swt_pair_coupling!(H, A, B, swt, phase, bond)
            end
        end
    end

    # Infer H21 by H=H'.
    set_H21!(H)

    # Ensure that H is hermitian up to round-off errors.
    @assert hermiticity_norm(H) < 1e-12

    # Make H exactly hermitian
    hermitianpart!(H)

    # Add small constant shift for positive-definiteness
    for i in 1:2L
        H[i,i] += swt.energy_ϵ
    end
end


# Calculate y = H_{onsite}*x, where H_{onsite} is the portion of the quadratic
# Hamiltonian matrix (dynamical matrix) due to onsite terms (other than Zeeman).
function multiply_by_onsite_coupling_SUN!(y, x, op, swt, atom)
    sys = swt.sys
    N = sys.Ns[1] 
    nflavors = N - 1 

    nq = size(y, 1)
    x = Base.ReshapedArray(x, (nq, nflavors, natoms(sys.crystal), 2), ())
    y = Base.ReshapedArray(y, (nq, nflavors, natoms(sys.crystal), 2), ())

    for m in 1:N-1
        for n in 1:N-1
            c = 0.5 * (op[m, n] - δ(m, n) * op[N, N])
            @inbounds for q in 1:nq
                y[q, m, atom, 1] += c * x[q, n, atom, 1]
                y[q, n, atom, 2] += c * x[q, m, atom, 2]
            end
        end
    end
end

# Calculate y = H_{pair}*x, where H_{pair} is the portion of the quadratic
# Hamiltonian matrix (dynamical matrix) due to pair-wise interactions.
function multiply_by_pair_coupling_SUN!(y, x, Ti, Tj, swt, phase, bond)
    (; i, j) = bond
    sys = swt.sys
    N = sys.Ns[1] 
    nflavors = N - 1 

    nq = size(y, 1)
    x = Base.ReshapedArray(x, (nq, nflavors, natoms(sys.crystal), 2), ())
    y = Base.ReshapedArray(y, (nq, nflavors, natoms(sys.crystal), 2), ())

    for m in 1:N-1
        for n in 1:N-1
            c1 = 0.5 * (Ti[m,n] - δ(m,n)*Ti[N,N]) * Tj[N,N]
            c2 = 0.5 * Ti[N,N] * (Tj[m,n] - δ(m,n)*Tj[N,N])
            c3 = 0.5 * Ti[m,N] * Tj[N,n]
            c4 = 0.5 * Ti[N,m] * Tj[n,N]
            c5 = 0.5 * Ti[m,N] * Tj[n,N]

            @inbounds for q in axes(y, 1)
                y[q, m, i, 1] += c1 * x[q, n, i, 1] 
                y[q, n, i, 2] += c1 * x[q, m, i, 2]

                y[q, m, j, 1] += c2 * x[q, n, j, 1]
                y[q, n, j, 2] += c2 * x[q, m, j, 2]

                y[q, m, i, 1] += c3 * phase[q] * x[q, n, j, 1]
                y[q, n, j, 2] += c3 * conj(phase[q]) * x[q, m, i, 2]

                y[q, n, j, 1] += c4 * conj(phase[q]) * x[q, m, i, 1]
                y[q, m, i, 2] += c4 * phase[q] * x[q, n, j, 2]
                
                y[q, m, i, 1] += c5 * phase[q] * x[q, n, j, 2]
                y[q, n, j, 1] += c5 * conj(phase[q]) * x[q, m, i, 2]
                y[q, m, i, 2] += conj(c5 * phase[q]) * x[q, n, j, 1]
                y[q, n, j, 2] += conj(c5) * phase[q] * x[q, m, i, 1]
            end
        end
    end
end

# Calculate y = H*x, where H is the quadratic Hamiltonian matrix (dynamical
# matrix). Note that x is assumed to be a 2D array with first index
# corresponding to q. 
function multiply_by_hamiltonian_SUN(x::Array{ComplexF64, 2}, swt::SpinWaveTheory, qs_reshaped::Array{Vec3})
    # Preallocate buffers
    y = zeros(ComplexF64, (size(qs_reshaped)..., size(x, 2)))
    phasebuf = zeros(ComplexF64, length(qs_reshaped))

    # Precompute e^{2πq_α} components
    qphase = map(qs_reshaped) do q  
        (exp(2π*im*q[1]), exp(2π*im*q[2]), exp(2π*im*q[3]))
    end

    # Perform batched matrix-vector multiply
    multiply_by_hamiltonian_SUN_aux!(reshape(y, (length(qs_reshaped), size(x, 2))), x, phasebuf, qphase, swt)

    return y 
end

function multiply_by_hamiltonian_SUN_aux!(y, x, phasebuf, qphase, swt)
    (; sys, data) = swt
    (; zeeman_operators) = data
    y .= 0

    # Add single-site terms (single-site anisotropy and external field)
    # Couple percent speedup if this is removed and accumulated into onsite term
    # (not pursuing for now to maintain parallelism with dipole mode). 
    for atom in 1:natoms(sys.crystal)
        zeeman = view(zeeman_operators, :, :, atom)
        multiply_by_onsite_coupling_SUN!(y, x, zeeman, swt, atom)
    end

    # Add pair interactions that use explicit bases
    for (atom, int) in enumerate(sys.interactions_union)

        # Set the onsite term
        multiply_by_onsite_coupling_SUN!(y, x, int.onsite, swt, atom)

        for coupling in int.pair
            # Extract information common to bond
            (; isculled, bond) = coupling
            isculled && break

            # phase = exp(2π*im * dot(q_reshaped, bond.n)) # Phase associated with periodic wrapping
            n1, n2, n3 = bond.n
            map!(qp -> (qp[1]^n1)*(qp[2]^n2)*(qp[3]^n3), phasebuf, qphase)
            for (A, B) in coupling.general.data 
                multiply_by_pair_coupling_SUN!(y, x, A, B, swt, phasebuf, bond)
            end
        end
    end

    # Add small constant shift for positive-definiteness
    @inbounds @. y += swt.energy_ϵ * x

    nothing
end

# This is a stopgap measure to avoid unnecessary reshaping. Revisit on merge.

# Calculate y = H*x, where H is the quadratic Hamiltonian matrix (dynamical matrix).
function multiply_by_hamiltonian_SUN!(y, x, swt, q_reshaped)
    (; sys, data) = swt
    (; zeeman_operators) = data
    y .= 0

    # Add single-site terms (single-site anisotropy and external field)
    # Couple percent speedup if this is removed and accumulated into onsite term
    # (not pursuing for now to maintain parallelism with dipole mode). 
    for atom in 1:natoms(sys.crystal)
        zeeman = view(zeeman_operators, :, :, atom)
        multiply_by_onsite_coupling_SUN_legacy!(y, x, zeeman, swt, atom)
    end

    # Add pair interactions that use explicit bases
    for (atom, int) in enumerate(sys.interactions_union)

        # Set the onsite term
        multiply_by_onsite_coupling_SUN_legacy!(y, x, int.onsite, swt, atom)

        for coupling in int.pair
            # Extract information common to bond
            (; isculled, bond) = coupling
            isculled && break

            phase = exp(2π*im * dot(q_reshaped, bond.n)) # Phase associated with periodic wrapping
            for (A, B) in coupling.general.data 
                multiply_by_pair_coupling_SUN_legacy!(y, x, A, B, swt, phase, bond)
            end
        end
    end

    # # Add small constant shift for positive-definiteness
    @. y += swt.energy_ϵ * x

    nothing
end

# Calculate y = H_{onsite}*x, where H_{onsite} is the portion of the quadratic
# Hamiltonian matrix (dynamical matrix) due to onsite terms (other than Zeeman).
function multiply_by_onsite_coupling_SUN_legacy!(y, x, op, swt, atom)
    sys = swt.sys
    N = sys.Ns[1] 
    nflavors = N - 1 

    x = reshape(x, nflavors, natoms(sys.crystal), 2)
    y = reshape(y, nflavors, natoms(sys.crystal), 2)

    for m in 1:N-1
        for n in 1:N-1
            c = 0.5 * (op[m, n] - δ(m, n) * op[N, N])
            y[m, atom, 1] += c * x[n, atom, 1]
            y[n, atom, 2] += c * x[m, atom, 2]
        end
    end
end

# Calculate y = H_{pair}*x, where H_{pair} is the portion of the quadratic
# Hamiltonian matrix (dynamical matrix) due to pair-wise interactions.
function multiply_by_pair_coupling_SUN_legacy!(y, x, Ti, Tj, swt, phase, bond)
    (; i, j) = bond
    sys = swt.sys
    N = sys.Ns[1] 
    nflavors = N - 1 

    x = reshape(x, nflavors, natoms(sys.crystal), 2)
    y = reshape(y, nflavors, natoms(sys.crystal), 2)

    for m in 1:N-1
        for n in 1:N-1
            c = 0.5 * (Ti[m,n] - δ(m,n)*Ti[N,N]) * Tj[N,N]
            y[m, i, 1] += c * x[n, i, 1] 
            y[n, i, 2] += c * x[m, i, 2]

            c = 0.5 * Ti[N,N] * (Tj[m,n] - δ(m,n)*Tj[N,N])
            y[m, j, 1] += c * x[n, j, 1]
            y[n, j, 2] += c * x[m, j, 2]

            c = 0.5 * Ti[m,N] * Tj[N,n]
            y[m, i, 1] += c * phase * x[n, j, 1]
            y[n, j, 2] += c * conj(phase) * x[m, i, 2]

            c = 0.5 * Ti[N,m] * Tj[n,N]
            y[n, j, 1] += c * conj(phase) * x[m, i, 1]
            y[m, i, 2] += c * phase * x[n, j, 2]
            
            c = 0.5 * Ti[m,N] * Tj[n,N]
            y[m, i, 1] += c * phase * x[n, j, 2]
            y[n, j, 1] += c * conj(phase) * x[m, i, 2]
            y[m, i, 2] += conj(c * phase) * x[n, j, 1]
            y[n, j, 2] += conj(c) *phase * x[m, i, 1]
        end
    end
end