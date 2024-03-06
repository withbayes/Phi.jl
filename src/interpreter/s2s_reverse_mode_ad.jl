#=
    LineToADDataMap

The "AD data associated to line id" is all of the data that is shared between the forwards-
and reverse-passes associated to line `id` in an `BBCode`.

An `LineToADDataMap` is characterised by a `Dict{ID, Int}`. Each `key` is the `ID` of a line
in the primal `BBCode`, and each `value` is the unique position associated to it in a
`Tuple` which gets shared between the forwards- and reverse-passes.

This map will generally only have keys for a subset of the `ID`s in the primal `BBCode`
because many of the lines in primal `BBCode` do not need to share data between the forwards-
and reverse-passes. This means that we can keep the size of the `Tuple` that must be shared
between the forwards- and reverse-passes as small as possible. For example, `PhiNode`s and
terminators never need to share information, nor do `:invoke` expressions which provably
have the `NoPullback` pullback.
=#
struct LineToADDataMap
    m::Dict{ID, Int}
    LineToADDataMap() = new(Dict{ID, Int}())
end

#=
    get_storage_location!(m::LineToADDataMap, line::ID)

Return the location in the `Tuple` shared between the forwards- and reverse-passes
associated to line `line`. If `m` does not already have an entry for `line`,
create one, insert it into `m`, and return it.
=#
function get_storage_location!(m::LineToADDataMap, line::ID)
    (line in keys(m.m)) || setindex!(m.m, length(m.m) + 1, line)
    return m.m[line]
end

#=
    ADInfo

This data structure is used to hold global information which gets passed around, in
particular to `make_ad_stmts!`.

- `interp`: a `TapedInterpreter`.
- `block_stack_id`: the ID associated to the block stack -- the stack which keeps track of
    which blocks we visited during the forwards-pass, and which is used on the reverse-pass
    to determine which blocks to visit. The location in the shared data storage associated
    to this can be retrieved using `block_stack_index`.
- `entry_id`: special ID associated to saying "there was no predecessor to this block".
- `line_map`: a `LineToADDataMap`.
- `arg_types`: a map from `Argument` to its static type.
- `ssa_types`: a map from `ID` associated to lines to their static type.
=#
struct ADInfo
    interp::TInterp
    block_stack_id::ID
    entry_id::ID
    line_map::LineToADDataMap
    arg_types::Dict{Argument, Any}
    ssa_types::Dict{ID, Any}
end

# The constructor that you should use for ADInfo -- the fields that you don't need to
# provide to this constructor can be automatically generated.
function ADInfo(interp::TInterp, arg_types::Dict{Argument, Any}, ssa_types::Dict{ID, Any})
    return ADInfo(interp, ID(), ID(), LineToADDataMap(), arg_types, ssa_types)
end

# Returns the index in the shared data tuple which contains the block stack.
block_stack_index(info::ADInfo) = get_storage_location!(info.line_map, info.block_stack_id)

# Returns the statically-inferred type associated to `x`.
get_primal_type(info::ADInfo, x::Argument) = info.arg_types[x]
get_primal_type(info::ADInfo, x::ID) = info.ssa_types[x]
get_primal_type(::ADInfo, x::QuoteNode) = _typeof(x.value)
get_primal_type(::ADInfo, x) = _typeof(x)
function get_primal_type(::ADInfo, x::GlobalRef)
    return isconst(x) ? _typeof(getglobal(x.mod, x.name)) : x.binding.ty
end

#=
    ADStmtInfo

Data structure which contains the result of `make_ad_stmts!`. Fields are
- `line`: the ID associated to the primal line from which this is derived
- `fwds`: the instruction which runs the forwards-pass of AD
- `rvs`: the instruction which runs the reverse-pass of AD / the pullback
- `data`: data which must be made available to the forwards- and reverse-pass of AD

For `rvs`, a value of `nothing` indicates that there should be no instruction associated
to the primal statement in the pullback.

