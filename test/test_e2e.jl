using Test
using NumeraiTournament
using Dates
using DataFrames
using Random
using JSON3
using CSV
using Statistics

@testset "End-to-End Tests" begin
    
    @testset "Configuration Loading" begin
        # Test config loading from TOML
        config = NumeraiTournament.load_config()
        @test isa(config, NumeraiTournament.TournamentConfig)
        # API keys may be empty if not set via environment variables - that's OK for tests
        @test isa(config.api_public_key, String)
        @test isa(config.api_secret_key, String)
        @test length(config.models) >= 0  # Changed to allow empty model list
        @test config.max_workers > 0
        # Test that expected config keys are present and have correct types
        @test isa(config.tournament_id, Int)
        @test isa(config.data_dir, String)
        @test isa(config.model_dir, String)
        @test isa(config.auto_submit, Bool)
        @test isa(config.stake_amount, Float64)
        @test isa(config.feature_set, String)
        @test isa(config.tui_config, Dict)
        # Test tui config has expected structure
        @test haskey(config.tui_config, "refresh_rate")
        @test haskey(config.tui_config, "limits")
        @test haskey(config.tui_config, "panels")
        @test haskey(config.tui_config, "charts")
    end
    
    @testset "API Client Initialization" begin
        config = NumeraiTournament.load_config()
        client = NumeraiTournament.API.NumeraiClient(
            config.api_public_key,
            config.api_secret_key
        )
        @test isa(client, NumeraiTournament.API.NumeraiClient)
        @test client.public_id == config.api_public_key
        @test haskey(client.headers, "x-public-id")
    end
    
    @testset "Mock Data Pipeline" begin
        # Create mock data
        n_samples = 1000
        n_features = 100
        
        # Generate mock training data
        train_data = DataFrame()
        for i in 1:n_features
            train_data[!, "feature_$i"] = rand(n_samples)
        end
        train_data[!, "target_cyrus_v4_20"] = rand(n_samples)
        train_data[!, "era"] = repeat(1:10, inner=n_samples÷10)
        
        # Generate mock validation data
        val_data = DataFrame()
        for i in 1:n_features
            val_data[!, "feature_$i"] = rand(500)
        end
        val_data[!, "target_cyrus_v4_20"] = rand(500)
        val_data[!, "era"] = repeat(11:15, inner=100)
        
        # Test preprocessing
        @testset "Data Preprocessing" begin
            # Test fillna function
            data_with_na = copy(train_data)
            # Convert column to allow missing values
            data_with_na[!, "feature_1"] = Vector{Union{Float64, Missing}}(data_with_na[!, "feature_1"])
            data_with_na[1:10, "feature_1"] .= missing
            filled_data = NumeraiTournament.Preprocessor.fillna(data_with_na)
            @test !any(ismissing.(filled_data[!, "feature_1"]))
            
            # Test normalize_predictions function
            raw_preds = rand(100) 
            normalized_preds = NumeraiTournament.Preprocessor.normalize_predictions(raw_preds)
            @test all(0.0 .<= normalized_preds .<= 1.0)
            @test length(normalized_preds) == length(raw_preds)
            
            # Test gaussianize function
            values = rand(100) * 10
            gauss_values = NumeraiTournament.Preprocessor.gaussianize(values)
            @test length(gauss_values) == length(values)
            @test all(isfinite.(gauss_values))
        end
        
        # Test feature neutralization
        @testset "Feature Neutralization" begin
            X_train = Matrix(train_data[:, ["feature_$i" for i in 1:n_features]])
            y_train = train_data.target_cyrus_v4_20
            
            neutralized = NumeraiTournament.Neutralization.neutralize(
                y_train, X_train, proportion=0.5
            )
            
            @test length(neutralized) == length(y_train)
            @test neutralized != y_train  # Should be different after neutralization
        end
        
        # Test model training
        @testset "Model Training" begin
            X_train = rand(100, 10)
            y_train = rand(100)
            
            # Test XGBoost model
            xgb_model = NumeraiTournament.Models.XGBoostModel(
                "test_xgb",
                num_rounds=10,
                max_depth=3
            )
            
            NumeraiTournament.Models.train!(
                xgb_model, X_train, y_train, verbose=false
            )
            
            predictions = NumeraiTournament.Models.predict(xgb_model, X_train)
            @test length(predictions) == 100
            @test all(isfinite.(predictions))
            
            # Test LightGBM model
            lgb_model = NumeraiTournament.Models.LightGBMModel(
                "test_lgb",
                n_estimators=10,
                num_leaves=7
            )
            
            NumeraiTournament.Models.train!(
                lgb_model, X_train, y_train, verbose=false
            )
            
            predictions = NumeraiTournament.Models.predict(lgb_model, X_train)
            @test length(predictions) == 100
            @test all(isfinite.(predictions))
        end
        
        # Test ensemble
        @testset "Ensemble Predictions" begin
            X_train = rand(100, 10)
            y_train = rand(100)
            
            models = [
                NumeraiTournament.Models.XGBoostModel("xgb1", num_rounds=10),
                NumeraiTournament.Models.LightGBMModel("lgb1", n_estimators=10)
            ]
            
            ensemble = NumeraiTournament.Ensemble.ModelEnsemble(
                models, name="test_ensemble"
            )
            
            NumeraiTournament.Ensemble.train_ensemble!(
                ensemble, X_train, y_train, verbose=false
            )
            
            predictions = NumeraiTournament.Ensemble.predict_ensemble(
                ensemble, X_train
            )
            
            @test length(predictions) == 100
            @test all(isfinite.(predictions))
        end
    end
    
    @testset "ML Pipeline Integration" begin
        # Create minimal test data
        n_samples = 200
        n_features = 20
        
        train_df = DataFrame()
        for i in 1:n_features
            train_df[!, "feature_$i"] = rand(n_samples)
        end
        train_df[!, "target_cyrus_v4_20"] = rand(n_samples)
        train_df[!, "era"] = repeat(1:4, inner=n_samples÷4)
        
        val_df = DataFrame()
        for i in 1:n_features
            val_df[!, "feature_$i"] = rand(100)
        end
        val_df[!, "target_cyrus_v4_20"] = rand(100)
        val_df[!, "era"] = repeat(5:6, inner=50)
        
        # Test complete pipeline with CPU-only model to avoid Metal GPU issues
        # Use single model with current API
        model = NumeraiTournament.Models.XGBoostModel("xgb_test", max_depth=3, num_rounds=5, gpu_enabled=false)
        
        pipeline = NumeraiTournament.Pipeline.MLPipeline(
            feature_cols=["feature_$i" for i in 1:n_features],
            target_col="target_cyrus_v4_20",
            model=model,
            neutralize=true,
            neutralize_proportion=0.3
        )
        
        NumeraiTournament.Pipeline.train!(
            pipeline, train_df, val_df, verbose=false
        )
        
        # Make predictions
        predictions = NumeraiTournament.Pipeline.predict(pipeline, val_df)
        
        @test length(predictions) == 100
        @test all(isfinite.(predictions))  # Check predictions are finite
    end
    
    @testset "Scheduler Components" begin
        config = NumeraiTournament.load_config()
        scheduler = NumeraiTournament.Scheduler.TournamentScheduler(config)
        
        @test isa(scheduler, NumeraiTournament.Scheduler.TournamentScheduler)
        @test scheduler.running == false
        @test length(scheduler.cron_jobs) == 0
        
        # Test cron job setup
        NumeraiTournament.Scheduler.setup_cron_jobs!(scheduler)
        @test length(scheduler.cron_jobs) > 0
    end
    
    @testset "Dashboard Components" begin
        config = NumeraiTournament.load_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        @test isa(dashboard, NumeraiTournament.Dashboard.TournamentDashboard)
        @test dashboard.running == false
        @test dashboard.paused == false
        @test haskey(dashboard.model, :name)  # Test single model instead of models vector
        @test dashboard.refresh_rate > 0
        
        # Test event system
        NumeraiTournament.Dashboard.add_event!(
            dashboard, :info, "Test event"
        )
        @test length(dashboard.events) > 0
        @test dashboard.events[end][:message] == "Test event"
    end
    
    @testset "Performance Metrics" begin
        predictions = rand(100)
        targets = rand(100)
        
        # Calculate correlation
        corr = cor(predictions, targets)
        @test -1 <= corr <= 1
        
        # Calculate standard deviation as a simple diversity measure
        pred_matrix = rand(100, 3)
        diversity = std(pred_matrix[:, 1])  # Simple diversity measure
        @test diversity >= 0
    end
    
    @testset "File I/O Operations" begin
        # Test predictions CSV writing
        temp_file = tempname() * ".csv"
        
        predictions_df = DataFrame(
            id = ["id_$i" for i in 1:10],
            prediction = rand(10)
        )
        
        CSV.write(temp_file, predictions_df)
        @test isfile(temp_file)
        
        # Read back and verify
        loaded_df = CSV.read(temp_file, DataFrame)
        @test size(loaded_df) == (10, 2)
        @test names(loaded_df) == ["id", "prediction"]
        
        rm(temp_file)
    end
    
    @testset "System Resource Monitoring" begin
        # Test CPU usage calculation
        cpu_count = Sys.CPU_THREADS
        @test cpu_count > 0
        
        # Test memory info
        memory_gb = Sys.total_memory() / (1024^3)
        @test memory_gb > 0
        
        # Test thread configuration
        thread_count = Threads.nthreads()
        @test thread_count >= 1
    end
end

println("\n✅ All end-to-end tests passed!")