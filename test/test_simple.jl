#!/usr/bin/env julia

# Simple test that bypasses the full module system
println("Running simple functionality test...")

using Pkg
Pkg.activate(".")

try
    using DataFrames
    using Random
    using Statistics
    using LinearAlgebra
    
    println("✓ Basic packages imported")
    
    # Test basic DataFrame operations (mimicking preprocessing)
    df = DataFrame(a=[1.0, missing, 3.0], b=[missing, 2.0, missing])
    
    # Simple fillna implementation
    for col in names(df)
        df[!, col] = coalesce.(df[!, col], 0.0)
    end
    
    @assert !any(ismissing, df.a)
    @assert !any(ismissing, df.b)
    @assert df.a == [1.0, 0.0, 3.0]
    
    println("✓ DataFrame processing test passed")
    
    # Test basic normalization
    values = [1.0, 2.0, 3.0, 4.0, 5.0]
    normalized = (values .- minimum(values)) ./ (maximum(values) - minimum(values))
    @assert minimum(normalized) >= 0.0
    @assert maximum(normalized) <= 1.0
    @assert length(normalized) == length(values)
    
    println("✓ Normalization test passed")
    
    # Test basic linear algebra operations
    n = 100
    predictions = randn(n)
    features = randn(n, 10)
    
    # Simple neutralization (orthogonal projection)
    feature_mean = mean(features, dims=1)[:]
    predictions_centered = predictions .- mean(predictions)
    features_centered = features .- feature_mean'
    
    β = (features_centered' * features_centered + 1e-6 * I) \ (features_centered' * predictions_centered)
    neutralized = predictions_centered - features_centered * β
    
    @assert length(neutralized) == n
    
    println("✓ Neutralization test passed")
    
    println("✅ All simple tests passed!")
    
catch e
    println("❌ Error during simple test:")
    println(e)
    rethrow()
end