For `data`, a value of `nothing` indicates that there is no data that needs to be shared
between the forwards-pass and pullback, and that there is no need to allocate an element of
the tuple which is shared between the forwards-pass and pullback to this primal line.
=#
struct ADStmtInfo
    line::ID
    fwds::Vector{Tuple{ID, Any}}
    rvs
    data
end

function ad_stmt_info(line::ID, fwds::Vector{Tuple{ID, Any}}, rvs, data)
    return ADStmtInfo(line, fwds, rvs, data)
end

function ad_stmt_info(line::ID, fwds, rvs, data)
    return ADStmtInfo(line, Tuple{ID, Any}[(line, fwds)], rvs, data)
end

#=
    make_ad_stmts(stmt, id::ID, info::ADInfo)::ADStmtInfo

Every line in the primal code is associated to exactly one line in the forwards-pass of AD,
and either one or zero lines in the pullback (many nodes do not need to appear in the
pullback at all). This function specifies this translation for every type of node.

Translates the statement `stmt`, associated to `id` in the primal, into a specification of
what should happen for this statement in the forwards- and reverse-passes of AD, and what
data should be shared between the forwards- and reverse-passes. Returns this in the form of
an `ADStmtInfo`.

`info` is a data structure containing various bits of global information that certain types
of nodes need access to.
=#
function make_ad_stmts! end

# `nothing` as a statement in Julia IR indicates the presence of a line which will later be
# removed. We emit a no-op on both the forwards- and reverse-passes. No shared data.
function make_ad_stmts!(::Nothing, line::ID, ::ADInfo)
    return ad_stmt_info(line, nothing, nothing, nothing)
end

# Identity forwards-pass, no-op reverse. No shared data.
function make_ad_stmts!(stmt::ReturnNode, line::ID, info::ADInfo)
    if !isdefined(stmt, :val) || isa(stmt.val, Union{Argument, ID})
        return ad_stmt_info(line, __inc_arg_numbers(stmt), nothing, nothing)
    else
        val_id = ID()
        val, shared_data = augmented_const_components(stmt.val, line, info)
        fwds = Tuple{ID, Any}[(val_id, val), (line, ReturnNode(val_id))]
        return ad_stmt_info(line, fwds, nothing, shared_data)
    end
end

# Identity forwards-pass, no-op reverse. No shared data.
function make_ad_stmts!(stmt::IDGotoNode, line::ID, ::ADInfo)
    return ad_stmt_info(line, __inc_arg_numbers(stmt), nothing, nothing)
end

# Identity forwards-pass, no-op reverse. No shared data.
function make_ad_stmts!(stmt::IDGotoIfNot, line::ID, ::ADInfo)
    stmt = __inc_arg_numbers(stmt)
    if stmt.cond isa Union{Argument, ID}
        # If cond refers to a register, then the primal must be extracted.
        cond_id = ID()
        cond = Expr(:call, primal, stmt.cond)
        fwds = Tuple{ID, Any}[(cond_id, cond), (line, IDGotoIfNot(cond_id, stmt.dest))]
        return ad_stmt_info(line, fwds, nothing, nothing)
    else
        # If something other than a register, then there is nothing to do.
        return ad_stmt_info(line, stmt, nothing, nothing)
    end
end

# Identity forwards-pass, no-op reverse. No shared data.
function make_ad_stmts!(stmt::IDPhiNode, line::ID, ::ADInfo)
    return ad_stmt_info(line, __inc_arg_numbers(stmt), nothing, nothing)
end

function make_ad_stmts!(stmt::PiNode, line::ID, info::ADInfo)
    isa(stmt.val, Union{Argument, ID}) || unhandled_feature("PiNode: $stmt")

    # Create line to sharpen type.
    sharp_primal_type = _get_type(stmt.typ)
    sharpened_register_type = AugmentedRegister{codual_type(_get_type(sharp_primal_type))}
    new_pi_line = ID()
    new_pi = PiNode(stmt.val, sharpened_register_type)
    n = get_storage_location!(info.line_map, line)
    shared_data = (
        make_tangent_stack(sharp_primal_type),
        make_tangent_ref_stack(tangent_ref_type_ub(get_primal_type(info, stmt.val))),
    )
    return ADStmtInfo(
        line,
        Tuple{ID, Any}[
            (new_pi_line, new_pi),
            (line, Expr(:call, __pi_fwds!, Argument(1), Val(n), new_pi_line)),
        ],
        Expr(:call, __pi_rvs!, Argument(1), Val(n)),
        shared_data,
    )
