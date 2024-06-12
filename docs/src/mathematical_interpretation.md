# Tapir.jl's Mathematical Intepretation of Julia Functions

The purpose of Tapir.jl is to differentiate Julia `function`s.
There are two aspects of Julia `function`s which are relevant to our discussion here:
1. how to represent gradients to inputs / outputs of `function`s, and
2. how to model + differentiate the computation which a function performs.

# Tangents

We call the argument or output of a derivative ``D f [x] : \mathcal{X} \to \mathcal{Y}`` a _tangent_, and will usually denote it with a dot over a symbol, e.g. ``\dot{x}``.
Conversely, we call an argument or output of the adjoint of this derivative ``D f [x]^\ast : \mathcal{Y} \to \mathcal{X}`` a _gradient_, and will usually denote it with a bar over a symbol, e.g. ``\bar{y}``.

Note, however, that the sets involved are the same whether dealing with a derivative or its adjoint.
Consequently, we use the same type to represent both.


_**A quick aside: Non-Differentiable Data**_

In the introduction to algorithmic differentiation, we assumed that the domain / range of function are the same as that of its derivative.
Unfortunately, this story is only partly true.
Matters are complicated by the fact that not all data types in Julia can reasonably be thought of as forming a Hilbert space.
e.g. the `String` type.

Consequently we introduce the special type `NoTangent`, instances of which can be thought of as representing the set containing only a ``0`` tangent.
Morally speaking, for any non-differentiable data `x`, `x + NoTangent() == x`.

Other than non-differentiable data, the model of data in Julia as living in a real-valued finite dimensional Hilbert space is quite reasonable.
Therefore, we hope readers will forgive us for largely ignoring the distinction between the domain and range of a function and that of its derivative in mathematical discussions, while simultaneously drawing a distinction when discussing code.


_**Representing Tangents**_

The extended docstring for [`tangent_type`](@ref) provides the best introduction to the types which are used to represent tangents.

```@docs
tangent_type(P)
```



_**FData and RData**_

While tangents are the things used to represent gradients, they are not strictly what gets propagated forwards and backwards by rules during AD.
Rather, they are split into fdata and rdata, and these are passed around.

```@docs
Tapir.fdata_type(T)
```



# The Rule Abstraction

A rule must return a `CoDual` and a function to run the reverse-pass, known as the pullback.
Upon exit from the rule, it must be true that
1. the state of the arguments / output are the same as they would be had the primal been run, and
2. the uniqueness of the mapping between address-identified primals and their fdata is maintained.

Upon exit from the pullback, it must be true that
1. the primal state is as it was before running the rule,
2. the fdata for the arguments has been incremented by the fdata in ``D f[x]^\ast (\bar{y})``, and 
3. the rdata for the arguments is equal to the rdata in ``D f[x]^\ast (\bar{y})``.


Tapir.jl makes use of a rule system which is at first glance similar to the `rrule` function offered by ChainRules.jl.
However, owing to Tapir.jl's support for mutation (e.g. differentiating through functions which write to arrays) and high degree of precision around the types used to represent (co)-tangent-like data, the number of situations in which the two are identical are actually rather small.

Nevertheless, we begin this explanation with an example which should be familiar to anyone who has used ChainRules.jl and seen its rrule.
Once this example has been explained, we move into new territory.

### Functions of Scalars: from ChainRules.rrule to Tapir.rrule!!

Consider the simple Julia function
```julia
mul(a::Float64, b::Float64) = a * b
```

A `ChainRules.rrule` for this might look something like
```julia
function ChainRules.rrule(::typeof(mul), a::Float64, b::Float64)
    mul_pullback(dc::Float64) = NoTangent(), dc * b, dc * a
    return a * b, mul_pullback
end
```

The corresponding `Tapir.rrule!!` would be something like
```julia
function Tapir.rrule!!(::CoDual{typeof(mul)}, a::CoDual{Float64}, b::CoDual{Float64})
    _a = primal(a)
    _b = primal(b)
    mul_pullback!!(dc::Float64) = NoRData(), dc * _b, dc * _a
    return CoDual(_a * _b, NoFData()), mul_pullback!
end
```

The core differences between the `rrule` and `rrule!!` are:
1. each argument is a `CoDual`, which contains the primal and one other piece of data (more on this later),
1. we must extract the primal values from `a` and `b` using the `primal` function in order to access them,
1. `NoTangent()` is replaced by `NoRData()`, and
1. we must return another `CoDual`, rather than just the primal value (more on this later).

