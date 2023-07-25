struct SiteSymmetry
    symbol       :: String
    multiplicity :: Int
    wyckoff      :: Char
end


"""
An object describing a crystallographic unit cell and its space group symmetry.
Constructors are as follows:


    Crystal(filename; symprec=1e-5)

Reads the crystal from a `.cif` file located at the path `filename`.  The
optional parameter `symprec` controls the precision tolerance for spacegroup
symmetries.

    Crystal(latvecs, positions; types=nothing, symprec=1e-5)

Constructs a crystal from the complete list of atom positions `positions`, with
coordinates (between 0 and 1) in units of lattice vectors `latvecs`. Spacegroup
symmetry information is automatically inferred. The optional parameter `types`
is a list of strings, one for each atom, and can be used to break
symmetry-equivalence between atoms.

    Crystal(latvecs, positions, spacegroup_number; types=nothing, setting=nothing, symprec=1e-5)

Builds a crystal by applying symmetry operators for a given international
spacegroup number. For certain spacegroups, there are multiple possible unit
cell settings; in this case, a warning message will be printed, and a list of
crystals will be returned, one for every possible setting. Alternatively, the
optional `setting` string will disambiguate between unit cell conventions.

Currently, crystals built using only the spacegroup number will be missing some
symmetry information. It is generally preferred to build a crystal from a `.cif`
file or from the full specification of the unit cell.


# Examples

```julia
# Read a Crystal from a .cif file
Crystal("filename.cif")

# Build an FCC crystal using the primitive unit cell. The spacegroup number
# 225 is inferred.
latvecs = [1 1 0;
            1 0 1;
            0 1 1] / 2
positions = [[0, 0, 0]]
Crystal(latvecs, positions)

# Build a CsCl crystal (two cubic sublattices). By providing distinct type
# strings, the spacegroup number 221 is inferred.
latvecs = lattice_vectors(1, 1, 1, 90, 90, 90)
positions = [[0,0,0], [0.5,0.5,0.5]]
types = ["Na", "Cl"]
cryst = Crystal(latvecs, positions; types)

# Build a diamond cubic crystal from its spacegroup number 227. This
# spacegroup has two possible settings ("1" or "2"), which determine an
# overall unit cell translation.
latvecs = lattice_vectors(1, 1, 1, 90, 90, 90)
positions = [[1, 1, 1] / 4]
cryst = Crystal(latvecs, positions, 227; setting="1")
```

See also [`lattice_vectors`](@ref).
"""
struct Crystal
    latvecs        :: Mat3                                 # Lattice vectors as columns
    prim_latvecs   :: Mat3                                 # Primitive lattice vectors
    positions      :: Vector{Vec3}                         # Positions in fractional coords
    types          :: Vector{String}                       # Types
    classes        :: Vector{Int}                          # Class indices
    sitesyms       :: Union{Nothing, Vector{SiteSymmetry}} # Optional site symmetries
    symops         :: Vector{SymOp}                        # Symmetry operations
    spacegroup     :: String                               # Description of space group
    symprec        :: Float64                              # Tolerance to imperfections in symmetry
end

"""
    natoms(crystal::Crystal)

Number of atoms in the unit cell, i.e., number of Bravais sublattices.
"""
@inline natoms(cryst::Crystal) = length(cryst.positions)

"""
    cell_volume(crystal::Crystal)

Volume of the crystal unit cell.
"""
cell_volume(cryst::Crystal) = abs(det(cryst.latvecs))

# Constructs a crystal from the complete list of atom positions `positions`,
# representing fractions (between 0 and 1) of the lattice vectors `latvecs`.
# All symmetry information is automatically inferred.
function Crystal(latvecs, positions; types::Union{Nothing,Vector{String}}=nothing, symprec=1e-5)
    print_crystal_warnings(latvecs, positions)
    latvecs = convert(Mat3, latvecs)
    positions = [convert(Vec3, p) for p in positions]
    if isnothing(types)
        types = fill("", length(positions))
    end
    return crystal_from_inferred_symmetry(latvecs, positions, types; symprec)