end

@inline function __pi_fwds!(captures, ::Val{n}, reg::AugmentedRegister) where {n}
    sharpened_tangent_stack, tangent_ref_stack = captures[n]
    push!(tangent_ref_stack, top_ref(reg.tangent_stack))
    push!(sharpened_tangent_stack, tangent(reg.codual))
    return AugmentedRegister(reg.codual, sharpened_tangent_stack)
end

@inline function __pi_rvs!(captures, ::Val{n}) where {n}
    sharpened_tangent_stack, tangent_ref_stack = captures[n]
    dout = pop!(sharpened_tangent_stack)
    increment_ref!(pop!(tangent_ref_stack), dout)
    return nothing
end

# Constant GlobalRefs are handled. See const_register. Non-constant
# GlobalRefs are not handled by Taped -- an appropriate error is thrown.
function make_ad_stmts!(stmt::GlobalRef, line::ID, info::ADInfo)
    isconst(stmt) || unhandled_feature("Non-constant GlobalRef not supported")
    return const_register(stmt, line, info)
end

# QuoteNodes are constant. See make_const_register for details.
make_ad_stmts!(stmt::QuoteNode, line::ID, info::ADInfo) = const_register(stmt, line, info)

# Literal constant. See const_register for details.
make_ad_stmts!(stmt, line::ID, info::ADInfo) = const_register(stmt, line, info)

# If `primal_type` is provably non-differentiable, return statement with no tangent stack.
# Otherwise return an AugmentedRegister whose tangent_stack is stored in shared data.
function const_register(primal_value, line::ID, info::ADInfo)
    fwds, shared_data = augmented_const_components(primal_value, line, info)
    return ad_stmt_info(line, fwds, nothing, shared_data)
end

# line should always be the primal line associated to the instruction you are producing.
function augmented_const_components(stmt, line::ID, info::ADInfo)
    primal_value = get_primal_value(stmt)
    capture_index = get_storage_location!(info.line_map, line)
    fwds = Expr(:call, __assemble_register, Argument(1), Val(capture_index), primal_value)
    shared_data = make_tangent_stack(_typeof(primal_value))
    push!(shared_data, zero_tangent(primal_value))
    return fwds, shared_data
end

get_primal_value(x::GlobalRef) = getglobal(x.mod, x.name)
get_primal_value(x::QuoteNode) = x.value
get_primal_value(x) = x

# Helper function, emitted from `make_const_augmented_register`.
@inline function __assemble_register(captures, ::Val{n}, x::P) where {n, P}
    return AugmentedRegister(zero_codual(x), captures[n])
end

# Taped does not yet handle `PhiCNode`s. Throw an error if one is encountered.
function make_ad_stmts!(stmt::Core.PhiCNode, ::ID, ::ADInfo)
    unhandled_feature("Encountered PhiCNode: $stmt")
end

# Taped does not yet handle `UpsilonNode`s. Throw an error if one is encountered.
function make_ad_stmts!(stmt::Core.UpsilonNode, ::ID, ::ADInfo)
    unhandled_feature("Encountered UpsilonNode: $stmt")
end

