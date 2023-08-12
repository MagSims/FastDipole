# # Powder averaged CoRh$_2$O$_4$
#
# This tutorial illustrates the calculation of the powder-averaged structure
# factor by performing an orientational average. We consider a simple model of
# the diamond-cubic crystal CoRh$_2$O$_4$, with parameters extracted from [Ge et
# al., Phys. Rev. B 96, 064413](https://doi.org/10.1103/PhysRevB.96.064413).

using Sunny, GLMakie

# Construct a diamond [`Crystal`](@ref) in the conventional (non-primitive)
# cubic unit cell. Sunny will populate all eight symmetry-equivalent sites when
# given the international spacegroup number 227 ("Fd-3m") and the appropriate
# setting. For this spacegroup, there are two conventional translations of the
# unit cell, and it is necessary to disambiguate through the `setting` keyword
# argument. (On your own: what happens if `setting` is omitted?)

a = 8.5031 # (Å)
latvecs = lattice_vectors(a, a, a, 90, 90, 90)
crystal = Crystal(latvecs, [[0,0,0]], 227, setting="1")

# Construct a [`System`](@ref) with an antiferromagnetic nearest neighbor
# interaction `J`. Because the diamond crystal is bipartite, the ground state
# will have unfrustrated Néel order. Selecting `latsize=(1,1,1)` is sufficient
# because the ground state is periodic over each cubic unit cell. By passing an
# explicit `seed`, the system's random number generator will give repeatable
# results.

latsize = (1,1,1)
seed = 0
S = 3/2
J = 7.5413*meV_per_K # (meV)
sys = System(crystal, latsize, [SpinInfo(1; S, g=2)], :dipole; seed=0)
set_exchange!(sys, J, Bond(1, 3, [0,0,0]))

# The ground state is non-frustrated. Each spin should be exactly anti-aligned
# with its 4 nearest-neighbors, such that every bond contributes an energy of
# $-JS^2$. This gives an energy per site of $-2JS^2$. In this calculation, a
# factor of 1/2 is necessary to avoid double-counting the bonds. Given the small
# magnetic supercell (which includes only one unit cell), direct energy
# minimization is successful in finding the ground state.

randomize_spins!(sys)
minimize_energy!(sys)

energy_per_site = energy(sys) / length(eachsite(sys))
@assert energy_per_site ≈ -2J*S^2

# Plotting the spins confirms the expected Néel order. Note that the overall,
# global rotation of dipoles is arbitrary.

plot_spins(sys; arrowlength=1.0, linewidth=0.4, arrowsize=0.5)

# We can now estimate ``𝒮(𝐪,ω)`` with [`SpinWaveTheory`](@ref) and
# [`intensity_formula`](@ref). The mode `:perp` contracts with a dipole factor
# to return the unpolarized intensity. We will also apply broadening with the
# [`lorentzian`](@ref) kernel, and will dampen intensities using the
# [`FormFactor`](@ref) for Cobalt(2+).

swt = SpinWaveTheory(sys)
η = 0.4 # (meV)
kernel = lorentzian(η)
formfactors = [FormFactor("Co2")]
formula = intensity_formula(swt, :perp; kernel, formfactors)

# First, we consider the "single crystal" results. Use
# [`reciprocal_space_path`](@ref) to construct a path that connects
# high-symmetry points in reciprocal space. The [`intensities_broadened`](@ref)
# function collects intensities along this path for the given set of energy
# values.

qpoints = [[0.0, 0.0, 0.0], [0.5, 0.0, 0.0], [0.5, 0.5, 0.0], [0.0, 0.0, 0.0]]
path, xticks = reciprocal_space_path(crystal, qpoints, 50)
energies = collect(0:0.01:6)
is = intensities_broadened(swt, path, energies, formula)

fig = Figure()
ax = Axis(fig[1,1]; aspect=1.4, ylabel="ω (meV)", xlabel="𝐪 (RLU)",
          xticks, xticklabelrotation=π/10)
heatmap!(ax, 1:size(is, 1), energies, is, colormap=:gnuplot2)
fig

# A scattering measurement on powder is effectively an average over all possible
# crystal orientations. We consider a sequence of wavevector magnitudes `qmags`,
# which define spherical shells in reciprocal space. Sample points on each shell
# using [`sphere_points`](@ref), and then average over the results of
# `intensities_broadened` to get a powder averaged intensity.

qmags = 0.01:0.02:3 # (1/Å)
output = zeros(Float64, length(qmags), length(energies))
for (i, qmag) in enumerate(qmags)
    qs = qmag .* sphere_points(300)
    is = intensities_broadened(swt, qs, energies, formula)
    output[i, :] = sum(is, dims=1) / size(is, 1)
end

empty!(fig)
ax = Axis(fig[1,1]; xlabel="|Q| (Å⁻¹)", ylabel="ω (meV)")
heatmap!(ax, qmags, energies, output, colormap=:gnuplot2)
fig

# This result can be compared to experimental neutron scattering data
# from Fig. 5 of [Ge et al.](https://doi.org/10.1103/PhysRevB.96.064413)
# ```@raw html
# <img width="95%" src="https://raw.githubusercontent.com/SunnySuite/Sunny.jl/main/docs/src/assets/CoRh2O4_intensity.jpg">
# ```
