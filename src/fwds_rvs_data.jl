"""
    NoFData

Singleton type which indicates that there is nothing to be propagated on the forwards-pass
in addition to the primal data.
"""
struct NoFData end

increment!!(::NoFData, ::NoFData) = NoFData()

"""
    FData(data::NamedTuple)

The component of a `struct` which is propagated alongside the primal on the forwards-pass of
AD. For example, the tangents for `Float64`s do not need to be propagated on the forwards-
pass of reverse-mode AD, so any `Float64` fields of `Tangent` do not need to appear in the
associated `FData`.
"""
struct FData{T<:NamedTuple}
    data::T
end

fields_type(::Type{FData{T}}) where {T<:NamedTuple} = T

increment!!(x::F, y::F) where {F<:FData} = F(tuple_map(increment!!, x.data, y.data))

"""
    fdata_type(T)

Returns the type of the forwards data associated to a tangent of type `T`.

# Extended help

Rules in Tapir.jl do not operate on tangents directly.
Rather, functionality is defined to split each tangent into two components, that we call _fdata_ (forwards-pass data) and _rdata_ (reverse-pass data).
In short, any component of a tangent which is identified by its address (e.g. a `mutable struct`s or an `Array`) gets passed around on the forwards-pass of AD and is incremented in-place on the reverse-pass, while components of tangents identified by their value get propagated and accumulated only on the reverse-pass.

Given a tangent type `T`, you can find out what type its fdata and rdata must be with `fdata_type(T)` and `rdata_type(T)` respectively.
A consequence of this is that there is exactly one valid fdata type and rdata type for each primal type.

Given a tangent `t`, you can get its fdata and rdata using `f = fdata(t)` and `r = rdata(t)` respectively.
`f` and `r` can be re-combined to recover the original tangent using the binary version of `tangent`: `tangent(f, r)`.
It must always hold that
```julia
tangent(fdata(t), rdata(t)) === t
```

The need for all of this is explained in the docs, but for now it suffices to consider our running examples again, and to see what their fdata and rdata look like.

#### Int

`Int`s are non-differentiable types, so there is nothing to pass around on the forwards- or reverse-pass.
Therefore
```jldoctest
julia> fdata_type(tangent_type(Int)), rdata_type(tangent_type(Int))
(NoFData, NoRData)
```

#### Float64

The tangent type of `Float64` is `Float64`.
`Float64`s are identified by their value / have no fixed address, so
```jldoctest
julia> (fdata_type(Float64), rdata_type(Float64))
(NoFData, Float64)
```

#### Vector{Float64}

The tangent type of `Vector{Float64}` is `Vector{Float64}`.
A `Vector{Float64}` is identified by its address, so
```jldoctest
julia> (fdata_type(Vector{Float64}), rdata_type(Vector{Float64}))
(Vector{Float64}, NoRData)
```

#### Tuple{Float64, Vector{Float64}, Int}

This is an example of a type which has both fdata and rdata.
The tangent type for `Tuple{Float64, Vector{Float64}, Int}` is
`Tuple{Float64, Vector{Float64}, NoTangent}`.
`Tuple`s have no fixed memory address, so we interogate each field on its own.
We have already established the fdata and rdata types for each element, so we recurse to obtain:
```jldoctest
julia> T = tangent_type(Tuple{Float64, Vector{Float64}, Int})
Tuple{Float64, Vector{Float64}, NoTangent}

julia> (fdata_type(T), rdata_type(T))
(Tuple{NoFData, Vector{Float64}, NoFData}, Tuple{Float64, NoRData, NoRData})
```

The zero tangent for `(5.0, [5.0])` is `t = (0.0, [0.0])`.
`fdata(t)` returns `(NoFData(), [0.0])`, where the second element is `===` to the second element of `t`.
`rdata(t)` returns `(0.0, NoRData())`.
In this example, `t` contains a mixture of data, some of which is identified by its value, and some of which is identified by its address, so there is some fdata and some rdata.

#### Structs

Structs are handled in more-or-less the same way as `Tuple`s, albeit with the possibility of undefined fields needing to be explicitly handled.
For example, a struct such as
```jldoctest foo_fdata
julia> struct Foo
           x::Float64
           y
           z::Int
       end
```
has tangent type
```jldoctest foo_fdata
julia> tangent_type(Foo)
Tangent{@NamedTuple{x::Float64, y, z::NoTangent}}
```
Its fdata and rdata are given by special `FData` and `RData` types:
```jldoctest foo_fdata
julia> (fdata_type(tangent_type(Foo)), rdata_type(tangent_type(Foo)))
(Tapir.FData{@NamedTuple{x::NoFData, y, z::NoFData}}, Tapir.RData{@NamedTuple{x::Float64, y, z::NoRData}})
```
Practically speaking, `FData` and `RData` both have the same structure as `Tangent`s and are just used in different contexts.

#### Mutable Structs

The fdata for a `mutable struct`s is its tangent, and it has no rdata.
This is because `mutable struct`s have fixed memory addresses, and can therefore be incremented in-place.
For example,
```jldoctest bar_fdata
julia> mutable struct Bar
           x::Float64
           y
           z::Int
       end
```
has tangent type
```jldoctest bar_fdata
julia> tangent_type(Bar)
MutableTangent{@NamedTuple{x::Float64, y, z::NoTangent}}
```
and fdata / rdata types
```jldoctest bar_fdata
julia> (fdata_type(tangent_type(Bar)), rdata_type(tangent_type(Bar)))
(MutableTangent{@NamedTuple{x::Float64, y, z::NoTangent}}, NoRData)
```

#### Primitive Types

As with tangents, each primitive type must specify what its fdata and rdata is.
See specific examples for details.
"""
fdata_type(T)

