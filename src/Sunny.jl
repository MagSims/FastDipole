module Sunny

using LinearAlgebra
import LinearMaps: LinearMap, FunctionMap
import StaticArrays: SVector, SMatrix, SArray, MVector, MMatrix, SA, @SVector
import Requires: @require
import OffsetArrays: OffsetArray, OffsetMatrix, Origin
import SpecialFunctions: erfc
import FFTW
import ProgressMeter: Progress, next!
import Printf: @printf, @sprintf
import Random: Random, randn!
import DynamicPolynomials as DP
import DataStructures: SortedDict, OrderedDict
import Optim
import JLD2
import CodecZlib # Required for reading compressed HDF

# Specific to Symmetry/
import FilePathsBase: Path
import CrystalInfoFramework as CIF
import Spglib
import RowEchelon: rref!

# Specific to SunnyGfx
import JSON
import Colors: distinguishable_colors, RGB, Colors
import Inflate: inflate_gzip
import Random: randstring, RandomDevice

const Vec3 = SVector{3, Float64}
const Mat3 = SMatrix{3, 3, Float64, 9}
const CVec{N} = SVector{N, ComplexF64}


include("Util/CartesianIndicesShifted.jl")

include("Operators/Spin.jl")
include("Operators/Rotation.jl")
include("Operators/Stevens.jl")
include("Operators/Symbolic.jl")
export 𝒪, 𝒮, rotate_operator, print_anisotropy_as_stevens, print_anisotropy_as_classical_spins

include("Symmetry/LatticeUtils.jl")
include("Symmetry/SymOp.jl")
include("Symmetry/Crystal.jl")
include("Symmetry/Bond.jl")
include("Symmetry/SymmetryAnalysis.jl")
include("Symmetry/AllowedCouplings.jl")
include("Symmetry/AllowedAnisotropy.jl")
include("Symmetry/Parsing.jl")
include("Symmetry/Printing.jl")
export Crystal, subcrystal, lattice_vectors, lattice_params, Bond, 
    reference_bonds, print_site, print_bond, print_symmetry_table,
    print_suggested_frame
    # natoms, cell_volume, cell_type, coordination_number, displacement, distance,
    # all_symmetry_related_bonds, all_symmetry_related_bonds_for_atom,
    # all_symmetry_related_couplings, all_symmetry_related_couplings_for_atom

include("Units.jl")
export meV_per_K, Units

include("System/SpinInfo.jl")
include("System/Types.jl")
include("System/System.jl")
include("System/PairExchange.jl")
include("System/SingleIonAnisotropy.jl")
include("System/Ewald.jl")
include("System/Interactions.jl")
export SpinInfo, System, Site, all_sites, position_to_site,
    global_position, magnetic_moment, polarize_spin!, polarize_spins!, randomize_spins!, energy, forces,
    set_external_field!, set_anisotropy!, set_exchange!, set_biquadratic!, dmvec, enable_dipole_dipole!,
    to_inhomogeneous, set_external_field_at!, set_vacancy_at!, set_anisotropy_at!,
    symmetry_equivalent_bonds, set_exchange_at!, set_biquadratic_at!, remove_periodicity!

include("Reshaping.jl")
export reshape_geometry, resize_periodically, repeat_periodically, 
    print_wrapped_intensities, suggest_magnetic_supercell

include("Integrators.jl")
export Langevin, ImplicitMidpoint, step!

include("Optimization.jl")
export minimize_energy! 

include("SpinWaveTheory/SpinWaveTheory.jl")
include("SpinWaveTheory/SWTCalculations.jl")
include("SpinWaveTheory/Lanczos.jl")
export SpinWaveTheory, dispersion, dssf, delta_function_kernel

include("StructureFactors/StructureFactors.jl")
include("StructureFactors/SFUtils.jl")
include("StructureFactors/SampleGeneration.jl")
include("StructureFactors/FormFactor.jl")
include("StructureFactors/BasisReduction.jl")
include("Intensities/Types.jl")
include("StructureFactors/DataRetrieval.jl")
export DynamicStructureFactor, InstantStructureFactor, StructureFactor, FormFactor, 
    add_sample!, broaden_energy, lorentzian,
    all_exact_wave_vectors, ωs, spherical_shell, merge!, intensity_formula, integrated_lorentzian

include("Intensities/ElementContraction.jl")

include("Intensities/Interpolation.jl")
export intensities_interpolated, instant_intensities_interpolated, connected_path

include("Intensities/Binning.jl")
export intensities_binned, BinningParameters, count_bins, integrate_axes!,
    unit_resolution_binning_parameters, 
    bin_absolute_units_as_rlu!, bin_rlu_as_absolute_units!,
    slice_2D_binning_parameters, axes_bincenters,
    connected_path_bins

include("Intensities/LinearSpinWaveIntensities.jl")
export intensities_broadened, intensities_bands

include("Intensities/PowderAveraging.jl")
export powder_average_binned

include("Intensities/ExperimentData.jl")
export load_nxs, generate_mantid_script_from_binning_parameters

include("SunnyGfx/SunnyGfx.jl")
include("SunnyGfx/CrystalViewer.jl")
export view_crystal, offline_viewers, browser

include("MonteCarlo/Samplers.jl")
include("MonteCarlo/BinnedArray.jl")
include("MonteCarlo/ParallelTempering.jl")
include("MonteCarlo/HistogramReweighting.jl")
include("MonteCarlo/WangLandau.jl")
include("MonteCarlo/ParallelWangLandau.jl")
export propose_uniform, propose_flip, propose_delta, @mix_proposals, LocalSampler

# Makie (e.g., WGLMakie or GLMakie) is an optional dependency
function __init__()
    @require Makie="ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a" begin
        include("Plotting.jl")
        export plot_spins
            # plot_lattice, plot_bonds, plot_all_bonds, anim_integration, live_integration, live_langevin_integration
    end
end

end