# There are quite a number of possible `Expr`s that can be encountered. Each case has its
# own comment, explaining what is going on.
function make_ad_stmts!(stmt::Expr, line::ID, info::ADInfo)
    is_invoke = Meta.isexpr(stmt, :invoke)
    if Meta.isexpr(stmt, :call) || is_invoke

        # Find the types of all arguments to this call / invoke.
        args = ((is_invoke ? stmt.args[2:end] : stmt.args)..., )
        arg_types = map(arg -> get_primal_type(info, arg), args)

        # Construct signature, and determine how the rrule is to be computed.
        sig = Tuple{arg_types...}
        rule = if is_invoke
            build_rrule(info.interp, sig)
        elseif is_primitive(context_type(info.interp), sig)
            rrule!!
        else
            error("Booo dynamic dispatch")
        end

        # Create data shared between the forwards- and reverse-passes.
        data = (
            rule=rule,
            pb_stack=build_pb_stack(_typeof(rule), arg_types),
            my_tangent_stack=make_tangent_stack(get_primal_type(info, line)),
            arg_tangent_stacks=map(__make_arg_tangent_stack, arg_types, args),
            fwds_ret_type=register_type(get_primal_type(info, line)),
        )

        # Get a location in the global captures in which `data` can live.
        capture_index = get_storage_location!(info.line_map, line)

        # Create a call to `fwds_pass!`, which runs the forwards-pass. `Argument(0)` always
        # contains the global collection of captures.
        inc_args = map(__inc, args)
        fwds = Expr(:call, __fwds_pass!, Argument(1), Val(capture_index), inc_args...)
        rvs = Expr(:call, __rvs_pass!, Argument(1), Val(capture_index))
        return ad_stmt_info(line, fwds, rvs, data)

    elseif Meta.isexpr(stmt, :code_coverage_effect)
        # Code coverage irrelevant for derived code.
        return ad_stmt_info(line, nothing, nothing, nothing)

    elseif stmt.head in [
        :boundscheck,
        :gc_preserve_begin,
        :gc_preserve_end,
        :loopinfo,
        :leave,
        :pop_exception,
        :throw_undef_if_not
    ]
        # Expressions which do not require any special treatment.
        return ad_stmt_info(line, stmt, nothing, nothing)
    else
        # Encountered an expression that we've not seen before.
        throw(error("Unrecognised expression $stmt"))
    end
end

function __make_arg_tangent_stack(arg_type, arg)
    is_active(arg) || return InactiveStack(InactiveRef(__zero_tangent(arg)))
    return make_tangent_ref_stack(tangent_ref_type_ub(arg_type))
end

is_active(::Union{Argument, ID}) = true
is_active(::Any) = false

__zero_tangent(arg) = zero_tangent(arg)
__zero_tangent(arg::GlobalRef) = zero_tangent(getglobal(arg.mod, arg.name))
__zero_tangent(arg::QuoteNode) = zero_tangent(arg.value)

function build_pb_stack(Trule, arg_types)
    T_pb!! = Core.Compiler.return_type(Tuple{Trule, map(codual_type, arg_types)...})
    if T_pb!! <: Tuple && T_pb!! !== Union{}
        F = T_pb!!.parameters[2]
        return Base.issingletontype(F) ? SingletonStack{F}() : Stack{F}()
    else
        return Stack{Any}()
    end
end

# Used in `make_ad_stmts!` method for `Expr(:call, ...)` and `Expr(:invoke, ...)`.
#
# Executes the fowards-pass. `data` is the data shared between the forwards-pass and
# pullback. It must be a `NamedTuple` with fields `arg_tangent_stacks`, `rule`,
# `my_tangent_stack`, and `pb_stack`.
@inline function __fwds_pass!(
    captures::C, ::Val{capture_index}, f::F, raw_args::Vararg{Any, N}
) where {C, capture_index, F, N}

    raw_args = (f, raw_args...)

    # Extract this rules data from the global collection of captures.
    data = getfield(captures, capture_index)

    # Log the location of the tangents associated to each argument.
    tangent_stacks = map(x -> isa(x, AugmentedRegister) ? x.tangent_stack : nothing, raw_args)
    map(__push_ref_stack, data.arg_tangent_stacks, tangent_stacks)

    # Run the rule.
    args = map(x -> isa(x, AugmentedRegister) ? x.codual : uninit_codual(x), raw_args)
    out, pb!! = data.rule(args...)

    # Log the results and return.
    push!(data.my_tangent_stack, tangent(out))
    push!(data.pb_stack, pb!!)
    return AugmentedRegister(out, data.my_tangent_stack)::data.fwds_ret_type
end