fdata_type(x) = throw(error("$x is not a type. Perhaps you meant typeof(x)?"))

fdata_type(::Type{T}) where {T<:IEEEFloat} = NoFData

function fdata_type(::Type{PossiblyUninitTangent{T}}) where {T}
    Tfields = fdata_type(T)
    return PossiblyUninitTangent{Tfields}
end

@generated function fdata_type(::Type{T}) where {T}

    # If the tangent type is NoTangent, then the forwards-component must be `NoFData`.
    T == NoTangent && return NoFData

    # This method can only handle struct types. Tell user to implement their own method.
    isprimitivetype(T) && throw(error(
        "$T is a primitive type. Implement a method of `fdata_type` for it."
    ))

    # If the type is a Union, then take the union type of its arguments.
    T isa Union && return Union{fdata_type(T.a), fdata_type(T.b)}

    # If `P` is a mutable type, then its forwards data is its tangent.
    ismutabletype(T) && return T

    # If the type is itself abstract, it's forward data could be anything.
    # The same goes for if the type has any undetermined type parameters.
    (isabstracttype(T) || !isconcretetype(T)) && return Any

    # If `P` is an immutable type, then some of its fields may not need to be propagated
    # on the forwards-pass.
    if T <: Tangent
        Tfields = fields_type(T)
        fwds_data_field_types = map(1:fieldcount(Tfields)) do n
            return fdata_type(fieldtype(Tfields, n))
        end
        all(==(NoFData), fwds_data_field_types) && return NoFData
        return FData{NamedTuple{fieldnames(Tfields), Tuple{fwds_data_field_types...}}}
    end

    return :(error("Unhandled type $T"))
end

fdata_type(::Type{T}) where {T<:Ptr} = T

@generated function fdata_type(::Type{P}) where {P<:Tuple}
    isa(P, Union) && return Union{fdata_type(P.a), fdata_type(P.b)}
    isempty(P.parameters) && return NoFData
    isa(last(P.parameters), Core.TypeofVararg) && return Any
    all(p -> fdata_type(p) == NoFData, P.parameters) && return NoFData
    return Tuple{map(fdata_type, fieldtypes(P))...}
end

@generated function fdata_type(::Type{NamedTuple{names, T}}) where {names, T<:Tuple}
    if fdata_type(T) == NoFData
        return NoFData
    elseif isconcretetype(fdata_type(T))
        return NamedTuple{names, fdata_type(T)}
    else
        return Any
    end
end

"""
    fdata_field_type(::Type{P}, n::Int) where {P}

Returns the type of to the nth field of the fdata type associated to `P`. Will be a
`PossiblyUninitTangent` if said field can be undefined.
"""
function fdata_field_type(::Type{P}, n::Int) where {P}
    Tf = tangent_type(fieldtype(P, n))
    f = ismutabletype(P) ? Tf : fdata_type(Tf)
    return is_always_initialised(P, n) ? f : _wrap_type(f)
end

