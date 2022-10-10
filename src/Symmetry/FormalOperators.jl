
# The index q = k...-k appears in descending order for consistency with the
# basis used for spin matrices (descending order of Jz eigenvalues). Note that
# the spin operators are used to generate rotations of the Stevens operators via
# the Wigner D matrices.
const stevens_operator_symbols = let
    # 𝒪₀ = identity
    𝒪₁ = collect(@ncpolyvar                     𝒪₁₁ 𝒪₁₀ 𝒪₁₋₁)
    𝒪₂ = collect(@ncpolyvar                 𝒪₂₂ 𝒪₂₁ 𝒪₂₀ 𝒪₂₋₁ 𝒪₂₋₂)
    𝒪₃ = collect(@ncpolyvar             𝒪₃₃ 𝒪₃₂ 𝒪₃₁ 𝒪₃₀ 𝒪₃₋₁ 𝒪₃₋₂ 𝒪₃₋₃)
    𝒪₄ = collect(@ncpolyvar         𝒪₄₄ 𝒪₄₃ 𝒪₄₂ 𝒪₄₁ 𝒪₄₀ 𝒪₄₋₁ 𝒪₄₋₂ 𝒪₄₋₃ 𝒪₄₋₄)
    𝒪₅ = collect(@ncpolyvar     𝒪₅₅ 𝒪₅₄ 𝒪₅₃ 𝒪₅₂ 𝒪₅₁ 𝒪₅₀ 𝒪₅₋₁ 𝒪₅₋₂ 𝒪₅₋₃ 𝒪₅₋₄ 𝒪₅₋₅)
    𝒪₆ = collect(@ncpolyvar 𝒪₆₆ 𝒪₆₅ 𝒪₆₄ 𝒪₆₃ 𝒪₆₂ 𝒪₆₁ 𝒪₆₀ 𝒪₆₋₁ 𝒪₆₋₂ 𝒪₆₋₃ 𝒪₆₋₄ 𝒪₆₋₅ 𝒪₆₋₆)
    [𝒪₁, 𝒪₂, 𝒪₃, 𝒪₄, 𝒪₅, 𝒪₆]
end

const spin_operator_symbols = let
    SVector{3}(@ncpolyvar 𝒮x 𝒮y 𝒮z)
end

const spin_classical_symbols = let
    SVector{3}(@polyvar sx sy sz)
end

# Convenient accessor for Stevens symbols
struct StevensOpsAbstract end
function Base.getindex(::StevensOpsAbstract, k::Int, q::Int)
    k < 0  && error("Stevens operators 𝒪[k,q] require k >= 0.")
    k > 6  && error("Stevens operators 𝒪[k,q] currently require k <= 6.")
    !(-k <= q <= k) && error("Stevens operators 𝒪[k,q] require -k <= q <= k.")
    if k == 0
        return 1.0
    else
        q_idx = k - q + 1
        return stevens_operator_symbols[k][q_idx]
    end
end

"""
    𝒪[k,q]

Abstract symbols for the Stevens operators. Linear combinations of these can be
used to specify the single-ion anisotropy.
"""
const 𝒪 = StevensOpsAbstract()

"""
    𝒮[1], 𝒮[2], 𝒮[3]

Abstract symbols for the spin operators. Polynomials of these can be used to
specify the single-ion anisotropy.
"""
const 𝒮 = spin_operator_symbols

function operator_to_matrix(p; N)
    rep = p(
        𝒮 => gen_spin_ops(N),
        [stevens_operator_symbols[k] => stevens_ops(N, k) for k=1:6]... 
    )
    if !(rep ≈ rep')
        println("Warning: Received non-Hermitian operator '$p'. Using symmetrized operator.")
    end
    # Symmetrize in any case for more accuracy
    return (rep+rep')/2
end

function operator_to_classical_polynomial(p)
    return p(
        𝒮 => spin_classical_symbols,
        [stevens_operator_symbols[k] => stevens_classical(k) for k=1:6]...
    )
end

function operator_to_classical_stevens_expansion(p)
    error("TODO")
end

"""
    function print_classical_anisotropy(p)

Prints a quantum operator (e.g. linear combination of Stevens operators) as a
polynomial of spin expectation values in the classical limit.
"""
function print_classical_anisotropy(p)
    println(operator_to_classical_polynomial(p))
end

"""
    function print_classical_anisotropy_as_stevens(p)

Prints a quantum operator (e.g. a polynomial of spin operators) as a linear
combination of Stevens operators in the classical limit.
"""
function print_classical_anisotropy_as_stevens(p)
    println(classical_polynomial_to_stevens_expansion(operator_to_classical_polynomial(p)))
end
