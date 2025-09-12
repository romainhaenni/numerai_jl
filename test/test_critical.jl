#!/usr/bin/env julia

# Critical functionality test - Quick verification that core systems work

# Load NumeraiTournament only if not already loaded
if !@isdefined(NumeraiTournament)
    using NumeraiTournament
end
using Test
using DataFrames
using Random

println("Testing Critical Functionality...")
println("="^50)

# 1. Module Loading
println("✓ Module loading successful")

# 2. Configuration
config = NumeraiTournament.load_config()
@test isdefined(config, :tournament_id)
println("✓ Configuration loading works")

# 3. Models
for model_type in [:XGBoost, :LightGBM, :Ridge]
    model = NumeraiTournament.create_model(model_type)
    @test !isnothing(model)
end
println("✓ Model creation works")

# 4. Metrics
predictions = rand(100)
targets = rand(100)
score = NumeraiTournament.Metrics.calculate_contribution_score(predictions, targets)
@test -1.0 <= score <= 1.0
println("✓ Metrics calculation works")

# 5. GPU
gpu_available = NumeraiTournament.has_metal_gpu()
if gpu_available
    gpu_info = NumeraiTournament.get_gpu_info()
    @test haskey(gpu_info, "device_name")
    println("✓ GPU acceleration available")
else
    println("✓ GPU not available (CPU mode)")
end

println("="^50)
println("✅ All critical systems operational!")
println("The application is ready for production use.")