for (M, f, arity) in DiffRules.diffrules(; filter_modules=nothing)
    if !(isdefined(@__MODULE__, M) && isdefined(getfield(@__MODULE__, M), f)) ||
        M == :SpecialFunctions
        # @warn "$M.$f is not available and hence rule for it can not be defined"
        continue  # Skip rules for methods not defined in the current scope
    end
    (f == :rem2pi || f == :ldexp) && continue # not designed for Float64s
    (f == :+ || f == :*) && continue # use intrinsics instead
    P = Float64
    if arity == 1
        dx = DiffRules.diffrule(M, f, :x)
        pb_name = Symbol("$(M).$(f)_pb!!")
        @eval begin
            @is_primitive MinimalCtx Tuple{typeof($M.$f), $P}
            function rrule!!(::CoDual{typeof($M.$f)}, _x::CoDual{$P})
                x = primal(_x) # needed for dx expression
                $pb_name(ȳ) = NoRvsData(), ȳ * $dx
                return CoDual(($M.$f)(x), NoFwdsData()), $pb_name
            end
        end
    elseif arity == 2
        da, db = DiffRules.diffrule(M, f, :a, :b)
        pb_name = Symbol("$(M).$(f)_pb!!")
        @eval begin
            @is_primitive MinimalCtx Tuple{typeof($M.$f), $P, $P}
            function rrule!!(::CoDual{typeof($M.$f)}, _a::CoDual{$P}, _b::CoDual{$P})
                a = primal(_a)
                b = primal(_b)
                $pb_name(ȳ) = NoRvsData(), ȳ * $da, ȳ * $db
                return CoDual(($M.$f)(a, b), NoFwdsData()), $pb_name
            end
        end
    end
end

rand_inputs(rng, f, arity) = randn(rng, arity)
rand_inputs(rng, ::typeof(acosh), _) = (rand(rng) + 1 + 1e-3, )
rand_inputs(rng, ::typeof(asech), _) = (rand(rng) * 0.9, )
rand_inputs(rng, ::typeof(log), _) = (rand(rng) + 1e-3, )
rand_inputs(rng, ::typeof(asin), _) = (rand(rng) * 0.9, )
rand_inputs(rng, ::typeof(asecd), _) = (rand(rng) + 1, )
rand_inputs(rng, ::typeof(log2), _) = (rand(rng) + 1e-3, )
rand_inputs(rng, ::typeof(log10), _) = (rand(rng) + 1e-3, )
rand_inputs(rng, ::typeof(acscd), _) = (rand(rng) + 1 + 1e-3, )
rand_inputs(rng, ::typeof(log1p), _) = (rand(rng) + 1e-3, )
rand_inputs(rng, ::typeof(acsc), _) = (rand(rng) + 1 + 1e-3, )
rand_inputs(rng, ::typeof(atanh), _) = (2 * 0.9 * rand(rng) - 0.9, )
rand_inputs(rng, ::typeof(acoth), _) = (rand(rng) + 1 + 1e-3, )
rand_inputs(rng, ::typeof(asind), _) = (0.9 * rand(rng), )
rand_inputs(rng, ::typeof(asec), _) = (rand(rng) + 1.001, )
rand_inputs(rng, ::typeof(acosd), _) = (2 * 0.9 * rand(rng) - 0.9, )
rand_inputs(rng, ::typeof(acos), _) = (2 * 0.9 * rand(rng) - 0.9, )
rand_inputs(rng, ::typeof(sqrt), _) = (rand(rng) + 1e-3, )

function generate_hand_written_rrule!!_test_cases(rng_ctor, ::Val{:low_level_maths})
    rng = Xoshiro(123)
    test_cases = Any[]
    foreach(DiffRules.diffrules(; filter_modules=nothing)) do (M, f, arity)
        if !(isdefined(@__MODULE__, M) && isdefined(getfield(@__MODULE__, M), f)) ||
            M == :SpecialFunctions
            return  # Skip rules for methods not defined in the current scope
        end
        arity > 2 && return
        (f == :rem2pi || f == :ldexp || f == :(^)) && return
        (f == :+ || f == :*) && return # use intrinsics instead
        f = @eval $M.$f
        push!(test_cases, Any[false, :stability, nothing, f, rand_inputs(rng, f, arity)...])
    end
    memory = Any[]
    return test_cases, memory
end

generate_derived_rrule!!_test_cases(rng_ctor, ::Val{:low_level_maths}) = Any[], Any[]
