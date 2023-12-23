@testset "integration_testing" begin
    interp = Taped.TInterp()
    @testset for (interface_only, f, x...) in vcat(
        [
            (false, getindex, randn(5), 4),
            (false, getindex, randn(5, 4), 1, 3),
            (false, setindex!, randn(5), 4.0, 3),
            (false, setindex!, randn(5, 4), 3.0, 1, 3),
            (false, x -> getglobal(Main, :sin)(x), 5.0),
            (false, x -> pointerref(bitcast(Ptr{Float64}, pointer_from_objref(Ref(x))), 1, 1), 5.0),
            (false, (v, x) -> (pointerset(pointer(x), v, 2, 1); x), 3.0, randn(5)),
            (false, x -> (pointerset(pointer(x), UInt8(3), 2, 1); x), rand(UInt8, 5)),
            (false, x -> Ref(x)[], 5.0),
            (false, x -> unsafe_load(bitcast(Ptr{Float64}, pointer_from_objref(Ref(x)))), 5.0),
            (false, x -> unsafe_load(Base.unsafe_convert(Ptr{Float64}, x)), randn(5)),
            (false, view, randn(5, 4), 1, 1),
            (false, view, randn(5, 4), 2:3, 1),
            (false, view, randn(5, 4), 1, 2:3),
            (false, view, randn(5, 4), 2:3, 2:4),
            (true, Array{Float64, 1}, undef, (1, )),
            (true, Array{Float64, 2}, undef, (2, 3)),
            (true, Array{Float64, 3}, undef, (2, 3, 4)),
            (false, Array{Vector{Float64}, 1}, undef, (1, )),
            (false, Array{Vector{Float64}, 2}, undef, (2, 3)),
            (false, Array{Vector{Float64}, 3}, undef, (2, 3, 4)),
            (false, Xoshiro, 123456),
            (false, push!, randn(5), 3.0),
            (false, x -> (a=x, b=x), 5.0),
        ],
        map(n -> (false, map, sin, (randn(n)..., )), 1:7),
        map(n -> (false, map, sin, randn(n)), 1:7),
        map(n -> (false, x -> sin.(x), (randn(n)..., )), 1:7),
        map(n -> (false, x -> sin.(x), randn(n)), 1:7),
        vec(map(Iterators.product(
            Any[
                randn(3, 5),
                transpose(randn(5, 3)),
                adjoint(randn(5, 3)),
                view(randn(5, 5), 1:3, 1:5),
                transpose(view(randn(5, 5), 1:5, 1:3)),
                adjoint(view(randn(5, 5), 1:5, 1:3)),
            ],
            Any[
                randn(3, 4),
                transpose(randn(4, 3)),
                adjoint(randn(4, 3)),
                view(randn(5, 5), 1:3, 1:4),
                transpose(view(randn(5, 5), 1:4, 1:3)),
                adjoint(view(randn(5, 5), 1:4, 1:3)),
            ],
            Any[
                randn(4, 5),
                transpose(randn(5, 4)),
                adjoint(randn(5, 4)),
                view(randn(5, 5), 1:4, 1:5),
                transpose(view(randn(5, 5), 1:5, 1:4)),
                adjoint(view(randn(5, 5), 1:5, 1:4)),
            ],
        )) do (A, B, C)
            (false, mul!, A, B, C, randn(), randn())
        end),
        vec(map(product(
            Any[
                LowerTriangular(randn(3, 3)),
                UpperTriangular(randn(3, 3)),
                UnitLowerTriangular(randn(3, 3)),
                UnitUpperTriangular(randn(3, 3)),
                LowerTriangular(view(randn(5, 5), 2:4, 2:4)),
                UpperTriangular(view(randn(5, 5), 2:4, 2:4)),
                UnitLowerTriangular(view(randn(5, 5), 2:4, 2:4)),
                UnitUpperTriangular(view(randn(5, 5), 2:4, 2:4)),
            ],
            Any[
                LowerTriangular(randn(3, 3)),
                UpperTriangular(randn(3, 3)),
                UnitLowerTriangular(randn(3, 3)),
                UnitUpperTriangular(randn(3, 3)),
                LowerTriangular(view(randn(5, 5), 2:4, 2:4)),
                UpperTriangular(view(randn(5, 5), 2:4, 2:4)),
                UnitLowerTriangular(view(randn(5, 5), 2:4, 2:4)),
                UnitUpperTriangular(view(randn(5, 5), 2:4, 2:4)),
            ],
        )) do (B, C)
            A = randn(3, 3)
            (false, mul!, A, B, C, randn(), randn())
        end),
    )
        @info "$(map(typeof, (f, x...)))"
        rng = Xoshiro(123456)
        sig = Tuple{Core.Typeof(f), map(Core.Typeof, x)...}
        in_f = Taped.InterpretedFunction(DefaultCtx(), sig, interp)
        if interface_only
            in_f(f, deepcopy(x)...)
        else
            x_cpy_1 = deepcopy(x)
            x_cpy_2 = deepcopy(x)
            @test has_equal_data(in_f(f, x_cpy_1...), f(x_cpy_2...))
            @test has_equal_data(x_cpy_1, x_cpy_2)
        end
        # TestUtils.test_interpreted_rrule!!(rng, f, deepcopy(x)...; interface_only, perf_flag=:none)
    end
end
