using Test
using NumeraiTournament
using DataFrames
using Random
using Dates
using Statistics
using LinearAlgebra

Random.seed!(123)

@testset "NumeraiTournament.jl Tests" begin
    
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
    
    @testset "Neural Network Models" begin
        @testset "MLPModel creation" begin
            model = NumeraiTournament.MLPModel("test_mlp", gpu_enabled=false)
            @test model.name == "test_mlp"
            @test model isa NumeraiTournament.NeuralNetworkModel
            @test model.params["hidden_layers"] == [256, 128, 64]
            @test model.gpu_enabled == false
        end
        
        @testset "ResNetModel creation" begin
            model = NumeraiTournament.ResNetModel("test_resnet", gpu_enabled=false)
            @test model.name == "test_resnet"
            @test model isa NumeraiTournament.NeuralNetworkModel
            @test model.params["hidden_layers"] == [256, 256, 256, 128]
        end
        
        @testset "TabNetModel creation" begin
            model = NumeraiTournament.TabNetModel("test_tabnet", gpu_enabled=false)
            @test model.name == "test_tabnet"
            @test model isa NumeraiTournament.NeuralNetworkModel
            @test model.params["n_d"] == 64
            @test model.params["n_a"] == 64
        end
    end
    
    @testset "ML Pipeline" begin
        @testset "ModelConfig for neural networks" begin
            # Test neural network model configs
            mlp_config = NumeraiTournament.Pipeline.ModelConfig("mlp", 
                Dict(:hidden_layers=>[128, 64], :epochs=>5), name="test_mlp")
            @test mlp_config.type == "mlp"
            @test mlp_config.name == "test_mlp"
            @test mlp_config.params[:hidden_layers] == [128, 64]
            
            resnet_config = NumeraiTournament.Pipeline.ModelConfig("resnet",
                Dict(:hidden_layers=>[64, 64], :epochs=>5), name="test_resnet")  
            @test resnet_config.type == "resnet"
            @test resnet_config.name == "test_resnet"
            
            tabnet_config = NumeraiTournament.Pipeline.ModelConfig("tabnet",
                Dict(:n_d=>32, :n_a=>32, :epochs=>5), name="test_tabnet")
            @test tabnet_config.type == "tabnet"
            @test tabnet_config.name == "test_tabnet"
        end
        
        @testset "Default pipeline includes neural networks" begin
            feature_cols = ["feature_$(i)" for i in 1:10]
            pipeline = NumeraiTournament.Pipeline.MLPipeline(
                feature_cols=feature_cols,
                target_col="target_cyrus_v4_20"
            )
            
            # Should include both traditional ML models and neural networks
            @test length(pipeline.models) == 6  # 4 traditional + 2 neural networks
            @test any(model -> model isa NumeraiTournament.MLPModel, pipeline.models)
            @test any(model -> model isa NumeraiTournament.ResNetModel, pipeline.models)
            @test any(model -> model isa NumeraiTournament.XGBoostModel, pipeline.models)
            @test any(model -> model isa NumeraiTournament.LightGBMModel, pipeline.models)
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
        
        @testset "Ensemble with neural networks" begin
            models = [
                NumeraiTournament.Models.XGBoostModel("xgb1"),
                NumeraiTournament.MLPModel("mlp1", gpu_enabled=false)
            ]
            
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(models)
            @test length(ensemble.models) == 2
            @test sum(ensemble.weights) ≈ 1.0
            @test any(model -> model isa NumeraiTournament.NeuralNetworkModel, ensemble.models)
        end
        
        @testset "diversity_score" begin
            predictions_matrix = rand(100, 3)
            diversity = NumeraiTournament.Ensemble.diversity_score(predictions_matrix)
            @test 0 <= diversity <= 1
        end
    end
    
    @testset "Notifications" begin
        if Sys.isapple()
            @testset "macOS notification" begin
                NumeraiTournament.Notifications.send_notification("Test", "Test message", :info)
                @test true
            end
        end
    end
    
    # Include MMC metrics tests
    include("test_metrics.jl")
    
    # Include cron scheduler tests
    include("test_cron_scheduler.jl")
    
    # Include dashboard commands tests
    include("test_dashboard_commands.jl")
    
    # Include compounding module tests
    include("test_compounding.jl")
    
    # Include retry logic tests
    include("test_retry.jl")
    
end

println("\n✅ All tests passed!")

# Run end-to-end tests
include("test_e2e.jl")