end


# Builds a crystal by applying the symmetry operators for a given spacegroup
# symbol.
function Crystal(latvecs, positions, symbol::String; types::Union{Nothing,Vector{String}}=nothing, setting=nothing, symprec=1e-5)
    print_crystal_warnings(latvecs, positions)
    latvecs = convert(Mat3, latvecs)
    positions = [convert(Vec3, p) for p in positions]
    if isnothing(types)
        types = fill("", length(positions))
    end
    crystal_from_symbol(latvecs, positions, types, symbol; setting, symprec)
end

# Builds a crystal by applying symmetry operators for a given international
# spacegroup number.
function Crystal(latvecs, positions, spacegroup_number::Int; types::Union{Nothing,Vector{String}}=nothing, setting=nothing, symprec=1e-5)
    print_crystal_warnings(latvecs, positions)
    latvecs = convert(Mat3, latvecs)
    positions = [convert(Vec3, p) for p in positions]
    if isnothing(types)
        types = fill("", length(positions))
    end
    symbol = string(spacegroup_number)
    crystal_from_symbol(latvecs, positions, types, symbol; setting, symprec)
end

function print_crystal_warnings(latvecs, positions)
    det(latvecs) < 0 && @warn "Lattice vectors are not right-handed."
    if length(positions) >= 100
        @warn """This a very large crystallographic cell, which Sunny does not handle well.
                 If the intention is to model chemical inhomogeneity, the recommended procedure is as
                 follows: First, create a small unit cell with an idealized structure. Next, create
                 a perfectly periodic `System` of the desired size. Finally, use `to_inhomogeneous`
                 and related functions to design a system with the desired inhomogeneities."""
    end
end

function spacegroup_name(hall_number::Int)
    # String representation of space group
    sgt = Spglib.get_spacegroup_type(hall_number)
    return "HM symbol '$(sgt.international)' ($(sgt.number))"
end

function symops_from_spglib(rotations, translations)
    Rs = Mat3.(transpose.(eachslice(rotations, dims=3)))
    Ts = Vec3.(eachcol(translations))
    return SymOp.(Rs, Ts)
end


# Sort the sites according to class and fractional coordinates.
function sort_sites!(cryst::Crystal)
    function less_than(i, j)
        ci = cryst.classes[i]
        cj = cryst.classes[j]
        if ci != cj
            return ci < cj
        end
        ri = cryst.positions[i]
        rj = cryst.positions[j]
        for k = 3:-1:1
            if !isapprox(ri[k], rj[k], atol=cryst.symprec)
                return ri[k] < rj[k]
            end
        end
        error("Positions $i and $j cannot be distinguished.")
    end
    perm = sort(eachindex(cryst.positions), lt=less_than)
    cryst.positions .= cryst.positions[perm]
    cryst.classes .= cryst.classes[perm]
    cryst.types .= cryst.types[perm]
end


function crystal_from_inferred_symmetry(latvecs::Mat3, positions::Vector{Vec3}, types::Vector{String}; symprec=1e-5)
    for i in 1:length(positions)
        for j in i+1:length(positions)
            ri = positions[i]
            rj = positions[j]
            if all_integer(ri-rj; symprec)
                error("Positions $ri and $rj are symmetry equivalent.")
            end
        end
    end

    positions = wrap_to_unit_cell.(positions; symprec)

    cell = Spglib.Cell(latvecs, positions, types)
    d = Spglib.get_dataset(cell, symprec)
    classes = d.crystallographic_orbits
    # classes = d.equivalent_atoms
    symops = symops_from_spglib(d.rotations, d.translations)
    spacegroup = spacegroup_name(d.hall_number)

    # renumber class indices so that they go from 1:max_class
    classes = [findfirst(==(c), unique(classes)) for c in classes]
    @assert unique(classes) == 1:maximum(classes)

    # multiplicities for the equivalence classes
    multiplicities = map(classes) do c
        # atoms that belong to class c
        atoms = findall(==(c), classes)
        # atoms in the primitive cell that belong to class c
        prim_atoms = unique(d.mapping_to_primitive[atoms])
        # number of atoms in the standard cell that correspond to each primitive index for class c
        counts = [count(==(i), d.std_mapping_to_primitive) for i in prim_atoms]
        # sum over all equivalent atoms in the primitive cell
        sum(counts)
    end

    sitesyms = SiteSymmetry.(d.site_symmetry_symbols, multiplicities, d.wyckoffs)

    ret = Crystal(latvecs, d.primitive_lattice, positions, types, classes, sitesyms, symops, spacegroup, symprec)
    validate(ret)
    return ret
