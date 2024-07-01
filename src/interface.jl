"""
    __value_and_pullback!!(rule, ȳ, f::CoDual, x::CoDual...)

*Note:* this is not part of the public Tapir.jl interface, and may change without warning.

In-place version of `value_and_pullback!!` in which the arguments have been wrapped in
`CoDual`s. Note that any mutable data in `f` and `x` will be incremented in-place. As such,
if calling this function multiple times with different values of `x`, should be careful to
ensure that you zero-out the tangent fields of `x` each time.
"""
function __value_and_pullback!!(rule::R, ȳ::T, fx::Vararg{CoDual, N}) where {R, N, T}
    fx_fwds = tuple_map(to_fwds, fx)
    __verify_sig(rule, fx_fwds)
    out, pb!! = rule(fx_fwds...)
    @assert _typeof(tangent(out)) == fdata_type(T)
    increment!!(tangent(out), fdata(ȳ))
    v = copy(primal(out))
    return v, tuple_map((f, r) -> tangent(fdata(tangent(f)), r), fx, pb!!(rdata(ȳ)))
end

function __verify_sig(
    ::DerivedRule{<:MistyClosure{<:OpaqueClosure{sig}}}, ::Tfx
) where {sig, Tfx}
    if sig != Tfx
        msg = "signature of arguments, $Tfx, not equal to signature required by rule, $sig."
        throw(ArgumentError(msg))
    end
end

__verify_sig(rule::SafeRRule, fx) = __verify_sig(rule.rule, fx)

# rrule!! doesn't specify specific argument types which must be used, so there's nothing to
# check here.
__verify_sig(::typeof(rrule!!), fx::Tuple) = nothing

"""
    __value_and_gradient!!(rule, f::CoDual, x::CoDual...)

*Note:* this is not part of the public Tapir.jl interface, and may change without warning.

Equivalent to `__value_and_pullback!!(rule, 1.0, f, x...)` -- assumes `f` returns a `Float64`.

```jldoctest
# Set up the problem.
f(x, y) = sum(x .* y)
x = [2.0, 2.0]
y = [1.0, 1.0]
rule = build_rrule(f, x, y)

# Allocate tangents. These will be written to in-place. You are free to re-use these if you
# compute gradients multiple times.
tf = zero_tangent(f)
tx = zero_tangent(x)
ty = zero_tangent(y)

# Do AD.
Tapir.__value_and_gradient!!(
    rule, Tapir.CoDual(f, tf), Tapir.CoDual(x, tx), Tapir.CoDual(y, ty)
)
# output

(4.0, (NoTangent(), [1.0, 1.0], [2.0, 2.0]))
```
"""
function __value_and_gradient!!(rule::R, fx::Vararg{CoDual, N}) where {R, N}
    return __value_and_pullback!!(rule, 1.0, fx...)
end

"""
    value_and_pullback!!(rule, ȳ, f, x...)

Compute the value and pullback of `f(x...)`. `ȳ` must be a valid tangent for the primal
return by `f(x...)`.

`rule` should be constructed using `build_rrule`.

*Note:* There are lots of subtle ways to mis-use `value_and_pullback!!`, so we generally
recommend using `value_and_gradient!!` where possible.

*Note:* If calling `value_and_pullback!!` multiple times for various values of `x`, you
should use the same instance of `rule` each time.

*Note:* It is your responsibility to ensure that there is no aliasing in `f` and `x`.
For example,
```julia
X = randn(5, 5)
rule = build_rrule(dot, X, X)
value_and_pullback!!(rule, 1.0, dot, X, X)
```
will yield the wrong result.

*Note:* This method of `value_and_pullback!!` has to first call `zero_codual` on all of its
arguments. This may cause some additional allocations. If this is a problem in your
use-case, consider pre-allocating the `CoDual`s and calling the other method of this
function. The `CoDual`s should be primal-tangent pairs (as opposed to primal-fdata pairs).
There are lots of ways to get this wrong though, so we generally advise against doing this.
"""
function value_and_pullback!!(rule::R, ȳ, fx::Vararg{Any, N}) where {R, N}
    return __value_and_pullback!!(rule, ȳ, __create_coduals(fx)...)
end

"""
    value_and_gradient!!(rule, f, x...)

Equivalent to `value_and_pullback!!(rule, 1.0, f, x...)`, and assumes `f` returns a
`Float64`.

*Note:* There are lots of subtle ways to mis-use `value_and_pullback!!`, so we generally
recommend using [`value_and_gradient!!`](@ref) (this function) where possible. The docstring for
`value_and_pullback!!` is useful for understanding this function though.

An example:
```jldoctest
f(x, y) = sum(x .* y)
x = [2.0, 2.0]
y = [1.0, 1.0]
rule = build_rrule(f, x, y)
value_and_gradient!!(rule, f, x, y)

# output

(4.0, (NoTangent(), [1.0, 1.0], [2.0, 2.0]))
```
"""
function value_and_gradient!!(rule::R, fx::Vararg{Any, N}) where {R, N}
    return __value_and_gradient!!(rule, __create_coduals(fx)...)
end

function __create_coduals(args)
    try
        return tuple_map(zero_codual, args)
    catch e
        if e isa StackOverflowError
            error(
                "Found a StackOverFlow error when trying to wrap inputs. This often " *
                "means that Tapir.jl has encountered a self-referential type. Tapir.jl " *
                "is not presently able to handle self-referential types, so if you are " *
                "indeed using a self-referential type somewhere, you will need to " *
                "refactor to avoid it if you wish to use Tapir.jl."
            )
        else
            rethrow(e)
        end
    end
end
