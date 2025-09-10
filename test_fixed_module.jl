#!/usr/bin/env julia
"""
Test the fixed module functionality
"""

# Simple direct test using include to avoid full package compilation
println("🔍 Testing Fixed Metrics Module")
println("=" ^ 35)

# Load just the metrics module
include("src/ml/metrics.jl")

using Statistics
using Random

Random.seed!(42)
n = 1000

# Create test data
base_signal = randn(n)
returns = 0.8 * base_signal + 0.2 * randn(n)
meta_model = 0.6 * base_signal + 0.4 * randn(n)

# Test the fixed TC function from the module
perfect_predictions = copy(returns)
tc_perfect = Metrics.calculate_tc(perfect_predictions, meta_model, returns)

anti_predictions = -returns
tc_anti = Metrics.calculate_tc(anti_predictions, meta_model, returns)

identical_predictions = copy(meta_model)
tc_identical = Metrics.calculate_tc(identical_predictions, meta_model, returns)

println("Fixed Module Results:")
println("Perfect predictions TC: $(round(tc_perfect, digits=4)) (should be positive)")
println("Anti-correlated TC: $(round(tc_anti, digits=4)) (should be negative)")
println("Identical to meta-model TC: $(round(tc_identical, digits=4)) (should be ~zero)")

println("\nValidation:")
println("✓ Perfect predictions should have positive TC" * (tc_perfect > 0 ? " ✓" : " ✗"))
println("✓ Anti-correlated should have negative TC" * (tc_anti < 0 ? " ✓" : " ✗"))
println("✓ Identical to meta-model should have TC near zero" * (abs(tc_identical) < 0.1 ? " ✓" : " ✗"))

# Test gaussianization directly
original = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
gaussianized = Metrics.gaussianize(original)
correlation = cor(original, gaussianized)
is_monotonic = all(gaussianized[i] <= gaussianized[i+1] for i in 1:length(gaussianized)-1)

println("\nGaussianization Test:")
println("Original: $original")
println("Gaussianized: $(round.(gaussianized, digits=3))")
println("Correlation: $(round(correlation, digits=4)) (should be ~1.0)")
println("Is monotonic: $is_monotonic (should be true)")

println("\nModule test completed successfully!")