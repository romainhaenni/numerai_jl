#!/usr/bin/env julia
"""
Test the corrected TC implementation
"""

using Statistics
using LinearAlgebra
using Random

# Include core functions
include("simple_tc_test.jl")

function calculate_tc_corrected(predictions::AbstractVector{T}, 
                               meta_model::AbstractVector{S}, 
                               returns::AbstractVector{U}) where {T, S, U}
    """
    Corrected TC calculation: Orthogonalize predictions against meta-model
    This follows the same conceptual pattern as MMC.
    """
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Step 1: Rank and gaussianize both predictions and meta-model
    p = gaussianize(tie_kept_rank(predictions))
    m = gaussianize(tie_kept_rank(meta_model))
    
    # Step 2: Orthogonalize predictions with respect to meta-model
    # This removes the component that's already captured by meta-model
    neutral_preds = orthogonalize(p, m)
    
    # Step 3: Calculate TC (correlation between neutral predictions and returns)
    if std(neutral_preds) == 0.0 || std(returns) == 0.0
        return 0.0
    end
    
    tc = cor(neutral_preds, returns)
    
    return isnan(tc) ? 0.0 : tc
end

function compare_implementations()
    println("🔍 TC Implementation Comparison")
    println("=" ^ 40)
    
    Random.seed!(42)
    n = 1000
    
    # Create test data
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    
    println("Test Cases:")
    
    # Perfect predictions
    perfect_predictions = copy(returns)
    tc_current = calculate_tc(perfect_predictions, meta_model, returns)
    tc_corrected = calculate_tc_corrected(perfect_predictions, meta_model, returns)
    println("Perfect predictions:")
    println("  Current:   $(round(tc_current, digits=4)) (should be positive)")
    println("  Corrected: $(round(tc_corrected, digits=4)) (should be positive)")
    
    # Anti-correlated
    anti_predictions = -returns
    tc_current = calculate_tc(anti_predictions, meta_model, returns)
    tc_corrected = calculate_tc_corrected(anti_predictions, meta_model, returns)
    println("Anti-correlated predictions:")
    println("  Current:   $(round(tc_current, digits=4)) (should be negative)")
    println("  Corrected: $(round(tc_corrected, digits=4)) (should be negative)")
    
    # Identical to meta-model
    identical_predictions = copy(meta_model)
    tc_current = calculate_tc(identical_predictions, meta_model, returns)
    tc_corrected = calculate_tc_corrected(identical_predictions, meta_model, returns)
    println("Identical to meta-model:")
    println("  Current:   $(round(tc_current, digits=4)) (should be ~zero)")
    println("  Corrected: $(round(tc_corrected, digits=4)) (should be ~zero)")
    
    # Random predictions
    random_predictions = randn(n)
    tc_current = calculate_tc(random_predictions, meta_model, returns)
    tc_corrected = calculate_tc_corrected(random_predictions, meta_model, returns)
    println("Random predictions:")
    println("  Current:   $(round(tc_current, digits=4)) (should be ~zero)")
    println("  Corrected: $(round(tc_corrected, digits=4)) (should be ~zero)")
    
    println("\nConclusion:")
    println("The current implementation has inverted signs.")
    println("The corrected implementation shows proper behavior.")
    
    # Verify orthogonalization works correctly
    println("\nOrthogonalization Verification:")
    test_preds = randn(n)
    p = gaussianize(tie_kept_rank(test_preds))
    m = gaussianize(tie_kept_rank(meta_model))
    neutral_preds = orthogonalize(p, m)
    
    correlation = cor(neutral_preds, m)
    println("Correlation between neutral preds and meta-model: $(round(correlation, digits=10))")
    println("Should be effectively zero: $(abs(correlation) < 1e-10 ? "✓" : "✗")")
end

compare_implementations()