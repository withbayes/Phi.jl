
# Tapir.jl and Reverse-Mode AD

The point of Tapir.jl is to perform reverse-mode algorithmic differentiation (AD).
The purpose of this section is to explain _what_ precisely is meant by this, and _how_ it can be interpreted mathematically.
1. we recap what AD is, and introduce the mathematics necessary to understand is,
1. explain how this mathematics relates to functions and data structures in Julia, and
1. how this is handled in Tapir.jl.

Since Tapir.jl supports in-place operations / mutation, these will push beyond what is encountered in Zygote / Diffractor / ChainRules.
Consequently, while there is a great deal of overlap with these existing systems, you will need to read through this section of the docs in order to properly understand Tapir.jl.

# Who Are These Docs For?

These are primarily designed for anyone who is interested in contributing to Tapir.jl.
They are also hopefully of interest to anyone how is interested in understanding AD more broadly.
If you aren't interested in understanding how Tapir.jl and AD work, you don't need to have read them in order to make use of this package.

# Prerequisites and Resources

This introduction assumes familiarity with the differentiation of vector-valued functions -- familiarity with the gradient and Jacobian matrices is a given.

In order to provide a convenient exposition of AD, we need to abstract a little further than this and make use of a slightly more general notion of the derivative, gradient, and "transposed Jacobian".
Please note that, fortunately, we only ever have to handle finite dimensional objects when doing AD, so there is no need for any knowledge of functional analysis to understand what is going on here.
The required concepts will be introduced here, but I cannot promise that these docs give the best exposition -- they're most appropriate as a refresher and to establish notation.
Rather, I would recommend a couple of lectures from the "Matrix Calculus for Machine Learning and Beyond" course, which you can find [on MIT's OCW website](https://ocw.mit.edu/courses/18-s096-matrix-calculus-for-machine-learning-and-beyond-january-iap-2023/), delivered by Edelman and Johnson (who will be familiar faces to anyone who has spent much time in the Julia world!).
It is designed for undergraduates, and is accessible to anyone with some undergraduate-level linear algebra and calculus.
While I recommend the whole course, Lecture 1 part 2 and Lecture 4 part 1 are especially relevant to the problems we shall discuss -- you can skip to 11:30 in Lecture 4 part 1 if you're in a hurry.



# Derivatives


A foundation on which all of AD is built the the derivate -- we require a fairly general definition of it, which we build up to here.

_**Scalar-to-Scalar Functions**_

Consider first ``f : \RR \to \RR``, which we require to be differentiable at ``x \in \RR``.
Its derivative at ``x`` is usually thought of as the scalar ``\alpha \in \RR`` such that
```math
\text{d}f = \alpha \, \text{d}x .
```
Loosely speaking, by this notation we mean that for arbitrary small changes ``\text{d} x`` in the input to ``f``, the change in the output ``\text{d} f`` is ``\alpha \, \text{d}x``.
We refer readers to the first few minutes of the first lecture mentioned above for a more careful explanation.

_**Vector-to-Vector Functions**_

The generalisation of this to Euclidean space should be familiar: if ``f : \RR^P \to \RR^Q`` is differentiable at a point ``x \in \RR^P``, then the derivative of ``f`` at ``x`` is given by the Jacobian matrix at ``x``, denoted ``J[x] \in \RR^{Q \times P}``, such that
```math
\text{d}f = J[x] \, \text{d}x .
```

It is possible to stop here, as all the functions we shall need to consider can in principle be written as functions on some subset ``\RR^P``.

However, when we consider differentiating computer programmes, we will have to deal with complicated nested data structures, e.g. `struct`s inside `Tuple`s inside `Vector`s etc.
While all of these data structures _can_ be mapped onto a flat vector in order to make sense of the Jacobian of a computer programme, this becomes very inconvenient very quickly.
To see the problem, consider the Julia function whose input of type `Tuple{Tuple{Float64, Vector{Float64}}, Vector{Float64}, Float64}` and whose output is of type `Tuple{Vector{Float64}, Float64}`.
What kind of object might be use to represent the derivative of a function mapping between these two spaces?
We certainly _can_ treat these as structured "view" into a "flat" `Vector{Float64}`s, and then define a Jacobian, but actually _finding_ this mapping is a tedious exercise even if it quite obviously exists.

Similarly, while "vector-Jacobian" products are usually used to explain reverse-mode AD, a more general formulation of the derivative is used all the time -- the matrix calculus discussed by [giles2008extended](@cite) and [minka2000old](@cite) (to name a couple) make use of a generalised form of derivative in order to work with functions which map to and from matrices (despite slight differences in naming conventions from text to text).

Consequently, it will be much easier to avoid these kinds of "flattening" operations wherever possible.
In order to do so, we make use a generalised notion of the derivative.

_**Functions Between More General Spaces**_

In order to avoid the difficulties described above, we consider we consider functions ``f : \mathcal{X} \to \mathcal{Y}``, where ``\mathcal{X}`` and ``\mathcal{Y}`` are _finite_ dimensional real Hilbert spaces (read: finite-dimensional vector space with an inner product, and real-valued scalars).
This definition includes functions to / from ``\RR``, ``\RR^D``, but also real-valued matrices.
Furthermore, we shall see later how we can model all sorts of structured representations of data directly as such spaces.

For such spaces, the derivative of ``f`` at ``x \in \mathcal{X}`` is the linear operator (read: linear function) ``D f [x] : \mathcal{X} \to \mathcal{Y}`` satisfying
```math
\text{d}f = D f [x] \, \text{d} x
```
That is, instead of thinking of the derivative as a number or a matrix, we think about it as a _function_.
We can express the previous notions of the derivative in this language.

In the scalar case, rather than thinking of the derivative as _being_ ``\alpha``, we think of it is a the linear operator ``D f [x] (\dot{x}) := \alpha \dot{x}``.
Put differently, rather than thinking of the derivative as the slope of the tangent to ``f`` at ``x``, think of it as the function decribing the tangent itself.

Similarly, if ``\mathcal{X} = \RR^P`` and ``\mathcal{Y} = \RR^Q`` then this operator can be specified in terms of the Jacobian matrix: ``D f [x] (\dot{x}) := J[x] \dot{x}`` -- brackets are used to emphasise that ``D f [x]`` is a function, and is being applied to ``\dot{x}``.

The difference from usual is a little bit subtle.
We do not define the derivative to _be_ ``\alpha`` or ``J[x]``, rather we define it to be "multiply by ``\alpha``" or "multiply by ``J[x]``".
For the rest of this document we shall use this definition of the derivative.
So whenever you see the word "derivative", you should think "linear function".

_**An aside: the definition of the Frechet Derivative**_

This definition of the derivative has a name: the Frechet derivative.
It is a generalisation of the Total Derivative.
Formally, we say that a function ``f : \mathcal{X} \to \mathcal{Y}`` is differentiable at a point ``x \in \mathcal{X}`` if there exists a linear operator ``D f [x] : \mathcal{X} \to \mathcal{Y}`` (the derivative) satisfying
```math
\lim_{\text{d} h \to 0} \frac{\| f(x + \text{d} h) - f(x) + D f [x] (\text{d} h)  \|_\mathcal{Y}}{\| \text{d}h \|_\mathcal{X}} = 0,
```
where ``\| \cdot \|_\mathcal{X}`` and ``\| \cdot \|_\mathcal{Y}`` are the norms associated to Hilbert spaces ``\mathcal{X}`` and ``\mathcal{Y}`` respectively.
It is a good idea to consider what this looks like when ``\mathcal{X} = \mathcal{Y} = \RR`` and when ``\mathcal{X} = \mathcal{Y} = \RR^D``.
It is sometimes helpful to refer to this definition to e.g. verify the correctness of the derivative of a function -- as with single-variable calculus, however, this is rare.



_**Another aside: what does Forwards-Mode AD compute?**_

At this point we have enough machinery to discuss forwards-mode AD.
Expressed in the language of linear operators and Hilbert spaces, the goal of forwards-mode AD is the following:
given a function ``f`` which is differentiable at a point ``x``, compute ``D f [x] (\dot{x})`` for a given vector ``\dot{x}``.
If ``f : \RR^P \to \RR^Q``, this is equivalent to computing ``J[x] \dot{x}``, where ``J[x]`` is the Jacobian of ``f`` at ``x``.
We provide a high-level explanation of _how_ forwards-mode AD does this in [_How_ does Forwards-Mode AD work?](@ref).



# Reverse-Mode AD: _what_ does it do?

In order to explain what reverse-mode AD does, we first consider the "vector-Jacobian product" definition in Euclidean space which will be familiar to many readers.
We then generalise.

_**Reverse-Mode AD: what does it do in Euclidean space?**_

In this setting, the goal of reverse-mode AD is the following: given a function ``f : \RR^P \to \RR^Q`` which is differentiable at ``x \in \RR^P`` with Jacobian ``J[x]`` at ``x``, compute ``J[x]^\top \bar{y}`` for any ``\bar{y} \in \RR^Q``.
This is useful because we can obtain the gradient from this when ``Q = 1`` by letting ``\bar{y} = 1``.

_**Adjoint Operators**_

In order to generalise this algorithm to work with linear operators, we must first generalise the idea of multiplying a vector by the transpose of the Jacobian.
The relevant concept here is that of the _adjoint_ _operator_.
Specifically, the adjoint ``A^\ast`` of linear operator ``A`` is the linear operator satisfying
```math
\langle A^\ast \bar{y}, \dot{x} \rangle = \langle \bar{y}, A \dot{x} \rangle.
```
The relationship between the adjoint and matrix transpose is this: if ``A (x) := J x`` for some matrix ``J``, then ``A^\ast (y) := J^\top y``.

Moreover, just as ``(A B)^\top = B^\top A^\top`` when ``A`` and ``B`` are matrices, ``(A B)^\ast = B^\ast A^\ast`` when ``A`` and ``B`` are linear operators.
This result follows in short order from the definition of the adjoint operator -- (and is a good exercise!)

_**Reverse-Mode AD: what does it do in general?**_

Equipped with adjoints, we can express reverse-mode AD only in terms of linear operators, dispensing with the need to express everything in terms of Jacobians.
The goal of reverse-mode AD is as follows: given a differentiable function ``f : \mathcal{X} \to \mathcal{Y}``, compute ``D f [x]^\ast (\bar{y})`` for some ``\bar{y}``.

We will explain _how_ reverse-mode AD goes about computing this after some worked examples.

### Some Worked Examples

We now present some worked examples in order to prime intuition, and to introduce the important classes of problems that will be encountered when doing AD in the Julia language.
We will put all of these problems in a single general framework later on.

#### An Example with Matrix Calculus

We have introduced some mathematical abstraction in order to simplify the calculations involved in AD.
To this end, we consider differentiating ``f(X) := X^\top X``.
Results for this and similar operations are given by [giles2008extended](@cite).
A similar operation, but which maps from matrices to ``\RR`` is discussed in Lecture 4 part 2 of the MIT course mentioned previouly.
Both [giles2008extended](@cite) and Lecture 4 part 2 provide approaches to obtaining the derivative of this function.

Following either resource will yield the derivative:
```math
D f [X] (\dot{X}) = \dot{X}^\top X + X^\top \dot{X}
```
Observe that this is indeed a linear operator (i.e. it is linear in its argument, ``\dot{X}``).
(You can always plug it in to the definition of the Frechet derivative to confirm that it is indeed the derivative.)

In order to perform reverse-mode AD, we need to find the adjoint operator.
Using the usual definition of the inner product between matrices,
```math
\langle X, Y \rangle := \textrm{tr} (X^\top Y)
```
we can rearrange the inner product as follows:
```math
\begin{align}
    \langle \bar{Y}, D f [X] (\dot{X}) \rangle &= \langle \bar{Y}, \dot{X}^\top X + X^\top \dot{X} \rangle \nonumber \\
        &= \textrm{tr} (\bar{Y}^\top \dot{X}^\top X) + \textrm{tr}(\bar{Y}^\top X^\top \dot{X}) \nonumber \\
        &= \textrm{tr} ( [\bar{Y} X^\top]^\top \dot{X}) + \textrm{tr}( [X \bar{Y}]^\top \dot{X}) \nonumber \\
        &= \langle \bar{Y} X^\top + X \bar{Y}, \dot{X} \rangle. \nonumber
\end{align}
```
We can read off the adjoint operator from the first argument to the inner product:
```math
D f [X]^\ast (\bar{Y}) = \bar{Y} X^\top + X \bar{Y}.
```

#### AD of a Julia function: a trivial example

We now turn to differentiating Julia `function`s.
The way that Tapir.jl handles immutable data is very similar to how Zygote / ChainRules do.
For example, consider the Julia function
```julia
f(x::Float64) = sin(x)
```
If you've previously worked with ChainRules / Zygote, without thinking too hard about the formalisms we introduced previously (perhaps by considering a variety of partial derivatives) you can probably arrive at the following adjoint for the derivative of `f`:
```julia
g -> g * cos(x)
```

Implicitly, you have performed three steps:
1. model `f` as a differentiable function,
2. compute its derivative, and
3. compute the adjoint of the derivative.

It is helpful to work through this simple example in detail, as the steps involved apply more generally.
The goal is to spell out the steps involved in detail, as this detail becomes helpful in more complicated examples.
If at any point this exercise feels pedantic, we ask you to stick with it.

_**Step 1: Differentiable Mathematical Model**_

Obviously, we model the Julia `function` `f` as the function ``f : \RR \to \RR`` where
```math
f(x) := \sin(x)
```
Observe that, we've made (at least) two modelling assumptions here:
1. a `Float64` is modelled as a real number,
2. the Julia `function` `sin` is modelled as the usual mathematical function ``sin``.

As promised we're being quite pedantic.
While the first assumption is obvious and will remain true, we will shortly see examples where we have to work a bit harder to obtain a correspondence between a Julia `function` and a mathematical object.

_**Step 2: Compute Derivative**_

Now that we have a mathematical model, we can differentiate it:
```math
D f [x] (\dot{x}) = \cos(x) \dot{x}
```

_**Step 3: Compute Adjoint of Derivative**_

Given the derivative, we can find its adjoint:
```math
\langle \bar{f}, D f [x](\dot{x}) \rangle = \langle \bar{f}, \cos(x) \dot{x} \rangle = \langle \cos(x) \bar{f}, \dot{x} \rangle.
```
From here the adjoint can be read off from the first argument to the inner product:
```math
D f [x]^\ast (\bar{f}) = \cos(x) \bar{f}.
```


Author contributions, code availability, data availability

#### AD of a Julia function: a slightly less trivial example

We now turn to differentiating Julia `function`s.
The way that Tapir.jl handles immutable data is very similar to how Zygote / ChainRules do.
For example, consider the Julia function
```julia
f(x::Float64, y::Tuple{Float64, Float64}) = x + y[1] * y[2]
```
If you've previously worked with ChainRules / Zygote, without thinking too hard about the formalisms we introduced previously (perhaps by considering a variety of partial derivatives) you can probably arrive at the following adjoint for the derivative of `f`:
```julia
g -> (g, (y[2] * g, y[1] * g))
```

It is helpful to work through this simple example in detail, as the steps involved apply more generally.
If at any point this exercise feels pedantic, we ask you to stick with it.
The goal is to spell out the steps involved in excessive detail, as this level of detail will be required in more complicated examples, and it is most straightforwardly demonstrated in a simple case.



_**Step 1: Differentiable Mathematical Model**_

There are a couple of aspects of `f` which require thought:
1. it has two arguments -- we've only handled single argument functions previously, and
2. the second argument is a `Tuple` -- we've not yet decided how to model this.

To this end, we define a mathematical notion of a tuple.
A tuple is a collection of ``N`` elements, each of which is drawn from some set ``\mathcal{X}_n``.
We denote by ``\mathcal{X} := \{ \mathcal{X}_1 \times \dots \times \mathcal{X}_N \}`` the set of all ``N``-tuples whose ``n``th element is drawn from ``\mathcal{X}_n``.
Provided that each ``\mathcal{X}_n`` forms a finite Hilbert space, ``\mathcal{X}`` forms a Hilbert space with
1. ``\alpha x := (\alpha x_1, \dots, \alpha x_N)``,
2. ``x + y := (x_1 + y_1, \dots, x_N + y_N)``, and
3. ``\langle x, y \rangle := \sum_{n=1}^N \langle x_n, y_n \rangle``.

We can think of multi-argument functions as single-argument functions of a tuple, so a reasonable mathematical model for `f` might be a function ``f : \{ \RR \times \{ \RR \times \RR \} \} \to \RR``, where
```math
f(x, y) := x + y_1 y_2
```
Note that while the function is written with two arguments, you should treat them as a single tuple, where we've assigned the name ``x`` to the first element, and ``y`` to the second.

_**Step 2: Compute Derivative**_

Now that we have a mathematical object, we can differentiate it:
```math
D f [x, y](\dot{x}, \dot{y}) = \dot{x} + \dot{y}_1 y_2 + y_1 \dot{y}_2
```

_**Step 3: Compute Adjoint of Derivative**_

``D f[x, y]`` maps ``\{ \RR \times \{ \RR \times \RR \}\}`` to ``\RR``, so ``D f [x, y]^\ast`` must map the other way.
You should verify that the following follows quickly from the definition of the adjoint:
```math
D f [x, y]^\ast (\bar{f}) =  (\bar{f}, (\bar{f} y_2, \bar{f} y_1))
```


#### AD with mutable data

In the previous two examples there was an obvious mathematical model for the Julia function.
Indeed this model was sufficiently obvious that it required little explanation.
This is not always the case though, in particular, Julia functions which modify / mutate their inputs require a little more thought.

Consider the following Julia `function`:
```julia
function f!(x::Vector{Float64})
    x .*= x
    return sum(x)
end
```
This `function` squares each element of its input in-place, and returns the sum of the result.
So what is an appropriate mathematical model for this `function`?

_**Step 1: Differentiable Mathematical Model**_

The trick is to distingush between the state of `x` upon _entry_ to / _exit_ from `f!`.
In particular, let ``\phi_{\text{f!}} : \RR^N \to \{ \RR^N \times \RR \}`` be given by
```math
\phi_{\text{f!}}(x) = (x \odot x, \sum_{n=1}^N x_n^2)
```
where ``\odot`` denotes the Hadamard / elementwise product.
The point here is that the inputs to ``\phi_{\text{f!}}`` are the inputs to `x` upon entry to `f!`, and the value returned from ``\phi_{\text{f!}}`` is a tuple containing the both the inputs upon exit from `f!` and the value returned by `f!`.

The remaining steps are straightforward now that we have the model.


_**Step 2: Compute Derivative**_

The derivative of ``\phi_{\text{f!}}`` is
```math
D \phi_{\text{f!}} [x](\dot{x}) = (2 x \odot x, 2 \sum_{n=1}^N x_n \dot{x}_n).
```

_**Step 3: Compute Adjoint of Derivative**_

The argument to the adjoint of the derivative must be a 2-tuple whose elements are drawn from ``\{\RR^N \times \RR \}``.
Denote such a tuple as ``(\bar{y}_1, \bar{y}_2)``.
Plugging this into an inner product with the derivative and rearranging yields
```math
\begin{align}
    \langle (\bar{y}_1, \bar{y}_2), D \phi_{\text{f!}} [x] (\dot{x}) \rangle &= \langle (\bar{y}_1, \bar{y}_2), (2 x \odot \dot{x}, 2 \sum_{n=1}^N x_n \dot{x}_n) \rangle \nonumber \\
        &= \langle (2 x \odot \bar{y}_1, 2 \bar{y}_2 x), (\text{d} x, \text{d} x) \rangle \nonumber \\
        &= \langle 2 x \odot \bar{y}_1 + 2 \bar{y}_2 x, \text{d} x \rangle. \nonumber
\end{align}
```
So we can read off the adjoint to be
```math
D \phi_{\text{f!}} [x]^\ast (\bar{y}) = 2 (x \odot \bar{y}_1 + \bar{y}_2 x).
```

# Directional Derivatives and Gradients

It's worth taking a few minutes to consider the ideas discussed thus far relate to other similar ideas.

The derivative discussed here can be used to compute directional derivatives.
Consider a function ``f : \mathcal{X} \to \RR`` with Frechet derivative ``D f [x] : \mathcal{X} \to \RR`` at ``x \in \mathcal{X}``.
Then ``D f[x](\dot{x})`` returns the directional derivative in direction ``\dot{x}``.

Gradients are closely related to the adjoint of the derivative.
Recall that the gradient of ``f`` at ``x`` is defined to be the vector ``\nabla f (x) \in \mathcal{X}`` such that ``\langle \nabla f (x), \dot{x} \rangle`` gives the directional derivative of ``f`` at ``x`` in direction ``\dot{x}``.
Having noted that ``D f[x](\dot{x})`` is exactly this directional derivative, we can equivalently say that
```math
D f[x](\dot{x}) = \langle \nabla f (x), \dot{x} \rangle .
```

The role of the adjoint is revealed when we consider ``f := \mathcal{l} \circ g``, where ``g : \mathcal{X} \to \mathcal{Y}`` and ``\mathcal{l}(y) := \langle \bar{y}, y \rangle``, where ``\bar{y} \in \mathcal{Y}`` is some fixed vector.
From the chain rule and noting that ``D \mathcal{l} [y](\dot{y}) = \langle \bar{y}, \dot{y} \rangle``, we obtain
```math
\begin{align}
D f [x] (\dot{x}) &= [(D \mathcal{l} [g(x)]) \circ (D g [x])](\dot{x}) \nonumber \\
    &= \langle \bar{y}, D g [x] (\dot{x}) \rangle \nonumber \\
    &= \langle D g [x]^\ast (\bar{y}), \dot{x} \rangle, \nonumber
\end{align}
```
from which we conclude that ``D g [x]^\ast (\bar{y})`` is the gradient of the composition ``l \circ g`` at ``x``.

The consequence is that we can always view the computation performed by reverse-mode AD as computing the gradient of the composition of the function in question and an inner product with the argument to the adjoint.

# Summary

This document explains the core mathematical foundations of AD.
It focuses on _what_ AD does, without worrying about how it might go about it.
Some basic examples are given which show how these mathematical foundations can be applied to differentiate functions of matrices, and Julia `function`s.

Subsequent sections will build on these foundations.



# Asides

### _How_ does Forwards-Mode AD work?

Forwards-mode AD achieves this by breaking down ``f`` into the composition ``f = f_N \circ \dots \circ f_1``, # where each ``f_n`` is a simple function whose derivative (function) ``D f_n [x_n]`` we know for any given ``x_n``. By the chain rule, we have that
```math
D f [x] (\dot{x}) = D f_N [x_N] \circ \dots \circ D f_1 [x_1] (\dot{x})
```
which suggests the following algorithm:
1. let ``x_1 = x``, ``\dot{x}_1 = \dot{x}``, and ``n = 1``
2. let ``\dot{x}_{n+1} = D f_n [x_n] (\dot{x}_n)``
3. let ``x_{n+1} = f(x_n)``
4. let ``n = n + 1``
5. if ``n = N+1`` then return `\dot{x}_{N+1}`, otherwise go to 2.

When each function ``f_n`` maps between Euclidean spaces, the applications of derivatives ``D f_n [x_n] (\dot{x}_n)`` are given by ``J_n \dot{x}_n`` where ``J_n`` is the Jacobian of ``f_n`` at ``x_n``.v

```@bibliography
```