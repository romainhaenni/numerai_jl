#!/usr/bin/env julia

# Production Readiness Test Suite
# This test verifies that the NumeraiTournament.jl package is production-ready
# by checking all critical components and functionality

using NumeraiTournament
using Test
using DataFrames
using Random
using JSON3
using CSV
using Logging

# Access submodules properly
const API = NumeraiTournament.API
const Models = NumeraiTournament.Models  
const DataProcessing = NumeraiTournament.DataProcessing
const Database = NumeraiTournament.Database
const Logger = NumeraiTournament.Logger
const GPU = NumeraiTournament.GPU
const TUI = NumeraiTournament.TUI
const Scheduler = NumeraiTournament.Scheduler

println("="^80)
println(" NumeraiTournament.jl Production Readiness Test Suite")
println("="^80)

# Test results tracking
test_results = Dict{String, Bool}()
critical_failures = String[]

function test_component(name::String, test_fn::Function)
    print("Testing $name... ")
    try
        result = test_fn()
        if result
            println("✅ PASSED")
            test_results[name] = true
        else
            println("❌ FAILED")
            test_results[name] = false
            push!(critical_failures, name)
        end
    catch e
        println("❌ ERROR: $e")
        test_results[name] = false
        push!(critical_failures, "$name (Error: $(typeof(e)))")
    end
end

# 1. Module Loading Test
test_component("Module Loading") do
    @test isdefined(NumeraiTournament, :run_dashboard)
    @test isdefined(NumeraiTournament, :MLPipeline)
    @test isdefined(NumeraiTournament, :API)
    true
end

# 2. Configuration Test
test_component("Configuration Loading") do
    config_path = joinpath(dirname(@__DIR__), "config.toml")
    @test isfile(config_path)
    config = NumeraiTournament.load_config(config_path)
    @test haskey(config, "tournament")
    @test haskey(config, "models")
    @test haskey(config, "tui")
    true
end

# 3. Logger Test
test_component("Logger System") do
    temp_dir = mktempdir()
    Logger.initialize_logger(temp_dir; console_level=Logging.Error, file_level=Logging.Debug)
    Logger.log_info("Test message")
    Logger.log_debug("Debug test")
    Logger.log_error("Error test")
    log_file = joinpath(temp_dir, "logs", "numerai.log")
    @test isfile(log_file)
    true
end

# 4. API Client Test (Public Endpoints)
test_component("API Client (Public)") do
    client = API.NumeraiClient("test_public", "test_secret")
    
    # Test current round retrieval
    round = API.get_current_round(client)
    @test isa(round.number, Int)
    @test round.number > 0
    
    # Test dataset info
    dataset = API.get_dataset_info(client)
    @test !isempty(dataset.version)
    @test !isempty(dataset.train_url)
    
    true
end

# 5. Database Test
test_component("Database System") do
    temp_db = tempname() * ".db"
    try
        db = Database.init_database(temp_db)
        
        # Test predictions table
        test_df = DataFrame(
            id = ["test1", "test2"],
            prediction = [0.5, 0.6]
        )
        Database.save_predictions(db, test_df, "test_model", 500)
        
        # Test model metadata
        Database.save_model_metadata(db, "test_model", 500, 
            Dict("corr" => 0.02, "mmc" => 0.01))
        
        @test isfile(temp_db)
        true
    finally
        rm(temp_db, force=true)
    end
end

# 6. Data Processing Test
test_component("Data Processing") do
    # Create synthetic data
    Random.seed!(42)
    n_samples = 100
    n_features = 10
    
    df = DataFrame()
    for i in 1:n_features
        df[!, "feature_$i"] = randn(n_samples)
    end
    df[!, "target"] = rand(n_samples)
    df[!, "era"] = repeat(1:10, inner=10)
    
    # Test preprocessing
    preprocessor = DataProcessing.DataPreprocessor()
    processed_df = DataProcessing.preprocess_data(preprocessor, df, 
        ["feature_$i" for i in 1:n_features])
    
    @test size(processed_df) == size(df)
    @test !any(ismissing, Matrix(processed_df))
    true
end

# 7. Model Creation Test
test_component("Model Creation") do
    # Test each model type can be created
    model_types = [:xgboost, :lightgbm, :evotrees, :catboost, 
                   :ridge, :lasso, :elasticnet]
    
    for model_type in model_types
        model = Models.create_model(model_type)
        @test isa(model, Models.NumeraiModel)
    end
    true
end

