# This file is largely copy + pasted + modified from the Zygote extension in
# LogDensityProblemsAD.jl. 

module TapirLogDensityProblemsADExt

if isdefined(Base, :get_extension)
    using ADTypes
    using LogDensityProblemsAD: ADGradientWrapper
    import LogDensityProblemsAD: ADgradient, logdensity_and_gradient, dimension, logdensity
    import Tapir
else
    using ADTypes
    using ..LogDensityProblemsAD: ADGradientWrapper
    import ..LogDensityProblemsAD: ADgradient, logdensity_and_gradient, dimension, logdensity
    import ..Tapir
end

struct TapirGradientLogDensity{Trule, L} <: ADGradientWrapper
    rule::Trule
    ℓ::L
end

dimension(∇l::TapirGradientLogDensity) = dimension(Tapir.primal(∇l.ℓ))

function logdensity(∇l::TapirGradientLogDensity, x::Vector{Float64})
    return logdensity(Tapir.primal(∇l.ℓ), x)
end

"""
    ADgradient(Val(:Tapir), ℓ)

Gradient using algorithmic/automatic differentiation via Tapir.
"""
function ADgradient(::Val{:Tapir}, ℓ; safety_on::Bool=false)
    primal_sig = Tuple{typeof(logdensity), typeof(ℓ), Vector{Float64}}
    rule = Tapir.build_rrule(Tapir.TapirInterpreter(), primal_sig; safety_on)
    return TapirGradientLogDensity(rule, Tapir.uninit_fcodual(ℓ))
end

function Base.show(io::IO, ∇ℓ::TapirGradientLogDensity)
    return print(io, "Tapir AD wrapper for ", Tapir.primal(∇ℓ.ℓ))
end

# We only test Tapir with `Float64`s at the minute, so make strong assumptions about the
# types supported in order to prevent silent errors.
function logdensity_and_gradient(::TapirGradientLogDensity, ::AbstractVector)
    msg = "Only Vector{Float64} presently supported for logdensity_and_gradients."
    throw(ArgumentError(msg))
end

function logdensity_and_gradient(∇l::TapirGradientLogDensity, x::Vector{Float64})
    dx = zeros(length(x))
    y, pb!! = ∇l.rule(Tapir.zero_fcodual(logdensity), ∇l.ℓ, Tapir.CoDual(x, dx))
    @assert Tapir.primal(y) isa Float64
    pb!!(1.0)
    return Tapir.primal(y), dx
end

# Interop with ADTypes.
function ADgradient(x::ADTypes.AutoTapir, ℓ)
    if x.safe_mode
        msg = "Running Tapir in safe mode. This mode is computationally expensive, " *
            "should only be used when debugging a problem with AD, and turned off in " *
            "general use. Do this by using AutoTapir(safe_mode=false)."
        @info msg
    end
    return ADgradient(Val(:Tapir), ℓ; safety_on=x.safe_mode)
end

end
