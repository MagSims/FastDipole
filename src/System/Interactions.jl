function empty_interactions(mode, na, N)
    # Cannot use `fill` because the PairCoupling arrays must be
    # allocated separately for later mutation.
    return map(1:na) do _
        Interactions(empty_anisotropy(mode, N), PairCoupling[])
    end
end

# Warn up to `OverrideWarningMax` times about overriding a coupling
OverrideWarningCnt::Int = 0
OverrideWarningMax::Int = 5
function warn_coupling_override(str)
    global OverrideWarningCnt, OverrideWarningMax
    OverrideWarningCnt < OverrideWarningMax && @info str
    OverrideWarningCnt += 1
    OverrideWarningCnt == OverrideWarningMax && @info "Suppressing future override notifications."
end


# Creates a copy of the Vector of PairCouplings. This is useful when cloning a
# system; mutable updates to one clone should not affect the other.
function clone_interactions(ints::Interactions)
    (; onsite, pair) = ints
    return Interactions(onsite, copy(pair))
end

function interactions_homog(sys::System{N}) where N
    return sys.interactions_union :: Vector{Interactions}
end

function interactions_inhomog(sys::System{N}) where N
    return sys.interactions_union :: Array{Interactions, 4}
end

function is_homogeneous(sys::System{N}) where N
    return sys.interactions_union isa Vector{Interactions}
end

"""
    to_inhomogeneous(sys::System)

Returns a copy of the system that allows for inhomogeneous interactions, which
can be set using [`set_onsite_coupling_at!`](@ref), [`set_exchange_at!`](@ref),
and [`set_vacancy_at!`](@ref).

Inhomogeneous systems do not support symmetry-propagation of interactions or
system reshaping.
"""
function to_inhomogeneous(sys::System{N}) where N
    is_homogeneous(sys) || error("System is already inhomogeneous.")
    ints = interactions_homog(sys)

    ret = clone_system(sys)
    na = natoms(ret.crystal)
    ret.interactions_union = Array{Interactions}(undef, ret.latsize..., na)
    for i in 1:natoms(ret.crystal)
        for cell in eachcell(ret)
            ret.interactions_union[cell, i] = clone_interactions(ints[i])
        end
    end

    return ret
end


"""
    enable_dipole_dipole!(sys::System)

Enables long-range dipole-dipole interactions,

```math
    -(μ_0/4π) ∑_{⟨ij⟩}  (3 (𝐌_j⋅𝐫̂_{ij})(𝐌_i⋅𝐫̂_{ij}) - 𝐌_i⋅𝐌_j) / |𝐫_{ij}|^3
```

where the sum is over all pairs of spins (singly counted), including periodic
images, regularized using the Ewald summation convention. The magnetic moments
are ``𝐌_i = μ_B g 𝐒_i`` where ``g`` is the g-factor or g-tensor, and ``𝐒_i``
is the spin angular momentum dipole in units of ħ. The Bohr magneton ``μ_B`` and
vacuum permeability ``μ_0`` are physical constants, with numerical values
determined by the unit system.
"""
function enable_dipole_dipole!(sys::System{N}) where N
    sys.ewald = Ewald(sys)
    return
end

"""
    set_external_field!(sys::System, B::Vec3)

Sets the external field `B` that couples to all spins.
"""
function set_external_field!(sys::System, B)
    for site in eachsite(sys)
        set_external_field_at!(sys, B, site)
    end
end

"""
    set_external_field_at!(sys::System, B::Vec3, site::Site)

Sets a Zeeman coupling between a field `B` and a single spin. [`Site`](@ref)
includes a unit cell and a sublattice index.
"""
function set_external_field_at!(sys::System, B, site)
    sys.extfield[to_cartesian(site)] = Vec3(B)
end

"""
    set_vacancy_at!(sys::System, site::Site)

Make a single site nonmagnetic. [`Site`](@ref) includes a unit cell and a
sublattice index.
"""
function set_vacancy_at!(sys::System{N}, site) where N
    is_homogeneous(sys) && error("Use `to_inhomogeneous` first.")

    site = to_cartesian(site)
    sys.κs[site] = 0.0
    sys.dipoles[site] = zero(Vec3)
    sys.coherents[site] = zero(CVec{N})
