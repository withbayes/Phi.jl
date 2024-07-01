"""
    NoTangent

The type in question has no meaningful notion of a tangent space.
Generally, you shouldn't use this -- just let the default recursive tangent
construction work.
You might need to use this for `primitive type`s though.
"""
struct NoTangent end

"""
    PossiblyUninitTangent{T}

Represents a `T` which maybe or may not be present. Does not distinguish between 0 and
not being present.
"""
struct PossiblyUninitTangent{T}
    tangent::T
    PossiblyUninitTangent{T}(tangent::T) where {T} = new{T}(tangent)
    PossiblyUninitTangent{T}() where {T} = new{T}()
end

@inline PossiblyUninitTangent(tangent::T) where {T} = PossiblyUninitTangent{T}(tangent)
@inline PossiblyUninitTangent(T::Type) = PossiblyUninitTangent{T}()

@inline is_init(t::PossiblyUninitTangent) = isdefined(t, :tangent)
is_init(t) = true

function val(x::PossiblyUninitTangent{T}) where {T}
    if is_init(x)
        return x.tangent
    else
        throw(error("Uninitialised"))
    end
end
val(x) = x

function Base.:(==)(t::PossiblyUninitTangent{T}, s::PossiblyUninitTangent{T}) where {T}
    is_init(t) && is_init(s) && return val(t) == val(s)
    is_init(t) && !is_init(s) && return false
    !is_init(t) && is_init(s) && return false
    return true
end

_wrap_type(::Type{T}) where {T} = PossiblyUninitTangent{T}

_wrap_field(::Type{Q}, x::T) where {Q, T} = PossiblyUninitTangent{Q}(x)
_wrap_field(x::T) where {T} = _wrap_field(T, x)

struct Tangent{Tfields<:NamedTuple}
    fields::Tfields
end

Base.:(==)(x::Tangent, y::Tangent) = x.fields == y.fields

mutable struct MutableTangent{Tfields<:NamedTuple}
    fields::Tfields
end

Base.:(==)(x::MutableTangent, y::MutableTangent) = x.fields == y.fields

fields_type(::Type{MutableTangent{Tfields}}) where {Tfields<:NamedTuple} = Tfields
fields_type(::Type{Tangent{Tfields}}) where {Tfields<:NamedTuple} = Tfields
fields_type(::Type{<:Union{MutableTangent, Tangent}}) = NamedTuple

const PossiblyMutableTangent{T} = Union{MutableTangent{T}, Tangent{T}}

"""
    get_tangent_field(t::Union{MutableTangent, Tangent}, i::Int)

Gets the `i`th field of data in `t`.

Has the same semantics that `getfield!` would have if the data in the `fields` field of `t`
were actually fields of `t`. This is the moral equivalent of `getfield` for
`MutableTangent`.
"""
@inline function get_tangent_field(t::PossiblyMutableTangent{Tfs}, i::Int) where {Tfs}
    v = getfield(t.fields, i)
    return fieldtype(Tfs, i) <: PossiblyUninitTangent ? val(v) : v
end

@inline function get_tangent_field(t::PossiblyMutableTangent{F}, s::Symbol) where {F}
    return get_tangent_field(t, _sym_to_int(F, Val(s)))
end

"""
    set_tangent_field!(t::MutableTangent{Tfields}, i::Int, x) where {Tfields}

Sets the value of the `i`th field of the data in `t` to value `x`.

Has the same semantics that `setfield!` would have if the data in the `fields` field of `t`
were actually fields of `t`. This is the moral equivalent of `setfield!` for
`MutableTangent`.
"""
@inline function set_tangent_field!(t::MutableTangent{Tfields}, i::Int, x) where {Tfields}
    fields = t.fields
    Ti = fieldtype(Tfields, i)
    new_val = Ti <: PossiblyUninitTangent ? Ti(x) : x
    new_fields = Tfields(ntuple(n -> n == i ? new_val : fields[n], fieldcount(Tfields)))
    t.fields = new_fields
    return x
end

@inline function set_tangent_field!(t::MutableTangent{Tfields}, s::Symbol, x) where {Tfields}
    return set_tangent_field!(t, _sym_to_int(Tfields, Val(s)), x)
end

@generated function _sym_to_int(::Type{Tfields}, ::Val{s}) where {Tfields, s}
    return findfirst(==(s), fieldnames(Tfields))
end

@generated function build_tangent(::Type{P}, fields::Vararg{Any, N}) where {P, N}
    tangent_values_exprs = map(enumerate(fieldtypes(P))) do (n, field_type)
        if tangent_field_type(P, n) <: PossiblyUninitTangent
            tt = PossiblyUninitTangent{tangent_type(field_type)}
            if n <= N
                return Expr(:call, tt, :(fields[$n]))
            else
                return Expr(:call, tt)
            end
        else
            return :(fields[$n])
        end
    end
    return Expr(
        :call,
        tangent_type(P),
        Expr(:call, NamedTuple{fieldnames(P)}, Expr(:tuple, tangent_values_exprs...)),
    )
