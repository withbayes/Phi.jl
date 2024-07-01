
"""
    SafePullback(pb, y, x)

Construct a callable which is equivalent to `pb`, but which enforces type-based pre- and
post-conditions to `pb`. Let `dx = pb.pb(dy)`, for some rdata `dy`, then this function
- checks that `dy` has the correct rdata type for `y`, and
- checks that each element of `dx` has the correct rdata type for `x`.

Reverse pass counterpart to [`SafeRRule`](@ref)
"""
struct SafePullback{Tpb, Ty, Tx}
    pb::Tpb
    y::Ty
    x::Tx
end

"""
    (pb::SafePullback)(dy)

Apply type checking to enforce pre- and post-conditions on `pb.pb`. See the docstring for
`SafePullback` for details.
"""
@inline function (pb::SafePullback)(dy)
    verify_rvs_input(pb.y, dy)
    dx = pb.pb(dy)
    verify_rvs_output(pb.x, dx)
    return dx
end

@noinline verify_rvs_input(y, dy) = verify_rdata_value(y, dy)

@noinline function verify_rvs_output(x, dx)

    # Number of arguments and number of elements in pullback must match. Have to check this
    # because `zip` doesn't require equal lengths for arguments.
    l_pb = length(x)
    l_dx = length(dx)
    if l_pb != l_dx
        error("Number of args = $l_pb but number of rdata = $l_dx. They must to be equal.")
    end

    # Use for-loop to keep stack trace as simple as possible.
    for (_x, _dx) in zip(x, dx)
        verify_rdata_value(_x, _dx)
    end
end

"""
    SafeRRule(rule)

Construct a callable which is equivalent to `rule`, but inserts additional type checking.
In particular:
- check that the fdata in each argument is of the correct type for the primal
- check that the fdata in the `CoDual` returned from the rule is of the correct type for the
    primal.

This happens recursively.
For example, each element of a `Vector{Any}` is compared against each element of the
associated fdata to ensure that its type is correct, as this cannot be guaranteed from the
static type alone.

Some additional dynamic checks are also performed (e.g. that an fdata array of the same size
as its primal).

Let `rule` return `y, pb!!`, then `SafeRRule(rule)` returns `y, SafePullback(pb!!)`.
`SafePullback` inserts the same kind of checks as `SafeRRule`, but on the reverse-pass. See
the docstring for details.

*Note:* at any given point in time, the checks performed by this function constitute a
necessary but insufficient set of conditions to ensure correctness. If you find that an
error isn't being caught by these tests, but you believe it ought to be, please open an
issue or (better still) a PR.

*Note:* this is a "safe mode" in the sense of operating systems. See e.g. this Wikipedia
article: https://en.wikipedia.org/wiki/Safe_mode . Its purpose is to help with debugging,
and should not be used when trying to differentiate code in general, as it decreases
performance quite substantially in many cases.
"""
struct SafeRRule{Trule}
    rule::Trule
end

"""
    (rule::SafeRRule)(x::CoDual...)

Apply type checking to enforce pre- and post-conditions on `rule.rule`. See the docstring
for `SafeRRule` for details.
"""
@inline function (rule::SafeRRule)(x::Vararg{CoDual, N}) where {N}
    verify_fwds_inputs(x)
    y, pb = rule.rule(x...)
    verify_fwds_output(x, y)
    return y::CoDual, SafePullback(pb, primal(y), map(primal, x))
end

@noinline function verify_fwds_inputs(@nospecialize(x::Tuple))
    try
        # Use for-loop to keep the stack trace as simple as possible.
        for _x in x
            verify_fwds(_x)
        end
    catch e
        error("error in inputs to rule with input types $(_typeof(x))")
    end
end

@noinline function verify_fwds_output(@nospecialize(x), @nospecialize(y))
    try
        verify_fwds(y)
    catch e
        error("error in outputs of rule with input types $(_typeof(x))")
    end
end

@noinline verify_fwds(x::CoDual) = verify_fdata_value(primal(x), tangent(x))
