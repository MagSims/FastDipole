using Sunny
using LinearAlgebra
using MPI

# nearest-neighbor ferromagnetic Ising (z-dir) interactions
J = -1.0
FM = exchange(diagm([J, J, J]), Bond(1, 1, [1, 0, 0]))
interactions = [FM]

# SC lattice -- extend lattice vector in z-direction to emulate 2D
lvecs = Sunny.lattice_vectors(1.0, 1.0, 2.0, 90, 90 ,90)
bvecs = [[0.0, 0.0, 0.0]]
crystal = Crystal(lvecs, bvecs)

extent = (20, 20, 1)
system = SpinSystem(crystal, interactions, extent, [SiteInfo(1,1,1)])

# randomize spins
randflips!(system)

# make replica for PT
replica = Replica(IsingSampler(system, 1.0, 1))

kT_min = 0.1
kT_max = 10.0

# geometric temperature schedule
kT_sched(i, N) = kT_min * (kT_max/kT_min) ^ ((i-1)/(N-1))

# get feedback-optimized temperature schedule
kT_opt = run_FBOPT!(
    replica, 
    kT_sched; 
    max_mcs_opt=500_000, 
    update_interval=100_000, 
    rex_interval=1, 
    print_ranks=Int64[], 
    print_interval=100
)

# run parallel tempering
run_PT!(
    replica, 
    kT_opt;
    therm_mcs=5000, 
    measure_interval=100, 
    rex_interval=10, 
    max_mcs=1_000_000, 
    bin_size=1.0, 
    print_hist=true
)