end


function local_energy_change(sys::System{N}, site, state::SpinState) where N
    (; s, Z) = state
    (; latsize, extfield, dipoles, coherents, ewald) = sys

    if is_homogeneous(sys)
        (; onsite, pair) = interactions_homog(sys)[to_atom(site)]
    else
        (; onsite, pair) = interactions_inhomog(sys)[site]
    end

    s₀ = dipoles[site]
    Z₀ = coherents[site]
    Δs = s - s₀
    ΔE = 0.0

    # Zeeman coupling to external field
    ΔE -= sys.units.μB * dot(extfield[site], sys.gs[site], Δs)

    # Single-ion anisotropy, dipole or SUN mode
    if N == 0
        stvexp = onsite :: StevensExpansion
        E_new, _ = energy_and_gradient_for_classical_anisotropy(s, stvexp)
        E_old, _ = energy_and_gradient_for_classical_anisotropy(s₀, stvexp)
        ΔE += E_new - E_old
    else
        Λ = onsite :: HermitianC64
        ΔE += real(dot(Z, Λ, Z) - dot(Z₀, Λ, Z₀))
    end

    # Quadratic exchange matrix
    for pc in pair
        cellⱼ = offsetc(to_cell(site), pc.bond.n, latsize)
        sⱼ = dipoles[cellⱼ, pc.bond.j]
        Zⱼ = coherents[cellⱼ, pc.bond.j]

        # Bilinear
        J = pc.bilin
        ΔE += dot(Δs, J, sⱼ)

        # Biquadratic
        if !iszero(pc.biquad)
            J = pc.biquad
            if sys.mode == :dipole
                ΔE += J * ((s⋅sⱼ)^2 - (s₀⋅sⱼ)^2)
            elseif sys.mode == :SUN
                error("Biquadratic currently unsupported in SU(N) mode.") 
            end
        end

        # General
        if N > 0
            for (A, B) in pc.general.data
                ΔĀ = real(dot(Z, A, Z) - dot(Z₀, A, Z₀))
                B̄ = real(dot(Zⱼ, B, Zⱼ))
                ΔE += ΔĀ * B̄
            end
        end
    end

    # Long-range dipole-dipole
    if !isnothing(ewald)
        ΔE += ewald_energy_delta(sys, site, s)
    end

    return ΔE
end

"""
    energy_per_site(sys::System)

The total system [`energy`](@ref) divided by the number of sites.
"""
function energy_per_site(sys::System{N}) where N
    return energy(sys) / length(eachsite(sys))
end

"""
    energy(sys::System)

The total system energy. See also [`energy_per_site`](@ref).
"""
function energy(sys::System{N}) where N
    E = 0.0

    # Zeeman coupling to external field
    for site in eachsite(sys)
        E -= sys.units.μB * sys.extfield[site] ⋅ (sys.gs[site] * sys.dipoles[site])
    end

    # Anisotropies and exchange interactions
    for i in 1:natoms(sys.crystal)
        if is_homogeneous(sys)
            # Interactions for sublattice i (same for every cell)
            interactions = sys.interactions_union[i]
            E += energy_aux(interactions, sys, i, eachcell(sys))
        else
            for cell in eachcell(sys)
                interactions = sys.interactions_union[cell, i]
                E += energy_aux(interactions, sys, i, (cell,))
            end
        end
    end

    # Long-range dipole-dipole
    if !isnothing(sys.ewald)
        E += ewald_energy(sys)
    end
    
    return E
end