"""
    fdata(t)::fdata_type(typeof(t))

Extract the forwards data from tangent `t`.
"""
@generated function fdata(t::T) where {T}

    # Ask for the forwards-data type. Useful catch-all error checking for unexpected types.
    F = fdata_type(T)

    # Catch-all for anything with no forwards-data.
    F == NoFData && return :(NoFData())

    # Catch-all for anything where we return the whole object (mutable structs, arrays...).
    F == T && return :(t)

    # T must be a `Tangent` by now. If it's not, something has gone wrong.
    !(T <: Tangent) && return :(error("Unhandled type $T"))
    return :($F(fdata(t.fields)))
end

function fdata(t::T) where {T<:PossiblyUninitTangent}
    F = fdata_type(T)
    return is_init(t) ? F(fdata(val(t))) : F()
end

@generated function fdata(t::Union{Tuple, NamedTuple})
    fdata_type(t) == NoFData && return NoFData()
    return :(tuple_map(fdata, t))
end

uninit_fdata(p) = fdata(uninit_tangent(p))

"""
    InvalidFDataException(msg::String)

Exception indicating that there is a problem with the fdata associated to a primal.
"""
struct InvalidFDataException <: Exception
    msg::String
end

"""
    verify_fdata_type(P::Type, F::Type)::Nothing

Check that `F` is a valid type for fdata associated to a primal of type `P`. Returns
`nothing` if valid, throws an `InvalidFDataException` if a problem is found.

This applies to both concrete and non-concrete `P`. For example, if `P` is the type inferred
for a primal `q::Q`, such that `Q <: P`, then this method is still applicable.
"""
function verify_fdata_type(P::Type, F::Type)::Nothing
    _F = fdata_type(tangent_type(P))
    F <: _F && return nothing
    throw(InvalidFDataException("Type $P has fdata type $_F, but got $F."))
end

"""
    verify_fdata_value(p, f)::Nothing

Check that `f` cannot be proven to be invalid fdata for `p`.

This method attempts to provide some confidence that `f` is valid fdata for `p` by checking
a collection of necessary conditions. We do not guarantee that these amount to a sufficient
condition, just that they rule out a variety of common problems.

Put differently, we cannot prove that `f` is valid fdata, only that it is not obviously
invalid.
"""
function verify_fdata_value(p, f)::Nothing
    verify_fdata_type(_typeof(p), typeof(f))
    _verify_fdata_value(p, f)
end

_verify_fdata_value(::IEEEFloat, ::NoFData) = nothing

_verify_fdata_value(::Ptr, ::Ptr) = nothing

function _verify_fdata_value(p::Array, f::Array)
    if size(p) != size(f)
        throw(InvalidFDataException("p has size $(size(p)) but f has size $(size(f))"))
    end

    # If the element type is `NoFData` then stop here.
    eltype(f) == NoFData && return nothing

    # Recurse into each element and check that it is correct. Note that the elements of an
    # Array contain the tangents, so we must check that the fdata and rdata components are
    # correct separately.
    for n in eachindex(p)
        if isassigned(p, n)
            t = f[n]
            verify_fdata_value(p[n], fdata(t))
            verify_rdata_value(p[n], rdata(t))
        end
    end

    return nothing
end

# (mutable) structs, Tuples, and NamedTuples all have slightly different storage.
_get_fdata_field(f::NamedTuple, name) = getfield(f, name)
_get_fdata_field(f::Tuple, name) = getfield(f, name)
_get_fdata_field(f::FData, name) = val(getfield(f.data, name))
_get_fdata_field(f::MutableTangent, name) = fdata(val(getfield(f.fields, name)))

function _verify_fdata_value(p, f)

    # If f is a NoFData then there are no checks needed, because we have already verified
    # that NoFData is the correct type for fdata for p, and NoFData is a singleton type.
    f isa NoFData && return nothing

    # When a primitive is encountered here, it means that we don't have a method of
    # _verify_fdata_value which is specific to it, and its fdata type is not NoFData.
    # The rest of this method assumes p is an instance of a struct type, so we must error.
    P = _typeof(p)
    isprimitivetype(P) && error("Encountered primitive $p with fdata $f")

    # Having excluded primitive types, we must have a (mutable) struct type. Recurse into
    # its fields and verify each of them.
    for name in fieldnames(P)
        if isdefined(p, name)
            _p = getfield(p, name)
            t = _get_fdata_field(f, name)
            verify_fdata_value(_p, t)
            if f isa MutableTangent
                verify_rdata_value(_p, rdata(val(getfield(f.fields, name))))
            end
        end
    end

    return nothing
