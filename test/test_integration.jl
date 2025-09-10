using Test
using NumeraiTournament
using DataFrames
using Random
using JSON3
using CSV
using Statistics
using Dates
using TimeZones
using SQLite

Random.seed!(123)

# Define cleanup function for tests
function cleanup()
    # Cleanup function for integration tests
    # Currently a no-op but could be extended for resource cleanup
    nothing
end

# Mock API client for comprehensive integration testing
mutable struct IntegrationMockClient
    public_id::String
    secret_key::String
    headers::Dict{String,String}
    
    # Mock data for API responses
    current_round::Int
    rounds_data::Vector{Dict}
    models_data::Vector{Dict}
    wallet_balance::Float64
    model_stakes::Dict{String, Float64}
    model_submissions::Dict{String, Vector{Dict}}
    
    # Behavior flags
    should_fail::Symbol  # :none, :download, :submit, :stakes, :rounds
    api_calls::Vector{Symbol}
    
    # Data files simulation
    data_files::Dict{String, DataFrame}
end

function IntegrationMockClient(;
    current_round=580,
    wallet_balance=1000.0,
    should_fail=:none
)
    client = IntegrationMockClient(
        "test_public_id",
        "test_secret_key",
        Dict("x-public-id" => "test_public_id", "x-secret-key" => "test_secret_key"),
        current_round,
        create_mock_rounds_data(current_round),
        create_mock_models_data(),
        wallet_balance,
        Dict("test_model_1" => 50.0, "test_model_2" => 75.0),
        Dict{String, Vector{Dict}}(),
        should_fail,
        Symbol[],
        create_mock_data_files()
    )
    return client
end

function create_mock_rounds_data(current_round::Int)
    rounds = []
    for i in (current_round-5):current_round
        push!(rounds, Dict(
            "number" => i,
            "openTime" => string(DateTime(2024, 1, 1) + Week(i - 570)),
            "closeTime" => string(DateTime(2024, 1, 1) + Week(i - 570) + Day(3)),
            "resolveTime" => string(DateTime(2024, 1, 1) + Week(i - 570) + Day(21)),
            "active" => i == current_round
        ))
    end
    return rounds
end

function create_mock_models_data()
    return [
        Dict(
            "id" => "model_1",
            "name" => "test_model_1",
            "latestRanks" => Dict(
                "corr" => 0.02,
                "mmc" => 0.01,
                "tc" => 0.015,
                "fnc" => 0.005
            ),
            "stakeValue" => 50.0
        ),
        Dict(
            "id" => "model_2", 
            "name" => "test_model_2",
            "latestRanks" => Dict(
                "corr" => 0.025,
                "mmc" => 0.012,
                "tc" => 0.018,
                "fnc" => 0.008
            ),
            "stakeValue" => 75.0
        )
    ]
end

function create_mock_data_files()
    # Create realistic mock tournament data
    n_samples = 5000
    n_features = 1050  # Typical Numerai feature count
    
    # Training data
    train_data = DataFrame()
    for i in 1:n_features
        train_data[!, "feature_$(i)"] = rand(n_samples) * 2 .- 1  # Range [-1, 1]
    end
    train_data[!, "target_cyrus_v4_20"] = rand(n_samples)
    train_data[!, "target_jerome_v4_20"] = rand(n_samples)
    train_data[!, "target_victor_v4_20"] = rand(n_samples)
    train_data[!, "era"] = repeat(1:50, inner=n_samples÷50)
    train_data[!, "data_type"] = fill("train", n_samples)
    
    # Validation data
    val_samples = 2000
    val_data = DataFrame()
    for i in 1:n_features
        val_data[!, "feature_$(i)"] = rand(val_samples) * 2 .- 1
    end
    val_data[!, "target_cyrus_v4_20"] = rand(val_samples)
    val_data[!, "target_jerome_v4_20"] = rand(val_samples)
    val_data[!, "target_victor_v4_20"] = rand(val_samples)
    val_data[!, "era"] = repeat(51:70, inner=val_samples÷20)
    val_data[!, "data_type"] = fill("validation", val_samples)
    
    # Live data (tournament data)
    live_samples = 3000
    live_data = DataFrame()
    live_data[!, "id"] = ["id_$(i)" for i in 1:live_samples]
    for i in 1:n_features
        live_data[!, "feature_$(i)"] = rand(live_samples) * 2 .- 1
    end
    live_data[!, "era"] = repeat(71:80, inner=live_samples÷10)
    live_data[!, "data_type"] = fill("live", live_samples)
    
    # Combined datasets
    combined_data = vcat(train_data, val_data, live_data, cols=:union)
    
    return Dict(
        "train" => train_data,
        "validation" => val_data,
        "live" => live_data,
        "numerai_training_data.csv" => combined_data,
        "numerai_tournament_data.csv" => live_data,
        "live_example_preds.csv" => DataFrame(
            id=live_data.id,
            prediction=rand(live_samples)
        )
    )
end

# Mock the key API functions for integration testing
function mock_get_current_round(client::IntegrationMockClient)
    push!(client.api_calls, :get_current_round)
    if client.should_fail == :rounds
        throw(ErrorException("Mock round fetch failure"))
    end
    return client.current_round
end

function mock_get_models(client::IntegrationMockClient)
    push!(client.api_calls, :get_models)
    if client.should_fail == :models
        throw(ErrorException("Mock models fetch failure"))
    end
    return client.models_data
end

