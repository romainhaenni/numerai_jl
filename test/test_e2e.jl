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
        @test config.api_public_key != ""
        @test config.api_secret_key != ""
        @test length(config.models) > 0
        @test config.max_workers > 0
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
            preprocessor = NumeraiTournament.Preprocessor.DataPreprocessor(
                feature_cols=["feature_$i" for i in 1:n_features],
                target_col="target_cyrus_v4_20"
            )
            
            X_train, y_train = NumeraiTournament.Preprocessor.preprocess(
                preprocessor, train_data
            )
            
            @test size(X_train, 1) == n_samples
            @test size(X_train, 2) == n_features
            @test length(y_train) == n_samples
            @test all(isfinite.(X_train))  # Check for finite values
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
                n_estimators=10,
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
                max_depth=3
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
                NumeraiTournament.Models.XGBoostModel("xgb1", n_estimators=10),
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
        
        # Test complete pipeline
        pipeline = NumeraiTournament.Pipeline.MLPipeline(
            feature_cols=["feature_$i" for i in 1:n_features],
            target_col="target_cyrus_v4_20",
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
        @test length(scheduler.timers) == 0
        
        # Test timer setup
        NumeraiTournament.Scheduler.setup_timers!(scheduler)
        @test length(scheduler.timers) > 0
    end
    
    @testset "Dashboard Components" begin
        config = NumeraiTournament.load_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        @test isa(dashboard, NumeraiTournament.Dashboard.TournamentDashboard)
        @test dashboard.running == false
        @test dashboard.paused == false
        @test length(dashboard.models) == length(config.models)
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
        
        # Calculate diversity score
        pred_matrix = rand(100, 3)
        diversity = NumeraiTournament.Ensemble.diversity_score(pred_matrix)
        @test 0 <= diversity <= 1
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