end

"""
    NoRData()

Nothing to propagate backwards on the reverse-pass.
"""
struct NoRData end

@inline increment!!(::NoRData, ::NoRData) = NoRData()

@inline increment_field!!(::NoRData, y, ::Val) = NoRData()

struct RData{T<:NamedTuple}
    data::T
end

fields_type(::Type{RData{T}}) where {T<:NamedTuple} = T

@inline increment!!(x::RData{T}, y::RData{T}) where {T} = RData(increment!!(x.data, y.data))

@inline function increment_field!!(x::RData{T}, y, ::Val{f}) where {T, f}
    y isa NoRData && return x
    new_val = fieldtype(T, f) <: PossiblyUninitTangent ? fieldtype(T, f)(y) : y
    return RData(increment_field!!(x.data, new_val, Val(f)))
end

@doc"""
    rdata_type(T)

Returns the type of the reverse data of a tangent of type T.

# Extended help

See extended help in [`fdata_type`](@ref) docstring.
"""
rdata_type(T)

rdata_type(x) = throw(error("$x is not a type. Perhaps you meant typeof(x)?"))

rdata_type(::Type{T}) where {T<:IEEEFloat} = T

function rdata_type(::Type{PossiblyUninitTangent{T}}) where {T}
    return PossiblyUninitTangent{rdata_type(T)}
end

@generated function rdata_type(::Type{T}) where {T}

    # If the tangent type is NoTangent, then the reverse-component must be `NoRData`.
    T == NoTangent && return NoRData

    # This method can only handle struct types. Tell user to implement their own method.
    isprimitivetype(T) && throw(error(
        "$T is a primitive type. Implement a method of `rdata_type` for it."
    ))

    # If the type is a Union, then take the union type of its arguments.
    T isa Union && return Union{rdata_type(T.a), rdata_type(T.b)}

    # If `P` is a mutable type, then all tangent info is propagated on the forwards-pass.
    ismutabletype(T) && return NoRData

    # If the type is itself abstract, it's reverse data could be anything.
    # The same goes for if the type has any undetermined type parameters.
    (isabstracttype(T) || !isconcretetype(T)) && return Any

    # If `T` is an immutable type, then some of its fields may not have been propagated on
    # the forwards-pass.
    if T <: Tangent
        Tfs = fields_type(T)
        rvs_types = map(n -> rdata_type(fieldtype(Tfs, n)), 1:fieldcount(Tfs))
        all(==(NoRData), rvs_types) && return NoRData
        return RData{NamedTuple{fieldnames(Tfs), Tuple{rvs_types...}}}
    end
end

rdata_type(::Type{<:Ptr}) = NoRData

@generated function rdata_type(::Type{P}) where {P<:Tuple}
    isa(P, Union) && return Union{rdata_type(P.a), rdata_type(P.b)}
    isempty(P.parameters) && return NoRData
    isa(last(P.parameters), Core.TypeofVararg) && return Any
    all(p -> rdata_type(p) == NoRData, P.parameters) && return NoRData
    return Tuple{map(rdata_type, fieldtypes(P))...}
end

function rdata_type(::Type{NamedTuple{names, T}}) where {names, T<:Tuple}
    if rdata_type(T) == NoRData
        return NoRData
    elseif isconcretetype(rdata_type(T))
        return NamedTuple{names, rdata_type(T)}
    else
        return Any
    end
end

"""
    rdata_field_type(::Type{P}, n::Int) where {P}

Returns the type of to the nth field of the rdata type associated to `P`. Will be a
`PossiblyUninitTangent` if said field can be undefined.
"""
function rdata_field_type(::Type{P}, n::Int) where {P}
    r = rdata_type(tangent_type(fieldtype(P, n)))
    return is_always_initialised(P, n) ? r : _wrap_type(r)
end

"""
    rdata(t)::rdata_type(typeof(t))

Extract the reverse data from tangent `t`.

# Extended help

See extended help section of [fdata_type](@ref).
"""
@generated function rdata(t::T) where {T}

    # Ask for the reverse-data type. Useful catch-all error checking for unexpected types.
    R = rdata_type(T)

    # Catch-all for anything with no reverse-data.
    R == NoRData && return :(NoRData())

    # Catch-all for anything where we return the whole object (Float64, isbits structs, ...)
    R == T && return :(t)

    # T must be a `Tangent` by now. If it's not, something has gone wrong.
    !(T <: Tangent) && return :(error("Unhandled type $T"))
    return :($(rdata_type(T))(rdata(t.fields)))
