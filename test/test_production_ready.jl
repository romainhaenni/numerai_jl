#!/usr/bin/env julia

# Production Readiness Test Suite
# This test verifies that the NumeraiTournament.jl package is production-ready
# by checking all critical components and functionality

# NumeraiTournament is already loaded by runtests.jl
using Test
using DataFrames
using Random
using JSON3
using CSV
using Logging
# Metrics functions accessed via NumeraiTournament.Metrics module

# Access submodules properly
const API = NumeraiTournament.API
const ML_Models = NumeraiTournament.Models  
const DataProcessing = NumeraiTournament.Preprocessor
const Database = NumeraiTournament.Database
const TournamentLogger = NumeraiTournament.Logger
const MetalGPU = NumeraiTournament.MetalAcceleration
const GPUBenchmarks = NumeraiTournament.GPUBenchmarks
const TUIDashboard = NumeraiTournament.Dashboard
const TournamentSchedulerModule = NumeraiTournament.Scheduler

println("="^80)
println(" NumeraiTournament.jl Production Readiness Test Suite")
println("="^80)

# Test results tracking
test_results = Dict{String, Bool}()
critical_failures = String[]

function test_component(test_fn::Function, name::String)
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
    @test isdefined(config, :tournament_id)
    @test isdefined(config, :models)
    @test isdefined(config, :tui_config)
    true
end

# 3. Logger Test
test_component("Logger System") do
    temp_dir = mktempdir()
    log_file = joinpath(temp_dir, "test.log")
    # Use init_logger with keyword arguments
    TournamentLogger.init_logger(log_file=log_file, console_level=Logging.Error, file_level=Logging.Debug)
    # Check that logger was initialized and functions are available
    @test isdefined(TournamentLogger, :init_logger)
    @test isdefined(TournamentLogger, Symbol("@log_info"))
    @test isdefined(TournamentLogger, Symbol("@log_error"))
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
        db = Database.init_database(db_path=temp_db)
        
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
    # Create synthetic data with missing values
    Random.seed!(42)
    n_samples = 100
    n_features = 10
    
    df = DataFrame()
    for i in 1:n_features
        values = Vector{Union{Float64, Missing}}(randn(n_samples))
        # Introduce some missing values
        missing_indices = rand(1:n_samples, 5)
        values[missing_indices] .= missing
        df[!, "feature_$i"] = values
    end
    df[!, "target"] = rand(n_samples)
    df[!, "era"] = repeat(1:10, inner=10)
    
    # Test preprocessing functions
    # Test fillna function
    clean_df = DataProcessing.fillna(df, 0.0)
    @test size(clean_df) == size(df)
    @test !any(ismissing.(clean_df[!, "feature_1"]))
    
    # Test rank normalization
    test_predictions = rand(100)
    ranked = DataProcessing.rank_predictions(test_predictions)
    @test minimum(ranked) >= 0.0
    @test maximum(ranked) <= 1.0
    
    true
end

# 7. Model Creation Test
test_component("Model Creation") do
    # Test each model type can be created
    model_types = [:XGBoost, :LightGBM, :EvoTrees, :CatBoost, 
                   :Ridge, :Lasso, :ElasticNet]
    
    for model_type in model_types
        model = ML_Models.create_model(model_type)
        @test !isnothing(model)
    end
    true
end

# 8. ML Pipeline Test
test_component("ML Pipeline") do
    # Create a simple pipeline
    # Use the Pipeline module directly 
    pipeline = NumeraiTournament.Pipeline.MLPipeline(
        feature_cols = ["feature_1", "feature_2"],
        target_col = "target",
        model = ML_Models.create_model(:Ridge)
    )
    
    @test pipeline.n_targets == 1
    @test !pipeline.is_multi_target
    @test !isnothing(pipeline.model)  # Model is set but not trained
    true
end

# 9. GPU Acceleration Test
test_component("GPU Acceleration") do
    gpu_available = MetalGPU.has_metal_gpu()
    if gpu_available
        # Test basic GPU operations
        gpu_info = MetalGPU.get_gpu_info()
        @test haskey(gpu_info, "device_name")
        @test haskey(gpu_info, "memory_gb") && gpu_info["memory_gb"] > 0
    else
        println(" (GPU not available - skipping)")
    end
    true
end

# 10. Multi-Target Support Test
test_component("Multi-Target Support") do
    # Test single-target
    single_pipeline = NumeraiTournament.Pipeline.MLPipeline(
        feature_cols = ["f1", "f2"],
        target_col = "target",
        model = ML_Models.create_model(:XGBoost)
    )
    @test !single_pipeline.is_multi_target
    @test single_pipeline.n_targets == 1
    
    # Test multi-target
    multi_pipeline = NumeraiTournament.Pipeline.MLPipeline(
        feature_cols = ["f1", "f2"],
        target_col = ["target1", "target2", "target3"],
        model = ML_Models.create_model(:XGBoost)
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
    predictions = rand(100)
    targets = rand(100)
    
    # Test contribution score (correlation)
    corr = NumeraiTournament.Metrics.calculate_contribution_score(predictions, targets)
    @test -1.0 <= corr <= 1.0
    
    # Test Sharpe ratio
    returns = randn(100) * 0.01
    sharpe = NumeraiTournament.Metrics.calculate_sharpe(returns)
    @test isa(sharpe, Float64)
    true
end

# 13. TUI Module Test
test_component("TUI Dashboard Module") do
    @test isdefined(NumeraiTournament, :run_dashboard)
    @test isdefined(NumeraiTournament.Dashboard, :TournamentDashboard)
    @test isdefined(NumeraiTournament.Dashboard, :run_dashboard)
    true
end

# 14. Scheduler Module Test
test_component("Scheduler Module") do
    @test isdefined(TournamentSchedulerModule, :TournamentScheduler)
    @test isdefined(TournamentSchedulerModule, :start_scheduler)
    @test isdefined(TournamentSchedulerModule, :stop_scheduler)
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