end


# Build Crystal using the space group denoted by a unique Hall number. The complete
# list is given at http://pmsl.planet.sci.kobe-u.ac.jp/~seto/?page_id=37&lang=en
function crystal_from_hall_number(latvecs::Mat3, positions::Vector{Vec3}, types::Vector{String}, hall_number::Int; symprec=1e-5)
    cell = cell_type(latvecs)
    hall_cell = cell_type(hall_number)
    allowed_cells = all_compatible_cells(hall_cell)
    @assert cell in allowed_cells "Hall number $hall_number requires a $hall_cell cell, but found $cell."

    if hall_cell == Sunny.monoclinic
        is_compatible = is_compatible_monoclinic_cell(latvecs, hall_number)
        @assert is_compatible "Lattice vectors define a monoclinic cell that is incompatible with Hall number $hall_number."
    end

    symops = symops_from_spglib(Spglib.get_symmetry_from_database(hall_number)...)
    spacegroup = spacegroup_name(hall_number)

    return crystal_from_symops(latvecs, positions, types, symops, spacegroup; symprec)
end

function crystal_from_symbol(latvecs::Mat3, positions::Vector{Vec3}, types::Vector{String}, symbol::String; setting=nothing, symprec=1e-5)
    hall_numbers = Int[]
    crysts = Crystal[]

    n_hall_numbers = 530
    for hall_number in 1:n_hall_numbers
        sgt = Spglib.get_spacegroup_type(hall_number)

        if (replace(symbol, " "=>"") == sgt.international_short || 
            symbol in [string(sgt.number), sgt.hall_symbol, sgt.international, sgt.international_full])

            # Some Hall numbers may be incompatible with unit cell of provided
            # lattice vectors; skip them.
            is_compatible = true

            cell = cell_type(latvecs)
            hall_cell = cell_type(hall_number)
            allowed_cells = all_compatible_cells(hall_cell)

            # Special handling of trigonal space groups
            if Sunny.is_trigonal_symmetry(hall_number)
                # Trigonal symmetry must have either hexagonal or rhombohedral
                # cell, according to the Hall number.
                is_latvecs_valid = cell in [Sunny.rhombohedral, Sunny.hexagonal]
                if !is_latvecs_valid
                    error("Symbol $symbol requires a rhomobohedral or hexagonal cell, but found $cell.")
                end
                is_compatible = cell in allowed_cells
            else
                # For all other symmetry types, there is a unique cell for each Hall number
                if !(cell in allowed_cells)
                    error("Symbol $symbol requires a $hall_cell cell, but found $cell.")
                end
            end

            if hall_cell == Sunny.monoclinic
                is_compatible = is_compatible_monoclinic_cell(latvecs, hall_number)
            end

            if is_compatible
                cryst = crystal_from_hall_number(latvecs, positions, types, hall_number; symprec)
                push!(hall_numbers, hall_number)
                push!(crysts, cryst)
            end
        end
    end

    if length(crysts) == 0
        error("Could not find symbol '$symbol' in database.")
    elseif length(crysts) == 1
        return first(crysts)
    else
        if !isnothing(setting)
            i = findfirst(hall_numbers) do hall_number
                sgt = Spglib.get_spacegroup_type(hall_number)
                setting == sgt.choice
            end
            if isnothing(i)
                error("The symbol '$symbol' is ambiguous, and the specified setting '$setting' is not valid.")
            else
                return crysts[i]
            end
        end

        println("The spacegroup '$symbol' allows for multiple settings!")
        println("Returning a list of the possible crystals:")
        for (i, (hall_number, c)) in enumerate(zip(hall_numbers, crysts))
            sgt = Spglib.get_spacegroup_type(hall_number)
            hm_symbol = sgt.international
            choice = sgt.choice
            n_atoms = length(c.positions)
            i_str = @sprintf "%2d" i
            natoms_str = @sprintf "%2d" n_atoms
            println("   $i_str. \"$hm_symbol\", setting=\"$choice\", with $natoms_str atoms")
        end
        println()
        println("Note: To disambiguate, you may pass a named parameter, setting=\"...\".")
        println()
        return crysts
    end