end

function rdata(t::T) where {T<:PossiblyUninitTangent}
    R = rdata_type(T)
    return is_init(t) ? R(rdata(val(t))) : R()
end

@generated function rdata(t::Union{Tuple, NamedTuple})
    rdata_type(t) == NoRData && return NoRData()
    return :(tuple_map(rdata, t))
end

function rdata_backing_type(::Type{P}) where {P}
    rdata_field_types = map(n -> rdata_field_type(P, n), 1:fieldcount(P))
    all(==(NoRData), rdata_field_types) && return NoRData
    return NamedTuple{fieldnames(P), Tuple{rdata_field_types...}}
end

"""
    zero_rdata(p)

Given value `p`, return the zero element associated to its reverse data type.
"""
zero_rdata(p)

zero_rdata(p::IEEEFloat) = zero(p)

@generated function zero_rdata(p::P) where {P}

    # Get types associated to primal.
    T = tangent_type(P)
    R = rdata_type(T)

    # If there's no reverse data, return no reverse data, e.g. for mutable types.
    R == NoRData && return :(NoRData())

    # T ought to be a `Tangent`. If it's not, something has gone wrong.
    !(T <: Tangent) && Expr(:call, error, "Unhandled type $T")
    rdata_field_zeros_exprs = ntuple(fieldcount(P)) do n
        R_field = rdata_field_type(P, n)
        if R_field <: PossiblyUninitTangent
            return :(isdefined(p, $n) ? $R_field(zero_rdata(getfield(p, $n))) : $R_field())
        else
            return :(zero_rdata(getfield(p, $n)))
        end
    end
    backing_data_expr = Expr(:call, :tuple, rdata_field_zeros_exprs...)
    backing_expr = :($(rdata_backing_type(P))($backing_data_expr))
    return Expr(:call, R, backing_expr)
end

@generated function zero_rdata(p::Union{Tuple, NamedTuple})
    rdata_type(tangent_type(p)) == NoRData && return NoRData()
    return :(tuple_map(zero_rdata, p))
end

"""
    can_produce_zero_rdata_from_type(::Type{P}) where {P}

Returns whether or not the zero element of the rdata type for primal type `P` can be
obtained from `P` alone.
"""
@generated function can_produce_zero_rdata_from_type(::Type{P}) where {P}
    R = rdata_type(tangent_type(P))
    R == NoRData && return true
    isabstracttype(P) && return false
    (isconcretetype(P) || P <: Tuple) || return false
    (P <: Tuple && Base.datatype_fieldcount(P) === nothing) && return false

    # For general structs, just look at their fields.
    return isstructtype(P) ? all(can_produce_zero_rdata_from_type, fieldtypes(P)) : false
end

can_produce_zero_rdata_from_type(::Type{<:IEEEFloat}) = true

"""
    CannotProduceZeroRDataFromType()

Returned by `zero_rdata_from_type` if is not possible to construct the zero rdata element
for a given type. See `zero_rdata_from_type` for more info.
"""
struct CannotProduceZeroRDataFromType end