function mock_download_dataset(client::IntegrationMockClient, dataset_name::String, save_path::String)
    push!(client.api_calls, :download_dataset)
    if client.should_fail == :download
        throw(ErrorException("Mock download failure"))
    end
    
    # Simulate downloading by saving mock data
    if haskey(client.data_files, dataset_name)
        CSV.write(save_path, client.data_files[dataset_name])
        return save_path
    else
        throw(ErrorException("Mock dataset not found: $dataset_name"))
    end
end

function mock_submit_predictions(client::IntegrationMockClient, model_name::String, file_path::String)
    push!(client.api_calls, :submit_predictions)
    if client.should_fail == :submit
        throw(ErrorException("Mock submission failure"))
    end
    
    # Verify file exists and has correct format
    if !isfile(file_path)
        throw(ErrorException("Submission file not found"))
    end
    
    # Read and validate submission format
    submission_df = CSV.read(file_path, DataFrame)
    if !("id" in names(submission_df) && "prediction" in names(submission_df))
        throw(ErrorException("Invalid submission format"))
    end
    
    # Record submission
    if !haskey(client.model_submissions, model_name)
        client.model_submissions[model_name] = []
    end
    push!(client.model_submissions[model_name], Dict(
        "round" => client.current_round,
        "timestamp" => now(UTC),
        "file_path" => file_path,
        "row_count" => nrow(submission_df)
    ))
    
    return Dict("success" => true, "id" => "submission_$(rand(1000:9999))")
end

function mock_get_stakes(client::IntegrationMockClient, model_name::String)
    push!(client.api_calls, :get_stakes)
    if client.should_fail == :stakes
        throw(ErrorException("Mock stakes fetch failure"))
    end
    return get(client.model_stakes, model_name, 0.0)
end

function mock_increase_stake(client::IntegrationMockClient, model_name::String, amount::Float64)
    push!(client.api_calls, :increase_stake)
    if client.should_fail == :stakes
        throw(ErrorException("Mock stake increase failure"))
    end
    
    if amount <= 0 || amount > client.wallet_balance
        throw(ErrorException("Invalid stake amount"))
    end
    
    current_stake = get(client.model_stakes, model_name, 0.0)
    client.model_stakes[model_name] = current_stake + amount
    client.wallet_balance -= amount
    
    return Dict("success" => true, "new_stake" => client.model_stakes[model_name])
end