The point of this example is to highlight that `Tapir.rrule!!`s look a lot like `ChainRules.rrule`s in some situations, so some of your existing knowledge should transfer over.

### Functions of Vectors

We now turn to the obvious question: why do `Tapir.rrule!!`s differ from `ChainRules.rrule`s?
The short answer is that Tapir.jl requires that each unique primal memory address associated to differentiable data be associated to a unique tangent (a.k.a. shadow) memory address.
(See [Why Unique Memory Address](@ref) to understand why this is necessary.)

To see how this is achieved, consider the function
```julia
function set_1!(x::Vector{Float64}, y::Float64)
    x[1] = y
    return x
end
```
A valid `Tapir.rrule!!` for this function given below.
There are a lot of concepts introduced here, so you'll need to hop back and forth between this and the text below which explains everything.
```julia
function Tapir.rrule!!(
    ::CoDual{typeof(set_1!)}, x::CoDual{Vector{Float64}}, y::CoDual{Float64}
)
    # Extract the primal and "fdata" from x.
    px = primal(x)
    dx = tangent(x)

    # Store the current values.
    px_1_old = px[1]
    dx_1_old = dx[1]

    # Set x_p[1] to `y` and zero-out x_f[1].
    px[1] = primal(y)
    dx[1] = 0.0

    function set_1_pullback!!(::NoRData)

        # The (co)tangent to `y` is just the value in the first position of x_f.
        dy = dx

        # We _must_ undo any changes which occur on the forwards-pass, both to the primal
        # and the fdata (the forwards-component of the tangent).
        px[1] = px_1_old
        dx[1] = dx_1_old

        # There's nothing to propagate backwards for `f` because it's non-differentiable.
        # It has "no reverse data", hence `NoRData`.
        df = NoRData()

        # There's nothing to propagate backwards for `x`, because its tangent is entirely
        # represented by `dx` on the forwards-pass, hence `NoRData`.
        dx = NoRData()

        return df, dx, dy
    end

    # Just return x (the CoDual) -- this propagates forwards the correct unique tangent
    # memory for `x`.
    return x, set_1_pullback!!
end
```
Let's unpack the above:

#### Memory Propagation

We stated at the top of this section that each unique address associated to differentiable data must have a unique tangent memory address associated to it.
To see how this rule preserves this, consider the function
```julia
g(x::Vector{Float64}, y::Float64) = x, set_1!(x, y)
```
The output of `g` is a `Tuple` with the same `Vector{Float64}` in each element.
Therefore, during AD, they _must_ be associated to the same tangent address.
Happily, simple by by returning `x` at the end of the `rrule!!` for `set_1!` we ensure that this happens.

#### The other field in a `CoDual`

In this example, the other field in the `CoDual` associated to `x` must contain a `Vector{Float64}`, which represents the tangent to `x`.
We call this the _fdata_ ("forwards data") associated to `x`.
We didn't show it, but the fdata associated to `y` is `NoFData` ("no forwards data"), indicating that there is no additional data associated to `y` on the forwards-pass.

Why is this the case?


#### Summary

Note that this very simple function does _not_ have a meaningful `ChainRules.rrule` counterpart because it mutates (modifies) `x`, and `ChainRules.rrule` does not support mutation.







# Asides

### Why Uniqueness of Tangents / FData / RData?

Why does Tapir.jl insist that each primal type `P` be paired with a single tangent type `T`, as opposed to being more permissive.
There are a few notable reasons:
1. To provide a precise interface. Rules pass fdata around on the forwards-pass and rdata on the reverse-pass -- being able to make strong assumptions about the type of the fdata / rdata given the primal type makes implementing rules much easier in practice.
1. Conditional type stability. We wish to have a high degree of confidence that if the primal code is type-stable, then the AD code will also be. It is straightforward to construct type stable primal codes which have type-unstable forwards- and reverse-passes if you permit there to be more than one fdata / rdata type for a given primal. So while uniqueness is certainly not sufficient on its own to guarantee conditional type stability, it is probably necessary in general.
1. Test-case generation and coverage. There being a unique tangent / fdata / rdata type for each primal makes being confident that a given rule is being tested thoroughly much easier. For a given primal, rather than there being many possible input / output types to consider, there is just one.

This topic, in particular what goes wrong with permissive tangent type systems like those employed by ChainRules, deserves a more thorough treatment -- hopefully someone will write something more expansive on this topic at some point.


### Why Unique Memory Address
TODO