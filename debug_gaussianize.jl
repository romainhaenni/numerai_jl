#!/usr/bin/env julia
"""
Debug the gaussianization process to understand why signs are flipping.
"""

using Statistics
using LinearAlgebra
using Random

include("simple_tc_test.jl")

function debug_gaussianization_steps()
    println("🔍 Debugging Gaussianization Steps")
    println("=" ^ 40)
    
    Random.seed!(42)
    n = 20  # Small dataset for easy inspection
    
    # Create simple test data
    original = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    println("Original data: $(original)")
    
    # Step 1: Ranking
    ranks = tie_kept_rank(original)
    println("Ranks: $(ranks)")
    
    # Step 2: Convert to percentiles
    percentiles = (ranks .- 0.5) ./ length(ranks)
    println("Percentiles: $(percentiles)")
    
    # Step 3: Convert to normal quantiles
    quantiles = map(p -> quantile_normal_approx(p), percentiles)
    println("Quantiles: $(quantiles)")
    
    # Step 4: Standardize
    gaussianized = (quantiles .- mean(quantiles)) ./ std(quantiles)
    println("Gaussianized: $(gaussianized)")
    
    # Check correlation with original
    correlation = cor(original, gaussianized)
    println("Correlation with original: $(correlation)")
    
    # Test with the actual function
    gauss_result = gaussianize(original)
    println("Function result: $(gauss_result)")
    println("Correlation with function result: $(cor(original, gauss_result))")
    
    println("\nThe gaussianization preserves rank order, so correlation should be positive!")
    
    # Test with the problematic case
    println("\n" * "=" * 40)
    println("Testing problematic case:")
    
    base_signal = randn(100)  # Random baseline
    returns = 0.8 * base_signal + 0.2 * randn(100)  # Correlated with baseline
    perfect_predictions = copy(returns)  # Perfect predictions
    
    println("Original correlation (perfect vs returns): $(round(cor(perfect_predictions, returns), digits=4))")
    
    # Apply ranking and gaussianization
    perfect_ranks = tie_kept_rank(perfect_predictions)
    perfect_gauss = gaussianize(perfect_predictions)
    
    println("After ranking: $(round(cor(perfect_ranks, returns), digits=4))")
    println("After gaussianization: $(round(cor(perfect_gauss, returns), digits=4))")
    
    # The issue might be in the quantile_normal_approx function or the standardization
    println("Investigating quantile function...")
    
    # Test quantile function with simple percentiles
    test_percentiles = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
    test_quantiles = [quantile_normal_approx(p) for p in test_percentiles]
    println("Test percentiles: $(test_percentiles)")
    println("Test quantiles: $(test_quantiles)")
    
    # These should be monotonically increasing
    is_monotonic = all(test_quantiles[i] <= test_quantiles[i+1] for i in 1:length(test_quantiles)-1)
    println("Quantiles are monotonic: $(is_monotonic)")
    
end

debug_gaussianization_steps()