end

# Builds a crystal from an explicit set of symmetry operations and a minimal set of positions
function crystal_from_symops(latvecs::Mat3, positions::Vector{Vec3}, types::Vector{String}, symops::Vector{SymOp}, spacegroup::String; symprec=1e-5)
    all_positions = Vec3[]
    all_types = String[]
    classes = Int[]
    
    for i = eachindex(positions)
        for s = symops
            x = wrap_to_unit_cell(transform(s, positions[i]); symprec)

            j = findfirst(y -> all_integer(x-y; symprec), all_positions)
            if isnothing(j)
                push!(all_positions, x)
                push!(all_types, types[i])
                push!(classes, i)
            else
                j_ref = classes[j]
                if i != j_ref
                    error("Reference positions $(positions[i]) and $(positions[j_ref]) are symmetry equivalent.")
                end
            end
        end
    end

    # Atoms are sorted by contiguous equivalence classes: 1, 2, ..., n
    @assert unique(classes) == 1:maximum(classes)

    # Ask Spglib to infer the spacegroup for the given positions and types
    inferred = crystal_from_inferred_symmetry(latvecs, all_positions, all_types; symprec)

    # Compare the inferred symops to the provided ones
    is_subgroup = all(symops) do s
        any(inferred.symops) do s′
            isapprox(s, s′; atol=symprec)
        end
    end
    is_supergroup = all(inferred.symops) do s
        any(symops) do s′
            isapprox(s, s′; atol=symprec)
        end
    end

    if !is_subgroup
        @warn """User provided symmetry operation could not be inferred by Spglib,
                 which likely indicates a non-conventional unit cell."""
    end

    # If the inferred symops match the provided ones, then we use the inferred
    # Crystal. Otherwise we must construct a new Crystal without primitive
    # lattice and site symmetry information.
    ret = if is_subgroup && is_supergroup
        inferred
    else
        prim_latvecs = latvecs
        Crystal(latvecs, prim_latvecs, all_positions, all_types, classes, nothing, symops, spacegroup, symprec)
    end
    sort_sites!(ret)
    validate(ret)
    return ret
end


