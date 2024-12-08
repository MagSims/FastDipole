# Return a matrix whose columns are an orthogonal basis for the span of columns
# in A. Adapted from LinearAlgebra.nullspace().
function colspace(A; atol::Float64)
    m, n = size(A, 1), size(A, 2)
    (m == 0 || n == 0) && return A
    SVD = svd(A)
    indices = findall(>(atol), SVD.S)
    return copy(SVD.U[:, indices])
end


# Calculate coefficients b that satisfy `bᵀ 𝒪 = cᵀ T`, where 𝒪 are the Stevens
# operators, and T are the spherical harmonics. Using `𝒪 = α T`, we must solve
# bᵀ α = cᵀ, or b = α⁻ᵀ c.
function transform_spherical_to_stevens_coefficients(k, c)
    return transpose(stevens_αinv[k]) * c
end


function basis_for_symmetry_allowed_anisotropies(cryst::Crystal, i::Int; k::Int, R::Mat3, atol::Float64)
    # The symmetry operations for the point group at atom i. Each one encodes a
    # rotation/reflection.
    symops = symmetries_for_pointgroup_of_atom(cryst, i)

    # The Wigner D matrices for each symop
    Ds = map(symops) do s
        # R is an orthogonal matrix that transforms positions, x → x′ = R x. It
        # might or might not include a reflection, i.e., det R = ±1.
        sR = cryst.latvecs * s.R * inv(cryst.latvecs)

        # Unlike position x, spin S = [Sx, Sy, Sz] is a _pseudo_ vector, which
        # means that, under reflection, the output gains an additional minus
        # sign. That is, the orthogonal transformation R applied to spin has the
        # action, S → S′ = ± R S, where the minus sign corresponds to the case
        # det(R) = -1. More simply, we may write S′ = Q S, where Q = det(R) R.
        Q = det(sR) * sR

        # The Wigner D matrix, whose action on a spherical tensor corresponds to
        # the 3x3 rotation Q (see more below).
        return unitary_irrep_for_rotation(Q; N=2k+1)
    end

    # A general operator in the spin-k representation can be decomposed in the
    # basis of spherical tensors, 𝒜 = ∑_q c_q T_kq, for some coefficients c_q.
    # Spherical tensors transform as T_kq → D^{*}_qq′ T_kq′. Alternatively, we
    # can treat T_kq as invariant, and calculate the transformed 𝒜 as a
    # transformation of the coefficients c → c′ = D† c. Given arbitrary eᵢ, the
    # operator represented by coefficients cᵢ = (D₁† + D₂† + ... Dₙ†) eᵢ is
    # invariant to all point group operations, i.e., Dj† cᵢ = cᵢ. Repeating this
    # procedure for a complete basis {e₁, e₂, ...}, we determine all
    # symmetry-invariant operators 𝒜. Specifically, every column of the matrix
    # C = (D₁† + D₂† + ... Dₙ†) gives coefficients to a symmetry-invariant
    # operator 𝒜.
    C = sum(D' for D in Ds)

    # Transform coefficients c to c′ in rotated Stevens operators, T′ = D* T,
    # where the Wigner D matrix is associated with the rotation R. That is, find
    # c′ satisfying c′ᵀ T′ = c T. Recall c′ᵀ T′ = (c′ᵀ D*) T = (D† c′)ᵀ T. The
    # constraint becomes D† c′ = c. Since D is unitary, we have c′ = D c. We
    # apply this transformation to each column c of C.
    D = unitary_irrep_for_rotation(R; N=2k+1)
    C = D * C

    # Transform columns c of C to columns b of B such that 𝒜 = cᵀ T = bᵀ 𝒪.
    # Effectively, this reexpresses the symmetry-allowed operators 𝒜 in the
    # basis of Stevens operators 𝒪.
    B = mapslices(C; dims=1) do c
        transform_spherical_to_stevens_coefficients(k, c)
    end

    # If 𝒜 is symmetry-allowed, then its Hermitian and anti-Hermitian parts are
    # independently symmetry-allowed. These are associated with the real and
    # imaginary parts of B. Use the real and imaginary parts of B to construct
    # an over-complete set of symmetry-allowed operators that are guaranteed to
    # be Hermitian. Create a widened real matrix from these two parts, and
    # eliminate linearly-dependent vectors from the column space.
    B = colspace(hcat(real(B), imag(B)); atol)

    # Find linear combination of columns that sparsifies B
    B = sparsify_columns(B; atol)

    # Scale each column to make prettier
    return map(eachcol(B)) do b
        # Rescale column so that the largest component is 1
        b /= argmax(abs, b)

        if any(x -> atol < abs(x) < sqrt(atol), b)
            @info """Found a very small but nonzero expansion coefficient.
                        This may indicate a slightly misaligned reference frame."""
        end

        # Rescale by up to 60× if it makes all coefficients integer
        denoms = denominator.(rationalize.(b; tol=atol))
        if all(<=(60), denoms)
            factor = lcm(denominator.(rationalize.(b; tol=atol)))
            if factor <= 60
                b .*= factor
            end
        end

        b
    end

    return B
end


# Subject to change. Users should call print_suggested_frame() instead
function suggest_frame_for_atom(cryst::Crystal, i::Int)
    # Collect list of symmetry axes along with their counts
    axes_counts = Tuple{Vec3, Int}[]
    symops = symmetries_for_pointgroup_of_atom(cryst, i)
    for s in symops
        # Not interested in the identity, nor pure inversions
        (s.R ≈ I || s.R ≈ -I) && continue

        # Orthogonal transformation for pointgroup symmetry
        R = cryst.latvecs * s.R * inv(cryst.latvecs)

        # Extract normalized vector n, either a rotation axis or the normal of a
        # reflection plane
        Q = det(R) * R
        n, _ = matrix_to_axis_angle(Q)

        # Prefer positive coordinates
        if sum(n) < 0
            n = -n
        end

        # Collect all unique axes, along with their counts. We compare against
        # the director n*n' to be insensitive to sign, n → -n.
        i = findfirst(x -> x[1]*x[1]' ≈ n*n', axes_counts)
        if isnothing(i)
            push!(axes_counts, (n, 1))
        else
            (n′, cnt) = axes_counts[i]
            axes_counts[i] = (n′, cnt+1)
        end
    end

    if isempty(axes_counts)
        @info "Could not find a symmetry axis."
        return Mat3(I)
    end

    function select_axis(axes_counts)
        # Candidates are those with maximimal symmetry
        max_count = maximum(x -> x[2], axes_counts)
        candidates = [x[1] for x in axes_counts if (x[2] == max_count)]

        # Choose according to aesthetic heuristics
        return argmin(candidates) do n
            # Standard axis (x, y, or z) is preferred
            n ≈ Vec3(0,0,1) && return 0
            n ≈ Vec3(1,0,0) && return 1
            n ≈ Vec3(0,1,0) && return 2
        
            # Look for [1,1,1] axis
            n ≈ Vec3(1,1,1)/√3 && return 3
        
            # Look for [±1,±1,±1] axis
            abs.(n) ≈ Vec3(1,1,1)/√3 && return 4
        
            # Try to minimize the number of zeros, thus preferring axes in the
            # (x,y) plane, etc.
            return 10 * count(n_i -> abs(n_i) > 1e-12, n)
        end
    end
    
    z_dir = select_axis(axes_counts)

    # Collect all symmetry axes orthogonal to the primary axis, along with their
    # counts
    orthogonal_axes_counts = filter(x -> abs(x[1]⋅z_dir) < 1e-12, axes_counts)

    if isempty(orthogonal_axes_counts)
        @info "Could not find a symmetry axis orthogonal to $(fractional_vec3_to_string(z_dir))."
        x_dir = (z_dir ≈ Vec3(1,0,0)) ? Vec3(0,0,1) : Vec3(1,0,0)
        x_dir = normalize(x_dir - (x_dir⋅z_dir)*z_dir)
    else
        x_dir = select_axis(orthogonal_axes_counts)
    end

    y_dir = z_dir × x_dir

    # Rows of output matrix are the new reference directions
    return Mat3([x_dir y_dir z_dir])'
end
