@testitem "Dipole Factor Ordering" begin
    obs = Sunny.parse_observables(3)
    dipoleinfo = Sunny.DipoleFactor(obs)
    fake_intensities = [1. 3 5;0 7 11;0 0 13]
    # This is the order expected by contract(...)
    fake_dipole_elements = fake_intensities[[1,4,5,7,8,9]]
    k = @SVector[1.,2.,3.]
    mat = Sunny.polarization_matrix(k)
    out = Sunny.contract(fake_dipole_elements,k,dipoleinfo)
    out_true = dot(Hermitian(fake_intensities),mat)
    @test isapprox(out,out_true)
end