"""
    zero_rdata_from_type(::Type{P}) where {P}

Returns the zero element of `rdata_type(tangent_type(P))` if this is possible given only
`P`. If not possible, returns an instance of `CannotProduceZeroRDataFromType`.

For example, the zero rdata associated to any primal of type `Float64` is `0.0`, so for
`Float64`s this function is simple. Similarly, if the rdata type for `P` is `NoRData`, that
can simply be returned.

However, it is not possible to return the zero rdata element for abstract types e.g. `Real`
as the type does not uniquely determine the zero element -- the rdata type for `Real` is
`Any`.

These considerations apply recursively to tuples / namedtuples / structs, etc.

If you encounter a type which this function returns `CannotProduceZeroRDataFromType`, but
you believe this is done in error, please open an issue. This kind of problem does not
constitute a correctness problem, but can be detrimental to performance, so should be dealt
with.
"""
@generated function zero_rdata_from_type(::Type{P}) where {P}
    R = rdata_type(tangent_type(P))

    # If we know we can't produce a tangent, say so.
    can_produce_zero_rdata_from_type(P) || return CannotProduceZeroRDataFromType()

    # Simple case.
    R == NoRData && return NoRData()

    # If `P` is a struct type, attempt to derive the zero rdata for it. We cannot derive
    # the zero rdata if it is not possible to derive the zero rdata for any of its fields.
    if isstructtype(P)
        names = fieldnames(P)
        types = fieldtypes(P)
        wrapped_field_zeros = tuple_map(ntuple(identity, length(names))) do n
            fzero = :(zero_rdata_from_type($(types[n])))
            if tangent_field_type(P, n) <: PossiblyUninitTangent
                Q = rdata_type(tangent_type(fieldtype(P, n)))
                return :(_wrap_field($Q, $fzero))
            else
                return fzero
            end
        end
        wrapped_field_zeros_tuple = Expr(:call, :tuple, wrapped_field_zeros...)
        return :($R(NamedTuple{$names}($wrapped_field_zeros_tuple)))
    end

    # Fallback -- we've not been able to figure out how to produce an instance of zero rdata
    # so report that it cannot be done.
    return throw(error("Unhandled type $P"))
end

@generated function zero_rdata_from_type(::Type{P}) where {P<:Tuple}
    can_produce_zero_rdata_from_type(P) || return CannotProduceZeroRDataFromType()
    rdata_type(tangent_type(P)) == NoRData && return NoRData()
    return tuple_map(zero_rdata_from_type, fieldtypes(P))
end

function zero_rdata_from_type(::Type{P}) where {P<:NamedTuple}
    can_produce_zero_rdata_from_type(P) || return CannotProduceZeroRDataFromType()
    rdata_type(tangent_type(P)) == NoRData && return NoRData()
    return NamedTuple{fieldnames(P)}(tuple_map(zero_rdata_from_type, fieldtypes(P)))
end

zero_rdata_from_type(::Type{P}) where {P<:IEEEFloat} = zero(P)


"""
    InvalidRDataException(msg::String)

Exception indicating that there is a problem with the rdata associated to a primal.
"""
struct InvalidRDataException <: Exception
    msg::String
end

"""
    verify_rdata_type(P::Type, R::Type)::Nothing

Check that `R` is a valid type for rdata associated to a primal of type `P`. Returns
`nothing` if valid, throws an `InvalidRDataException` if a problem is found.

This applies to both concrete and non-concrete `P`. For example, if `P` is the type inferred
for a primal `q::Q`, such that `Q <: P`, then this method is still applicable.
"""
function verify_rdata_type(P::Type, R::Type)::Nothing
    _R = rdata_type(tangent_type(P))
    R <: _R && return nothing
    throw(InvalidRDataException("Type $P has rdata type $_R, but got $R."))
end

"""
    verify_rdata_value(p, r)::Nothing

Check that `r` cannot be proven to be invalid rdata for `p`.

This method attempts to provide some confidence that `r` is valid rdata for `p` by checking
a collection of necessary conditions. We do not guarantee that these amount to a sufficient
condition, just that they rule out a variety of common problems.

Put differently, we cannot prove that `r` is valid rdata, only that it is not obviously
invalid.
"""
function verify_rdata_value(p, r)::Nothing
    r isa ZeroRData && return nothing
    verify_rdata_type(_typeof(p), typeof(r))
    _verify_rdata_value(p, r)
end

_verify_rdata_value(::P, ::P) where {P<:IEEEFloat} = nothing

_verify_rdata_value(::Array, ::NoRData) = nothing

function _verify_rdata_value(p, r)

    # If f is a NoFData then there are no checks needed, because we have already verified
    # that NoFData is the correct type for fdata for p, and NoFData is a singleton type.
    r isa NoRData && return nothing

    # When a primitive is encountered here, it means that we don't have a method of
    # _verify_rdata_value which is specific to it, and its fdata type is not NoFData.
    # The rest of this method assumes p is an instance of a struct type, so we must error.
    P = _typeof(p)
    isprimitivetype(P) && error("Encountered primitive $p with rdata $r")

    # (mutable) structs, Tuples, and NamedTuples all have slightly different storage.
    _get_rdata_field(r::NamedTuple, name) = getfield(r, name)
    _get_rdata_field(r::Tuple, name) = getfield(r, name)
    _get_rdata_field(r::RData, name) = val(getfield(r.data, name))

    # Having excluded primitive types, we must have a (mutable) struct type. Recurse into
    # its fields and verify each of them.
    for name in fieldnames(P)
        if isdefined(p, name)
            verify_rdata_value(getfield(p, name), _get_rdata_field(r, name))
        end
    end

    return nothing