end

function build_tangent(::Type{P}, fields::Vararg{Any, N}) where {P<:Union{Tuple, NamedTuple}, N}
    T = tangent_type(P)
    if T == NoTangent
        return NoTangent()
    elseif isconcretetype(P)
        return T(fields)
    else
        return __tangent_from_non_concrete(P, fields)
    end
end

__tangent_from_non_concrete(::Type{P}, fields) where {P<:Tuple} = Tuple(fields)
function __tangent_from_non_concrete(::Type{P}, fields) where {names, P<:NamedTuple{names}}
    return NamedTuple{names}(fields)
end

"""
    tangent_type(P)

There must be a single type used to represents tangents of primals of type `P`, and it must
be given by `tangent_type(P)`.

# Extended help

The tangent types which Tapir.jl uses are quite similar in spirit to ChainRules.jl.
For example, tangent "vectors" for
1. `Float64`s are `Float64`s,
1. `Vector{Float64}`s are `Vector{Float64}`s, and
1. `struct`s are other another (special) `struct` with field types specified recursively.

There are, however, some major differences.
Firstly, while it is certainly true that the above tangent types are permissible in
ChainRules.jl, they are not the uniquely permissible types. For example, `ZeroTangent` is
also a permissible type of tangent for any of them, and `Float32` is permissible for
`Float64`. This is a general theme in ChainRules.jl -- it intentionally declines to place
restrictions on what type can be used to represent the tangent of a given type.

Tapir.jl differs from this.
**It insists that each primal type is associated to a _single_ tangent type.**
Furthermore, this type is _always_ given by the function `Tapir.tangent_type(primal_type)`.

Consider some more worked examples.

#### Int

`Int` is not a differentiable type, so its tangent type is `NoTangent`:
```jldoctest
julia> tangent_type(Int)
NoTangent
```

#### Tuples

The tangent type of a `Tuple` is defined recursively based on its field types. For example
```jldoctest
julia> tangent_type(Tuple{Float64, Vector{Float64}, Int})
Tuple{Float64, Vector{Float64}, NoTangent}
```

There is one edge case to be aware of: if all of the field of a `Tuple` are
non-differentiable, then the tangent type is `NoTangent`. For example,
```jldoctest
julia> tangent_type(Tuple{Int, Int})
NoTangent
```

#### Structs

As with `Tuple`s, the tangent type of a struct is, by default, given recursively.
In particular, the tangent type of a `struct` type is `Tangent`.
This type contains a `NamedTuple` containing the tangent to each field in the primal `struct`.

As with `Tuple`s, if all field types are non-differentiable, the tangent type of the entire
struct is `NoTangent`.

There are a couple of additional subtleties to consider over `Tuple`s though. Firstly, not
all fields of a `struct` have to be defined. Fortunately, Julia makes it easy to determine
how many of the fields might possibly not be defined. The tangent associated to any field
which might possibly not be defined is wrapped in a `PossiblyUninitTangent`.

Furthermore, `struct`s can have fields whose static type is abstract. For example
```jldoctest foo
julia> struct Foo
           x
       end
```
If you ask for the tangent type of `Foo`, you will see that it is
```jldoctest foo
julia> tangent_type(Foo)
Tangent{@NamedTuple{x}}
```
Observe that the field type associated to `x` is `Any`. The way to understand this result is
to observe that
1. `x` could have literally any type at runtime, so we know nothing about what its tangent
    type must be until runtime, and
1. we require that the tangent type of `Foo` be unique.
The consequence of these two considerations is that the tangent type of `Foo` must be able
to contain any type of tangent in its `x` field. It follows that the fieldtype of the `x`
field of `Foo`s tangent must be `Any`.



#### Mutable Structs

The tangent type for `mutable struct`s have the same set of considerations as `struct`s.
The only difference is that they must themselves be mutable.
Consequently, we use a type called `MutableTangent` to represent their tangents.
It is a `mutable struct` with the same structure as `Tangent`.

For example, if you ask for the `tangent_type` of
```jldoctest bar
julia> mutable struct Bar
           x::Float64
       end
```
you will find that it is
```jldoctest bar
julia> tangent_type(Bar)
MutableTangent{@NamedTuple{x::Float64}}
```


#### Primitive Types

We've already seen a couple of primitive types (`Float64` and `Int`).
The basic story here is that all primitive types require an explicit specification of what their tangent type must be.

One interesting case are `Ptr` types.
The tangent type of a `Ptr{P}` is `Ptr{T}`, where `T = tangent_type(P)`.
For example
```julia
julia> tangent_type(Ptr{Float64})
Ptr{Float64}
```

"""
tangent_type(T)