# 8. ML Pipeline Test
test_component("ML Pipeline") do
    # Create a simple pipeline
    pipeline = NumeraiTournament.MLPipeline(
        feature_cols = ["feature_1", "feature_2"],
        target_col = "target",
        model_configs = [
            Dict("type" => "ridge", "alpha" => 1.0)
        ],
        cv_folds = 2
    )
    
    @test pipeline.n_targets == 1
    @test !pipeline.is_multi_target
    @test length(pipeline.models) == 0  # No models trained yet
    true
end

# 9. GPU Acceleration Test
test_component("GPU Acceleration") do
    gpu_available = GPU.is_gpu_available()
    if gpu_available
        # Test basic GPU operations
        test_array = randn(Float32, 100, 100)
        gpu_array = GPU.to_gpu(test_array)
        @test size(gpu_array) == size(test_array)
        
        cpu_array = GPU.to_cpu(gpu_array)
        @test cpu_array ≈ test_array
    else
        println(" (GPU not available - skipping)")
    end
    true
end

# 10. Multi-Target Support Test
test_component("Multi-Target Support") do
    # Test single-target
    single_pipeline = NumeraiTournament.MLPipeline(
        feature_cols = ["f1", "f2"],
        target_col = "target"
    )
    @test !single_pipeline.is_multi_target
    @test single_pipeline.n_targets == 1
    
    # Test multi-target
    multi_pipeline = NumeraiTournament.MLPipeline(
        feature_cols = ["f1", "f2"],
        target_col = ["target1", "target2", "target3"]
    )
    @test multi_pipeline.is_multi_target
    @test multi_pipeline.n_targets == 3
    true
end

# 11. Feature Groups Test
test_component("Feature Groups") do
    # Check feature groups file exists
    features_path = joinpath(dirname(@__DIR__), "data", "features.json")
    if isfile(features_path)
        feature_data = JSON3.read(read(features_path, String))
        @test haskey(feature_data, "feature_sets")
        @test haskey(feature_data, "feature_groups")
    else
        println(" (features.json not found - skipping)")
    end
    true
end

# 12. Metrics Calculation Test
test_component("Metrics Calculation") do
    using NumeraiTournament.Metrics: calculate_correlation, calculate_sharpe
    
    predictions = rand(100)
    targets = rand(100)
    
    # Test correlation
    corr = calculate_correlation(predictions, targets)
    @test -1.0 <= corr <= 1.0
    
    # Test Sharpe ratio
    returns = randn(100) * 0.01
    sharpe = calculate_sharpe(returns)
    @test isa(sharpe, Float64)
    true
end

# 13. TUI Module Test
test_component("TUI Dashboard Module") do
    @test isdefined(NumeraiTournament, :run_dashboard)
    @test isdefined(NumeraiTournament.TUI, :Dashboard)
    @test isdefined(NumeraiTournament.TUI, :create_dashboard_state)
    true
end

# 14. Scheduler Module Test
test_component("Scheduler Module") do
    using NumeraiTournament.Scheduler
    
    @test isdefined(Scheduler, :TournamentScheduler)
    @test isdefined(Scheduler, :schedule_tournament_tasks)
    @test isdefined(Scheduler, :is_submission_window_open)
    true
end

# 15. File I/O Test
test_component("File I/O Operations") do
    temp_dir = mktempdir()
    test_file = joinpath(temp_dir, "test.csv")
    
    # Create test data
    df = DataFrame(a = 1:3, b = 4:6)
    CSV.write(test_file, df)
    
    # Read back
    df_read = CSV.read(test_file, DataFrame)
    @test df == df_read
    
    rm(temp_dir, recursive=true)
    true
end

println("\n" * "="^80)
println(" Test Results Summary")
println("="^80)

# Calculate statistics
total_tests = length(test_results)
passed_tests = sum(values(test_results))
failed_tests = total_tests - passed_tests
pass_rate = passed_tests / total_tests * 100

println("\nTotal Tests: $total_tests")
println("Passed: $passed_tests ✅")
println("Failed: $failed_tests ❌")
println("Pass Rate: $(round(pass_rate, digits=1))%")

if !isempty(critical_failures)
    println("\n⚠️ Critical Failures:")
    for failure in critical_failures
        println("  - $failure")
    end
end

# Production readiness assessment
println("\n" * "="^80)
println(" Production Readiness Assessment")
println("="^80)

if pass_rate >= 95.0
    println("\n✅ PRODUCTION READY - All critical systems operational")
    println("   The application is ready for production deployment.")
elseif pass_rate >= 80.0
    println("\n⚠️ MOSTLY READY - Some non-critical issues present")
    println("   Review and fix the failed components before production deployment.")
else
    println("\n❌ NOT READY - Critical failures detected")
    println("   Multiple critical systems have failures. Do not deploy to production.")
end

println("\n" * "="^80)

# Exit with appropriate code
exit(failed_tests == 0 ? 0 : 1)