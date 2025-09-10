#!/usr/bin/env julia
"""
Direct test of TC functions without full package loading for faster execution.
"""

using Statistics
using LinearAlgebra
using Random

# Copy the core functions from the metrics file for direct testing
function tie_kept_rank(x::AbstractVector{T}) where T
    n = length(x)
    if n == 0
        return Float64[]
    end
    
    # Create pairs of (value, original_index)
    indexed_values = [(x[i], i) for i in 1:n]
    
    # Sort by value, keeping original order for ties
    sort!(indexed_values, by=pair -> (pair[1], pair[2]))
    
    # Assign ranks
    ranks = Vector{Float64}(undef, n)
    for (rank, (_, original_idx)) in enumerate(indexed_values)
        ranks[original_idx] = Float64(rank)
    end
    
    return ranks
end

function quantile_normal_approx(p::Float64)
    # Beasley-Springer-Moro algorithm for inverse normal CDF
    if p <= 0.0
        return -Inf
    elseif p >= 1.0
        return Inf
    elseif p == 0.5
        return 0.0
    end
    
    # Coefficients for the approximation
    a = [0.0, -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    
    b = [0.0, -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 
         6.680131188771972e+01, -1.328068155288572e+01]
    
    c = [0.0, -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, 
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    
    d = [0.0, 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 
         3.754408661907416e+00]
    
    # Define split points
    p_low = 0.02425
    p_high = 1.0 - p_low
    
    if p < p_low
        # Rational approximation for lower region
        q = sqrt(-2.0 * log(p))
        return (((((c[7]*q + c[6])*q + c[5])*q + c[4])*q + c[3])*q + c[2])*q + c[1] / 
               ((((d[5]*q + d[4])*q + d[3])*q + d[2])*q + d[1])
    elseif p <= p_high
        # Rational approximation for central region
        q = p - 0.5
        r = q * q
        return (((((a[7]*r + a[6])*r + a[5])*r + a[4])*r + a[3])*r + a[2])*r + a[1] * q / 
               (((((b[6]*r + b[5])*r + b[4])*r + b[3])*r + b[2])*r + b[1])
    else
        # Rational approximation for upper region
        q = sqrt(-2.0 * log(1.0 - p))
        return -(((((c[7]*q + c[6])*q + c[5])*q + c[4])*q + c[3])*q + c[2])*q - c[1] / 
                ((((d[5]*q + d[4])*q + d[3])*q + d[2])*q + d[1])
    end
end

function gaussianize(x::AbstractVector{T}) where T
    if length(x) <= 1
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    # First get the tie-kept ranks
    ranks = tie_kept_rank(x)
    
    # Convert ranks to percentiles (0 to 1)
    n = length(ranks)
    percentiles = (ranks .- 0.5) ./ n
    
    # Clip to avoid infinite values at extremes
    percentiles = clamp.(percentiles, 1e-10, 1.0 - 1e-10)
    
    # Convert to standard normal quantiles
    gaussianized = map(p -> quantile_normal_approx(p), percentiles)
    
    # Ensure mean=0 and std=1
    gaussianized = (gaussianized .- mean(gaussianized)) ./ std(gaussianized)
    
    return gaussianized
end

function orthogonalize(x::AbstractVector{T}, reference::AbstractVector{S}) where {T, S}
    if length(x) != length(reference)
        throw(ArgumentError("Vectors must have the same length"))
    end
    
    if length(x) <= 1
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    # Center both vectors
    x_centered = x .- mean(x)
    ref_centered = reference .- mean(reference)
    
    # Calculate the projection coefficient
    ref_norm_sq = dot(ref_centered, ref_centered)
    
    if ref_norm_sq == 0.0
        # Reference vector has no variance, return original x
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    projection_coeff = dot(x_centered, ref_centered) / ref_norm_sq
    
    # Remove the projection onto the reference
    orthogonal = x_centered - projection_coeff * ref_centered
    
    return orthogonal
end

function calculate_tc(predictions::AbstractVector{T}, 
                      meta_model::AbstractVector{S}, 
                      returns::AbstractVector{U}) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Step 1: Rank and gaussianize predictions
    p = gaussianize(tie_kept_rank(predictions))
    
    # Step 2: Orthogonalize returns with respect to meta-model
    orthogonal_returns = orthogonalize(returns, meta_model)
    
    # Step 3: Calculate TC (correlation between gaussianized predictions and orthogonalized returns)
    if std(orthogonal_returns) == 0.0
        return 0.0
    end
    
    tc = cor(p, orthogonal_returns)
    
    return isnan(tc) ? 0.0 : tc
end

function test_tc_implementation()
    println("🔍 Direct TC Implementation Test")
    println("=" ^ 40)
    
    Random.seed!(42)
    n = 1000
    
    # Basic test case
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    predictions = 0.7 * base_signal + 0.3 * randn(n)
    
    tc = calculate_tc(predictions, meta_model, returns)
    println("Basic TC calculation: $(round(tc, digits=4))")
    
    # Test perfect correlation
    perfect_predictions = copy(returns)
    tc_perfect = calculate_tc(perfect_predictions, meta_model, returns)
    println("Perfect predictions TC: $(round(tc_perfect, digits=4))")
    
    # Test anti-correlation
    anti_predictions = -returns
    tc_anti = calculate_tc(anti_predictions, meta_model, returns)
    println("Anti-correlated TC: $(round(tc_anti, digits=4))")
    
    # Test identical to meta-model
    identical_predictions = copy(meta_model)
    tc_identical = calculate_tc(identical_predictions, meta_model, returns)
    println("Identical to meta-model TC: $(round(tc_identical, digits=4))")
    
    println("\nResults Analysis:")
    println("✓ Basic TC is reasonable: " * (-1.0 < tc < 1.0 ? "✓" : "✗"))
    println("✓ Perfect should be positive: " * (tc_perfect > 0 ? "✓" : "✗"))
    println("✓ Anti-correlated should be negative: " * (tc_anti < 0 ? "✓" : "✗"))
    println("✓ Identical should be near zero: " * (abs(tc_identical) < 0.1 ? "✓" : "✗"))
    
    # Test edge cases
    println("\nEdge Cases:")
    # Constant returns
    constant_returns = fill(5.0, 100)
    constant_meta = fill(3.0, 100)
    normal_preds = randn(100)
    tc_constant = calculate_tc(normal_preds, constant_meta, constant_returns)
    println("Constant returns TC: $(tc_constant)")
    
    # Very small dataset
    small_tc = calculate_tc([1.0, 2.0, 3.0], [1.5, 2.5, 3.5], [1.2, 2.2, 3.2])
    println("Small dataset TC: $(small_tc)")
    
    println("\nAll tests completed!")
end

test_tc_implementation()