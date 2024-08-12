# # SW19 - Different magnetic ions
#
# This is a Sunny port of [SpinW Tutorial
# 19](https://spinw.org/tutorials/19tutorial), originally authored by Bjorn Fak
# and Sandor Toth. This tutorial illustrates how to eliminate magnetic
# contributions from a subset of ions via the special value `zero(FormFactor)`.

using Sunny, GLMakie

# Build a crystal with Cu²⁺ and Fe²⁺ ions
a = 3.0
b = 8.0
c = 4.0
latvecs = lattice_vectors(a, b, c, 90, 90, 90)
positions = [[0, 0, 0], [0, 1/2, 0]]
types = ["Cu2", "Fe2"]
cryst = Crystal(latvecs, positions, 1; types)
view_crystal(cryst)

# Set interactions
J_Cu_Cu = 1.0
J_Fe_Fe = 1.0
J_Cu_Fe = -0.1
sys = System(cryst, (2,1,1), [SpinInfo(1,S=1/2,g=2), SpinInfo(2,S=2,g=2)], :dipole; seed=0)
set_exchange!(sys, J_Cu_Cu, Bond(1, 1, [-1, 0, 0]))
set_exchange!(sys, J_Fe_Fe, Bond(2, 2, [-1, 0, 0]))
set_exchange!(sys, J_Cu_Fe, Bond(2, 1, [0, 1, 0]))
set_exchange!(sys, J_Cu_Fe, Bond(1, 2, [0, 0, 0]))

# Find and plot a minimum energy configuration

randomize_spins!(sys)
minimize_energy!(sys)
plot_spins(sys)

# Plot dispersions colored by total summed intensity for each degenerate band

swt = SpinWaveTheory(sys)
qs = [[0,0,0], [1,0,0]]
path = Sunny.q_space_path(cryst, qs, 5e-3)
measure = Sunny.DSSF_perp(sys)

# Plot all correlations

res = Sunny.intensities_bands2(swt, path; measure)
plot_intensities(res, :meV; title="All correlations")

# Plot Cu-Cu correlations only

formfactors = [FormFactor("Cu2"), zero(FormFactor)]
res = Sunny.intensities_bands2(swt, path; formfactors, measure)
plot_intensities(res, :meV; title="Cu-Cu correlations")

# Fe-Fe correlations only

formfactors = [zero(FormFactor), FormFactor("Fe2")]
res = Sunny.intensities_bands2(swt, path; formfactors, measure)
plot_intensities(res, :meV; title="Fe-Fe correlations")
