#!/usr/bin/env julia
"""
Proper TC implementation based on the actual definition from research.

Based on Numerai documentation, TC measures the gradient of portfolio returns 
with respect to the stake of a particular model. Since we can't implement the
full portfolio optimization, we need a simpler approximation.

The key insight is that TC should measure:
1. How much the model contributes BEYOND what the meta-model already captures
2. The contribution should be to actual returns, not targets

Key correction: The signs were inverted because we need to think about what
"contribution" means in the context of orthogonalization.
"""

using Statistics
using LinearAlgebra
using Random

# Include core functions
include("simple_tc_test.jl")

function calculate_tc_proper(predictions::AbstractVector{T}, 
                            meta_model::AbstractVector{S}, 
                            returns::AbstractVector{U}) where {T, S, U}
    """
    Proper TC calculation based on understanding the actual definition.
    
    TC should measure: If I add this model to the meta-model, how much does it
    improve the correlation with returns?
    
    This is conceptually similar to MMC but measures return contribution directly.
    """
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Step 1: Gaussianize everything for fair comparison
    p = gaussianize(tie_kept_rank(predictions))
    m = gaussianize(tie_kept_rank(meta_model))
    r = returns  # Don't gaussianize returns - we want actual contribution to returns
    
    # Step 2: Get the unique contribution of predictions
    # This is the component of predictions not explained by meta-model  
    neutral_preds = orthogonalize(p, m)
    
    # Step 3: Measure how much this unique component correlates with returns
    if std(neutral_preds) == 0.0
        return 0.0  # No unique contribution
    end
    
    tc = cor(neutral_preds, r)
    
    return isnan(tc) ? 0.0 : tc
end

function calculate_tc_alternative(predictions::AbstractVector{T}, 
                                 meta_model::AbstractVector{S}, 
                                 returns::AbstractVector{U}) where {T, S, U}
    """
    Alternative TC calculation: Direct marginal contribution approach.
    
    Measures: What's the marginal improvement in correlation when adding 
    this model to the meta-model?
    """
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Baseline correlation of meta-model with returns
    baseline_corr = cor(meta_model, returns)
    
    # Create enhanced meta-model by adding this model with small weight
    weight = 0.1  # Small weight to measure marginal contribution
    enhanced_meta = (1 - weight) * meta_model + weight * predictions
    enhanced_corr = cor(enhanced_meta, returns)
    
    # TC is the improvement in correlation
    tc = enhanced_corr - baseline_corr
    
    return isnan(tc) ? 0.0 : tc
end

function debug_orthogonalization()
    """Debug the orthogonalization to understand the sign issue"""
    println("🔍 Debugging Orthogonalization")
    println("=" ^ 40)
    
    Random.seed!(42)
    n = 100  # Smaller for easier debugging
    
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    
    println("Original correlations:")
    println("  returns vs base_signal: $(round(cor(returns, base_signal), digits=3))")
    println("  meta_model vs base_signal: $(round(cor(meta_model, base_signal), digits=3))")
    println("  returns vs meta_model: $(round(cor(returns, meta_model), digits=3))")
    
    # Test perfect predictions
    perfect_predictions = copy(returns)
    p = gaussianize(tie_kept_rank(perfect_predictions))
    m = gaussianize(tie_kept_rank(meta_model))
    r = returns
    
    println("\nAfter gaussianization:")
    println("  gaussianized predictions vs returns: $(round(cor(p, r), digits=3))")
    println("  gaussianized meta_model vs returns: $(round(cor(m, r), digits=3))")
    println("  gaussianized predictions vs gaussianized meta_model: $(round(cor(p, m), digits=3))")
    
    # Orthogonalize 
    neutral_preds = orthogonalize(p, m)
    
    println("\nAfter orthogonalization:")
    println("  neutral_preds vs gaussianized meta_model: $(round(cor(neutral_preds, m), digits=10))")
    println("  neutral_preds vs returns: $(round(cor(neutral_preds, r), digits=3))")
    
    # The key insight: orthogonal component might have opposite sign
    # Let's check the projection
    p_centered = p .- mean(p)
    m_centered = m .- mean(m)
    proj_coeff = dot(p_centered, m_centered) / dot(m_centered, m_centered)
    
    println("\nProjection analysis:")
    println("  projection coefficient: $(round(proj_coeff, digits=3))")
    println("  (positive means p and m are positively correlated)")
    
    # When we remove positive projection, we get negative residual
    # This explains the sign inversion!
    
    return neutral_preds, r
end

function test_all_approaches()
    println("🔍 Testing All TC Approaches")
    println("=" ^ 40)
    
    Random.seed!(42)
    n = 1000
    
    # Create test data
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    
    test_cases = [
        ("Perfect predictions", copy(returns)),
        ("Anti-correlated", -returns),
        ("Same as meta-model", copy(meta_model)),
        ("Random noise", randn(n))
    ]
    
    println("Approach comparison:")
    for (desc, predictions) in test_cases
        tc_current = calculate_tc(predictions, meta_model, returns)
        tc_proper = calculate_tc_proper(predictions, meta_model, returns)
        tc_alt = calculate_tc_alternative(predictions, meta_model, returns)
        
        println("$(desc):")
        println("  Current:     $(round(tc_current, digits=4))")
        println("  Proper:      $(round(tc_proper, digits=4))")
        println("  Alternative: $(round(tc_alt, digits=4))")
        println()
    end
    
    # Debug the orthogonalization issue
    debug_orthogonalization()
end

test_all_approaches()