end


"""
    LazyZeroRData{P, Tdata}()

This type is a lazy placeholder for `zero_like_rdata_from_type`. This is used to defer
construction of zero data to the reverse pass. Calling `instantiate` on an instance of this
will construct a zero data.

Users should construct using `LazyZeroRData(p)`, where `p` is an value of type `P`. This
constructor, and `instantiate`, are specialised to minimise the amount of data which must
be stored. For example, `Float64`s do not need any data, so `LazyZeroRData(0.0)` produces
an instance of a singleton type, meaning that various important optimisations can be
performed in AD.
"""
struct LazyZeroRData{P, Tdata}
    data::Tdata
end

# Returns the type which must be output by LazyZeroRData whenever it is passed a `P`.
@inline function lazy_zero_rdata_type(::Type{P}) where {P}
    Tdata = can_produce_zero_rdata_from_type(P) ? Nothing : rdata_type(tangent_type(P))
    return LazyZeroRData{P, Tdata}
end

# Be lazy if we can compute the zero element given only the type, otherwise just store the
# zero element and use it later. L is the precise type of `LazyZeroRData` that you wish to
# construct -- very occassionally you need complete control over this, but don't want to
# figure out for yourself whether or not construction can be performed lazily.
@inline function lazy_zero_rdata(::Type{L}, p::P) where {L<:LazyZeroRData, P}
    return L(can_produce_zero_rdata_from_type(P) ? nothing : zero_rdata(p))
end

# If type parameters for `LazyZeroRData` are not provided, use the defaults.
@inline lazy_zero_rdata(p::P) where {P} = lazy_zero_rdata(lazy_zero_rdata_type(P), p)

# Ensure proper specialisation on types.
@inline lazy_zero_rdata(::Type{P}) where {P} = LazyZeroRData{Type{P}, Nothing}(nothing)

@inline instantiate(::LazyZeroRData{P, Nothing}) where {P} = zero_rdata_from_type(P)
@inline instantiate(r::LazyZeroRData) = r.data
@inline instantiate(::NoRData) = NoRData()

"""
    tangent_type(F::Type, R::Type)::Type

Given the type of the fdata and rdata, `F` and `R` resp., for some primal type, compute its
tangent type. This method must be equivalent to `tangent_type(_typeof(primal))`.
"""
tangent_type(::Type{NoFData}, ::Type{NoRData}) = NoTangent
tangent_type(::Type{NoFData}, ::Type{R}) where {R<:IEEEFloat} = R
tangent_type(::Type{F}, ::Type{NoRData}) where {F<:Array} = F

# Tuples
function tangent_type(::Type{F}, ::Type{R}) where {F<:Tuple, R<:Tuple}
    return Tuple{tuple_map(tangent_type, Tuple(F.parameters), Tuple(R.parameters))...}
end
function tangent_type(::Type{NoFData}, ::Type{R}) where {R<:Tuple}
    F_tuple = Tuple{tuple_fill(NoFData, Val(length(R.parameters)))...}
    return tangent_type(F_tuple, R)
end
function tangent_type(::Type{F}, ::Type{NoRData}) where {F<:Tuple}
    R_tuple = Tuple{tuple_fill(NoRData, Val(length(F.parameters)))...}
    return tangent_type(F, R_tuple)
end

# NamedTuples
function tangent_type(::Type{F}, ::Type{R}) where {ns, F<:NamedTuple{ns}, R<:NamedTuple{ns}}
    return NamedTuple{ns, tangent_type(tuple_type(F), tuple_type(R))}
end
function tangent_type(::Type{NoFData}, ::Type{R}) where {ns, R<:NamedTuple{ns}}
    return NamedTuple{ns, tangent_type(NoFData, tuple_type(R))}
end
function tangent_type(::Type{F}, ::Type{NoRData}) where {ns, F<:NamedTuple{ns}}
    return NamedTuple{ns, tangent_type(tuple_type(F), NoRData)}
end
tuple_type(::Type{<:NamedTuple{<:Any, T}}) where {T<:Tuple} = T

# mutable structs
tangent_type(::Type{F}, ::Type{NoRData}) where {F<:MutableTangent} = F

