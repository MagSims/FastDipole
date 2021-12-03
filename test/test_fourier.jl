println("test_fourier")

"Tests these field-using functions give the same answer as `ewald_sum_dipole`"
function test_energy_consistency(crystal, latsize)
    sys = SpinSystem(crystal, Sunny.Interaction[], latsize)
    rand!(sys)

    dipdip = dipole_dipole(; extent=5, η=0.5)
    dip_real = Sunny.DipoleRealCPU(dipdip, crystal, latsize, sys.sites_info)
    dip_fourier = Sunny.DipoleFourierCPU(dipdip, crystal, latsize, sys.sites_info)

    direct_energy = Sunny.ewald_sum_dipole(sys.lattice, sys.sites; extent=5, η=0.5)
    real_energy = Sunny.energy(sys.sites, dip_real)
    fourier_energy = Sunny.energy(sys.sites, dip_fourier)

    @test real_energy ≈ fourier_energy
    @test direct_energy ≈ fourier_energy
end

function test_field_consistency(crystal, latsize)
    sys = SpinSystem(crystal, Sunny.Interaction[], latsize)
    rand!(sys)
    
    dipdip = dipole_dipole(; extent=4, η=0.5)
    dip_real = Sunny.DipoleRealCPU(dipdip, crystal, latsize, sys.sites_info)
    dip_fourier = Sunny.DipoleFourierCPU(dipdip, crystal, latsize, sys.sites_info)

    H1 = zero(sys)
    H2 = zero(sys)
    Sunny._accum_neggrad!(H1, sys.sites, dip_real)
    Sunny._accum_neggrad!(H2, sys.sites, dip_fourier)

    @test all(H1 .≈ H2)
end

lat_vecs = lattice_vectors(1.0, 1.0, 2.0, 90., 90., 120.)
basis_vecs = [[0.0, 0.0, 0.0], [0.5, 0.5, 0.5]]
latsize = [5, 5, 5]
crystal = Crystal(lat_vecs, basis_vecs)

test_energy_consistency(crystal, latsize)
test_field_consistency(crystal, latsize)