# Total energy contributed by sublattice `i`, summed over the list of `cells`.
function energy_aux(ints::Interactions, sys::System{N}, i::Int, cells) where N
    E = 0.0

    # Single-ion anisotropy
    if N == 0       # Dipole mode
        stvexp = ints.onsite :: StevensExpansion
        for cell in cells
            s = sys.dipoles[cell, i]
            E += energy_and_gradient_for_classical_anisotropy(s, stvexp)[1]
        end
    else            # SU(N) mode
        Λ = ints.onsite :: HermitianC64
        for cell in cells
            Z = sys.coherents[cell, i]
            E += real(dot(Z, Λ, Z))
        end
    end

    for pc in ints.pair
        (; bond, isculled) = pc
        isculled && break

        for cellᵢ in cells
            cellⱼ = offsetc(cellᵢ, bond.n, sys.latsize)
            sᵢ = sys.dipoles[cellᵢ, bond.i]
            sⱼ = sys.dipoles[cellⱼ, bond.j]

            # Bilinear
            J = pc.bilin :: Union{Float64, Mat3}
            E += dot(sᵢ, J, sⱼ)

            # Biquadratic
            if !iszero(pc.biquad)
                J = pc.biquad
                if sys.mode == :dipole
                    E += J * (sᵢ⋅sⱼ)^2
                elseif sys.mode == :SUN
                    error("Biquadratic currently unsupported in SU(N) mode.")
                end
            end

            # General
            if N > 0
                Zᵢ = sys.coherents[cellᵢ, bond.i]
                Zⱼ = sys.coherents[cellⱼ, bond.j]
                for (A, B) in pc.general.data
                    Ā = real(dot(Zᵢ, A, Zᵢ))
                    B̄ = real(dot(Zⱼ, B, Zⱼ))
                    E += Ā * B̄
                end
            end
        end
    end

    return E
end


