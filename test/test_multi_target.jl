#!/usr/bin/env julia
"""
Test script to demonstrate multi-target support in NumeraiTournament.jl

This script tests:
1. Backward compatibility with single-target workflows
2. Multi-target pipeline creation and configuration
3. Multi-target data preparation
4. Multi-target model training (neural networks)
5. Multi-target prediction and evaluation
"""

using Pkg
Pkg.activate(".")

using DataFrames
using Random
using Statistics

# Load our module
include("../src/NumeraiTournament.jl")
using .NumeraiTournament

# Set random seed for reproducibility
Random.seed!(42)

println("🚀 Testing Multi-Target Support in NumeraiTournament.jl")
println(repeat("=", 60))

# Create synthetic test data
println("\n1. Creating synthetic test data...")
n_samples = 1000
n_features = 20
n_eras = 10

# Generate features
feature_names = ["feature_$i" for i in 1:n_features]
X_data = randn(n_samples, n_features)

# Generate multiple correlated targets (V5-style)
target_names = ["target_v5_a", "target_v5_b", "target_v5_c", "target_v5_d"]
n_targets = length(target_names)

# Create correlated targets
base_signal = X_data[:, 1:5] * randn(5, 1) |> vec
y_data = Matrix{Float64}(undef, n_samples, n_targets)
for i in 1:n_targets
    # Each target is the base signal plus some noise and slight variations
    y_data[:, i] = base_signal .+ 0.3 * randn(n_samples) .+ 0.1 * X_data[:, i]
end

# Create DataFrame
df = DataFrame()
for (i, name) in enumerate(feature_names)
    df[!, name] = X_data[:, i]
end
for (i, name) in enumerate(target_names)
    df[!, name] = y_data[:, i]
end
df.era = repeat(1:n_eras, inner=n_samples÷n_eras)[1:n_samples]
df.id = 1:n_samples

println("   ✅ Created dataset: $(nrow(df)) samples, $(n_features) features, $(n_targets) targets")

# Test 1: Backward compatibility with single target
println("\n2. Testing backward compatibility (single target)...")
try
    single_pipeline = NumeraiTournament.Pipeline.MLPipeline(
        feature_cols=feature_names,
        target_col="target_v5_a"
    )
    
    println("   ✅ Single-target pipeline created successfully")
    println("      - is_multi_target: $(single_pipeline.is_multi_target)")
    println("      - n_targets: $(single_pipeline.n_targets)")
    
    # Test data preparation
    X, y, eras = NumeraiTournament.Pipeline.prepare_data(single_pipeline, df)
    println("   ✅ Single-target data preparation: X=$(size(X)), y=$(size(y)), eras=$(length(eras))")
    
catch e
    println("   ❌ Single-target test failed: $e")
end

# Test 2: Multi-target pipeline creation
println("\n3. Testing multi-target pipeline creation...")
try
    multi_pipeline = NumeraiTournament.Pipeline.MLPipeline(
        feature_cols=feature_names,
        target_col=target_names,  # Vector of target names
        model_configs=[
            NumeraiTournament.Pipeline.ModelConfig("mlp", 
                Dict(:hidden_layers => [32, 16], :epochs => 5, :batch_size => 128))
        ]
    )
    
    println("   ✅ Multi-target pipeline created successfully")
    println("      - is_multi_target: $(multi_pipeline.is_multi_target)")
    println("      - n_targets: $(multi_pipeline.n_targets)")
    println("      - target_cols: $(multi_pipeline.target_cols)")
    
    # Test data preparation
    X, y, eras = NumeraiTournament.Pipeline.prepare_data(multi_pipeline, df)
    println("   ✅ Multi-target data preparation: X=$(size(X)), y=$(size(y)), eras=$(length(eras))")
    
    # Split data
    train_mask = df.era .<= 7
    train_df = df[train_mask, :]
    val_df = df[.!train_mask, :]
    
    println("   ✅ Data split: train=$(nrow(train_df)), val=$(nrow(val_df))")
    
    # Test training (quick test with small epochs)
    println("\n4. Testing multi-target training...")
    NumeraiTournament.Pipeline.train!(multi_pipeline, train_df, val_df, verbose=true)
    println("   ✅ Multi-target training completed")
    
    # Test prediction
    println("\n5. Testing multi-target prediction...")
    predictions = NumeraiTournament.Pipeline.predict(multi_pipeline, val_df, verbose=true)
    println("   ✅ Multi-target predictions: $(size(predictions))")
    
    # Calculate correlations for each target
    if predictions isa Matrix
        _, y_val, _ = NumeraiTournament.Pipeline.prepare_data(multi_pipeline, val_df)
        correlations = [cor(predictions[:, i], y_val[:, i]) for i in 1:n_targets]
        println("   ✅ Target correlations: $(round.(correlations, digits=4))")
        println("      - Average correlation: $(round(mean(correlations), digits=4))")
    end
    
    println("\n🎉 All multi-target tests passed successfully!")
    
catch e
    println("   ❌ Multi-target test failed: $e")
    println("   📚 Stack trace:")
    for (i, frame) in enumerate(stacktrace(catch_backtrace()))
        if i <= 5  # Show first 5 frames
            println("      $i. $frame")
        end
    end
end

println("\n" * repeat("=", 60))
println("✅ Multi-target support implementation test completed")