tangent_type(x) = throw(error("$x is not a type. Perhaps you meant typeof(x)?"))

# This is essential for DataType, as the recursive definition always recurses infinitely,
# because one of the fieldtypes is itself always a DataType. In particular, we'll always
# eventually hit `Any`, whose `super` field is `Any`.
# This makes it clear that we can't recursively construct tangents for data structures which
# refer to themselves...
tangent_type(::Type{<:Type}) = NoTangent

tangent_type(::Type{<:TypeVar}) = NoTangent

tangent_type(::Type{Ptr{P}}) where {P} = Ptr{tangent_type(P)}

tangent_type(::Type{<:Ptr}) = NoTangent

tangent_type(::Type{Bool}) = NoTangent

tangent_type(::Type{Char}) = NoTangent

tangent_type(::Type{Union{}}) = NoTangent

tangent_type(::Type{Symbol}) = NoTangent

tangent_type(::Type{Module}) = NoTangent

tangent_type(::Type{Nothing}) = NoTangent

tangent_type(::Type{SimpleVector}) = Vector{Any}

tangent_type(::Type{P}) where {P<:Union{UInt8, UInt16, UInt32, UInt64, UInt128}} = NoTangent

tangent_type(::Type{P}) where {P<:Union{Int8, Int16, Int32, Int64, Int128}} = NoTangent

tangent_type(::Type{<:Core.Builtin}) = NoTangent

tangent_type(::Type{P}) where {P<:IEEEFloat} = P

tangent_type(::Type{<:Core.LLVMPtr}) = NoTangent

tangent_type(::Type{String}) = NoTangent

tangent_type(::Type{<:Array{P, N}}) where {P, N} = Array{tangent_type(P), N}

tangent_type(::Type{<:Array{P, N} where {P}}) where {N} = Array

tangent_type(::Type{<:MersenneTwister}) = NoTangent

tangent_type(::Type{Core.TypeName}) = NoTangent

tangent_type(::Type{Core.MethodTable}) = NoTangent

tangent_type(::Type{DimensionMismatch}) = NoTangent

tangent_type(::Type{Method}) = NoTangent

function is_concrete_or_typelike(P::DataType)
    if P <: Tuple
        P == Tuple && return false
        return all(is_concrete_or_typelike, P.parameters)
    elseif P <: DataType
        return true
    else
        return isconcretetype(P)
    end
end

is_concrete_or_typelike(::Union) = true
is_concrete_or_typelike(::UnionAll) = false
is_concrete_or_typelike(::Core.TypeofVararg) = true

@generated function tangent_type(::Type{P}) where {P<:Tuple}
    isa(P, Union) && return Union{tangent_type(P.a), tangent_type(P.b)}
    isempty(P.parameters) && return NoTangent
    isa(last(P.parameters), Core.TypeofVararg) && return Any
    all(p -> tangent_type(p) == NoTangent, P.parameters) && return NoTangent
    all(is_concrete_or_typelike, P.parameters) || return Any
    return Tuple{map(tangent_type, fieldtypes(P))...}
end

@generated function tangent_type(::Type{NamedTuple{N, T}}) where {N, T<:Tuple}
    if tangent_type(T) == NoTangent
        return NoTangent
    elseif isconcretetype(tangent_type(T))
        return NamedTuple{N, tangent_type(T)}
    else
        return Any
    end
end

function backing_type(::Type{P}) where {P}
    tangent_field_types = map(n -> tangent_field_type(P, n), 1:fieldcount(P))
    all(==(NoTangent), tangent_field_types) && return NoTangent
    return NamedTuple{fieldnames(P), Tuple{tangent_field_types...}}
end

@generated function tangent_type(::Type{P}) where {P}

    # This method can only handle struct types. Tell user to implement tangent type
    # directly for primitive types.
    isprimitivetype(P) && throw(error(
        "$P is a primitive type. Implement a method of `tangent_type` for it."
    ))

    # If the type is a Union, then take the union type of its arguments.
    P isa Union && return Union{tangent_type(P.a), tangent_type(P.b)}

    # If the type is itself abstract, it's tangent could be anything.
    # The same goes for if the type has any undetermined type parameters.
    (isabstracttype(P) || !isconcretetype(P)) && return Any

    # If the type has no fields, then it's a `NoTangent`.
    Base.issingletontype(P) && return NoTangent

    # Derive tangent type.
    bt = backing_type(P)
    return bt == NoTangent ? bt : (ismutabletype(P) ? MutableTangent : Tangent){bt}
