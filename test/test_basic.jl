#!/usr/bin/env julia

# Basic test runner without neural networks
using Test
using DataFrames
using Random
using Dates
using Statistics
using LinearAlgebra

println("Loading NumeraiTournament...")
include("../src/NumeraiTournament.jl")
using .NumeraiTournament

Random.seed!(123)

@testset "NumeraiTournament.jl Basic Tests" begin
    
    @testset "Data Preprocessing" begin
        @testset "fillna" begin
            df = DataFrame(a=[1.0, missing, 3.0], b=[missing, 2.0, missing])
            filled = NumeraiTournament.Preprocessor.fillna(df, 0.0)
            @test !any(ismissing, filled.a)
            @test !any(ismissing, filled.b)
            @test filled.a == [1.0, 0.0, 3.0]
        end
        
        @testset "normalize_predictions" begin
            values = [1.0, 2.0, 3.0, 4.0, 5.0]
            normalized = NumeraiTournament.Preprocessor.normalize_predictions(values)
            @test minimum(normalized) >= 0.0
            @test maximum(normalized) <= 1.0
            @test length(normalized) == length(values)
        end
        
        @testset "clip_predictions" begin
            predictions = [0.0, 0.5, 1.0, -0.1, 1.1]
            clipped = NumeraiTournament.Preprocessor.clip_predictions(predictions)
            @test all(0.0001 .<= clipped .<= 0.9999)
        end
        
        @testset "rank_predictions" begin
            values = [1.0, 3.0, 2.0, 4.0, 5.0]
            ranked = NumeraiTournament.Preprocessor.rank_predictions(values)
            @test minimum(ranked) >= 0.0
            @test maximum(ranked) <= 1.0
            @test length(ranked) == length(values)
        end
    end
    
    @testset "Feature Neutralization" begin
        @testset "neutralize" begin
            n = 100
            predictions = randn(n)
            features = randn(n, 10)
            
            neutralized = NumeraiTournament.Neutralization.neutralize(predictions, features, proportion=1.0)
            @test length(neutralized) == n
            
            partial_neutralized = NumeraiTournament.Neutralization.neutralize(predictions, features, proportion=0.5)
            @test length(partial_neutralized) == n
        end
        
        @testset "l2_normalize" begin
            values = [3.0, 4.0]
            normalized = NumeraiTournament.Neutralization.l2_normalize(values)
            @test sqrt(sum(normalized .^ 2)) ≈ 1.0
        end
        
        @testset "orthogonalize" begin
            pred = [1.0, 2.0, 3.0]
            ref = [1.0, 1.0, 1.0]
            ortho = NumeraiTournament.Neutralization.orthogonalize(pred, ref)
            @test abs(LinearAlgebra.dot(ortho, ref)) < 1e-10
        end
    end
    
    @testset "API Schemas" begin
        @testset "Round struct" begin
            round = NumeraiTournament.Schemas.Round(
                570,
                DateTime(2024, 1, 1),
                DateTime(2024, 1, 3),
                DateTime(2024, 1, 24),
                true
            )
            @test round.number == 570
            @test round.is_active == true
        end
        
        @testset "ModelPerformance struct" begin
            perf = NumeraiTournament.Schemas.ModelPerformance(
                "model_1",
                "Test Model",
                0.02,
                0.01,
                0.015,
                0.005,
                1.5,
                100.0
            )
            @test perf.corr == 0.02
            @test perf.sharpe == 1.5
        end
    end
    
    @testset "Data Loader" begin
        @testset "create_submission_dataframe" begin
            ids = ["id1", "id2", "id3"]
            predictions = [0.1, 0.5, 0.9]
            
            submission = NumeraiTournament.DataLoader.create_submission_dataframe(ids, predictions)
            @test size(submission) == (3, 2)
            @test names(submission) == ["id", "prediction"]
            @test submission.prediction == predictions
        end
        
        @testset "get_era_column" begin
            df = DataFrame(
                era = [1, 1, 2, 2, 3, 3],
                value = rand(6)
            )
            
            eras = NumeraiTournament.DataLoader.get_era_column(df)
            @test length(eras) == 6
            @test all(eras .∈ [[1, 2, 3]])
        end
    end
    
    @testset "Charts" begin
        @testset "format_correlation_bar" begin
            bar = NumeraiTournament.Charts.format_correlation_bar(0.05, width=10)
            @test occursin("█", bar)
            @test occursin("0.05", bar)
        end
        
        @testset "create_mini_chart" begin
            values = [1.0, 2.0, 3.0, 2.0, 1.0]
            chart = NumeraiTournament.Charts.create_mini_chart(values, width=5)
            @test length(chart) == 5
        end
    end
    
    @testset "System Utilities" begin
        @testset "format_uptime" begin
            @test NumeraiTournament.Panels.format_uptime(90) == "1m"
            @test NumeraiTournament.Panels.format_uptime(3661) == "1h 1m"
            @test NumeraiTournament.Panels.format_uptime(90061) == "1d 1h 1m"
        end
        
        @testset "create_progress_bar" begin
            bar = NumeraiTournament.Panels.create_progress_bar(50, 100, width=10)
            @test occursin("█", bar)
            @test occursin("░", bar)
            @test length(bar) == 10
        end
    end
    
    @testset "Configuration" begin
        @testset "load_config with env vars" begin
            ENV["NUMERAI_PUBLIC_ID"] = "test_public"
            ENV["NUMERAI_SECRET_KEY"] = "test_secret"
            
            config = NumeraiTournament.load_config("nonexistent.toml")
            @test config.api_public_key == "test_public"
            @test config.api_secret_key == "test_secret"
            @test config.auto_submit == true
        end
    end
    
    @testset "ML Models" begin
        @testset "XGBoostModel creation" begin
            model = NumeraiTournament.Models.XGBoostModel("test_xgb")
            @test model.name == "test_xgb"
            @test model.params["objective"] == "reg:squarederror"
            @test model.num_rounds == 1000
        end
        
        @testset "LightGBMModel creation" begin
            model = NumeraiTournament.Models.LightGBMModel("test_lgbm")
            @test model.name == "test_lgbm"
            @test model.params["objective"] == "regression"
            @test model.params["metric"] == "rmse"
        end
        
        @testset "EvoTreesModel creation" begin
            model = NumeraiTournament.Models.EvoTreesModel("test_evotrees")
            @test model.name == "test_evotrees"
            @test model.params["loss"] == :mse
            @test model.params["metric"] == :mse
            @test model.params["max_depth"] == 5
            @test model.params["eta"] == 0.01
        end
    end
    
    @testset "Ensemble" begin
        @testset "ModelEnsemble creation" begin
            models = [
                NumeraiTournament.Models.XGBoostModel("xgb1"),
                NumeraiTournament.Models.LightGBMModel("lgbm1"),
                NumeraiTournament.Models.EvoTreesModel("evotrees1")
            ]
            
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(models)
            @test length(ensemble.models) == 3
            @test sum(ensemble.weights) ≈ 1.0
        end
        
        @testset "diversity_score" begin
            predictions_matrix = rand(100, 3)
            diversity = NumeraiTournament.Ensemble.diversity_score(predictions_matrix)
            @test 0 <= diversity <= 1
        end
    end
    
end

println("\n✅ All basic tests passed!")