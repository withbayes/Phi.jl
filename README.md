# Tapir

[![Build Status](https://github.com/compintell/Tapir.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/compintell/Tapir.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)
[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-Contributor's%20Guide-blueviolet)](https://github.com/SciML/ColPrac)
[![](https://img.shields.io/badge/docs-blue.svg)](https://compintell.github.io/Tapir.jl/dev)

The goal of the `Tapir.jl` project is to produce a reverse-mode AD package which is written entirely in Julia, which improves over both `ReverseDiff.jl` and `Zygote.jl` in several ways, and is competitive with `Enzyme.jl`.

## Note on project status

`Tapir.jl` is under active development.
You should presently expect releases involving breaking changes on a semi-regular basis.
We are trying to keep this README as up to date as possible, particularly with regards to the best examples of code to look at to understand how to use Tapir.jl.
If you encounter a new version of Tapir.jl in the wild, please consult this README for the most up-to-date advice.

# Getting Started

There are several ways to interact with Tapir.jl.
The one that we recommend people begin with is [DifferentiationInterface.jl](https://github.com/gdalle/DifferentiationInterface.jl/). For example, use it as follows to compute the gradient of a function mapping a `Vector{Float64}` to `Float64`.
```julia
using DifferentiationInterface
import Tapir

f(x) = sum(abs2, x)
backend = AutoTapir()
x = ones(3)
extras = prepare_gradient(f, backend, x)
gradient(f, backend, x, extras)
```
You should expect that the first time you run `gradient` that it will take a little bit of time, but subsequent runs should be fast.

We are committed to ensuring support for DifferentiationInterface, which is why we recommend using that.
If you are interested in slightly more flexible functionality, you should consider `Tapir.value_and_gradient!!`. See its docstring for more info.

# How it works

`Tapir.jl` is based around a function `rrule!!` (which computes vector-Jacobian products (VJPs)) and a related function, `build_rrule` (which builds functions semantically identical to `rrule!!`).
These VJPs can, for example, be used to compute gradients.
`rrule!!` is similar to ChainRules' `rrule` and Zygote's `_pullback`, but supports functions which mutate (modify) their arguments, in addition to those that do not, and immediately increments (co)tangents.
It has, perhaps unsurprisingly, wound up looking quite similar to the rule system in Enzyme.

For a given function and arguments, it is roughly speaking the case that either
1. a hand-written method of `rrule!!` is applicable, or
2. no hand-written method of `rrule!!` is applicable.

In the first case, we run the `rrule!!`.
In the second, we use `build_rrule` to create a function with the same semantics as `rrule!!` by "doing AD" -- we decompose the function into a composition of functions which _do_ have hand-written `rrule!!`s.
In general, the goal is to write as few hand-written `rrule!!`s as is necessary, and to "do AD" for the vast majority of functions.


# Project Goals

Below the four central objectives of this project are outlined, and the approaches that we take to achieve them.

### Coverage of more of the Language

The need for first-class support for mutation has been well understood in the Julia AD community for a number of years now.
Its primary benefit is the ability to differentiate through the truly vast quantity of mutating code on which users depend in `Base` / `Core`, the standard libraries, and packages in the general registry -- empowering users to AD through code which _they_ write in a mutating way is often of secondary importance.
Thus you should equate `rrule!!`'s support for mutation with good support for existing code.
Conversely, you should equate `Zygote.jl`'s / `ReverseDiff.jl`'s patchy support for mutation with patchy support for existing code.

`rrule!!`s impose no constraints on the types which can be operated on, as with `ChainRules`'s `rrule` and `Zygote`'s `_pullback`.
Consequently, there is in principle nothing to prevent `Tapir.jl` from operating on any type, for example, structured arrays, GPU arrays, and complicated `struct`s / `mutable struct`s.


### Correctness and Testing

Mutation support enables writing `rrule!!`s at a low-level (`Core.InstrincFunction`s, `built-in function`s, `ccall`s to e.g. `BLAS` and `LAPACK` and the bits of Base Julia which are implemented in C).
The simplicity of this low-level functionality makes implementing correct `rrule!!`s for it a simple task.
In conjunction with being strict about the types used internally to represent (co)tangents, we have found this leads to `rrule!!`s composing very well, and AD being correct in practice as a consequence.

Furthermore, the interfaces for `rrule!!` and the (co)tangent type system have been designed to make a reliable `test_rrule!!` function possible to create.
All of our testing is implemented via this (or via another function which calls this) which makes adding test-cases trivial, and has meant that we have produced a lot of test cases.

This contrasts with `Zygote.jl` / `ChainRules.jl`, where the permissive (co)tangent type system complicates both composition of `rrule`s and testing.

Additionally, our approach to AD naturally handles control flow which differs between multiple calls to the same function.
This contrasts with e.g. `ReverseDiff.jl`'s compiled tape, which can give silent numerical errors if control flow ought to differ between gradient evaluations at different arguments.
~~Additionally, we augment the tape that we construct with additional instructions which throw an error if control flow differs from when the tape was constructed.~~
~~This contrasts with `ReverseDiff.jl`, which silently fails in this scenario.~~

### Performance

Hand-written `rrule!!`s have excellent performance, provided that they have been written well (most of the hand-written rules in `Tapir.jl` have excellent performance, but some require optimisation. Doing this just requires investing some time).
Consequently, whether or not the overall AD system has good performance is largely a question of how much overhead is associated to the mechanism by which hand-written `rrules!!`s are algorithmically composed.

~~At present (11/2023), we do _not_ do this in a performant way, but this will change.~~
~~At present (01/2024), we do this in a _moderately_ performant way.~~
At present (03/2024), we do this in a _moderately_ performant way (but better than the previous way!)
See [Project Status](#project-status) below for more info.

Additionally, the strategy of immediately incrementing (co)tangents resolves long-standing performance issues associated with indexing arrays.

### Written entirely in Julia

`Tapir.jl` is written entirely in Julia.
This sits in contrast to `Enzyme.jl`, which targets LLVM and is primarily written in C++.
These two approaches entail different tradeoffs.

# Project Name

Before an initial release, this package was called `Taped.jl`, but that name ceased to be helpful when we stopped using a classic "Wengert list"-style type to implement AD.
For about 48 hours is was called `Phi.jl`, but the community guidelines state that the name of packages in the general registry should generally be at least 5 characters in length.

Disambiguation: when choosing the name `Tapir.jl` we were only vaguely aware of other work [of the same name](https://github.com/wsmoses/Tapir-LLVM), and didn't feel that it presented a serious name clash as it isn't AD-specific or a Julia project.
As it turns out, there has been significant work attempting to integrate the ideas from this work into the [Julia compiler](https://github.com/JuliaLang/julia/pull/39773), so it is possible that this package name _may_ change again at _some_ point in the future.

# Project Status

The plan is to proceed in three phases:
1. design, correctness and testing
1. performance optimisation
1. maintenance

You should take this with a pinch of salt, as it seems highly likely that we will have to revisit some design choices when optimising performance -- we do not, however, anticipate requiring major re-writes to the design as part of performance optimisation.
We aim to reach the maintenance phase of the project before 01/06/2024.

*Update: (30/04/2024)*
Phase 2 continues!
We are now finding that `Tapir.jl` comfortably outperforms compiled `ReverseDiff.jl` on type-stable code in all of the situations we have tested.
Optimising to get similar performance to `Enzyme.jl` is an on-going process.

*Update: (22/03/2024)*
~~Phase 2 is now further along.~~
~~`Tapir.jl` now uses something which could reasonably be described as a source-to-source system to perform AD.~~
~~At present the performance of this system is not as good as that of Enzyme, but often beats compiled ReverseDiff, and comfortably beats Zygote in any situations involving dynamic control flow.~~
~~The present focus is on dealing with some remaining performance limitations that should make `Tapir.jl`'s performance much closer to that of Enzyme, and consistently beat ReverseDiff on a range of benchmarks.~~
~~Fortunately, dealing with these performance limitations necessitates simplifying the internals substantially.~~

*Update: (16/01/2024)*
~~Phase 2 is now well underway. We now make use of a much faster approach to interpreting / executing Julia code, which yields performance that is comparable with ReverseDiff (when things go well). The current focus is on ironing out performance issues, and simplifying the implementation.~~

*Update: (06/11/2023)*
~~We are mostly through the first phase.~~
~~Correctness testing is proceeding well, and we are ironing out known issues.~~
~~Notably, our broad experience at present is that as we continue to increase the amount of Julia code on which the package is tested, things fail for known, predictable, straightforwardly-fixable reasons (largely missing rrules for `ccall`s), rather than unanticipated problems.~~

~~Please note that, since we have yet to enter phase 2 of the project, we have spent _no_ time whatsoever optimising for performance.~~
~~We strongly believe that there is nothing in principle preventing us from achieving excellent performance.~~
~~However, currently, you should expect to experience _amazingly_ poor performance.~~

### What things should work well

Noteworthy things which should work and be performant include:
1. code containing control flow
1. value-dependent control flow
1. mutation of arrays and mutable structs

These are noteworthy in the sense that they are different from ReverseDiff / Zygote.
Enzyme is also able to do these things.

Please be aware that by "performant" we mean similar or better performance than ReverseDiff with a compiled tape, but not as good performance as Enzyme.

### What won't work

While `Tapir.jl` should now work on a very large subset of the language, there remain things that you should expect not to work. A non-exhaustive list of things to bear in mind includes:
1. It is always necessary to produce hand-written rules for `ccall`s (and, more generally, foreigncall nodes). We have rules for many `ccall`s, but not all. If you encounter a foreigncall without a hand-written rule, you should get an informative error message which tells you what is going on and how to deal with it.
1. Builtins which require rules. The vast majority of them have rules now, but some don't. ~~Notably, `apply_iterate` does not have a rule, so `Tapir.jl` cannot currently AD through type-unstable splatting -- someone should resolve this.~~ `Core._apply_iterate` should now work correctly.
1. Anything involving tasks / threading -- we have no thread safety guarantees and, at the time of writing, I'm not entirely sure what error you will find if you attempt to AD through code which uses Julia's task / thread system. The same applies to distributed computing. These limitations ought to be possible to resolve.
