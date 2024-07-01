module Tapir

const CC = Core.Compiler

using
    ADTypes,
    DiffRules,
    ExprTools,
    Graphs,
    InteractiveUtils,
    LinearAlgebra,
    MistyClosures,
    Random,
    Setfield

import ChainRulesCore

using Base:
    IEEEFloat, unsafe_convert, unsafe_pointer_to_objref, pointer_from_objref, arrayref,
    arrayset
using Base.Experimental: @opaque
using Base.Iterators: product
using Core:
    Intrinsics, bitcast, SimpleVector, svec, ReturnNode, GotoNode, GotoIfNot, PhiNode,
    PiNode, SSAValue, Argument, OpaqueClosure
using Core.Compiler: IRCode, NewInstruction
using Core.Intrinsics: pointerref, pointerset
using LinearAlgebra.BLAS: @blasfunc, BlasInt, trsm!
using LinearAlgebra.LAPACK: getrf!, getrs!, getri!, trtrs!, potrf!, potrs!

# Needs to be defined before various other things.
function _foreigncall_ end

"""
    rrule!!(f::CoDual, x::CoDual...)

Performs the forwards-pass of AD. The `tangent` field of `f` and each `x` should contain the
forwards tangent data (fdata) associated to each corresponding `primal` field.

Returns a 2-tuple.
The first element, `y`, is a `CoDual` whose `primal` field is the value associated to
running `f.primal(map(x -> x.primal, x)...)`, and whose `tangent` field is its associated
`fdata`.
The second element contains the pullback, which runs the reverse-pass. It maps from
the rdata associated to `y` to the rdata associated to `f` and each `x`.

```jldoctest
using Tapir: zero_fcodual, CoDual, NoFData, rrule!!
y, pb!! = rrule!!(zero_fcodual(sin), CoDual(5.0, NoFData()))
pb!!(1.0)

# output

(NoRData(), 0.28366218546322625)
```
"""
function rrule!! end

include("utils.jl")
include("tangents.jl")
include("fwds_rvs_data.jl")
include("codual.jl")
include("safe_mode.jl")
include("stack.jl")

include(joinpath("interpreter", "contexts.jl"))
include(joinpath("interpreter", "abstract_interpretation.jl"))
include(joinpath("interpreter", "bbcode.jl"))
include(joinpath("interpreter", "ir_utils.jl"))
include(joinpath("interpreter", "ir_normalisation.jl"))
include(joinpath("interpreter", "zero_like_rdata.jl"))
include(joinpath("interpreter", "s2s_reverse_mode_ad.jl"))

include("test_utils.jl")

include(joinpath("rrules", "avoiding_non_differentiable_code.jl"))
include(joinpath("rrules", "blas.jl"))
include(joinpath("rrules", "builtins.jl"))
include(joinpath("rrules", "fastmath.jl"))
include(joinpath("rrules", "foreigncall.jl"))
include(joinpath("rrules", "iddict.jl"))
include(joinpath("rrules", "lapack.jl"))
include(joinpath("rrules", "low_level_maths.jl"))
include(joinpath("rrules", "misc.jl"))
include(joinpath("rrules", "new.jl"))
include(joinpath("rrules", "tasks.jl"))

include("chain_rules_macro.jl")
include("interface.jl")

export
    primal,
    tangent,
    randn_tangent,
    increment!!,
    NoTangent,
    Tangent,
    MutableTangent,
    PossiblyUninitTangent,
    set_to_zero!!,
    tangent_type,
    zero_tangent,
    _scale,
    _add_to_primal,
    _diff,
    _dot,
    zero_codual,
    codual_type,
    rrule!!,
    build_rrule,
    value_and_gradient!!,
    value_and_pullback!!,
    NoFData,
    NoRData,
    fdata_type,
    rdata_type,
    fdata,
    rdata

end
