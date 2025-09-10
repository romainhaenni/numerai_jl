#!/usr/bin/env julia
"""
Test the corrected TC implementation
"""

using Statistics
using LinearAlgebra
using Random

# Copy the corrected functions for testing
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

function quantile_normal_approx_corrected(p::Float64)
    # Corrected quantile function using simple robust approximation
    
    if p <= 0.0
        return -Inf
    elseif p >= 1.0
        return Inf
    elseif p == 0.5
        return 0.0
    end
    
    # Simple robust approximation using Box-Muller inspired method
    # This ensures monotonicity which is critical for TC calculation
    if p < 0.5
        # For lower half, use symmetry
        return -quantile_normal_approx_corrected(1.0 - p)
    else
        # For upper half, use approximation
        if p <= 0.5 + 1e-10
            return 0.0
        end
        
        # Simple approximation that maintains monotonicity
        t = sqrt(-2.0 * log(1.0 - p))
        
        # Rational approximation
        num = 2.515517 + 0.802853 * t + 0.010328 * t * t
        den = 1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t
        
        return t - num / den
    end
end

function gaussianize_corrected(x::AbstractVector{T}) where T
    if length(x) <= 1
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    # First get the tie-kept ranks
    ranks = tie_kept_rank(x)
    
    # Convert ranks to percentiles (0 to 1)
    n = length(ranks)
    percentiles = (ranks .- 0.5) ./ n
    
    # Clip to avoid infinite values at extremes
    percentiles = clamp.(percentiles, 1e-6, 1.0 - 1e-6)
    
    # Convert to standard normal quantiles
    gaussianized = map(p -> quantile_normal_approx_corrected(p), percentiles)
    
    # Check for any NaN or Inf values and handle them
    gaussianized = [isnan(x) || isinf(x) ? 0.0 : x for x in gaussianized]
    
    # Ensure mean=0 and std=1 (only if std > 0)
    if std(gaussianized) > 1e-10
        gaussianized = (gaussianized .- mean(gaussianized)) ./ std(gaussianized)
    end
    
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

function calculate_tc_corrected(predictions::AbstractVector{T}, 
                               meta_model::AbstractVector{S}, 
                               returns::AbstractVector{U}) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Step 1: Rank and gaussianize predictions using corrected function
    p = gaussianize_corrected(tie_kept_rank(predictions))
    
    # Step 2: Orthogonalize returns with respect to meta-model
    orthogonal_returns = orthogonalize(returns, meta_model)
    
    # Step 3: Calculate TC (correlation between gaussianized predictions and orthogonalized returns)
    if std(orthogonal_returns) == 0.0
        return 0.0
    end
    
    tc = cor(p, orthogonal_returns)
    
    return isnan(tc) ? 0.0 : tc
end

function test_corrected_implementation()
    println("🔍 Testing Corrected TC Implementation")
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
    tc_perfect = calculate_tc_corrected(perfect_predictions, meta_model, returns)
    println("Perfect predictions TC: $(round(tc_perfect, digits=4)) (should be positive)")
    
    # Anti-correlated
    anti_predictions = -returns
    tc_anti = calculate_tc_corrected(anti_predictions, meta_model, returns)
    println("Anti-correlated predictions TC: $(round(tc_anti, digits=4)) (should be negative)")
    
    # Identical to meta-model
    identical_predictions = copy(meta_model)
    tc_identical = calculate_tc_corrected(identical_predictions, meta_model, returns)
    println("Identical to meta-model TC: $(round(tc_identical, digits=4)) (should be ~zero)")
    
    # Random predictions
    random_predictions = randn(n)
    tc_random = calculate_tc_corrected(random_predictions, meta_model, returns)
    println("Random predictions TC: $(round(tc_random, digits=4)) (should be ~zero)")
    
    # Test gaussianization preservation of order
    println("\nGaussianization Test:")
    original = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    gaussianized = gaussianize_corrected(original)
    correlation = cor(original, gaussianized)
    is_monotonic = all(gaussianized[i] <= gaussianized[i+1] for i in 1:length(gaussianized)-1)
    
    println("Original: $original")
    println("Gaussianized: $(round.(gaussianized, digits=3))")
    println("Correlation: $(round(correlation, digits=4)) (should be ~1.0)")
    println("Is monotonic: $is_monotonic (should be true)")
    
    # Test quantile function monotonicity
    println("\nQuantile Function Test:")
    percentiles = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]
    quantiles = [quantile_normal_approx_corrected(p) for p in percentiles]
    is_monotonic_q = all(quantiles[i] <= quantiles[i+1] for i in 1:length(quantiles)-1)
    println("Percentiles: $percentiles")
    println("Quantiles: $(round.(quantiles, digits=3))")
    println("Is monotonic: $is_monotonic_q (should be true)")
    
    println("\nValidation:")
    println("✓ Perfect predictions should have positive TC" * (tc_perfect > 0 ? " ✓" : " ✗"))
    println("✓ Anti-correlated should have negative TC" * (tc_anti < 0 ? " ✓" : " ✗"))
    println("✓ Identical to meta-model should have TC near zero" * (abs(tc_identical) < 0.1 ? " ✓" : " ✗"))
    println("✓ Random should have TC near zero" * (abs(tc_random) < 0.2 ? " ✓" : " ✗"))
    println("✓ Gaussianization should preserve order" * (correlation > 0.9 ? " ✓" : " ✗"))
    println("✓ Quantile function should be monotonic" * (is_monotonic_q ? " ✓" : " ✗"))
end

test_corrected_implementation()