end

"""
    tangent_field_type(::Type{P}, n::Int) where {P}

Returns the type that lives in the nth elements of `fields` in a `Tangent` /
`MutableTangent`. Will either be the `tangent_type` of the nth fieldtype of `P`, or the
`tangent_type` wrapped in a `PossiblyUninitTangent`. The latter case only occurs if it is
possible for the field to be undefined.
"""
function tangent_field_type(::Type{P}, n::Int) where {P}
    t = tangent_type(fieldtype(P, n))
    return is_always_initialised(P, n) ? t : _wrap_type(t)
end

"""
    zero_tangent(x)

Returns the unique zero element of the tangent space of `x`.
It is an error for the zero element of the tangent space of `x` to be represented by
anything other than that which this function returns.
"""
zero_tangent(x)
@inline zero_tangent(::Union{Int8, Int16, Int32, Int64, Int128}) = NoTangent()
@inline zero_tangent(x::IEEEFloat) = zero(x)
@inline function zero_tangent(x::SimpleVector)
    return map!(n -> zero_tangent(x[n]), Vector{Any}(undef, length(x)), eachindex(x))
end
@inline function zero_tangent(x::Array{P, N}) where {P, N}
    return _map_if_assigned!(zero_tangent, Array{tangent_type(P), N}(undef, size(x)...), x)
end
@inline function zero_tangent(x::P) where {P<:Union{Tuple, NamedTuple}}
    return tangent_type(P) == NoTangent ? NoTangent() : tuple_map(zero_tangent, x)
end
@generated function zero_tangent(x::P) where {P}

    tangent_type(P) == NoTangent && return NoTangent()

    # This method can only handle struct types. Tell user to implement tangent type
    # directly for primitive types.
    isprimitivetype(P) && throw(error(
        "$P is a primitive type. Implement a method of `zero_tangent` for it."
    ))

    # Derive zero tangent. Tangent types of fields, and types of zeros need only agree
    # if field types are concrete.
    tangent_field_zeros_exprs = ntuple(fieldcount(P)) do n
        if tangent_field_type(P, n) <: PossiblyUninitTangent
            V = PossiblyUninitTangent{tangent_type(fieldtype(P, n))}
            return :(isdefined(x, $n) ? $V(zero_tangent(getfield(x, $n))) : $V())
        else
            return :(zero_tangent(getfield(x, $n)))
        end
    end
    backing_data_expr = Expr(:call, :tuple, tangent_field_zeros_exprs...)
    backing_expr = :($(backing_type(P))($backing_data_expr))
    return :($(tangent_type(P))($backing_expr))
end

"""
    uninit_tangent(x)

Related to `zero_tangent`, but a bit different. Check current implementation for
details -- this docstring is intentionally non-specific in order to avoid becoming outdated.
"""
@inline uninit_tangent(x) = zero_tangent(x)
@inline uninit_tangent(x::Ptr{P}) where {P} = bitcast(Ptr{tangent_type(P)}, x)

"""
    randn_tangent(rng::AbstractRNG, x::T) where {T}

Required for testing.
Generate a randomly-chosen tangent to `x`.
"""
randn_tangent(::AbstractRNG, ::NoTangent) = NoTangent()
randn_tangent(rng::AbstractRNG, ::T) where {T<:IEEEFloat} = randn(rng, T)
function randn_tangent(rng::AbstractRNG, x::Array{T, N}) where {T, N}
    dx = Array{tangent_type(T), N}(undef, size(x)...)
    return _map_if_assigned!(Base.Fix1(randn_tangent, rng), dx, x)
end
function randn_tangent(rng::AbstractRNG, x::SimpleVector)
    return map!(Vector{Any}(undef, length(x)), eachindex(x)) do n
        return randn_tangent(rng, x[n])
    end
end
function randn_tangent(rng::AbstractRNG, x::P) where {P <: Union{Tuple, NamedTuple}}
    tangent_type(P) == NoTangent && return NoTangent()
    return tuple_map(x -> randn_tangent(rng, x), x)
end
function randn_tangent(rng::AbstractRNG, x::T) where {T<:Union{Tangent, MutableTangent}}
    return T(randn_tangent(rng, x.fields))