# Updates ∇E in-place to hold energy gradient, dE/ds, for each spin. In the case
# of :SUN mode, s is interpreted as expected spin, and dE/ds only includes
# contributions from Zeeman coupling, bilinear exchange, and long-range
# dipole-dipole. Excluded terms include onsite coupling, and general pair
# coupling (biquadratic and beyond).
function set_energy_grad_dipoles!(∇E, dipoles::Array{Vec3, 4}, sys::System{N}) where N
    fill!(∇E, zero(Vec3))

    # Zeeman coupling
    for site in eachsite(sys)
        ∇E[site] -= sys.units.μB * (sys.gs[site]' * sys.extfield[site])
    end

    # Anisotropies and exchange interactions
    for i in 1:natoms(sys.crystal)
        if is_homogeneous(sys)
            # Interactions for sublattice i (same for every cell)
            interactions = sys.interactions_union[i]
            set_energy_grad_dipoles_aux!(∇E, dipoles, interactions, sys, i, eachcell(sys))
        else
            for cell in eachcell(sys)
                # Interactions for sublattice i and a specific cell
                interactions = sys.interactions_union[cell, i]
                set_energy_grad_dipoles_aux!(∇E, dipoles, interactions, sys, i, (cell,))
            end
        end
    end

    if !isnothing(sys.ewald)
        accum_ewald_grad!(∇E, dipoles, sys)
    end
end

# Calculate the energy gradient `∇E' for the sublattice `i' at all elements of
# `cells`.
function set_energy_grad_dipoles_aux!(∇E, dipoles::Array{Vec3, 4}, ints::Interactions, sys::System{N}, i::Int, cells) where N
    # Single-ion anisotropy only contributes in dipole mode. In SU(N) mode, the
    # anisotropy matrix will be incorporated directly into local H matrix.
    if N == 0
        stvexp = ints.onsite :: StevensExpansion
        for cell in cells
            s = dipoles[cell, i]
            ∇E[cell, i] += energy_and_gradient_for_classical_anisotropy(s, stvexp)[2]
        end
    end

    for pc in ints.pair
        (; bond, isculled) = pc
        isculled && break

        for cellᵢ in cells
            cellⱼ = offsetc(cellᵢ, bond.n, sys.latsize)
            sᵢ = dipoles[cellᵢ, bond.i]
            sⱼ = dipoles[cellⱼ, bond.j]

            # Bilinear
            J = pc.bilin
            ∇E[cellᵢ, bond.i] += J  * sⱼ
            ∇E[cellⱼ, bond.j] += J' * sᵢ

            # Biquadratic
            if !iszero(pc.biquad)
                J = pc.biquad
                if sys.mode == :dipole
                    ∇E[cellᵢ, bond.i] += J * 2sⱼ*(sᵢ⋅sⱼ)
                    ∇E[cellⱼ, bond.j] += J * 2sᵢ*(sᵢ⋅sⱼ)
                elseif sys.mode == :SUN
                    error("Biquadratic currently unsupported in SU(N) mode.")
                end
            end
        end
    end
end

# Updates `HZ` in-place to hold `dE/dZ̄`, which is the Schrödinger analog to the
# quantity `dE/ds`. **Overwrites the first two dipole buffers in `sys`.**
function set_energy_grad_coherents!(HZ, Z::Array{CVec{N}, 4}, sys::System{N}) where N
    @assert N > 0

    fill!(HZ, zero(CVec{N}))

    # Accumulate Zeeman, Ewald interactions, and spin-bilinear exchange
    # interactions into dE/ds, where s is the expected spin associated with Z.
    # Note that dE_ds does _not_ include the onsite coupling or biquadratic
    # couplings, which must be handled differently.
    dE_ds, dipoles = get_dipole_buffers(sys, 2)
    @. dipoles = expected_spin(Z)
    set_energy_grad_dipoles!(dE_ds, dipoles, sys)

    # Accumulate anisotropies and exchange interactions.
    for i in 1:natoms(sys.crystal)
        if is_homogeneous(sys)
            # Interactions for sublattice i (same for every cell)
            interactions = sys.interactions_union[i]
            set_energy_grad_coherents_aux!(HZ, Z, dE_ds, interactions, sys, i, eachcell(sys))
        else
            for cell in eachcell(sys)
                # Interactions for sublattice i and a specific cell
                interactions = sys.interactions_union[cell, i]
                set_energy_grad_coherents_aux!(HZ, Z, dE_ds, interactions, sys, i, (cell,))
            end
        end
    end

    fill!(dE_ds, zero(Vec3))
    fill!(dipoles, zero(Vec3))
end

function set_energy_grad_coherents_aux!(HZ, Z::Array{CVec{N}, 4}, dE_ds::Array{Vec3, 4}, ints::Interactions, sys::System{N}, i, cells) where N
    for cell in cells
        # HZ += (Λ + dE/ds S) Z
        Λ = ints.onsite :: HermitianC64
        HZ[cell, i] += mul_spin_matrices(Λ, dE_ds[cell, i], Z[cell, i])
    end

    for pc in ints.pair
        (; bond, isculled) = pc
        isculled && break

        for (A, B) in pc.general.data
            A = SMatrix{N, N}(A)
            B = SMatrix{N, N}(B)
            for cellᵢ in cells
                cellⱼ = offsetc(cellᵢ, bond.n, sys.latsize)
                Zᵢ = Z[cellᵢ, bond.i]
                Zⱼ = Z[cellⱼ, bond.j]
                Ā = real(dot(Zᵢ, A, Zᵢ))
                B̄ = real(dot(Zⱼ, B, Zⱼ))
                HZ[cellᵢ, bond.i] += (A * Zᵢ) * B̄
                HZ[cellⱼ, bond.j] += Ā * (B * Zⱼ)
            end
        end
    end
end


# Internal testing functions
function energy_grad_dipoles(sys::System{N}) where N
    ∇E = zero(sys.dipoles)
    set_energy_grad_dipoles!(∇E, sys.dipoles, sys)
    return ∇E
end
function energy_grad_coherents(sys::System{N}) where N
    ∇E = zero(sys.coherents)
    set_energy_grad_coherents!(∇E, sys.coherents, sys)
    return ∇E
end


# Returns (Λ + (dE/ds)⋅S) Z
@generated function mul_spin_matrices(Λ, dE_ds::Sunny.Vec3, Z::Sunny.CVec{N}) where N
    S = spin_matrices(; N)
    out = map(1:N) do i
        out_i = map(1:N) do j
            terms = Any[:(Λ[$i,$j])]
            for α = 1:3
                S_αij = S[α][i,j]
                if !iszero(S_αij)
                    push!(terms, :(dE_ds[$α] * $S_αij))
                end
            end
            :(+($(terms...)) * Z[$j])
        end
        :(+($(out_i...)))
    end
    return :(CVec{$N}($(out...)))
end
