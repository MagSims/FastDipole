# Utilities for working with Bravais lattices

"""
    lattice_params(latvecs)

Compute the lattice parameters ``(a, b, c, α, β, γ)`` for the three lattice
vectors provided as columns of `latvecs`. The inverse mapping is
[`lattice_vectors`](@ref).
"""
function lattice_params(latvecs) :: NTuple{6, Float64}
    v1, v2, v3 = eachcol(Mat3(latvecs))
    a, b, c = norm(v1), norm(v2), norm(v3)
    acosd_clipped(x) = acosd(min(max(x, -1), 1))
    α = acosd_clipped((v2 ⋅ v3) / (b * c))
    β = acosd_clipped((v1 ⋅ v3) / (a * c))
    γ = acosd_clipped((v1 ⋅ v2) / (a * b))
    return (a, b, c, α, β, γ)
end

"""
    lattice_vectors(a, b, c, α, β, γ)

Return the lattice vectors, as columns of the ``3×3`` output matrix, that define
the shape of a crystallographic cell in global Cartesian coordinates.
Conversely, one can view the output matrix as defining the global Cartesian
coordinate system with respect to the lattice system.

The lattice constants ``(a, b, c)`` have units of length, and the angles ``(α,
β, γ)`` are in degrees. The inverse mapping is [`lattice_params`](@ref).

# Example
```julia
latvecs = lattice_vectors(1, 1, 2, 90, 90, 120)
a1, a2, a3 = eachcol(latvecs)
@assert a1 ≈ [1, 0, 0]       # a1 always aligned with global x
@assert a2 ≈ [-1/2, √3/2, 0] # a2 always in global (x,y) plane
@assert a3 ≈ [0, 0, 2]       # a3 may generally be a combination of (x,y,z)
```
"""
function lattice_vectors(a, b, c, α, β, γ) :: Mat3
    @assert all(0 < x < 180 for x in (α, β, γ))

    sγ, cγ = sind(γ), cosd(γ)
    cβ, cα = cosd(β), cosd(α)
    v1 = Vec3(a, 0, 0)
    v2 = Vec3(b * cγ, b * sγ, 0)
    v3x = c * cβ
    v3y = c / sγ * (cα - cβ * cγ)
    v3z = c / sγ * √(sγ^2 - cα^2 - cβ^2 + 2 * cα * cβ * cγ)
    v3 = Vec3(v3x, v3y, v3z)
    latvecs = hcat(v1, v2, v3)

    @assert [a, b, c, α, β, γ] ≈ collect(lattice_params(latvecs))

    return latvecs
end

function is_standard_form(latvecs::Mat3)
    lat_params = lattice_params(latvecs)
    conventional_latvecs = lattice_vectors(lat_params...)
    return latvecs ≈ conventional_latvecs
end

"""
    CellType

An enumeration over the different types of 3D Bravais unit cells.
"""
@enum CellType begin
    triclinic
    monoclinic
    orthorhombic
    tetragonal
    # Rhombohedral is a special case. It is a lattice type (a=b=c, α=β=γ) but
    # not a spacegroup type. Trigonal space groups are conventionally described
    # using either hexagonal or rhombohedral lattices.
    rhombohedral
    hexagonal
    cubic
end

# Infer the `CellType` of a unit cell from its lattice vectors, i.e. the columns
# of `latvecs`. Report an error if the unit cell is not in conventional form,
# which would invalidate the table of symops for a given Hall number.
function cell_type(latvecs::Mat3)
    a, b, c, α, β, γ = lattice_params(latvecs)

    if a ≈ b ≈ c
        if α ≈ β ≈ γ ≈ 90
            return cubic
        elseif α ≈ β ≈ γ
            return rhombohedral
        end
    end

    if α ≈ β ≈ γ ≈ 90
        if a ≈ b
            return tetragonal
        elseif b ≈ c || c ≈ a
            error("Found a nonconventional tetragonal unit cell. Consider using `lattice_vectors(a, a, c, 90, 90, 90)`.")
        else
            return orthorhombic
        end
    end

    if (a ≈ b && α ≈ β ≈ 90 && (γ ≈ 60 || γ ≈ 120)) ||
       (b ≈ c && β ≈ γ ≈ 90 && (α ≈ 60 || α ≈ 120)) ||
       (c ≈ a && γ ≈ α ≈ 90 && (β ≈ 60 || β ≈ 120))
        if γ ≈ 120
            return hexagonal
        else
            error("Found a nonconventional hexagonal unit cell. Consider using `lattice_vectors(a, a, c, 90, 90, 120)`.")
        end
    end

    # Accept any of three possible permutations for monoclinic unit cell
    if α ≈ β ≈ 90 || β ≈ γ ≈ 90 || α ≈ γ ≈ 90
        return monoclinic
    end
    
    return triclinic
end

# Return the standard cell convention for a given Hall number using the
# convention of spglib, listed at
# http://pmsl.planet.sci.kobe-u.ac.jp/~seto/?page_id=37
function cell_type(hall_number::Int)
    if 1 <= hall_number <= 2
        triclinic
    elseif 3 <= hall_number <= 107
        monoclinic
    elseif 108 <= hall_number <= 348
        orthorhombic
    elseif 349 <= hall_number <= 429
        tetragonal
    elseif 430 <= hall_number <= 461
        # The trigonal space groups require either rhombohedral or hexagonal
        # cells. The Hall numbers below have "choice" R.
        hall_number in [434, 437, 445, 451, 453, 459, 461] ? rhombohedral : hexagonal
    elseif 462 <= hall_number <= 488
        hexagonal
    elseif 489 <= hall_number <= 530
        cubic
    else
        error("Invalid Hall number $hall_number. Allowed range is 1..530")
    end
end

function all_compatible_cells(cell::CellType)
    if cell == triclinic
        [triclinic, monoclinic, orthorhombic, tetragonal, rhombohedral, hexagonal, cubic]
    elseif cell == monoclinic
        [monoclinic, orthorhombic, tetragonal, hexagonal, cubic]
    elseif cell == orthorhombic
        [orthorhombic, tetragonal, cubic]
    elseif cell == tetragonal
        [tetragonal, cubic]
    elseif cell == rhombohedral
        [rhombohedral, cubic]
    elseif cell == hexagonal
        [hexagonal]
    elseif cell == cubic
        [cubic]
    else
        error()
    end
end

function is_trigonal_symmetry(hall_number::Int)
    return 430 <= hall_number <= 461
end