end
@generated function randn_tangent(rng::AbstractRNG, x::P) where {P}

    # If `P` doesn't have a tangent space, always return `NoTangent()`.
    tangent_type(P) === NoTangent && return NoTangent()

    # This method can only handle struct types. Tell user to implement tangent type
    # directly for primitive types.
    isprimitivetype(P) && throw(error(
        "$P is a primitive type. Implement a method of `randn_tangent` for it."
    ))

    # Assume `P` is a generic struct type, and derive the tangent recursively.
    tangent_field_exprs = map(1:fieldcount(P)) do n
        if tangent_field_type(P, n) <: PossiblyUninitTangent
            V = PossiblyUninitTangent{tangent_type(fieldtype(P, n))}
            return :(isdefined(x, $n) ? $V(randn_tangent(rng, getfield(x, $n))) : $V())
        else
            return :(randn_tangent(rng, getfield(x, $n)))
        end
    end
    tangent_fields_expr = Expr(:call, :tuple, tangent_field_exprs...)
    return :($(tangent_type(P))($(backing_type(P))($tangent_fields_expr)))
end

"""
    increment!!(x::T, y::T) where {T}

Add `x` to `y`. If `ismutabletype(T)`, then `increment!!(x, y) === x` must hold.
That is, `increment!!` will mutate `x`.
This must apply recursively if `T` is a composite type whose fields are mutable.
"""
increment!!(::NoTangent, ::NoTangent) = NoTangent()
increment!!(x::T, y::T) where {T<:IEEEFloat} = x + y
increment!!(x::Ptr{T}, y::Ptr{T}) where {T} = x === y ? x : throw(error("eurgh"))
function increment!!(x::T, y::T) where {P, N, T<:Array{P, N}}
    return x === y ? x : _map_if_assigned!(increment!!, x, x, y)
end
increment!!(x::T, y::T) where {T<:Tuple} = tuple_map(increment!!, x, y)::T
increment!!(x::T, y::T) where {T<:NamedTuple} = T(increment!!(Tuple(x), Tuple(y)))
function increment!!(x::T, y::T) where {T<:PossiblyUninitTangent}
    is_init(x) && is_init(y) && return T(increment!!(val(x), val(y)))
    is_init(x) && !is_init(y) && error("x is initialised, but y is not")
    !is_init(x) && is_init(y) && error("x is not initialised, but y is")
    return x
end
increment!!(x::T, y::T) where {T<:Tangent} = T(increment!!(x.fields, y.fields))
function increment!!(x::T, y::T) where {T<:MutableTangent}
    x === y && return x
    x.fields = increment!!(x.fields, y.fields)
    return x
end

"""
    set_to_zero!!(x)

Set `x` to its zero element (`x` should be a tangent, so the zero must exist).
"""
set_to_zero!!(::NoTangent) = NoTangent()
set_to_zero!!(x::Base.IEEEFloat) = zero(x)
set_to_zero!!(x::Union{Tuple, NamedTuple}) = map(set_to_zero!!, x)
set_to_zero!!(x::Array) = _map_if_assigned!(set_to_zero!!, x, x)
function set_to_zero!!(x::T) where {T<:PossiblyUninitTangent}
    return is_init(x) ? T(set_to_zero!!(val(x))) : x
end
set_to_zero!!(x::T) where {T<:Tangent} = T(set_to_zero!!(x.fields))
function set_to_zero!!(x::MutableTangent)
    x.fields = set_to_zero!!(x.fields)
    return x
end

"""
    _scale(a::Float64, t::T) where {T}

Required for testing.
Should be defined for all standard tangent types.

Multiply tangent `t` by scalar `a`. Always possible because any given tangent type must
correspond to a vector field. Not using `*` in order to avoid piracy.
"""
_scale(::Float64, ::NoTangent) = NoTangent()
_scale(a::Float64, t::T) where {T<:IEEEFloat} = T(a * t)
function _scale(a::Float64, t::Array{T, N}) where {T, N}
    t′ = Array{T, N}(undef, size(t)...)
    return _map_if_assigned!(Base.Fix1(_scale, a), t′, t)
end
_scale(a::Float64, t::Union{Tuple, NamedTuple}) = map(Base.Fix1(_scale, a), t)
function _scale(a::Float64, t::T) where {T<:PossiblyUninitTangent}
    return is_init(t) ? T(_scale(a, val(t))) : T()
end
_scale(a::Float64, t::T) where {T<:Union{Tangent, MutableTangent}} = T(_scale(a, t.fields))

struct FieldUndefined end

"""
    _dot(t::T, s::T)::Float64 where {T}

Required for testing.
Should be defined for all standard tangent types.

Inner product between tangents `t` and `s`. Must return a `Float64`.
Always available because all tangent types correspond to finite-dimensional vector spaces.
"""
_dot(::NoTangent, ::NoTangent) = 0.0
_dot(t::T, s::T) where {T<:IEEEFloat} = Float64(t * s)
function _dot(t::T, s::T) where {T<:Array}
    isbitstype(T) && return sum(_map(_dot, t, s))
    return sum(
        _map(eachindex(t)) do n
            (isassigned(t, n) && isassigned(s, n)) ? _dot(t[n], s[n]) : 0.0
        end
    )
