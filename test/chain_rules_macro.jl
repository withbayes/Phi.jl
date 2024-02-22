bleh(x::Float64, y::Int) = x * y

function ChainRulesCore.rrule(::typeof(bleh), x::Float64, y::Int)
    return x * y, dz -> (ChainRulesCore.NoTangent(), dz * y, ChainRulesCore.NoTangent())
end

Taped.@from_rrule DefaultCtx Tuple{typeof(bleh), Float64, Int}

@testset "chain_rules_macro" begin
    Taped.TestUtils.test_rrule!!(Xoshiro(1), bleh, 5.0, 4; perf_flag=:stability)
end