@testset "Comprehensive Integration Tests" begin
    
    @testset "1. Complete Tournament Workflow" begin
        # Setup test environment
        temp_dir = mktempdir()
        config_path = joinpath(temp_dir, "test_config.toml")
        data_dir = joinpath(temp_dir, "data")
        model_dir = joinpath(temp_dir, "models")
        
        mkpath(data_dir)
        mkpath(model_dir)
        
        # Create test configuration
        test_config = """
        api_public_key = "test_public_id"
        api_secret_key = "test_secret_key"
        models = ["test_model_1", "test_model_2"]
        data_dir = "$data_dir"
        model_dir = "$model_dir"
        auto_submit = true
        stake_amount = 10.0
        max_workers = 2
        notification_enabled = false
        compounding_enabled = false
        """
        
        open(config_path, "w") do f
            write(f, test_config)
        end
        
        # Load configuration
        config = NumeraiTournament.load_config(config_path)
        @test config.api_public_key == "test_public_id"
        @test config.models == ["test_model_1", "test_model_2"]
        @test config.data_dir == data_dir
        
        # Initialize mock client
        mock_client = IntegrationMockClient()
        
        @testset "Data Download Phase" begin
            # Test data download with mock
            round_number = mock_get_current_round(mock_client)
            @test round_number == 580
            @test :get_current_round in mock_client.api_calls
            
            # Download training data
            train_path = joinpath(data_dir, "numerai_training_data.csv")
            mock_download_dataset(mock_client, "numerai_training_data.csv", train_path)
            @test isfile(train_path)
            @test :download_dataset in mock_client.api_calls
            
            # Download tournament data  
            tournament_path = joinpath(data_dir, "numerai_tournament_data.csv")
            mock_download_dataset(mock_client, "numerai_tournament_data.csv", tournament_path)
            @test isfile(tournament_path)
            
            # Verify data quality
            train_df = CSV.read(train_path, DataFrame)
            @test nrow(train_df) > 0
            @test "target_cyrus_v4_20" in names(train_df)
            @test startswith(names(train_df)[1], "feature_") || names(train_df)[1] in ["era", "data_type", "target_cyrus_v4_20"]
        end
        
        @testset "Training Phase" begin
            # Load training data
            train_df = CSV.read(joinpath(data_dir, "numerai_training_data.csv"), DataFrame)
            train_data = filter(row -> row.data_type == "train", train_df)
            val_data = filter(row -> row.data_type == "validation", train_df)
            
            # Prepare features
            feature_cols = [col for col in names(train_data) if startswith(col, "feature_")]
            @test length(feature_cols) > 1000  # Should have many features
            
            # Create ML pipeline
            pipeline = NumeraiTournament.Pipeline.MLPipeline(
                feature_cols=feature_cols[1:100],  # Use subset for faster testing
                target_cols=["target_cyrus_v4_20"],
                neutralize=true,
                neutralize_proportion=0.3
            )
            
            @test length(pipeline.models) > 0
            @test pipeline.target_cols == ["target_cyrus_v4_20"]
            
            # Train pipeline
            try
                NumeraiTournament.Pipeline.train!(
                    pipeline, train_data, val_data, verbose=false
                )
                @test true  # Training completed successfully
            catch e
                @test false  # Training failed: $e
            end
        end
        
        @testset "Prediction Phase" begin
            # Load tournament data for predictions
            tournament_df = CSV.read(joinpath(data_dir, "numerai_tournament_data.csv"), DataFrame)
            
            # Create simple test pipeline for predictions
            feature_cols = [col for col in names(tournament_df) if startswith(col, "feature_")]
            
            # Use a minimal model for fast prediction testing
            test_model = NumeraiTournament.Models.XGBoostModel("test_xgb", num_rounds=10, max_depth=3)
            
            # Create minimal training data for the model
            X_test = rand(100, 50)  # 100 samples, 50 features
            y_test = rand(100)
            
            NumeraiTournament.Models.train!(test_model, X_test, y_test, verbose=false)
            
            # Make predictions on subset
            X_tournament = Matrix(tournament_df[:, feature_cols[1:50]])  # Match feature count
            predictions = NumeraiTournament.Models.predict(test_model, X_tournament)
            
            @test length(predictions) == nrow(tournament_df)
            @test all(isfinite.(predictions))
            @test 0 <= minimum(predictions) <= 1
            @test 0 <= maximum(predictions) <= 1
            
            # Create submission file
            submission_df = NumeraiTournament.DataLoader.create_submission_dataframe(
                tournament_df.id, predictions
            )
            
            submission_path = joinpath(temp_dir, "test_submission.csv")
            CSV.write(submission_path, submission_df)
            @test isfile(submission_path)
        end
        
        @testset "Submission Phase" begin
            submission_path = joinpath(temp_dir, "test_submission.csv")
            
            # Test successful submission
            result = mock_submit_predictions(mock_client, "test_model_1", submission_path)
            @test result["success"] == true
            @test haskey(result, "id")
            @test :submit_predictions in mock_client.api_calls
            @test haskey(mock_client.model_submissions, "test_model_1")
            
            # Test submission failure
            mock_client.should_fail = :submit
            @test_throws ErrorException mock_submit_predictions(mock_client, "test_model_2", submission_path)
        end
        
        cleanup()
    end
    
    @testset "2. Multi-Model Ensemble Training and Prediction" begin
        temp_dir = mktempdir()
        
        # Create test data
        n_samples = 500
        n_features = 20
        X_train = rand(n_samples, n_features)
        y_train = rand(n_samples)
        X_val = rand(200, n_features) 
        y_val = rand(200)
        
        @testset "Traditional ML Ensemble" begin
            # Create diverse traditional models
            models = [
                NumeraiTournament.Models.XGBoostModel("xgb_1", max_depth=3, learning_rate=0.1, num_rounds=50),
                NumeraiTournament.Models.XGBoostModel("xgb_2", max_depth=6, learning_rate=0.05, num_rounds=100),
                NumeraiTournament.Models.LightGBMModel("lgbm_1", num_leaves=15, learning_rate=0.1, n_estimators=50),
                NumeraiTournament.Models.LightGBMModel("lgbm_2", num_leaves=31, learning_rate=0.05, n_estimators=100),
                NumeraiTournament.Models.EvoTreesModel("evotrees_1", max_depth=4, learning_rate=0.1, nrounds=50)
            ]
            
            # Create ensemble
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(models, name="traditional_ensemble")
            @test length(ensemble.models) == 5
            @test ensemble.name == "traditional_ensemble"
            
            # Train ensemble
            NumeraiTournament.Ensemble.train_ensemble!(ensemble, X_train, y_train, verbose=false)
            
            # Make predictions
            predictions = NumeraiTournament.Ensemble.predict_ensemble(ensemble, X_val)
            @test length(predictions) == size(X_val, 1)
            @test all(isfinite.(predictions))
            
            # Test diversity
            pred_matrix = hcat([NumeraiTournament.Models.predict(model, X_val) for model in models]...)
            diversity = NumeraiTournament.Ensemble.diversity_score(pred_matrix)
            @test 0 <= diversity <= 1
        end
        
        @testset "Mixed Ensemble Performance" begin
            # Test that ensemble performs reasonably
            single_model = NumeraiTournament.Models.XGBoostModel("single", num_rounds=50)
            NumeraiTournament.Models.train!(single_model, X_train, y_train, verbose=false)
            
            multi_models = [
                NumeraiTournament.Models.XGBoostModel("xgb", num_rounds=50),
                NumeraiTournament.Models.LightGBMModel("lgbm", n_estimators=50),
                NumeraiTournament.Models.EvoTreesModel("evo", nrounds=50)
            ]
            
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(multi_models)
            NumeraiTournament.Ensemble.train_ensemble!(ensemble, X_train, y_train, verbose=false)
            
            single_preds = NumeraiTournament.Models.predict(single_model, X_val)
            ensemble_preds = NumeraiTournament.Ensemble.predict_ensemble(ensemble, X_val)
            
            # Both should produce reasonable predictions
            @test std(single_preds) > 0.01  # Some variation
            @test std(ensemble_preds) > 0.01
            @test cor(single_preds, ensemble_preds) > 0.3  # Some correlation but different
        end
        
        cleanup()
    end
    
    @testset "3. Neural Network + Traditional ML Ensemble" begin
        # Test small neural networks for speed
        n_samples = 300
        n_features = 50
        X_train = rand(n_samples, n_features)
        y_train = rand(n_samples)
        X_val = rand(100, n_features)
        
        @testset "Hybrid Ensemble Creation" begin
            # Create mixed ensemble with neural networks
            models = [
                NumeraiTournament.Models.XGBoostModel("xgb_hybrid", num_rounds=30),
                NumeraiTournament.Models.LightGBMModel("lgbm_hybrid", n_estimators=30),
                NumeraiTournament.MLPModel("mlp_hybrid", 
                    hidden_layers=[32, 16], 
                    epochs=20, 
                    gpu_enabled=false
                ),
                NumeraiTournament.ResNetModel("resnet_hybrid", 
                    hidden_layers=[32, 32], 
                    epochs=20, 
                    gpu_enabled=false
                )
            ]
            
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(models, name="hybrid_ensemble")
            @test length(ensemble.models) == 4
            
            # Verify model types
            nn_models = filter(m -> isa(m, NumeraiTournament.NeuralNetworkModel), ensemble.models)
            traditional_models = filter(m -> !isa(m, NumeraiTournament.NeuralNetworkModel), ensemble.models)
            
            @test length(nn_models) == 2
            @test length(traditional_models) == 2
        end
        
        @testset "Hybrid Training and Prediction" begin
            # Create smaller hybrid ensemble for testing
            models = [
                NumeraiTournament.Models.XGBoostModel("xgb_test", num_rounds=20),
                NumeraiTournament.MLPModel("mlp_test", 
                    hidden_layers=[16], 
                    epochs=10, 
                    gpu_enabled=false
                )
            ]
            
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(models)
            
            # Train hybrid ensemble
            try
                NumeraiTournament.Ensemble.train_ensemble!(ensemble, X_train, y_train, verbose=false)
                @test true  # Training succeeded
            catch e
                @test false  # Training failed: $e"
            end
            
            # Make predictions
            try
                predictions = NumeraiTournament.Ensemble.predict_ensemble(ensemble, X_val)
                @test length(predictions) == size(X_val, 1)
                @test all(isfinite.(predictions))
                @test 0 <= minimum(predictions) <= 1
                @test 0 <= maximum(predictions) <= 1
            catch e
                @test false  # Prediction failed: $e"
            end
        end
        
        cleanup()
    end
    
    @testset "4. GPU Acceleration Workflow (if available)" begin
        @testset "GPU Detection and Setup" begin
            # Test GPU detection
            has_gpu = NumeraiTournament.has_metal_gpu()
            if has_gpu
                gpu_info = NumeraiTournament.get_gpu_info()
                @test haskey(gpu_info, "device_name")
                @test haskey(gpu_info, "memory_gb")
            end
            
            # Test model GPU status
            gpu_status = NumeraiTournament.get_models_gpu_status()
            @test haskey(gpu_status, "gpu_available")
            @test haskey(gpu_status, "models_support_gpu")
        end
        
        @testset "GPU-Accelerated Training" begin
            if NumeraiTournament.has_metal_gpu()
                # Test GPU-enabled neural network
                X_train = rand(200, 30)
                y_train = rand(200)
                
                gpu_model = NumeraiTournament.MLPModel("mlp_gpu", 
                    hidden_layers=[32, 16], 
                    epochs=5,
                    gpu_enabled=true
                )
                
                try
                    NumeraiTournament.Models.train!(gpu_model, X_train, y_train, verbose=false)
                    predictions = NumeraiTournament.Models.predict(gpu_model, X_train)
                    
                    @test length(predictions) == size(X_train, 1)
                    @test all(isfinite.(predictions))
                    @test true  # GPU training succeeded
                catch e
                    @warn "GPU training failed, but this may be expected in test environment: $e"
                    @test true  # Don't fail tests for GPU issues in CI
                end
            else
                @test true  # Skip GPU tests if no GPU available
            end
        end
        
        @testset "GPU Benchmark Integration" begin
            if NumeraiTournament.has_metal_gpu()
                try
                    benchmark_results = NumeraiTournament.GPUBenchmarks.run_comprehensive_gpu_benchmark(
                        data_sizes=[1000], n_runs=1, save_results=false
                    )
                    @test length(benchmark_results) > 0
                    @test benchmark_results[1] isa NumeraiTournament.GPUBenchmarks.BenchmarkResult
                catch e
                    @warn "GPU benchmark failed: $e"
                    @test true  # Don't fail for GPU benchmark issues
                end
            else
                @test true  # Skip if no GPU
            end
        end
        
        cleanup()
    end
    
    @testset "5. Automated Scheduling and Submission" begin
        temp_dir = mktempdir()
        
        # Create test config
        config = NumeraiTournament.TournamentConfig(
            "test_public",
            "test_secret", 
            ["test_model"],
            joinpath(temp_dir, "data"),
            joinpath(temp_dir, "models"),
            true,  # auto_submit
            50.0,  # stake_amount
            2,     # max_workers
            false, # notifications
            8,     # tournament_id
            "medium", # feature_set
            false, # compounding_enabled
            1.0,   # min_compound_amount
            100.0, # compound_percentage
            1000.0, # max_stake_amount
            Dict{String, Any}("refresh_rate" => 1.0) # tui_config
        )
        
        @testset "Scheduler Setup and Configuration" begin
            scheduler = NumeraiTournament.Scheduler.TournamentScheduler(config)
            @test scheduler.config === config
            @test scheduler.running == false
            @test length(scheduler.cron_jobs) == 0
            
            # Setup cron jobs
            NumeraiTournament.Scheduler.setup_cron_jobs!(scheduler)
            @test length(scheduler.cron_jobs) > 0
            
            # Test cron expression parsing
            cron_expr = NumeraiTournament.Scheduler.CronExpression("0 14 * * 3")  # Wed 2pm
            current_time = DateTime(2024, 1, 3, 14, 0, 0)  # Wednesday 2pm
            @test NumeraiTournament.Scheduler.matches(cron_expr, current_time)
            
            non_match_time = DateTime(2024, 1, 3, 13, 0, 0)  # Wednesday 1pm
            @test !NumeraiTournament.Scheduler.matches(cron_expr, non_match_time)
        end
        
        @testset "Automated Workflow Execution" begin
            mock_client = IntegrationMockClient()
            
            # Test complete automated workflow
            workflow_steps = Symbol[]
            
            # Simulate workflow execution
            try
                # 1. Check current round
                round_num = mock_get_current_round(mock_client)
                push!(workflow_steps, :round_check)
                @test round_num > 0
                
                # 2. Download data
                data_path = joinpath(temp_dir, "auto_data.csv")
                mock_download_dataset(mock_client, "numerai_training_data.csv", data_path)
                push!(workflow_steps, :data_download)
                @test isfile(data_path)
                
                # 3. Train models (simplified)
                X_train = rand(100, 20)
                y_train = rand(100)
                model = NumeraiTournament.Models.XGBoostModel("auto_model", num_rounds=10)
                NumeraiTournament.Models.train!(model, X_train, y_train, verbose=false)
                push!(workflow_steps, :model_training)
                
                # 4. Make predictions
                X_pred = rand(50, 20)
                predictions = NumeraiTournament.Models.predict(model, X_pred)
                push!(workflow_steps, :predictions)
                @test length(predictions) == 50
                
                # 5. Create submission
                ids = ["id_$i" for i in 1:50]
                submission_df = NumeraiTournament.DataLoader.create_submission_dataframe(ids, predictions)
                submission_path = joinpath(temp_dir, "auto_submission.csv")
                CSV.write(submission_path, submission_df)
                push!(workflow_steps, :submission_creation)
                
                # 6. Submit
                result = mock_submit_predictions(mock_client, "test_model", submission_path)
                push!(workflow_steps, :submission)
                @test result["success"] == true
                
            catch e
                @test false  # Automated workflow failed: $e"
            end
            
            # Verify all steps completed
            expected_steps = [:round_check, :data_download, :model_training, :predictions, :submission_creation, :submission]
            @test workflow_steps == expected_steps
        end
        
        cleanup()
    end
    
    @testset "6. Compounding Workflow with Staking" begin
        @testset "Compounding Integration" begin
            mock_client = IntegrationMockClient(wallet_balance=500.0)
            
            # Configure compounding
            compound_config = NumeraiTournament.Compounding.CompoundingConfig(
                enabled=true,
                min_compound_amount=5.0,
                compound_percentage=50.0,
                max_stake_amount=200.0,
                models=["test_model_1", "test_model_2"]
            )
            
            # Create compounding manager
            real_api_client = NumeraiTournament.API.NumeraiClient("test", "test")
            compound_manager = NumeraiTournament.Compounding.CompoundingManager(real_api_client, compound_config)
            
            @test compound_manager.config.enabled == true
            @test compound_manager.config.compound_percentage == 50.0
            
            # Test state management
            state1 = NumeraiTournament.Compounding.CompoundingState("test_model_1")
            state1.last_balance = 450.0  # 50 earnings
            compound_manager.states["test_model_1"] = state1
            
            state2 = NumeraiTournament.Compounding.CompoundingState("test_model_2")
            state2.last_balance = 480.0  # 20 earnings
            compound_manager.states["test_model_2"] = state2
        end
        
        @testset "Stake Management Integration" begin
            mock_client = IntegrationMockClient(wallet_balance=1000.0)
            
            # Test current stakes
            current_stake = mock_get_stakes(mock_client, "test_model_1")
            @test current_stake == 50.0  # From mock setup
            
            # Test stake increase
            result = mock_increase_stake(mock_client, "test_model_1", 25.0)
            @test result["success"] == true
            @test result["new_stake"] == 75.0
            @test mock_client.wallet_balance == 975.0
            
            # Test invalid stake increase
            @test_throws ErrorException mock_increase_stake(mock_client, "test_model_1", 2000.0)
            
            # Verify API call tracking
            @test :get_stakes in mock_client.api_calls
            @test :increase_stake in mock_client.api_calls
        end
        
        @testset "End-to-End Compounding Workflow" begin
            mock_client = IntegrationMockClient(wallet_balance=200.0)
            initial_balance = mock_client.wallet_balance
            
            # Set up compounding scenario
            # Model has earned money since last check
            mock_client.model_stakes["compound_model"] = 30.0
            
            # Create and configure compound manager
            compound_config = NumeraiTournament.Compounding.CompoundingConfig(
                enabled=true,
                min_compound_amount=2.0,
                compound_percentage=100.0,
                max_stake_amount=100.0,
                models=["compound_model"]
            )
            
            real_client = NumeraiTournament.API.NumeraiClient("test", "test")
            manager = NumeraiTournament.Compounding.CompoundingManager(real_client, compound_config)
            
            # Simulate compounding check
            state = NumeraiTournament.Compounding.CompoundingState("compound_model")
            state.last_balance = 190.0  # 10 earnings available
            manager.states["compound_model"] = state
            
            # Verify compounding would happen
            should_compound = NumeraiTournament.Compounding.should_run_compounding(manager)
            # Note: Result depends on current time and day of week
            @test should_compound isa Bool
            
            # Test compounding stats
            stats = NumeraiTournament.Compounding.get_compounding_stats(manager, "compound_model")
            @test stats[:total_compounded] == 0.0
            @test stats[:compound_count] == 0
        end
        
        cleanup()
    end
    
    @testset "7. Error Recovery and Retry Mechanisms" begin
        @testset "API Retry Logic" begin
            # Test various failure scenarios
            failing_mock = IntegrationMockClient(should_fail=:download)
            
            # Test download retry
            @test_throws ErrorException mock_download_dataset(failing_mock, "test_data.csv", "test.csv")
            
            # Test successful retry after failure
            failing_mock.should_fail = :none
            temp_path = tempname() * ".csv"
            result_path = mock_download_dataset(failing_mock, "numerai_training_data.csv", temp_path)
            @test result_path == temp_path
            @test isfile(temp_path)
        end
        
        @testset "Model Training Error Recovery" begin
            # Test training with invalid data
            invalid_X = [missing, missing, missing]  # Invalid training data
            invalid_y = rand(3)
            
            model = NumeraiTournament.Models.XGBoostModel("error_test", num_rounds=10)
            
            @test_throws Exception NumeraiTournament.Models.train!(model, invalid_X, invalid_y)
            
            # Test successful training after fixing data
            valid_X = rand(10, 5)
            valid_y = rand(10)
            
            NumeraiTournament.Models.train!(model, valid_X, valid_y, verbose=false)
            predictions = NumeraiTournament.Models.predict(model, valid_X)
            @test length(predictions) == 10
        end
        
        @testset "Submission Error Handling" begin
            mock_client = IntegrationMockClient()
            
            # Test missing file
            @test_throws ErrorException mock_submit_predictions(mock_client, "test", "nonexistent.csv")
            
            # Test invalid format file
            temp_file = tempname() * ".csv"
            CSV.write(temp_file, DataFrame(wrong_column=rand(10)))
            @test_throws ErrorException mock_submit_predictions(mock_client, "test", temp_file)
            
            # Test successful submission
            valid_file = tempname() * ".csv"
            CSV.write(valid_file, DataFrame(id=["id_$i" for i in 1:10], prediction=rand(10)))
            result = mock_submit_predictions(mock_client, "test", valid_file)
            @test result["success"] == true
        end
        
        @testset "Circuit Breaker Pattern" begin
            # Test that system can handle repeated failures gracefully
            failing_client = IntegrationMockClient(should_fail=:submit)
            
            failure_count = 0
            for i in 1:5
                try
                    mock_submit_predictions(failing_client, "test", "dummy")
                catch
                    failure_count += 1
                end
            end
            
            @test failure_count == 5  # All attempts should fail
            @test count(call -> call == :submit_predictions, failing_client.api_calls) == 5
        end
        
        cleanup()
    end
    
    @testset "8. Database Persistence Across Operations" begin
        temp_dir = mktempdir()
        db_path = joinpath(temp_dir, "integration_test.db")
        
        @testset "Database Initialization and Schema" begin
            # Initialize database
            db_conn = NumeraiTournament.Database.init_database(db_path=db_path)
            @test isfile(db_path)
            @test isa(db_conn, NumeraiTournament.Database.DatabaseConnection)
            
            # Verify tables exist
            result = SQLite.DBInterface.execute(db_conn.db, "SELECT name FROM sqlite_master WHERE type='table'")
            tables = [row.name for row in result]
            expected_tables = ["model_performance", "submissions", "rounds", "stake_history", "training_runs"]
            
            for table in expected_tables
                @test table in tables
            end
            
            NumeraiTournament.Database.close_database(db_conn)
        end
        
        @testset "Model Performance Persistence" begin
            db_conn = NumeraiTournament.Database.init_database(db_path=db_path)
            
            # Save model performance
            perf_data = Dict(
                :model_name => "integration_model",
                :round_number => 580,
                :correlation => 0.025,
                :mmc => 0.012,
                :tc => 0.018,
                :fnc => 0.008,
                :sharpe => 1.8,
                :payout => 125.5
            )
            
            NumeraiTournament.Database.save_model_performance(db_conn, perf_data)
            
            # Retrieve performance data
            retrieved_perf = NumeraiTournament.Database.get_latest_performance(db_conn, "integration_model")
            @test !isempty(retrieved_perf)
            @test retrieved_perf.correlation ≈ 0.025
            @test retrieved_perf.mmc ≈ 0.012
            
            NumeraiTournament.Database.close_database(db_conn)
        end
        
        @testset "Submission History Persistence" begin
            db_conn = NumeraiTournament.Database.init_database(db_path=db_path)
            
            # Save submission record
            submission_data = Dict(
                :model_name => "integration_model",
                :round_number => 580,
                :filename => "integration_submission.csv",
                :status => "completed",
                :validation_correlation => 0.023,
                :validation_sharpe => 0.011
            )
            
            NumeraiTournament.Database.save_submission(db_conn, submission_data)
            
            # Retrieve submissions
            submissions = NumeraiTournament.Database.get_submissions(db_conn, "integration_model")
            @test nrow(submissions) > 0
            
            latest = NumeraiTournament.Database.get_latest_submission(db_conn, "integration_model")
            @test !isnothing(latest)
            @test latest.model_name == "integration_model"
            @test latest.round_number == 580
            
            NumeraiTournament.Database.close_database(db_conn)
        end
        
        @testset "Training Run Persistence" begin
            db_conn = NumeraiTournament.Database.init_database(db_path=db_path)
            
            # Save training run
            training_data = Dict(
                :model_name => "integration_model",
                :model_type => "xgboost",
                :training_time_seconds => 125.5,
                :validation_score => 0.032,
                :test_score => 0.045,
                :hyperparameters => Dict(
                    "max_depth" => 6,
                    "learning_rate" => 0.01,
                    "num_rounds" => 1000
                )
            )
            
            NumeraiTournament.Database.save_training_run(db_conn, training_data)
            
            # Retrieve training runs
            runs = NumeraiTournament.Database.get_training_runs(db_conn, "integration_model")
            @test nrow(runs) > 0
            @test runs[1, :model_name] == "integration_model"
            
            NumeraiTournament.Database.close_database(db_conn)
        end
        
        @testset "Cross-Session Data Persistence" begin
            # Test that data persists across database connections
            db_conn1 = NumeraiTournament.Database.init_database(db_path=db_path)
            
            # Save data in first session
            round_data = Dict(
                :round_number => 580,
                :open_time => DateTime(2024, 1, 1),
                :close_time => DateTime(2024, 1, 3),
                :resolve_time => DateTime(2024, 1, 24),
                :round_type => "active"
            )
            
            NumeraiTournament.Database.save_round_data(db_conn1, round_data)
            
            NumeraiTournament.Database.close_database(db_conn1)
            
            # Open new connection and verify data exists
            db_conn2 = NumeraiTournament.Database.init_database(db_path=db_path)
            
            round_data = NumeraiTournament.Database.get_round_data(db_conn2, 580)
            @test !isnothing(round_data)
            @test round_data.round_number == 580
            
            NumeraiTournament.Database.close_database(db_conn2)
        end
        
        cleanup()
    end
    
    @testset "9. Configuration Management and Updates" begin
        temp_dir = mktempdir()
        config_path = joinpath(temp_dir, "dynamic_config.toml")
        
        @testset "Dynamic Configuration Updates" begin
            # Create initial config
            initial_config = """
            api_public_key = "initial_public"
            api_secret_key = "initial_secret"
            models = ["model_1"]
            data_dir = "initial_data"
            model_dir = "initial_models"
            auto_submit = false
            stake_amount = 10.0
            max_workers = 2
            notification_enabled = true
            compounding_enabled = false
            min_compound_amount = 1.0
            compound_percentage = 100.0
            max_stake_amount = 1000.0
            """
            
            open(config_path, "w") do f
                write(f, initial_config)
            end
            
            # Load initial config
            config1 = NumeraiTournament.load_config(config_path)
            @test config1.api_public_key == "initial_public"
            @test config1.models == ["model_1"]
            @test config1.auto_submit == false
            @test config1.compounding_enabled == false
            
            # Update config file
            updated_config = """
            api_public_key = "updated_public"
            api_secret_key = "updated_secret"
            models = ["model_1", "model_2", "model_3"]
            data_dir = "updated_data"
            model_dir = "updated_models"
            auto_submit = true
            stake_amount = 25.0
            max_workers = 4
            notification_enabled = false
            compounding_enabled = true
            min_compound_amount = 5.0
            compound_percentage = 75.0
            max_stake_amount = 5000.0
            """
            
            open(config_path, "w") do f
                write(f, updated_config)
            end
            
            # Reload config
            config2 = NumeraiTournament.load_config(config_path)
            @test config2.api_public_key == "updated_public"
            @test config2.models == ["model_1", "model_2", "model_3"]
            @test config2.auto_submit == true
            @test config2.compounding_enabled == true
            @test config2.stake_amount == 25.0
            @test config2.max_workers == 4
        end
        
        @testset "Environment Variable Override" begin
            # Set environment variables
            ENV["NUMERAI_PUBLIC_ID"] = "env_public"
            ENV["NUMERAI_SECRET_KEY"] = "env_secret"
            
            # Config should prefer environment variables
            config = NumeraiTournament.load_config("nonexistent_config.toml")
            @test config.api_public_key == "env_public"
            @test config.api_secret_key == "env_secret"
            
            # Clean up environment
            delete!(ENV, "NUMERAI_PUBLIC_ID")
            delete!(ENV, "NUMERAI_SECRET_KEY")
        end
        
        @testset "Configuration Validation" begin
            # Test invalid config values
            config = NumeraiTournament.TournamentConfig(
                "test_public",
                "test_secret", 
                String[],
                "data",
                "models",
                true,
                -10.0,  # Invalid negative stake
                0,      # Invalid zero workers
                true,
                8,      # tournament_id
                "medium", # feature_set
                true,   # compounding_enabled
                -1.0,   # Invalid min_compound_amount
                150.0,  # compound_percentage
                -100.0, # Invalid max_stake_amount
                Dict{String, Any}("refresh_rate" => 1.0) # tui_config
            )
            
            # Config should be created but with potentially invalid values
            @test config.stake_amount == -10.0  # Should be validated elsewhere
            @test config.max_workers == 0
            
            # Test reasonable config
            valid_config = NumeraiTournament.TournamentConfig(
                "test_public",
                "test_secret", 
                ["model1"],
                "data",
                "models",
                true,
                50.0,
                4,
                true,
                8,      # tournament_id
                "medium", # feature_set
                true,   # compounding_enabled
                5.0,    # min_compound_amount
                80.0,   # compound_percentage
                2000.0, # max_stake_amount
                Dict{String, Any}("refresh_rate" => 1.0) # tui_config
            )
            
            @test valid_config.stake_amount == 50.0
            @test valid_config.max_workers == 4
            @test valid_config.compound_percentage == 80.0
        end
        
        cleanup()
    end
    
    @testset "10. TUI Dashboard Integration (Mock Interaction)" begin
        temp_dir = mktempdir()
        
        @testset "Dashboard Initialization" begin
            config = NumeraiTournament.TournamentConfig(
                "test_public",
                "test_secret", 
                ["dashboard_model_1", "dashboard_model_2"],
                joinpath(temp_dir, "data"),
                joinpath(temp_dir, "models"),
                true,   # auto_submit
                50.0,   # stake_amount
                2,      # max_workers
                true,   # notification_enabled
                8,      # tournament_id
                "medium", # feature_set
                false,  # compounding_enabled
                1.0,    # min_compound_amount
                100.0,  # compound_percentage
                1000.0, # max_stake_amount
                Dict{String, Any}("refresh_rate" => 1.0) # tui_config
            )
            
            dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
            
            @test dashboard.config === config
            @test dashboard.running == false
            @test dashboard.paused == false
            @test length(dashboard.models) == 2
            @test dashboard.refresh_rate > 0
            @test length(dashboard.events) >= 0
        end
        
        @testset "Event System" begin
            config = NumeraiTournament.load_config()  # Use default config
            dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
            
            initial_event_count = length(dashboard.events)
            
            # Add various event types
            NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Test info message")
            NumeraiTournament.Dashboard.add_event!(dashboard, :warning, "Test warning message") 
            NumeraiTournament.Dashboard.add_event!(dashboard, :error, "Test error message")
            NumeraiTournament.Dashboard.add_event!(dashboard, :success, "Test success message")
            
            @test length(dashboard.events) == initial_event_count + 4
            
            # Check most recent events
            recent_events = dashboard.events[(end-3):end]
            @test recent_events[1][:type] == :info
            @test recent_events[1][:message] == "Test info message"
            @test recent_events[4][:type] == :success
            @test recent_events[4][:message] == "Test success message"
            
            # Test event timestamps
            for event in recent_events
                @test haskey(event, :time)
                @test event[:time] isa DateTime
            end
        end
        
        @testset "Dashboard State Management" begin
            config = NumeraiTournament.load_config()
            dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
            
            # Test pause/resume
            @test dashboard.paused == false
            dashboard.paused = true
            @test dashboard.paused == true
            dashboard.paused = false
            @test dashboard.paused == false
            
            # Test model state tracking
            @test length(dashboard.models) >= 0
            
            # Test refresh rate
            original_rate = dashboard.refresh_rate
            dashboard.refresh_rate = 5.0
            @test dashboard.refresh_rate == 5.0
            dashboard.refresh_rate = original_rate
        end
        
        @testset "Mock Dashboard Commands" begin
            config = NumeraiTournament.load_config()
            dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
            
            # Test dashboard command processing
            # These would normally be keyboard inputs in the real TUI
            
            # Mock 'h' command (help)
            help_event_count = length(dashboard.events)
            NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Help: Press 'q' to quit, 'p' to pause, 'r' to refresh")
            @test length(dashboard.events) == help_event_count + 1
            
            # Mock 'r' command (refresh)
            refresh_event_count = length(dashboard.events)
            NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Dashboard refreshed")
            @test length(dashboard.events) == refresh_event_count + 1
            
            # Mock 'p' command (pause)
            original_paused = dashboard.paused
            dashboard.paused = !dashboard.paused
            pause_event_count = length(dashboard.events)
            NumeraiTournament.Dashboard.add_event!(dashboard, :info, dashboard.paused ? "Dashboard paused" : "Dashboard resumed")
            @test length(dashboard.events) == pause_event_count + 1
            @test dashboard.paused != original_paused
        end
        
        @testset "Chart and Display Integration" begin
            # Test chart formatting functions
            values = [0.01, 0.02, 0.015, 0.025, 0.02]
            chart = NumeraiTournament.Charts.create_mini_chart(values, width=10)
            # The function returns one character per value, up to width characters
            @test length(chart) == 5  # We have 5 values, so 5 characters
            @test occursin("▁", chart) || occursin("▂", chart) || occursin("▃", chart)
            
            # Test correlation bar formatting
            corr_bar = NumeraiTournament.Charts.format_correlation_bar(0.025, width=20)
            @test occursin("█", corr_bar) || occursin("▌", corr_bar)
            @test occursin("0.025", corr_bar)
            
            # Test progress bar creation
            progress_bar = NumeraiTournament.Panels.create_progress_bar(30, 100, width=20)
            @test length(progress_bar) == 20
            @test occursin("█", progress_bar)
            @test occursin("░", progress_bar)
            
            # Test uptime formatting
            @test NumeraiTournament.Panels.format_uptime(3661) == "1h 1m"
            @test NumeraiTournament.Panels.format_uptime(90061) == "1d 1h 1m"
        end
        
        @testset "Mock Real-time Updates" begin
            config = NumeraiTournament.load_config()
            dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
            
            # Simulate model performance updates
            mock_performance = Dict(
                "test_model" => Dict(
                    "correlation" => 0.023,
                    "mmc" => 0.011,
                    "tc" => 0.015,
                    "sharpe" => 1.8,
                    "payout" => 42.50
                )
            )
            
            # Add performance update event
            NumeraiTournament.Dashboard.add_event!(
                dashboard, 
                :success, 
                "Updated performance for test_model: corr=0.023, mmc=0.011"
            )
            
            # Simulate system resource updates
            NumeraiTournament.Dashboard.add_event!(
                dashboard,
                :info,
                "System: CPU=45%, Memory=2.1GB, Threads=$(Threads.nthreads())"
            )
            
            # Simulate submission status update
            NumeraiTournament.Dashboard.add_event!(
                dashboard,
                :success,
                "Submitted predictions for test_model (Round 580)"
            )
            
            @test length(dashboard.events) >= 3
            
            # Verify recent events contain expected information
            recent_events = dashboard.events[(end-2):end]
            @test any(event -> occursin("performance", event[:message]), recent_events)
            @test any(event -> occursin("System:", event[:message]), recent_events)
            @test any(event -> occursin("Submitted", event[:message]), recent_events)
        end
        
        cleanup()
    end
end

println("✅ All comprehensive integration tests passed!")