function reshape_crystal(cryst::Crystal, new_cell_size::Mat3)
    # TODO: support resizing to multiples of the primitive cell?
    @assert all(isinteger, new_cell_size)

    # Return the original crystal if no resizing needed
    new_cell_size == I && return cryst

    # Lattice vectors of the new unit cell in global coordinates
    new_latvecs = cryst.latvecs * new_cell_size

    # These don't change because both are in global coordinates
    prim_latvecs = cryst.prim_latvecs

    # This matrix defines a mapping from fractional coordinates in the original
    # unit cell to fractional coordinates in the new unit cell
    B = inv(new_cell_size)

    # Symmetry precision needs to be rescaled for the new unit cell. Ideally we
    # would have three separate rescalings (one per lattice vector), but we're
    # forced to pick just one.
    new_symprec = cryst.symprec * cbrt(abs(det(B)))

    # In original fractional coordinates, find a bounding box that completely
    # contains the new unit cell. Not sure how much shifting is needed here;
    # pick ±2 to be on the safe side.
    nmin = minimum.(eachrow(new_cell_size)) .- 2
    nmax = maximum.(eachrow(new_cell_size)) .+ 2

    new_positions = Vec3[]
    new_types     = String[]
    new_classes   = Int[]
    new_sitesyms  = isnothing(cryst.sitesyms) ? nothing : SiteSymmetry[]

    for i in 1:natoms(cryst)
        for n1 in nmin[1]:nmax[1], n2 in nmin[2]:nmax[2], n3 in nmin[3]:nmax[3]
            x = cryst.positions[i] + Vec3(n1, n2, n3)
            Bx = B*x

            # Check whether position x (in original fractional coordinates) is
            # inside the new unit cell. The position in the new fractional
            # coordinates is B*x. The mathematical test is whether each
            # component of B*x is within the range [0,1). This can be checked
            # using the condition `wrap_to_unit_cell(B*x) == B*x`. This function
            # accounts for finite "symmetry precision" ϵ in the new unit cell by
            # wrapping components of `B*x` to the range [-ϵ,1-ϵ).
            if wrap_to_unit_cell(Bx; symprec=new_symprec) ≈ Bx
                push!(new_positions, B*x)
                push!(new_types, cryst.types[i])
                push!(new_classes, cryst.classes[i])
                !isnothing(cryst.sitesyms) && push!(new_sitesyms, cryst.sitesyms[i])
            end
        end
    end

    # Check that we have exactly the right number of atoms
    N1, N2, N3 = eachcol(new_cell_size)
    @assert length(new_positions) == abs((N1×N2)⋅N3) * natoms(cryst)

    # Create an empty list of symops as a marker that this information has been
    # lost with the resizing procedure.
    new_symops = SymOp[]

    return Crystal(new_latvecs, prim_latvecs, new_positions, new_types, new_classes, new_sitesyms,
                new_symops, cryst.spacegroup, new_symprec)
end


"""
    subcrystal(cryst, types) :: Crystal

Filters sublattices of a `Crystal` by atom `types`, keeping the space group
unchanged.

    subcrystal(cryst, classes) :: Crystal

Filters sublattices of `Crystal` by equivalence `classes`, keeping the space
group unchanged.
"""
function subcrystal(cryst::Crystal, types::Vararg{String, N}) where N
    for s in types
        if !(s in cryst.types)
            error("types string '$s' is not present in crystal.")
        end
    end
    atoms = findall(in(types), cryst.types)
    classes = unique(cryst.classes[atoms])
    return subcrystal(cryst, classes...)
end

function subcrystal(cryst::Crystal, classes::Vararg{Int, N}) where N
    for c in classes
        if !(c in cryst.classes)
            error("Class '$c' is not present in crystal.")
        end
    end

    atoms = findall(in(classes), cryst.classes)
    new_positions = cryst.positions[atoms]
    new_types = cryst.types[atoms]
    new_classes = cryst.classes[atoms]
    new_sitesyms = cryst.sitesyms[atoms]

    if atoms != 1:maximum(atoms)
        @warn "Atoms are being renumbered."
    end

    ret = Crystal(cryst.latvecs, cryst.prim_latvecs, new_positions, new_types, new_classes, new_sitesyms,
                  cryst.symops, cryst.spacegroup, cryst.symprec)
    return ret
end


