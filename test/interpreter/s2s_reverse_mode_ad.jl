@testset "s2s_reverse_mode_ad" begin
    @testset "LineToADDataMap" begin
        m = LineToADDataMap()
        id = ID()
        n = Taped.get_storage_location!(m, id)
        @test Taped.get_storage_location!(m, id) == n
        @test maximum(values(m.m)) == 1
    end
    @testset "ADInfo" begin
        arg_types = Dict{Argument, Any}(Argument(1) => Float64, Argument(2) => Int)
        id_ssa_1 = ID()
        ssa_types = Dict{ID, Any}(id_ssa_1 => Float64, ID() => Any)
        info = ADInfo(Taped.TInterp(), ID(), LineToADDataMap(), arg_types, ssa_types)

        # Verify that we can access the interpreter and terminator block ID.
        @test info.interp isa Taped.TInterp
        @test info.terminator_block_id isa ID

        # Verify that we can get the type associated to Arguments, IDs, and others.
        global ___x = 5.0
        global ___y::Float64 = 5.0
        @test Taped.get_primal_type(info, Argument(1)) == Float64
        @test Taped.get_primal_type(info, Argument(2)) == Int
        @test Taped.get_primal_type(info, id_ssa_1) == Float64
        @test Taped.get_primal_type(info, GlobalRef(Base, :sin)) == typeof(sin)
        @test Taped.get_primal_type(info, GlobalRef(Main, :___x)) == Any
        @test Taped.get_primal_type(info, GlobalRef(Main, :___y)) == Float64
        @test Taped.get_primal_type(info, 5) == Int
        @test Taped.get_primal_type(info, QuoteNode(:hello)) == Symbol
    end
    @testset "make_ad_stmts!" begin

        # Set up ADInfo -- this state is required by `make_ad_stmts!`, and the
        # `LineToADDataMap` object can be mutated.
        id_line_1 = ID()
        id_line_2 = ID()
        info = ADInfo(
            Taped.TInterp(),
            ID(),
            LineToADDataMap(),
            Dict{Argument, Any}(Argument(1) => typeof(sin), Argument(2) => Float64),
            Dict{ID, Any}(id_line_1 => Float64, id_line_2 => Any),
        )

        @testset "Nothing" begin
            @test TestUtils.has_equal_data(
                make_ad_stmts!(nothing, ID(), info),
                ADStmtInfo(nothing, nothing, nothing),
            )
        end
        @testset "ReturnNode" begin
            @test TestUtils.has_equal_data(
                make_ad_stmts!(ReturnNode(), ID(), info),
                ADStmtInfo(ReturnNode(), nothing, nothing),
            )
            @test TestUtils.has_equal_data(
                make_ad_stmts!(ReturnNode(5.0), ID(), info),
                ADStmtInfo(IDGotoNode(info.terminator_block_id), nothing, nothing),
            )
        end
        @testset "IDGotoNode" begin
            stmt = IDGotoNode(ID())
            @test TestUtils.has_equal_data(
                make_ad_stmts!(stmt, ID(), info), ADStmtInfo(stmt, nothing, nothing),
            )
        end
        @testset "IDGotoIfNot" begin
            stmt = IDGotoIfNot(ID(), ID())
            @test TestUtils.has_equal_data(
                make_ad_stmts!(stmt, ID(), info), ADStmtInfo(stmt, nothing, nothing),
            )
        end
        @testset "IDPhiNode" begin
            stmt = IDPhiNode(ID[ID(), ID()], Any[ID(), 5.0])
            @test TestUtils.has_equal_data(
                make_ad_stmts!(stmt, ID(), info), ADStmtInfo(stmt, nothing, nothing),
            )
        end
        @testset "GlobalRef" begin
            @test TestUtils.has_equal_data(
                make_ad_stmts!(GlobalRef(Base, :sin), ID(), info),
                ADStmtInfo(
                    Expr(:call, Taped.zero_codual, GlobalRef(Base, :sin)), nothing, nothing,
                ),
            )
        end
        @testset "QuoteNode" begin
            @test TestUtils.has_equal_data(
                make_ad_stmts!(QuoteNode("hi"), ID(), info),
                ADStmtInfo(QuoteNode(CoDual("hi", NoTangent())), nothing, nothing),
            )
        end
        @testset "literal" begin
            @test TestUtils.has_equal_data(
                make_ad_stmts!(5, ID(), info),
                ADStmtInfo(QuoteNode(CoDual(5, NoTangent())), nothing, nothing),
            )
            @test TestUtils.has_equal_data(
                make_ad_stmts!(0.0, ID(), info),
                ADStmtInfo(QuoteNode(CoDual(0.0, 0.0)), nothing, nothing),
            )
        end
        @testset "PhiCNode" begin
            @test_throws ErrorException make_ad_stmts!(Core.PhiCNode(Any[]), ID(), info)
        end
        @testset "UpsilonNode" begin
            @test_throws ErrorException make_ad_stmts!(Core.UpsilonNode(5), ID(), info)
        end
        @testset "Expr" begin
            @testset "invoke" begin
                stmt = Expr(:invoke, nothing, cos, Argument(2))
                ad_stmts = make_ad_stmts!(stmt, id_line_1, info)
                @test Meta.isexpr(ad_stmts.fwds, :call)
                @test ad_stmts.fwds.args[1] == Taped.fwds_pass!
                @test Meta.isexpr(ad_stmts.rvs, :call)
                @test ad_stmts.rvs.args[1] == Taped.rvs_pass!
                @test hasproperty(ad_stmts.data, :arg_tangent_stacks)
                @test hasproperty(ad_stmts.data, :my_tangent_stack)
                @test hasproperty(ad_stmts.data, :pb_stack)
                @test hasproperty(ad_stmts.data, :rule)
            end
            @testset "throw_undef_if_not" begin
                cond_id = ID()
                expected_fwds = Expr(:call, Taped.__throw_undef_if_not, :x, cond_id)
                @test TestUtils.has_equal_data(
                    make_ad_stmts!(Expr(:throw_undef_if_not, :x, cond_id), ID(), info),
                    ADStmtInfo(expected_fwds, nothing, nothing),
                )
            end
            @testset "$stmt" for stmt in [
                Expr(:boundscheck),
            ]
                @test TestUtils.has_equal_data(
                    make_ad_stmts!(stmt, ID(), info), ADStmtInfo(stmt, nothing, nothing)
                )
            end
        end
    end

end