@inline __push_ref_stack(tangent_ref_stack, stack) = push!(tangent_ref_stack, top_ref(stack))
@inline __push_ref_stack(::InactiveStack, stack) = nothing
@inline __push_ref_stack(::NoTangentRefStack, stack) = nothing

# Used in `make_ad_stmts!` method for `Expr(:call, ...)` and `Expr(:invoke, ...)`.
#
# Executes the reverse-pass. `data` is the `NamedTuple` shared with `fwds_pass!`.
# Much of this pass will be optimised away in practice.
@inline function __rvs_pass!(captures, ::Val{capture_index})::Nothing where {capture_index}

    # Extract this rules data from the global collection of captures.
    data = captures[capture_index]

    # Get the tangent w.r.t. output, and the pullback, from this instructions' stacks.
    dout = pop!(data.my_tangent_stack)
    pb!! = pop!(data.pb_stack)

    # Get the tangent w.r.t. each argument of the primal.
    tangent_stacks = tuple_map(pop!, data.arg_tangent_stacks)

    # Run the pullback and increment the argument tangents.
    dargs = tuple_map(set_immutable_to_zero ∘ getindex, tangent_stacks)
    new_dargs = pb!!(dout, dargs...)
    map(increment_ref!, tangent_stacks, new_dargs)

    return nothing
end

#
# Runners for generated code.
#

struct Pullback{Tpb, Tret_ref, Targ_tangent_stacks}
    pb_oc::Tpb
    ret_ref::Tret_ref
    arg_tangent_stacks::Targ_tangent_stacks
end

function (pb::Pullback{P, Q})(dy, dargs::Vararg{Any, N}) where {P, Q, N}
    map(setindex!, map(top_ref, pb.arg_tangent_stacks), dargs)
    increment_ref!(top_ref(pb.ret_ref), dy)
    pb.pb_oc(dy, dargs...)
    return map(pop!, pb.arg_tangent_stacks)
end

struct DerivedRule{Tfwds_oc, Targ_tangent_stacks, Tpb_oc}
    fwds_oc::Tfwds_oc
    pb_oc::Tpb_oc
    arg_tangent_stacks::Targ_tangent_stacks
    block_stack::Stack{Int}
    entry_id::ID
end

function (fwds::DerivedRule{P, Q, S})(args::Vararg{CoDual, N}) where {P, Q, S, N}

    # Load arguments in to stacks, and create tuples.
    args_with_tangent_stacks = map(args, fwds.arg_tangent_stacks) do arg, arg_tangent_stack
        push!(arg_tangent_stack, tangent(arg))
        return AugmentedRegister(arg, arg_tangent_stack)
    end

    push!(fwds.block_stack, fwds.entry_id.id)
    reg = fwds.fwds_oc(args_with_tangent_stacks...)::AugmentedRegister
    return reg.codual, Pullback(fwds.pb_oc, reg.tangent_stack, fwds.arg_tangent_stacks)
end

