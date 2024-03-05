"""
    AugmentedRegister(codual::CoDual, tangent_stack)

A wrapper data structure for bundling together a codual and a tangent stack. These appear
in the code associated to active values in the primal.

For example, a statment in the primal such as
```julia
%5 = sin(%4)::Float64
```
which provably returns a `Float64` in the primal, would return an `register_type(Float64)`
in the forwards-pass, where `register_type` will return an `AugmentedRegister` when the
primal type is `Float64`.
"""
struct AugmentedRegister{T<:CoDual, V}
    codual::T
    tangent_stack::V
end

"""
    register_type(::Type{P}) where {P}

If `P` is the type associated to a primal register, the corresponding register in the
forwards-pass must be `register_type(P)`. If `tangent_type(P)` is `NoTangent`, this must
simply be `P`. Otherwise, it will be an `AugmentedRegister`.
"""
function register_type(::Type{P}) where {P}
    P == DataType && return Any
    P isa Union && return Union{register_type(P.a), register_type(P.b)}
    if isconcretetype(P)
        is_inactive = tangent_type(P) == NoTangent
        return is_inactive ? P : AugmentedRegister{codual_type(P), tangent_stack_type(P)}
    else
        return Any
    end
end