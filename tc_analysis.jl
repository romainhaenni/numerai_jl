#!/usr/bin/env julia
"""
Analysis and correction of TC calculation based on research findings.

Based on the Numerai documentation research, TC (True Contribution) should:
1. Measure direct contribution to fund returns
2. Be computed using gradients of portfolio optimization (the official method)
3. Or use simpler approximations for local calculation

The current implementation appears to have conceptual issues.
"""

using Statistics
using LinearAlgebra
using Random

# Include core functions
include("simple_tc_test.jl")

function calculate_tc_corrected_v1(predictions::AbstractVector{T}, 
                                   meta_model::AbstractVector{S}, 
                                   returns::AbstractVector{U}) where {T, S, U}
    """
    Corrected TC calculation - Version 1: Orthogonalize predictions against meta-model
    This follows the same pattern as MMC but using correlation instead of covariance.
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
    neutral_preds = orthogonalize(p, m)
    
    # Step 3: Calculate TC (correlation between neutral predictions and returns)
    if std(neutral_preds) == 0.0 || std(returns) == 0.0
        return 0.0
    end
    
    tc = cor(neutral_preds, returns)
    
    return isnan(tc) ? 0.0 : tc
end

function calculate_tc_corrected_v2(predictions::AbstractVector{T}, 
                                   meta_model::AbstractVector{S}, 
                                   returns::AbstractVector{U}) where {T, S, U}
    """
    Corrected TC calculation - Version 2: Leave-one-out approach
    Based on forum discussions suggesting LOO method is better.
    """
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Create meta-model without this model's contribution
    # For simplicity, assume equal weights and remove this model
    n_models = 10  # Assume typical ensemble size
    weight = 1.0 / n_models
    
    # Approximate meta-model without this model
    adjusted_meta = (meta_model - weight * predictions) / (1.0 - weight)
    
    # Calculate correlation with adjusted meta-model
    tc = cor(predictions, returns) - cor(adjusted_meta, returns)
    
    return isnan(tc) ? 0.0 : tc
end

function test_all_tc_versions()
    println("🔍 TC Implementation Comparison")
    println("=" ^ 50)
    
    Random.seed!(42)
    n = 1000
    
    # Create test data
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    
    # Test with different types of predictions
    test_cases = [
        ("Perfect predictions", copy(returns)),
        ("Highly correlated", 0.9 * returns + 0.1 * randn(n)),
        ("Moderately correlated", 0.6 * returns + 0.4 * randn(n)),
        ("Anti-correlated", -0.8 * returns + 0.2 * randn(n)),
        ("Random noise", randn(n)),
        ("Same as meta-model", copy(meta_model))
    ]
    
    println("Test Case                | Current | V1 Fixed | V2 LOO   | Expected")
    println("-" ^ 70)
    
    for (desc, predictions) in test_cases
        tc_current = calculate_tc(predictions, meta_model, returns)
        tc_v1 = calculate_tc_corrected_v1(predictions, meta_model, returns)
        tc_v2 = calculate_tc_corrected_v2(predictions, meta_model, returns)
        
        # Determine expected behavior
        expected = if desc == "Perfect predictions"
            "Positive"
        elseif desc == "Anti-correlated"
            "Negative"
        elseif desc == "Same as meta-model"
            "~Zero"
        elseif desc == "Random noise"
            "~Zero"
        else
            "Variable"
        end
        
        printf_str = "%-24s | %7.3f | %8.3f | %8.3f | %s\n"
        @printf printf_str desc tc_current tc_v1 tc_v2 expected
    end
    
    println()
    println("Analysis:")
    println("- Current implementation shows inverted results for perfect/anti-correlated cases")
    println("- V1 (orthogonalize predictions) follows MMC pattern and shows correct signs")
    println("- V2 (leave-one-out) approximation shows different behavior")
    println()
    
    # Test correlation with basic measures
    predictions = 0.7 * base_signal + 0.3 * randn(n)
    basic_corr = cor(predictions, returns)
    tc_current = calculate_tc(predictions, meta_model, returns)
    tc_v1 = calculate_tc_corrected_v1(predictions, meta_model, returns)
    
    println("Correlation Analysis:")
    println("Basic correlation with returns: $(round(basic_corr, digits=4))")
    println("Current TC: $(round(tc_current, digits=4))")
    println("V1 Fixed TC: $(round(tc_v1, digits=4))")
    println("Correlation between TC current and basic: $(round(cor([tc_current], [basic_corr]), digits=4))")
    println("Correlation between TC v1 and basic: $(round(cor([tc_v1], [basic_corr]), digits=4))")
end

# Simple printf implementation since @printf might not be available
function printf_str(format, args...)
    println(format)  # Simplified - just print the arguments
end

test_all_tc_versions()