function Base.show(io::IO, ::MIME"text/plain", cryst::Crystal)
    printstyled(io, "Crystal\n"; bold=true, color=:underline)
    println(io, cryst.spacegroup)

    if is_standard_form(cryst.latvecs)
        (a, b, c, α, β, γ) = lattice_params(cryst.latvecs)
        @printf io "Lattice params a=%.4g, b=%.4g, c=%.4g, α=%.4g°, β=%.4g°, γ=%.4g°\n" a b c α β γ
    else
        println(io, "Lattice vectors:")
        for a in eachcol(cryst.latvecs)
            @printf io "   [%.4g %.4g %.4g]\n" a[1] a[2] a[3]
        end
    end

    @printf io "Cell volume %.4g\n" cell_volume(cryst)

    for c in unique(cryst.classes)
        i = findfirst(==(c), cryst.classes)
        descr = String[]
        if cryst.types[i] != ""
            push!(descr, "Type '$(cryst.types[i])'")
        end
        if !isnothing(cryst.sitesyms)
            symbol = cryst.sitesyms[i].symbol
            multiplicity = cryst.sitesyms[i].multiplicity
            wyckoff = cryst.sitesyms[i].wyckoff
            push!(descr, "Wyckoff $multiplicity$wyckoff (point group '$symbol')")
        end
        println(io, join(descr, ", "), ":")

        for i in findall(==(c), cryst.classes)
            pos = atom_pos_to_string(cryst.positions[i])
            println(io, "   $i. $pos")
        end
    end
end

function validate(cryst::Crystal)
    # Atoms of the same class must have the same type
    for i in eachindex(cryst.positions)
        for j in eachindex(cryst.positions)
            if cryst.classes[i] == cryst.classes[j]
                @assert cryst.types[i] == cryst.types[j]
            end
        end
    end

    # Rotation matrices in global coordinates must be orthogonal
    for s in cryst.symops
        R = cryst.latvecs * s.R * inv(cryst.latvecs)
        # Due to possible imperfections in the lattice vectors, only require
        # that R is approximately orthogonal
        @assert norm(R*R' - I) < cryst.symprec "Lattice vectors and symmetry operations are incompatible."
    end

    # TODO: Check that space group is closed and that symops have inverse?
end

#= Definitions of common crystals =#

function cubic_crystal(; a=1.0)
    latvecs = lattice_vectors(a, a, a, 90, 90, 90)
    positions = [[0, 0, 0]]
    Crystal(latvecs, positions)
end

function fcc_crystal(; a=1.0)
    latvecs = lattice_vectors(a, a, a, 90, 90, 90)
    positions = [[0, 0, 0]/2,
                  [1, 1, 0]/2,
                  [1, 0, 1]/2,
                  [0, 1, 1]/2]
    cryst = Crystal(latvecs, positions)
    sort_sites!(cryst)
    cryst
end

function fcc_primitive_crystal(; a=1.0)
    latvecs = [1 1 0; 0 1 1; 1 0 1]' * a/2
    positions = [[0, 0, 0]]
    Crystal(latvecs, positions)
end

function bcc_crystal(; a=1.0)
    latvecs = lattice_vectors(a, a, a, 90, 90, 90)
    positions = [[0, 0, 0]/2,
                  [1, 1, 1]/2,]
    Crystal(latvecs, positions)
end

function bcc_primitive_crystal(; a=1.0)
    latvecs = [1 1 -1; 1 -1 1; -1 1 1]' * a/2
    positions = [[0, 0, 0]]
    Crystal(latvecs, positions)
end


function diamond_crystal(; a=1.0)
    latvecs = lattice_vectors(a, a, a, 90, 90, 90)
    positions = [
        [0, 0, 0]/4,
        [2, 2, 0]/4,
        [1, 1, 1]/4,
        [3, 3, 1]/4,
        [2, 0, 2]/4,
        [0, 2, 2]/4,
        [3, 1, 3]/4,
        [1, 3, 3]/4,
    ]
    cryst = Crystal(latvecs, positions)
    sort_sites!(cryst)
    cryst
end

function diamond_primitive_crystal(; a=1.0)
    latvecs = [1 1 0; 1 0 1; 0 1 1]' * a/2
    positions = [
        [0, 0, 0]/4,
        [1, 1, 1]/4,
    ]
    Crystal(latvecs, positions)
end

function pyrochlore_lattice(; a=1.0)
    latvecs = [1 1 0; 1 0 1; 0 1 1]' * a/2
    positions = [
        [5, 5, 5]/8,
        [1, 5, 5]/8,
        [5, 5, 1]/8,
        [5, 1, 5]/8
    ]
    cryst = Crystal(latvecs, positions)
    sort_sites!(cryst)
    cryst
end