"""
    build_rrule(interp::TInterp{C}, sig::Type{<:Tuple}) where {C}

Returns a `DerivedRule` which is an `rrule!!` for `sig` in context `C`.
"""
function build_rrule(interp::TInterp{C}, sig::Type{<:Tuple}) where {C}

    # If we have a hand-coded rule, just use that.
    is_primitive(C, sig) && return rrule!!

    # Grab code associated to the primal.
    ir, Treturn = lookup_ir(interp, sig)

    # Normalise the IR, and generated BBCode version of it.
    is_vararg, spnames = is_vararg_sig_and_sparam_names(sig)
    ir = normalise!(ir, spnames)
    primal_ir = BBCode(ir)

    # Compute global info.
    arg_types = Dict{Argument, Any}(
        map(((n, t),) -> (Argument(n) => _get_type(t)), enumerate(ir.argtypes))
    )
    ssa_types = Dict{ID, Any}(
        map((id, t) -> (id, _get_type(t)), concatenate_ids(primal_ir), ir.stmts.type)
    )
    info = ADInfo(interp, arg_types, ssa_types)

    # For each block in the fwds and pullback BBCode, translate all statements.
    ad_stmts_blocks = map(primal_ir.blocks) do primal_blk
        ids = concatenate_ids(primal_blk)
        primal_stmts = concatenate_stmts(primal_blk)
        return (primal_blk.id, make_ad_stmts!.(primal_stmts, ids, Ref(info)))
    end

    # Construct captures for forwards-pass and pullback.
    block_stack = Stack{Int}()
    shared_data = compute_shared_data(info, ad_stmts_blocks, block_stack)

    # Construct BBCode for forwards-pass and pullback.
    fwds_ir = forwards_pass_ir(primal_ir, ad_stmts_blocks, info, _typeof(shared_data))
    pb_ir = pullback_ir(primal_ir, Treturn, ad_stmts_blocks, info, _typeof(shared_data))

    # Construct opaque closures and arg tangent stacks, and build the rule.
    # println("ir")
    # display(ir)
    # println("fwds")
    # display(fwds_ir.argtypes)
    # display(IRCode(fwds_ir))
    # display("fwds_optimised")
    # display(optimise_ir!(IRCode(fwds_ir); do_inline=false))
    # println("pb")
    # display(IRCode(pb_ir))
    # println("pb optimised")
    # display(optimise_ir!(IRCode(pb_ir); do_inline=false))
    fwds_oc = OpaqueClosure(optimise_ir!(IRCode(fwds_ir)), shared_data...; do_compile=true)
    pb_oc = OpaqueClosure(optimise_ir!(IRCode(pb_ir)), shared_data...; do_compile=true)
    arg_tangent_stacks = (map(make_tangent_stack ∘ _get_type, primal_ir.argtypes)..., )
    return DerivedRule(fwds_oc, pb_oc, arg_tangent_stacks, block_stack, info.entry_id)
end

const ADStmts = Vector{Tuple{ID, Vector{ADStmtInfo}}}

# Compute the type of the captured variables in the forwards-pass and pullback.
function compute_shared_data(info::ADInfo, ad_stmts_blocks::ADStmts, block_stack)

    # Build map from ID to type.
    tmp = map(ad_stmts -> map(x -> (x.line, x.data), ad_stmts[2]), ad_stmts_blocks)
    id_to_data = Dict{ID, Any}([(info.block_stack_id, block_stack), reduce(vcat, tmp)...])
    id_to_data = filter(p -> p.second !== nothing, id_to_data)

    # Build map from index to type.
    index_to_data = Dict(
        (get_storage_location!(info.line_map, id), id_to_data[id]) for id in keys(id_to_data)
    )

    # Compute Tuple type.
    return (map(last, sort(collect(index_to_data); by=x->x.first))..., )
end

function forwards_pass_ir(ir::BBCode, ad_stmts_blocks::ADStmts, info::ADInfo, Tshared_data)

    # Construct augmented version of each basic block from the primal. For each block:
    # 1. pull the translated basic block statements from ad_stmts_blocks.
    # 2. insert a statement which logs the ID of the current block to the block stack.
    # 3. construct and return a BBlock.
    n = block_stack_index(info)
    blocks = map(ad_stmts_blocks) do (block_id, ad_stmts)
        fwds_stmts = reduce(vcat, map(x -> x.fwds, ad_stmts))
        ins_loc = length(fwds_stmts) + (isa(fwds_stmts[end][2], Terminator) ? 0 : 1)
        ins_stmt = (ID(), Expr(:call, __push_block_stack!, Argument(1), Val(n), block_id.id))
        return BBlock(block_id, insert!(fwds_stmts, ins_loc, ins_stmt))
    end

    # Create and return the `BBCode` for the forwards-pass.
    arg_types = vcat(Tshared_data, map(register_type ∘ _get_type, ir.argtypes))
    return BBCode(blocks, arg_types, ir.sptypes, ir.linetable, ir.meta)
end

# push a block index `id` onto the block_stack, which is found in `captures[n]`.
@inline __push_block_stack!(captures, ::Val{n}, id::Int) where {n} = push!(captures[n], id)

