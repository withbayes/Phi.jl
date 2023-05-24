struct ForwardsModeADContext end

const FMC = ForwardsModeADContext

struct Dual{Tx, Tdx}
    x::Tx
    dx::Tdx
end



isprimitive(::typeof(sin), x::Union{Float32, Float64}) = true
function frule(::typeof(sin), x::Dual{<:Union{Float32, Float64}})
    return Dual(sin(x.x), cos(x.x) * x.dx)
end

isprimitive(::typeof(cos), x::Union{Float32, Float64}) = true
function frule(::typeof(cos), x::Dual{<:Union{Float32, Float64}})
    return Dual(cos(x.x), -sin(x.x) * x.dx)
end

frule(::typeof(>), a::Int, b::Int) = a > b
frule(::typeof(-), a::Int, b::Int) = a - b
frule(::Colon, a::Int, b::Int) = a:b
frule(::typeof(iterate), x...) = iterate(x...)
frule(::typeof(===), x, y) = x === y

# Hacky
function frule(f::Core.IntrinsicFunction, x)
    if f === Core.Intrinsics.not_int
        return f(x)
    end
end

frule(::typeof(getfield), x::Tuple, v::Int) = getfield(x, v)

function to_forwards_mode_ad(tape::Tape{FMC}, args...)
    new_tape = Tape(tape.c)
    for (n, arg) in enumerate(args)
        a_type = typeof(tape.ops[n].val)
        @assert typeof(arg) == a_type || typeof(arg) <: Dual{a_type}
        push!(new_tape, Input(arg))
    end
    for op in tape.ops[length(args)+1:end]
        push!(new_tape, to_forwards_mode_ad(op))
    end
    new_tape.result = unbind(tape.result)
    return new_tape
end

to_forwards_mode_ad(x::Constant) = x
to_forwards_mode_ad(x::Call) = mkcall(frule, x.fn, map(unbind, x.args)...)