@testitem "Spin precession handedness" begin
    using LinearAlgebra

    crystal = Crystal(lattice_vectors(1, 1, 1, 90, 90, 90), [[0, 0, 0]])
    sys_dip = System(crystal, [SpinInfo(1; S=1, g=2)], :dipole)
    sys_sun = System(crystal, [SpinInfo(1; S=1, g=2)], :SUN)

    B = [0, 0, 1]
    set_field!(sys_dip, B)
    set_field!(sys_sun, B)

    ic = [1/√2, 0, 1/√2]
    set_dipole!(sys_dip, ic, (1, 1, 1, 1))
    set_dipole!(sys_sun, ic, (1, 1, 1, 1))

    integrator = ImplicitMidpoint(0.05)
    for _ in 1:5
        step!(sys_dip, integrator)
        step!(sys_sun, integrator)
    end

    dip_is_lefthanded = B ⋅ (ic × magnetic_moment(sys_dip, (1,1,1,1))) < 0
    sun_is_lefthanded = B ⋅ (ic × magnetic_moment(sys_sun, (1,1,1,1))) < 0

    @test dip_is_lefthanded == sun_is_lefthanded == true
end


@testitem "DM chain" begin
    latvecs = lattice_vectors(2, 2, 1, 90, 90, 90)
    cryst = Crystal(latvecs, [[0,0,0]], "P1")
    sys = System(cryst, [SpinInfo(1,S=1,g=-1)], :dipole)
    D = 1
    B = 10.0
    set_exchange!(sys, dmvec([0, 0, D]), Bond(1, 1, [0, 0, 1]))
    set_field!(sys, [0, 0, B])

    # Above the saturation field, the ground state is fully polarized, with no
    # energy contribution from the DM term.

    randomize_spins!(sys)
    minimize_energy!(sys)
    @test energy_per_site(sys) ≈ -B
    qs = [[0, 0, -1/2], [0, 0, 1/3]]
    swt = SpinWaveTheory(sys; measure=ssf_trace(sys))
    res = intensities_bands(swt, qs)
    disp_ref = [B + 2D*sin(2π*q[3]) for q in qs]
    intens_ref = [1.0 for _ in qs]
    @test res.disp[1,:] ≈ disp_ref
    @test res.data[1,:] ≈ intens_ref

    # Check SpiralSpinWaveTheory

    swt = SpiralSpinWaveTheory(sys; measure=ssf_trace(sys; apply_g=false), k=[0,0,0], axis=[0,0,1])
    res = intensities_bands(swt, qs)
    @test res.disp[1, :] ≈ res.disp[2, :] ≈ res.disp[3, :] ≈ [B + 2D*sin(2π*q[3]) for q in qs]
    @test res.data ≈ [1 1; 0 0; 0 0]

    # Below the saturation field, the ground state is a canted spiral

    set_field!(sys, [0, 0, 1])
    axis = [0, 0, 1]
    polarize_spins!(sys, [0.5, -0.2, 0.3])
    k = spiral_minimize_energy!(sys, axis; k_guess=[0.1, 0.2, 0.9])
    @test k[3] ≈ 3/4
    @test spiral_energy_per_site(sys; k, axis) ≈ -5/4

    # Check SpiralSpinWaveTheory

    qs = [[0,0,-1/3], [0,0,1/3]]
    swt = SpiralSpinWaveTheory(sys; measure=ssf_trace(sys; apply_g=false), k, axis)
    res = intensities_bands(swt, qs)
    disp_ref = [3.0133249314 2.5980762316 0.6479760935
                 3.0133249314 2.5980762316 0.6479760935]
    intens_ref = [0.0292617379 0.4330127014 0.8804147011
                   0.5292617379 0.4330127014 0.3804147011]
    @test res.disp ≈ disp_ref'
    @test res.data ≈ intens_ref'

    # Check supercell equivalent

    sys_enlarged = repeat_periodically_as_spiral(sys, (1, 1, 4); k, axis)
    swt = SpinWaveTheory(sys_enlarged; measure=ssf_trace(sys_enlarged; apply_g=false))
    res = intensities_bands(swt, qs)
    disp2_ref = [3.0133249314 2.5980762316 1.3228756763 0.6479760935
                 3.0133249314 2.5980762316 1.3228756763 0.6479760935]
    intens2_ref = [0.0292617379 0.4330127014 0.0 0.8804147011
                   0.5292617379 0.4330127014 0.0 0.3804147011]
    @test res.disp ≈ disp2_ref'
    @test res.data ≈ intens2_ref'
end