end
_dot(t::T, s::T) where {T<:Union{Tuple, NamedTuple}} = sum(map(_dot, t, s); init=0.0)
function _dot(t::T, s::T) where {T<:PossiblyUninitTangent}
    is_init(t) && is_init(s) && return _dot(val(t), val(s))
    return 0.0
end
function _dot(t::T, s::T) where {T<:Union{Tangent, MutableTangent}}
    return sum(_map(_dot, t.fields, s.fields); init=0.0)
end

"""
    _add_to_primal(p::P, t::T) where {P, T}

Required for testing.
_Not_ currently defined by default.
`_containerlike_add_to_primal` is potentially what you want to target when implementing for
a particular primal-tangent pair.

Adds `t` to `p`, returning a `P`. It must be the case that `tangent_type(P) == T`.
"""
_add_to_primal(x, ::NoTangent) = x
_add_to_primal(x::T, t::T) where {T<:IEEEFloat} = x + t
function _add_to_primal(x::Array{P, N}, t::Array{<:Any, N}) where {P, N}
    x′ = Array{P, N}(undef, size(x)...)
    return _map_if_assigned!(_add_to_primal, x′, x, t)
end
function _add_to_primal(x::SimpleVector, t::Vector{Any})
    return svec(map(n -> _add_to_primal(x[n], t[n]), eachindex(x))...)
end
_add_to_primal(x::Tuple, t::Tuple) = _map(_add_to_primal, x, t)
_add_to_primal(x::NamedTuple, t::NamedTuple) = _map(_add_to_primal, x, t)
_add_to_primal(x, ::Tangent{NamedTuple{(), Tuple{}}}) = x

function _add_to_primal(p::P, t::T) where {P, T<:Union{Tangent, MutableTangent}}
    Tt = tangent_type(P)
    if Tt != typeof(t)
        throw(ArgumentError("p of type $P has tangent_type $Tt, but t is of type $T"))
    end
    tmp = map(fieldnames(P)) do f
        tf = getfield(t.fields, f)
        isdefined(p, f) && is_init(tf) && return _add_to_primal(getfield(p, f), val(tf)) 
        !isdefined(p, f) && !is_init(tf) && return FieldUndefined()
        throw(error("unable to handle undefined-ness"))
    end
    i = findfirst(==(FieldUndefined()), tmp)
    return i === nothing ? P(tmp...) : P(tmp[1:i-1]...)
end

"""
    _diff(p::P, q::P) where {P}

Required for testing.

Computes the difference between `p` and `q`, which _must_ be of the same type, `P`.
Returns a tangent of type `tangent_type(P)`.
"""
function _diff(p::P, q::P) where {P}
    tangent_type(P) === NoTangent && return NoTangent()
    T = Tangent{NamedTuple{(), Tuple{}}}
    tangent_type(P) === T && return T((;))
    return _containerlike_diff(p, q)
end
_diff(p::P, q::P) where {P<:IEEEFloat} = p - q
function _diff(p::P, q::P) where {V, N, P<:Array{V, N}}
    t = Array{tangent_type(V), N}(undef, size(p))
    return _map_if_assigned!(_diff, t, p, q)
end
function _diff(p::P, q::P) where {P<:SimpleVector}
    return Any[_diff(a, b) for (a, b) in zip(p, q)]
end
function _diff(p::P, q::P) where {P<:Union{Tuple, NamedTuple}}
    return tangent_type(P) == NoTangent ? NoTangent() : _map(_diff, p, q)
end

function _containerlike_diff(p::P, q::P) where {P}
    diffed_fields = map(fieldnames(P)) do f
        isdefined(p, f) && isdefined(q, f) && return _diff(getfield(p, f), getfield(q, f))
        !isdefined(p, f) && !isdefined(q, f) && return FieldUndefined()
        throw(error("Unhandleable undefinedness"))
    end
    i = findfirst(==(FieldUndefined()), diffed_fields)
    diffed_fields = i === nothing ? diffed_fields : diffed_fields[1:i-1]
    return build_tangent(P, diffed_fields...)
end

"""
    increment_field!!(x::T, y::V, f) where {T, V}

`increment!!` the field `f` of `x` by `y`, and return the updated `x`.
"""
@inline @generated function increment_field!!(x::Tuple, y, ::Val{i}) where {i}
    exprs = map(n -> n == i ? :(increment!!(x[$n], y)) : :(x[$n]), fieldnames(x))
    return Expr(:tuple, exprs...)
end

# Optimal for homogeneously-typed Tuples with dynamic field choice.
function increment_field!!(x::Tuple, y, i::Int)
    return ntuple(n -> n == i ? increment!!(x[n], y) : x[n], length(x))
end