# Increments by 1 the number associated to an `Argument`. This is helpful in the forwards-
# pass because all arguments are shuffled along by 1.
__inc_arg_numbers(x::Expr) = Expr(x.head, map(__inc, x.args)...)
__inc_arg_numbers(x::ReturnNode) = isdefined(x, :val) ? ReturnNode(__inc(x.val)) : x
__inc_arg_numbers(x::IDGotoIfNot) = IDGotoIfNot(__inc(x.cond), x.dest)
__inc_arg_numbers(x::IDGotoNode) = x
function __inc_arg_numbers(x::IDPhiNode)
    new_values = Vector{Any}(undef, length(x.values))
    for n in eachindex(x.values)
        if isassigned(x.values, n)
            new_values[n] = __inc(x.values[n])
        end
    end
    return IDPhiNode(x.edges, new_values)
end
__inc_arg_numbers(::Nothing) = nothing
__inc_arg_numbers(x::GlobalRef) = x

__inc(x::Argument) = Argument(x.n + 1)
__inc(x) = x

function pullback_ir(ir::BBCode, Tret, ad_stmts_blocks::ADStmts, info::ADInfo, Tshared_data)

    # Create entry block, which pops the block_stack, and switches to whichever block we
    # were in at the end of the forwards-pass.
    primal_exit_blocks_inds = findall(is_reachable_return_node ∘ terminator, ir.blocks)
    exit_blocks_ids = map(n -> ir.blocks[n].id, primal_exit_blocks_inds)
    entry_block = BBlock(ID(), make_switch_stmts(exit_blocks_ids, info))

    # For each basic block in the primal:
    # 1. pull the translated basic block statements from ad_stmts_blocks
    # 2. reverse the statements
    # 3. pop block stack to get the predecessor block
    # 4. insert a switch statement to determine which block to jump to. Restrict blocks
    #   considered to only those which are predecessors of this one. If in the first block,
    #   check whether or not the block stack is empty. If empty, jump to the exit block.
    main_blocks = map(ad_stmts_blocks, enumerate(ir.blocks)) do (blk_id, ad_stmts), (n, blk)
        rvs_stmts = reverse(Tuple{ID, Any}[(x.line, x.rvs) for x in ad_stmts])
        pred_ids = vcat(predecessors(blk, ir), n == 1 ? [info.entry_id] : ID[])
        switch_stmts = make_switch_stmts(pred_ids, info)
        return BBlock(blk_id, vcat(rvs_stmts, switch_stmts))
    end

    # Create an exit block. Simply returns nothing.
    exit_block = BBlock(info.entry_id, Tuple{ID, Any}[(ID(), ReturnNode(nothing))])

    # Create and return `BBCode` for the pullback.
    blks = vcat(entry_block, main_blocks, exit_block)
    darg_types = map(tangent_type ∘ _get_type, ir.argtypes)
    arg_types = vcat(Tshared_data, tangent_type(Tret), darg_types)
    return _sort_blocks!(BBCode(blks, arg_types, ir.sptypes, ir.linetable, ir.meta))
end

function make_switch_stmts(pred_ids::Vector{ID}, info::ADInfo)

    # Get the predecessor that we actually had in the primal.
    prev_blk_id = ID()
    prev_blk = Expr(:call, __pop_block_stack!, Argument(1), Val(block_stack_index(info)))

    # Compare predecessor from primal with all possible predecessors.
    conds = Tuple{ID, Any}[
        (ID(), Expr(:call, __switch_case, id.id, prev_blk_id)) for id in pred_ids[1:end-1]
    ]

    # Switch statement to change to the predecessor.
    switch = (ID(), Switch(Any[c[1] for c in conds], pred_ids[1:end-1], pred_ids[end]))

    return vcat((prev_blk_id, prev_blk), conds, switch)
end

# pops the top of the black stack, which is found in `captures[n]`.
__pop_block_stack!(captures::C, ::Val{n}) where {C, n} = pop!(captures[n])

__switch_case(id::Int, prev_blk_id::Int) = !(id === prev_blk_id)