# structs
function tangent_type(::Type{F}, ::Type{R}) where {F<:FData, R<:RData}
    return Tangent{tangent_type(fields_type(F), fields_type(R))}
end
function tangent_type(::Type{NoFData}, ::Type{R}) where {R<:RData}
    return Tangent{tangent_type(NoFData, fields_type(R))}
end
function tangent_type(::Type{F}, ::Type{NoRData}) where {F<:FData}
    return Tangent{tangent_type(fields_type(F), NoRData)}
end

function tangent_type(
    ::Type{PossiblyUninitTangent{F}}, ::Type{PossiblyUninitTangent{R}}
) where {F, R}
    return PossiblyUninitTangent{tangent_type(F, R)}
end

# Abstract types.
tangent_type(::Type{Any}, ::Type{Any}) = Any


"""
    tangent(f, r)

Reconstruct the tangent `t` for which `fdata(t) == f` and `rdata(t) == r`.
"""
tangent(::NoFData, ::NoRData) = NoTangent()
tangent(::NoFData, r::IEEEFloat) = r
tangent(f::Array, ::NoRData) = f

# Tuples
tangent(f::Tuple, r::Tuple) = tuple_map(tangent, f, r)
tangent(::NoFData, r::Tuple) = tuple_map(_r -> tangent(NoFData(), _r), r)
tangent(f::Tuple, ::NoRData) = tuple_map(_f -> tangent(_f, NoRData()), f)

# NamedTuples
function tangent(f::NamedTuple{n}, r::NamedTuple{n}) where {n}
    return NamedTuple{n}(tangent(Tuple(f), Tuple(r)))
end
function tangent(::NoFData, r::NamedTuple{ns}) where {ns}
    return NamedTuple{ns}(tangent(NoFData(), Tuple(r)))
end
function tangent(f::NamedTuple{ns}, ::NoRData) where {ns}
    return NamedTuple{ns}(tangent(Tuple(f), NoRData()))
end

# mutable structs
tangent(f::MutableTangent, r::NoRData) = f

# structs
function tangent(f::F, r::R) where {F<:FData, R<:RData}
    return tangent_type(F, R)(tangent(f.data, r.data))
end
function tangent(::NoFData, r::R) where {R<:RData}
    return tangent_type(NoFData, R)(tangent(NoFData(), r.data))
end
function tangent(f::F, ::NoRData) where {F<:FData}
    return tangent_type(F, NoRData)(tangent(f.data, NoRData()))
end

function tangent(f::PossiblyUninitTangent{F}, r::PossiblyUninitTangent{R}) where {F, R}
    T = PossiblyUninitTangent{tangent_type(F, R)}
    is_init(f) && is_init(r) && return T(tangent(val(f), val(r)))
    !is_init(f) && !is_init(r) && return T()
    throw(ArgumentError("Initialisation mismatch"))
end
function tangent(f::PossiblyUninitTangent{F}, ::PossiblyUninitTangent{NoRData}) where {F}
    T = PossiblyUninitTangent{tangent_type(F, NoRData)}
    return is_init(f) ? T(tangent(val(f), NoRData())) : T()
end
function tangent(::PossiblyUninitTangent{NoFData}, r::PossiblyUninitTangent{R}) where {R}
    T = PossiblyUninitTangent{tangent_type(NoFData, R)}
    return is_init(r) ? T(tangent(NoFData(), val(r))) : T()
end
function tangent(::PossiblyUninitTangent{NoFData}, ::PossiblyUninitTangent{NoRData})
    return PossiblyUninitTangent(NoTangent())
end

"""
    increment_rdata!!(t::T, r)::T where {T}

Increment the rdata component of tangent `t` by `r`, and return the updated tangent.
Useful for implementation getfield-like rules for mutable structs, pointers, dicts, etc.
"""
increment_rdata!!(t::T, r) where {T} = tangent(fdata(t), increment!!(rdata(t), r))::T

"""
    zero_tangent(p, ::NoFData)


"""
zero_tangent(p, ::NoFData) = zero_tangent(p)

function zero_tangent(p::P, f::F) where {P, F}
    T = tangent_type(P)
    T == F && return f
    r = rdata(zero_tangent(p))
    return tangent(f, r)
end

zero_tangent(p::Tuple, f::Union{Tuple, NamedTuple}) = tuple_map(zero_tangent, p, f)