@inline @generated function increment_field!!(x::T, y, ::Val{f}) where {T<:NamedTuple, f}
    i = f isa Symbol ? findfirst(==(f), fieldnames(T)) : f
    new_fields = Expr(:call, increment_field!!, :(Tuple(x)), :y, :(Val($i)))
    return Expr(:call, T, new_fields)
end

# Optimal for homogeneously-typed NamedTuples with dynamic field choice.
function increment_field!!(x::T, y, i::Int) where {T<:NamedTuple}
    return T(increment_field!!(Tuple(x), y, i))
end
function increment_field!!(x::T, y, s::Symbol) where {T<:NamedTuple}
    return T(tuple_map(n -> n == s ? increment!!(x[n], y) : x[n], fieldnames(T)))
end

function increment_field!!(x::Tangent{T}, y, f::Val{F}) where {T, F}
    y isa NoTangent && return x
    new_val = fieldtype(T, F) <: PossiblyUninitTangent ? fieldtype(T, F)(y) : y
    return Tangent(increment_field!!(x.fields, new_val, f))
end
function increment_field!!(x::MutableTangent{T}, y, f::V) where {T, F, V<:Val{F}}
    y isa NoTangent && return x
    new_val = fieldtype(T, F) <: PossiblyUninitTangent ? fieldtype(T, F)(y) : y
    setfield!(x, :fields, increment_field!!(x.fields, new_val, f))
    return x
end

increment_field!!(x, y, f::Symbol) = increment_field!!(x, y, Val(f))
increment_field!!(x, y, n::Int) = increment_field!!(x, y, Val(n))

# Fallback method for when a tangent type for a struct is declared to be `NoTangent`.
for T in [Symbol, Int, Val]
    @eval increment_field!!(::NoTangent, ::NoTangent, f::Union{$T}) = NoTangent()
end

#=
    tangent_test_cases()

Constructs a `Vector` of `Tuple`s containing test cases for the tangent infrastructure.

If the returned tuple has 2 elements, the elements should be interpreted as follows:
1 - interface_only
2 - primal value

interface_only is a Bool which will be used to determine which subset of tests to run.

If the returned tuple has 5 elements, then the elements are interpreted as follows:
1 - interface_only
2 - primal value
3, 4, 5 - tangents, where <5> == increment!!(<3>, <4>).

Generally speaking, it's very straightforward to produce test cases in the first format,
while the second requires more work. Consequently, at the time of writing there are many
more instances of the first format than the second.

