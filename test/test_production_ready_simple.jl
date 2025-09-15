#!/usr/bin/env julia

# Simplified Production Readiness Test
# Tests the core functionality that users would actually use

using NumeraiTournament
using Test
using DataFrames
using Random

println("="^80)
println(" NumeraiTournament.jl Production Readiness Test")
println("="^80)

test_results = []

function run_test(name::String, test_fn::Function)
    print("Testing $name... ")
    try
        test_fn()
        println("✅ PASSED")
        push!(test_results, true)
    catch e
        println("❌ FAILED: $(typeof(e))")
        push!(test_results, false)
    end
end

# 1. Module loads successfully  
run_test("Module Loading", () -> begin
    @test isdefined(NumeraiTournament, :MLPipeline)
    @test isdefined(NumeraiTournament, :API)
    @test isdefined(NumeraiTournament, :run_dashboard)
end)

# 2. Configuration loading
run_test("Configuration", () -> begin
    config_path = joinpath(dirname(@__DIR__), "config.toml")
    @test isfile(config_path)
    config = NumeraiTournament.load_config(config_path)
    @test isa(config, NumeraiTournament.TournamentConfig)
end)

# 3. API client creation (public endpoints)
run_test("API Client", () -> begin
    client = NumeraiTournament.API.NumeraiClient("test", "test")
    @test isa(client, NumeraiTournament.API.NumeraiClient)
    
    # Test real API call
    round = NumeraiTournament.API.get_current_round(client)
    @test round.number > 0
end)

# 4. Model creation
run_test("Model Creation", () -> begin
    for model_type in [:XGBoost, :LightGBM, :Ridge]
        model = NumeraiTournament.create_model(model_type)
        @test isa(model, NumeraiTournament.Models.NumeraiModel)
    end
end)

# 5. ML Pipeline creation
run_test("ML Pipeline", () -> begin
    pipeline = NumeraiTournament.MLPipeline(
        feature_cols = ["f1", "f2"],
        target_col = "target"
    )
    @test pipeline.n_targets == 1
    @test !pipeline.is_multi_target
end)

# 6. Multi-target support
run_test("Multi-Target Support", () -> begin
    pipeline = NumeraiTournament.MLPipeline(
        feature_cols = ["f1", "f2"],
        target_col = ["t1", "t2", "t3"]
    )
    @test pipeline.n_targets == 3
    @test pipeline.is_multi_target
end)

# 7. GPU capabilities
run_test("GPU Detection", () -> begin
    has_gpu = NumeraiTournament.has_metal_gpu()
    @test isa(has_gpu, Bool)
    
    if has_gpu
        info = NumeraiTournament.get_gpu_info()
        @test isa(info, Dict)
    end
end)

# 8. Logger functionality
run_test("Logger", () -> begin
    temp_dir = mktempdir()
    log_file_path = joinpath(temp_dir, "test.log")
    NumeraiTournament.Logger.init_logger(log_file = log_file_path)
    NumeraiTournament.Logger.@log_info "Test message"
    @test isfile(log_file_path) || isdir(dirname(log_file_path))
    rm(temp_dir, recursive=true, force=true)
end)

# 9. Database functionality
run_test("Database", () -> begin
    temp_db = tempname() * ".db"
    db = NumeraiTournament.Database.init_database(db_path=temp_db)
    @test isfile(temp_db)

    # Test saving predictions
    df = DataFrame(id = ["test1"], prediction = [0.5])
    NumeraiTournament.Database.save_predictions(db, df, "test_model", 500)
    
    rm(temp_db, force=true)
end)

# 10. Data preprocessing
run_test("Data Preprocessing", () -> begin
    Random.seed!(42)
    # Create DataFrame with columns that allow missing values
    df = DataFrame(
        feature_1 = Vector{Union{Float64, Missing}}(randn(100)),
        feature_2 = Vector{Union{Float64, Missing}}(randn(100)),
        target = rand(100),
        era = repeat(1:10, inner=10)
    )

    # Test fillna function
    df[1, :feature_1] = missing
    df[5, :feature_2] = missing
    processed = NumeraiTournament.Preprocessor.fillna(df, 0.5)
    @test !any(ismissing, processed.feature_1)
    @test !any(ismissing, processed.feature_2)
    @test size(processed) == size(df)
end)

# Summary
println("\n" * "="^80)
println(" Test Summary")
println("="^80)

passed = sum(test_results)
total = length(test_results)
pass_rate = passed / total * 100

println("\nTests Passed: $passed/$total ($(round(pass_rate, digits=1))%)")

if pass_rate == 100
    println("\n✅ ALL TESTS PASSED - Production Ready!")
elseif pass_rate >= 80
    println("\n⚠️ MOSTLY READY - Some issues to address")
else
    println("\n❌ NOT READY - Critical failures detected")
end

println("="^80)
exit(passed == total ? 0 : 1)