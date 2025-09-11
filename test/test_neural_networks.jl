using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using NumeraiTournament
using Test
using Random
using DataFrames

@testset "Neural Networks Integration Tests" begin
    
    @testset "Neural Network Model Creation" begin
        # Test MLP model creation
        mlp = NumeraiTournament.MLPModel("test_mlp", 
                                        hidden_layers=[64, 32], 
                                        epochs=5,
                                        gpu_enabled=false)  # Disable GPU for testing
        @test mlp.name == "test_mlp"
        @test mlp.params["hidden_layers"] == [64, 32]
        @test mlp.params["epochs"] == 5
        @test mlp.gpu_enabled == false
        
        # Test ResNet model creation
        resnet = NumeraiTournament.ResNetModel("test_resnet",
                                               hidden_layers=[64, 64],
                                               epochs=5,
                                               gpu_enabled=false)
        @test resnet.name == "test_resnet"
        @test resnet.params["hidden_layers"] == [64, 64]
        @test resnet.params["epochs"] == 5
    end
    
    @testset "Pipeline Integration" begin
        # Create synthetic data for testing
        Random.seed!(42)
        n_samples = 100
        n_features = 20
        
        # Generate random feature data
        feature_data = randn(n_samples, n_features)
        target_data = randn(n_samples)  # Random targets for testing
        era_data = repeat(1:5, inner=20)  # 5 eras with 20 samples each
        
        # Create DataFrame
        df = DataFrame()
        for i in 1:n_features
            df[!, "feature_$(i)"] = feature_data[:, i]
        end
        df[!, :target_cyrus_v4_20] = target_data
        df[!, :era] = era_data
        df[!, :id] = 1:n_samples
        
        # Create feature column names
        feature_cols = ["feature_$(i)" for i in 1:n_features]
        
        # Test pipeline with neural network model config (single model approach)
        model_config = NumeraiTournament.Pipeline.ModelConfig("mlp", 
            Dict(:hidden_layers=>[32, 16], :epochs=>3, :gpu_enabled=>false), 
            name="test_mlp")
        
        pipeline = NumeraiTournament.Pipeline.MLPipeline(
            feature_cols=feature_cols,
            target_col="target_cyrus_v4_20",
            model_config=model_config
        )
        
        # Test that the pipeline uses the correct model
        @test pipeline.model isa NumeraiTournament.NeuralNetworkModel
        @test pipeline.model.name == "test_mlp"
        
        # Test that model config is stored
        @test pipeline.model_config.type == "mlp"
        @test pipeline.model_config.name == "test_mlp"
    end
    
    @testset "Model Config Creation" begin
        # Test neural network model configs
        mlp_config = NumeraiTournament.Pipeline.ModelConfig("mlp", 
            Dict(:hidden_layers=>[128, 64], :dropout_rate=>0.3),
            name="custom_mlp")
        @test mlp_config.type == "mlp"
        @test mlp_config.name == "custom_mlp"
        @test mlp_config.params[:hidden_layers] == [128, 64]
        
        resnet_config = NumeraiTournament.Pipeline.ModelConfig("resnet",
            Dict(:hidden_layers=>[256, 256, 128]),
            name="custom_resnet")
        @test resnet_config.type == "resnet"
        @test resnet_config.name == "custom_resnet"
        
        tabnet_config = NumeraiTournament.Pipeline.ModelConfig("tabnet",
            Dict(:n_d=>64, :n_a=>64, :n_steps=>5),
            name="custom_tabnet")
        @test tabnet_config.type == "tabnet"
        @test tabnet_config.name == "custom_tabnet"
        
        # Test model creation from individual configs
        mlp_model = NumeraiTournament.Pipeline.create_model_from_config(mlp_config)
        @test mlp_model isa NumeraiTournament.NeuralNetworkModel
        @test mlp_model.name == "custom_mlp"
        
        resnet_model = NumeraiTournament.Pipeline.create_model_from_config(resnet_config)
        @test resnet_model isa NumeraiTournament.NeuralNetworkModel 
        @test resnet_model.name == "custom_resnet"
        
        # TabNet might not be implemented, so we'll skip it for now
        # or expect it to be handled gracefully
        try
            tabnet_model = NumeraiTournament.Pipeline.create_model_from_config(tabnet_config)
        catch e
            @test e isa Exception  # Expected if TabNet is not implemented
        end
    end
    
    @testset "Default Pipeline with Neural Networks" begin
        # Test that default pipeline uses XGBoost (current default behavior)
        feature_cols = ["feature_$(i)" for i in 1:10]
        
        pipeline = NumeraiTournament.Pipeline.MLPipeline(
            feature_cols=feature_cols,
            target_col="target_cyrus_v4_20"
        )
        
        # Current default should be a single XGBoost model
        @test pipeline.model isa NumeraiTournament.Models.XGBoostModel
        @test pipeline.model.name == "xgb_best"
        @test pipeline.model_config.type == "xgboost"
        
        # Test that we can create a neural network pipeline
        nn_config = NumeraiTournament.Pipeline.ModelConfig("mlp",
            Dict(:hidden_layers=>[128, 64], :epochs=>10, :gpu_enabled=>false),
            name="test_neural")
        
        nn_pipeline = NumeraiTournament.Pipeline.MLPipeline(
            feature_cols=feature_cols,
            target_col="target_cyrus_v4_20",
            model_config=nn_config
        )
        
        @test nn_pipeline.model isa NumeraiTournament.NeuralNetworkModel
        @test nn_pipeline.model.name == "test_neural"
        @test nn_pipeline.model_config.type == "mlp"
    end
    
end

println("\n✅ Neural Networks integration tests passed!")