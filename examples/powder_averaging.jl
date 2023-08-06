# # Powder Averaging
#
# This tutorial illustrates the calculation of the powder-averaged structure
# factor by performing an orientational average. We consider a simple model of
# the diamond-cubic crystal CoRh$_2$O$_4$, with parameters extracted from Ge et
# al., Phys. Rev. B 96, 064413 (https://doi.org/10.1103/PhysRevB.96.064413).

using Sunny, GLMakie

# Construct a diamond [`Crystal`](@ref) in the conventional (non-primitive)
# cubic unit cell. Sunny will populate all eight symmetry-equivalent sites when
# given the international spacegroup number 227 ("Fd-3m") and the appropriate
# setting. For this spacegroup, there are two conventional translations of the
# unit cell, and it is necessary to disambiguate through the `setting` keyword
# argument. Try omitting the `setting` argument and see how Sunny responds.

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

energy_per_site = energy(sys) / length(all_sites(sys))
@assert energy_per_site ≈ -2J*S^2

# Plotting the spins confirms the expected Néel order. Note that the overall,
# global rotation of dipoles is arbitrary.

plot_spins(sys; arrowlength=1.0, linewidth=0.4, arrowsize=0.5)

# We can now estimate ``𝒮(𝐪,ω)`` with [`SpinWaveTheory`](@ref) and
# [`intensity_formula`](@ref). The mode `:perp` contracts with a dipole factor
# to return the unpolarized intensity. We will also apply broadening with the
# [`lorentzian`](@ref) kernel.

swt = SpinWaveTheory(sys)
η = 0.3 # (meV)
formula = intensity_formula(swt, :perp, kernel=lorentzian(η)) # TODO: formfactors=[FormFactor(1, "Co2")]

# First, we consider the "single crystal" results. Use
# [`connected_path_from_rlu`](@ref) to construct a path that connects
# high-symmetry points in reciprocal space. The [`intensities_broadened`](@ref)
# function collects intensities along this path for the given set of energy
# ($ħω$) values.

qpoints = [[0.0, 0.0, 0.0], [0.5, 0.0, 0.0], [0.5, 0.5, 0.0], [0.0, 0.0, 0.0]]
path, xticks = connected_path_from_rlu(crystal, qpoints, 50)
energies = collect(0:0.01:6)
is = intensities_broadened(swt, path, energies, formula)

# Plot the results

fig = Figure()
ax = Axis(fig[1,1]; aspect=1.4, ylabel="ω (meV)", xlabel="𝐪 (RLU)",
          xticks, xticklabelrotation=π/10)
heatmap!(ax, 1:size(is, 1), energies, is, colormap=:gnuplot2)
fig

# To compare with experimental measurements on a crystal powder, we should
# average over all possible crystal orientations. For this, consider a sequence
# of radii `rs` (units of inverse Å) that define spherical shells in reciprocal
# space. The function [`spherical_shell`](@ref) selects points on these shells
# that are approximately equidistant. For each shell, again call
# `intensities_broadened`, and average over the energy index. The result is a
# powder averaged intensity.

rs = 0.01:0.02:3 # (1/Å)
output = zeros(Float64, length(rs), length(energies))
for (i, r) in enumerate(rs)
    qs = spherical_shell(r; minpoints=300)
    is = intensities_broadened(swt, qs, energies, formula)
    output[i, :] = sum(is, dims=1) / size(is, 1)
end

empty!(fig)
ax = Axis(fig[1,1]; xlabel="|Q| (Å⁻¹)", ylabel="ω (meV)")
heatmap!(ax, rs, energies, output, colormap=:gnuplot2)
fig

# This result can be compared to experimental neutron scattering data
# from [Ge et al.](https://doi.org/10.1038/s41567-020-01110-1)
# ```@raw html
# <img src="https://raw.githubusercontent.com/SunnySuite/Sunny.jl/main/docs/src/assets/CoRh2O4_intensity.jpg">
# ```
