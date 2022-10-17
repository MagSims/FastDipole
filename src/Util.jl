# Mod functions for CartesianIndex
@inline function modc(i::CartesianIndex{D}, m) :: CartesianIndex{D} where {D}
    CartesianIndex(mod.(Tuple(i), Tuple(m)))
end
@inline function modc1(i::CartesianIndex{D}, m) :: CartesianIndex{D} where {D}
    CartesianIndex(mod1.(Tuple(i), Tuple(m)))
end
@inline function offset(i::CartesianIndex{D}, n::SVector{D,Int}, m) :: CartesianIndex{D} where {D}
    CartesianIndex( Tuple(mod1.(Tuple(i) .+ n, Tuple(m))) )
end
"Splits a CartesianIndex into its first index, and the rest"
@inline function splitidx(i::CartesianIndex{D}) where {D}
    return (CartesianIndex(Tuple(i)[1:3]), i[4])
end

# Taken from:
# https://discourse.julialang.org/t/efficient-tuple-concatenation/5398/8
@inline tuplejoin(x) = x
@inline tuplejoin(x, y) = (x..., y...)
@inline tuplejoin(x, y, z...) = (x..., tuplejoin(y, z...)...)

# For efficiency, may need to look into Base.unsafe_wrap
#   and pointer trickery if we want to stick with Vec3.

# TODO: Remove this functions and write them inline

"Reinterprets an array of Vec3 to an equivalent array of Float64"
@inline function _reinterpret_from_spin_array(A::Array{Vec3}) :: Array{Float64}
    Ar = reinterpret(reshape, Float64, A)
end

"Reinterprets an array of Floats with leading dimension 3 to an array of Vec3"
@inline function _reinterpret_to_spin_array(A::Array{Float64}) :: Array{Vec3}
    Ar = reinterpret(reshape, Vec3, A)
end

"Reinterprets an array of Mat3 to an equivalent array of Float64"
@inline function _reinterpret_dipole_tensor(A::OffsetArray{Mat3}) :: Array{Float64}
    Ar = reinterpret(reshape, Float64, parent(A))
    return reshape(Ar, 3, 3, size(A)...)    # make sure this doesn't mess up indexing
end
