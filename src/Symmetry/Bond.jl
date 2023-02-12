"""
    Bond(i, j, n)

Represents a bond between atom indices `i` and `j`. `n` is a vector of three integers
specifying unit cell displacement in terms of lattice vectors.
"""
struct Bond
    i :: Int
    j :: Int
    n :: SVector{3, Int}
end

# kbtodo: Rename BondPos
# A bond expressed as two positions in fractional coordinates
struct BondRaw
    ri::Vec3
    rj::Vec3
end

function Bond(cryst::Crystal, b::BondRaw)
    i = position_to_index(cryst, b.ri)::Int
    j = position_to_index(cryst, b.rj)::Int
    ri = cryst.positions[i]
    rj = cryst.positions[j]
    n = round.(Int, (b.rj-b.ri) - (rj-ri))
    return Bond(i, j, n)
end

function BondRaw(cryst::Crystal, b::Bond)
    return BondRaw(cryst.positions[b.i], cryst.positions[b.j]+b.n)
end

function Base.show(io::IO, ::MIME"text/plain", bond::Bond)
    print(io, "Bond($(bond.i), $(bond.j), $(bond.n))")
end

# kbtodo: Remove this function or use `global_` prefix.

# The displacement vector ``𝐫_j - 𝐫_i`` in global coordinates between atoms
# `b.i` and `b.j`, accounting for the integer offsets `b.n` between unit cells.
function displacement(cryst::Crystal, b::BondRaw)
    return cryst.lat_vecs * (b.rj - b.ri)
end

function displacement(cryst::Crystal, b::Bond)
    return displacement(cryst, BondRaw(cryst, b))
end

# The global distance between atoms in bond `b`. Equivalent to
# `norm(displacement(cryst, b))`.
function distance(cryst::Crystal, b::BondRaw)
    return norm(displacement(cryst, b))
end

function distance(cryst::Crystal, b::Bond)
    return norm(displacement(cryst, b))
end

function transform(s::SymOp, b::BondRaw)
    return BondRaw(transform(s, b.ri), transform(s, b.rj))
end

function transform(cryst::Crystal, s::SymOp, b::Bond)
    return Bond(cryst, transform(s, BondRaw(cryst, b)))
end

function Base.reverse(b::Bond)
    return Bond(b.j, b.i, -1 .* b.n)
end

function Base.reverse(b::BondRaw)
    return BondRaw(b.rj, b.ri)
end

# Partition every nonzero bound into one of two sets
function bond_parity(bond)
    bond_delta = (bond.j - bond.i, bond.n...)
    @assert bond_delta != (0, 0, 0, 0)
    return bond_delta > (0, 0, 0, 0)
end

# Given a `bond` with indices into `cryst`, return a new bond with indices into
# `new_cryst`, which will typically be created from `reshape_crystal`.
function transform_bond(new_cryst::Crystal, cryst::Crystal, bond::Bond)
    # Positions in new fractional coordinates
    br = BondRaw(cryst, bond)
    new_ri = new_cryst.lat_vecs \ cryst.lat_vecs * br.ri
    new_rj = new_cryst.lat_vecs \ cryst.lat_vecs * br.rj

    # Construct bond using new indexing system
    new_i = position_to_index(new_cryst, new_ri)
    new_j, new_n = position_to_index_and_offset(new_cryst, new_rj)
    return Bond(new_i, new_j, new_n)
end
