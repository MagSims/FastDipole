# # 7. Long-range dipole interactions
#
# This example demonstrates Sunny's ability to incorporate long-range dipole
# interactions using Ewald summation. The calculation reproduces previous
# results in  [Del Maestro and Gingras, J. Phys.: Cond. Matter, **16**, 3339
# (2004)](https://arxiv.org/abs/cond-mat/0403494).

using Sunny, GLMakie

# Create a Pyrochlore lattice from spacegroup 227 in the standard setting.
latvecs = lattice_vectors(10.19, 10.19, 10.19, 90, 90, 90)
cryst = Crystal(latvecs, [[0,0,0]], 227, setting="2")

sys = System(cryst, (1, 1, 1), [SpinInfo(1, S=7/2, g=2)], :dipole, seed=2)

J1 = 0.304 * meV_per_K
set_exchange!(sys, J1, Bond(1,2,[0,0,0]))

shape = [1/2 1/2 0; 0 1/2 1/2; 1/2 0 1/2]
sys_prim = reshape_supercell(sys, shape)

set_dipole!(sys_prim, [+1, -1, 0], position_to_site(sys_prim, [0,0,0]))
set_dipole!(sys_prim, [-1, +1, 0], position_to_site(sys_prim, [1/4,1/4,0]))
set_dipole!(sys_prim, [+1, +1, 0], position_to_site(sys_prim, [1/4,0,1/4]))
set_dipole!(sys_prim, [-1, -1, 0], position_to_site(sys_prim, [0,1/4,1/4]))

plot_spins(sys_prim)

q_points = [[0,0,0], [0,1,0], [1,1/2,0], [1/2,1/2,1/2], [3/4,3/4,0], [0,0,0]]
q_labels = ["Γ","X","W","L","K","Γ"]
density = 150
path, xticks = reciprocal_space_path(cryst, q_points, density);
xticks = (xticks[1], q_labels)

swt = SpinWaveTheory(sys_prim, energy_ϵ=1e-6)
disp1 = dispersion(swt, path)

enable_dipole_dipole!(sys_prim)
swt = SpinWaveTheory(sys_prim, energy_ϵ=1e-6)
disp2 = dispersion(swt, path);

# Plot dispersions with and without long-range dipole interactions. To reproduce
# Fig. 2 of [Del Maestro and Gingras](https://arxiv.org/abs/cond-mat/0403494),
# an empirical rescaling of energy is necessary.

fudge_factor = 1/2 # For purposes of reproducing prior work

fig = Figure(size=(900,300))

ax = Axis(fig[1,1]; xlabel="", ylabel="Energy (K)", xticks, xticklabelrotation=0)
ylims!(ax, 0, 2)
xlims!(ax, 1, size(disp1, 1))
for i in axes(disp1, 2)
    lines!(ax, 1:length(disp1[:,i]), fudge_factor*disp1[:,i]/meV_per_K)
end

ax = Axis(fig[1,2]; xlabel="", ylabel="Energy (K)", xticks, xticklabelrotation=0)
ylims!(ax, 0.0, 3)
xlims!(ax, 1, size(disp2, 1))
for i in axes(disp2, 2)
    lines!(ax, 1:length(disp2[:,i]), fudge_factor*disp2[:,i]/meV_per_K)
end

fig