Test cases in the first format make use of `zero_tangent` / `randn_tangent` etc to generate
tangents, but they're unable to check that `increment!!` is correct in an absolute sense.
=#
function tangent_test_cases()

    N_large = 33
    _names = Tuple(map(n -> Symbol("x$n"), 1:N_large))

    abs_test_cases = vcat(
        [
            (sin, NoTangent(), NoTangent(), NoTangent()),
            (map(Float16, (5.0, 4.0, 3.1, 7.1))...),
            (5f0, 4f0, 3f0, 7f0),
            (5.1, 4.0, 3.0, 7.0),
            (svec(5.0), Any[4.0], Any[3.0], Any[7.0]),
            ([3.0, 2.0], [1.0, 2.0], [2.0, 3.0], [3.0, 5.0]),
            (
                [1, 2],
                [NoTangent(), NoTangent()],
                [NoTangent(), NoTangent()],
                [NoTangent(), NoTangent()],
            ),
            (
                [[1.0], [1.0, 2.0]],
                [[2.0], [2.0, 3.0]],
                [[3.0], [4.0, 5.0]],
                [[5.0], [6.0, 8.0]],
            ),
            (
                setindex!(Vector{Vector{Float64}}(undef, 2), [1.0], 1),
                setindex!(Vector{Vector{Float64}}(undef, 2), [2.0], 1),
                setindex!(Vector{Vector{Float64}}(undef, 2), [3.0], 1),
                setindex!(Vector{Vector{Float64}}(undef, 2), [5.0], 1),
            ),
            (
                setindex!(Vector{Vector{Float64}}(undef, 2), [1.0], 2),
                setindex!(Vector{Vector{Float64}}(undef, 2), [2.0], 2),
                setindex!(Vector{Vector{Float64}}(undef, 2), [3.0], 2),
                setindex!(Vector{Vector{Float64}}(undef, 2), [5.0], 2),
            ),
            (
                (6.0, [1.0, 2.0]),
                (5.0, [3.0, 4.0]),
                (4.0, [4.0, 3.0]),
                (9.0, [7.0, 7.0]),
            ),
            ((), NoTangent(), NoTangent(), NoTangent()),
            ((1,), NoTangent(), NoTangent(), NoTangent()),
            ((2, 3), NoTangent(), NoTangent(), NoTangent()),
            (
                Tapir.tuple_fill(5.0, Val(N_large)),
                Tapir.tuple_fill(6.0, Val(N_large)),
                Tapir.tuple_fill(7.0, Val(N_large)),
                Tapir.tuple_fill(13.0, Val(N_large)),
            ),
            (
                (a=6.0, b=[1.0, 2.0]),
                (a=5.0, b=[3.0, 4.0]),
                (a=4.0, b=[4.0, 3.0]),
                (a=9.0, b=[7.0, 7.0]),
            ),
            ((;), NoTangent(), NoTangent(), NoTangent()),
            (
                NamedTuple{_names}(Tapir.tuple_fill(5.0, Val(N_large))),
                NamedTuple{_names}(Tapir.tuple_fill(6.0, Val(N_large))),
                NamedTuple{_names}(Tapir.tuple_fill(7.0, Val(N_large))),
                NamedTuple{_names}(Tapir.tuple_fill(13.0, Val(N_large))),
            ),
            (
                TestResources.TypeStableMutableStruct{Float64}(5.0, 3.0),
                build_tangent(TestResources.TypeStableMutableStruct{Float64}, 5.0, 4.0),
                build_tangent(TestResources.TypeStableMutableStruct{Float64}, 3.0, 3.0),
                build_tangent(TestResources.TypeStableMutableStruct{Float64}, 8.0, 7.0),
            ),
            ( # complete init
                TestResources.StructFoo(6.0, [1.0, 2.0]),
                build_tangent(TestResources.StructFoo, 5.0, [3.0, 4.0]),
                build_tangent(TestResources.StructFoo, 3.0, [2.0, 1.0]),
                build_tangent(TestResources.StructFoo, 8.0, [5.0, 5.0]),
            ),
            ( # partial init
                TestResources.StructFoo(6.0),
                build_tangent(TestResources.StructFoo, 5.0),
                build_tangent(TestResources.StructFoo, 4.0),
                build_tangent(TestResources.StructFoo, 9.0),
            ),
            ( # complete init
                TestResources.MutableFoo(6.0, [1.0, 2.0]),
                build_tangent(TestResources.MutableFoo, 5.0, [3.0, 4.0]),
                build_tangent(TestResources.MutableFoo, 3.0, [2.0, 1.0]),
                build_tangent(TestResources.MutableFoo, 8.0, [5.0, 5.0]),
            ),
            ( # partial init
                TestResources.MutableFoo(6.0),
                build_tangent(TestResources.MutableFoo, 5.0),
                build_tangent(TestResources.MutableFoo, 4.0),
                build_tangent(TestResources.MutableFoo, 9.0),
            ),
            (
                TestResources.StructNoFwds(5.0),
                build_tangent(TestResources.StructNoFwds, 5.0),
                build_tangent(TestResources.StructNoFwds, 4.0),
                build_tangent(TestResources.StructNoFwds, 9.0),
            ),
            (
                TestResources.StructNoRvs([5.0]),
                build_tangent(TestResources.StructNoRvs, [5.0]),
                build_tangent(TestResources.StructNoRvs, [4.0]),
                build_tangent(TestResources.StructNoRvs, [9.0]),
            ),
            (UnitRange{Int}(5, 7), NoTangent(), NoTangent(), NoTangent()),
        ],
        map([
            LowerTriangular{Float64, Matrix{Float64}},
            UpperTriangular{Float64, Matrix{Float64}},
            UnitLowerTriangular{Float64, Matrix{Float64}},
            UnitUpperTriangular{Float64, Matrix{Float64}},
        ]) do T
            return (
                T(randn(2, 2)),
                build_tangent(T, [1.0 2.0; 3.0 4.0]),
                build_tangent(T, [2.0 1.0; 5.0 4.0]),
                build_tangent(T, [3.0 3.0; 8.0 8.0]),
            )
        end,
        [
            (p, NoTangent(), NoTangent(), NoTangent()) for p in
                [Array, Float64, Union{Float64, Float32}, Union, UnionAll,
                typeof(<:)]
        ],
    )
    rel_test_cases = Any[
        (2.0, 3),
        (3, 2.0),
        (2.0, 1.0),
        (randn(10), 3),
        (3, randn(10)),
        (randn(10), randn(10)),
        (a=2.0, b=3),
        (a=3, b=2.0),
        (a=randn(10), b=3),
        (a=3, b=randn(10)),
        (a=randn(10), b=randn(10)),
    ]
    return vcat(
        map(x -> (false, x...), abs_test_cases),
        map(x -> (false, x), rel_test_cases),
        map(Tapir.TestTypes.instantiate, Tapir.TestTypes.PRIMALS),
    )
end
