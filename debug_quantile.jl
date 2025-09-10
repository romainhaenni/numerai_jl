#!/usr/bin/env julia
"""
Debug the quantile_normal_approx function
"""

using Statistics
using LinearAlgebra

include("simple_tc_test.jl")

function test_quantile_function()
    println("🔍 Testing Quantile Function")
    println("=" ^ 30)
    
    # Test with evenly spaced percentiles
    percentiles = [0.01, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99]
    
    println("Percentile -> Quantile:")
    quantiles = Float64[]
    for p in percentiles
        q = quantile_normal_approx(p)
        push!(quantiles, q)
        println("  $p -> $q")
    end
    
    # Check if monotonic
    is_monotonic = true
    for i in 1:length(quantiles)-1
        if quantiles[i] > quantiles[i+1]
            println("NON-MONOTONIC at index $i: $(quantiles[i]) > $(quantiles[i+1])")
            is_monotonic = false
        end
    end
    
    println("Is monotonic: $is_monotonic")
    
    # Test the specific problematic values from the debug
    problematic = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]
    println("\nProblematic values:")
    for p in problematic
        q = quantile_normal_approx(p)
        println("  $p -> $q")
    end
end

# Let's try a simple standard library approach instead
function quantile_normal_simple(p::Float64)
    """Simple approximation using the Box-Muller inspired approach"""
    if p <= 0.0001
        return -4.0
    elseif p >= 0.9999
        return 4.0
    elseif p == 0.5
        return 0.0
    end
    
    # Simple linear interpolation around key points
    # This is not accurate but should be monotonic
    if p < 0.5
        return -4.0 + 8.0 * p
    else
        return -4.0 + 8.0 * p
    end
end

function test_simple_quantile()
    println("\\n🔍 Testing Simple Quantile Function")
    println("=" * 35)
    
    percentiles = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]
    
    println("Percentile -> Simple Quantile:")
    for p in percentiles
        q = quantile_normal_simple(p)
        println("  $p -> $q")
    end
end

function test_fixed_gaussianize()
    """Test a corrected version of gaussianize using a proper quantile function"""
    println("\\n🔍 Testing Fixed Gaussianization")
    println("=" * 35)
    
    # Use Julia's built-in quantile function with normal distribution
    using Distributions
    
    function gaussianize_fixed(x::AbstractVector{T}) where T
        if length(x) <= 1
            return x isa Vector{Float64} ? x : Float64.(x)
        end
        
        # Get ranks
        ranks = tie_kept_rank(x)
        
        # Convert to percentiles
        n = length(ranks)
        percentiles = (ranks .- 0.5) ./ n
        
        # Use proper quantile function
        normal_dist = Normal(0, 1)
        gaussianized = [quantile(normal_dist, clamp(p, 1e-6, 1-1e-6)) for p in percentiles]
        
        # Standardize
        gaussianized = (gaussianized .- mean(gaussianized)) ./ std(gaussianized)
        
        return gaussianized
    end
    
    # Test with simple increasing data
    original = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    
    fixed_gauss = gaussianize_fixed(original)
    correlation = cor(original, fixed_gauss)
    
    println("Original: $original")
    println("Fixed gaussianized: $fixed_gauss")
    println("Correlation: $correlation (should be ~1.0)")
    
    # Check if monotonic
    is_monotonic = all(fixed_gauss[i] <= fixed_gauss[i+1] for i in 1:length(fixed_gauss)-1)
    println("Is monotonic: $is_monotonic")
end

test_quantile_function()
test_simple_quantile()
test_fixed_gaussianize()