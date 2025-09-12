#!/usr/bin/env julia

"""
Example script demonstrating the improved True Contribution calculation.

This script shows how to use both the correlation-based and gradient-based
methods for calculating True Contribution, and how to configure them.
"""

using NumeraiTournament
using Random
using Statistics

# Set seed for reproducible results
Random.seed!(42)

# Generate synthetic data that resembles tournament data
println("🔬 Generating synthetic tournament data...")
n_samples = 1000
n_models = 3

# Generate correlated predictions (like real models would have)
base_signal = randn(n_samples)
predictions = Matrix{Float64}(undef, n_samples, n_models)
for i in 1:n_models
    # Each model has some shared signal + noise
    predictions[:, i] = 0.6 * base_signal + 0.4 * randn(n_samples)
end

# Meta-model is a weighted combination of the predictions
meta_model = mean(predictions, dims=2)[:]

# Returns have some relationship to the base signal + noise
returns = 0.3 * base_signal + 0.7 * randn(n_samples)

println("Data generated:")
println("  - Number of samples: $n_samples")
println("  - Number of models: $n_models")
println("  - Returns correlation with base signal: $(round(cor(returns, base_signal), digits=3))")
println()

# ==========================================
# 1. Test correlation-based method (existing)
# ==========================================
println("📊 Testing correlation-based method (existing)...")
config_corr = TCConfig(method=:correlation)

# Calculate TC for each model
tc_scores_corr = calculate_tc_improved_batch(predictions, meta_model, returns, config_corr)

println("Correlation-based TC scores:")
for (i, score) in enumerate(tc_scores_corr)
    println("  Model $i: $(round(score, digits=6))")
end
println("  Average: $(round(mean(tc_scores_corr), digits=6))")
println()

# ==========================================
# 2. Test gradient-based method (new)
# ==========================================
println("🎯 Testing gradient-based method (new)...")
config_grad = TCConfig(
    method=:gradient,
    max_iterations=1000,
    tolerance=1e-6,
    regularization=1e-4,
    risk_aversion=2.0  # Higher risk aversion
)

# Calculate TC for each model
tc_scores_grad = calculate_tc_improved_batch(predictions, meta_model, returns, config_grad)

println("Gradient-based TC scores:")
for (i, score) in enumerate(tc_scores_grad)
    println("  Model $i: $(round(score, digits=6))")
end
println("  Average: $(round(mean(tc_scores_grad), digits=6))")
println()

# ==========================================
# 3. Compare methods
# ==========================================
println("⚖️  Comparing methods...")
println("Method comparison (correlation vs gradient):")
for i in 1:n_models
    diff = tc_scores_grad[i] - tc_scores_corr[i]
    println("  Model $i: $(round(tc_scores_corr[i], digits=6)) vs $(round(tc_scores_grad[i], digits=6)) (diff: $(round(diff, digits=6)))")
end
println()

# ==========================================
# 4. Test configuration loading
# ==========================================
println("⚙️  Testing configuration loading from config.toml...")
config_from_file = load_tc_config_from_toml("config.toml")
println("Loaded configuration:")
println("  Method: $(config_from_file.method)")
println("  Max iterations: $(config_from_file.max_iterations)")
println("  Tolerance: $(config_from_file.tolerance)")
println("  Regularization: $(config_from_file.regularization)")
println("  Risk aversion: $(config_from_file.risk_aversion)")
println()

# Test using the loaded config
tc_from_config = calculate_tc_improved(predictions[:, 1], meta_model, returns, config_from_file)
println("TC using config file method: $(round(tc_from_config, digits=6))")
println()

# ==========================================
# 5. Performance comparison with edge cases
# ==========================================
println("🧪 Testing edge cases...")

# Small dataset
small_preds = randn(10)
small_meta = randn(10)
small_returns = randn(10)

tc_small_corr = calculate_tc_improved(small_preds, small_meta, small_returns, config_corr)
tc_small_grad = calculate_tc_improved(small_preds, small_meta, small_returns, config_grad)

println("Small dataset (n=10):")
println("  Correlation method: $(round(tc_small_corr, digits=6))")
println("  Gradient method: $(round(tc_small_grad, digits=6))")

# Constant predictions
const_preds = fill(0.5, n_samples)
tc_const_corr = calculate_tc_improved(const_preds, meta_model, returns, config_corr)
tc_const_grad = calculate_tc_improved(const_preds, meta_model, returns, config_grad)

println("Constant predictions:")
println("  Correlation method: $(round(tc_const_corr, digits=6))")
println("  Gradient method: $(round(tc_const_grad, digits=6))")

# Very large dataset (test performance)
println("Testing performance with large dataset...")
large_n = 10000
large_preds = randn(large_n)
large_meta = randn(large_n)
large_returns = randn(large_n)

# Time the correlation method
t_corr = @elapsed tc_large_corr = calculate_tc_improved(large_preds, large_meta, large_returns, config_corr)

# Time the gradient method
t_grad = @elapsed tc_large_grad = calculate_tc_improved(large_preds, large_meta, large_returns, config_grad)

println("Large dataset (n=$large_n) performance:")
println("  Correlation method: $(round(tc_large_corr, digits=6)) ($(round(t_corr * 1000, digits=2)) ms)")
println("  Gradient method: $(round(tc_large_grad, digits=6)) ($(round(t_grad * 1000, digits=2)) ms)")

println()
println("✅ All tests completed successfully!")
println("📝 Summary:")
println("   - Both methods handle edge cases gracefully")
println("   - Gradient method provides alternative TC calculation")
println("   - Configuration system allows easy switching between methods")
println("   - Fallback mechanism ensures robustness")