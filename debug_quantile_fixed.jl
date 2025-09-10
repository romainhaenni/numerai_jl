#!/usr/bin/env julia
"""
Debug the quantile_normal_approx function
"""

using Statistics
using LinearAlgebra
using Distributions

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
    
    # Compare with Julia's built-in
    println("\nComparison with Julia built-in:")
    normal_dist = Normal(0, 1)
    for p in percentiles
        our_q = quantile_normal_approx(p)
        julia_q = quantile(normal_dist, p)
        diff = abs(our_q - julia_q)
        println("  p=$p: ours=$our_q, julia=$julia_q, diff=$diff")
    end
end

function test_fixed_gaussianize()
    """Test a corrected version of gaussianize using a proper quantile function"""
    println("\n🔍 Testing Fixed Gaussianization")
    println("=" ^ 35)
    
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
    
    broken_gauss = gaussianize(original)
    fixed_gauss = gaussianize_fixed(original)
    
    correlation_broken = cor(original, broken_gauss)
    correlation_fixed = cor(original, fixed_gauss)
    
    println("Original: $original")
    println("Broken gaussianized: $(round.(broken_gauss, digits=3))")
    println("Fixed gaussianized: $(round.(fixed_gauss, digits=3))")
    println("Broken correlation: $correlation_broken")
    println("Fixed correlation: $correlation_fixed")
    
    # Check if monotonic
    is_monotonic_fixed = all(fixed_gauss[i] <= fixed_gauss[i+1] for i in 1:length(fixed_gauss)-1)
    println("Fixed is monotonic: $is_monotonic_fixed")
end

function test_tc_with_fixed_gaussianize()
    """Test TC with the corrected gaussianization"""
    println("\n🔍 Testing TC with Fixed Gaussianization")
    println("=" ^ 40)
    
    using Random
    Random.seed!(42)
    
    function gaussianize_fixed(x::AbstractVector{T}) where T
        if length(x) <= 1
            return x isa Vector{Float64} ? x : Float64.(x)
        end
        
        ranks = tie_kept_rank(x)
        n = length(ranks)
        percentiles = (ranks .- 0.5) ./ n
        
        normal_dist = Normal(0, 1)
        gaussianized = [quantile(normal_dist, clamp(p, 1e-6, 1-1e-6)) for p in percentiles]
        gaussianized = (gaussianized .- mean(gaussianized)) ./ std(gaussianized)
        
        return gaussianized
    end
    
    function calculate_tc_fixed(predictions, meta_model, returns)
        if length(predictions) <= 1
            return 0.0
        end
        
        # Use fixed gaussianization
        p = gaussianize_fixed(predictions)
        
        # Orthogonalize returns with respect to meta-model (current approach)
        orthogonal_returns = orthogonalize(returns, meta_model)
        
        if std(orthogonal_returns) == 0.0
            return 0.0
        end
        
        tc = cor(p, orthogonal_returns)
        return isnan(tc) ? 0.0 : tc
    end
    
    # Test data
    n = 1000
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    
    # Test cases
    test_cases = [
        ("Perfect predictions", copy(returns)),
        ("Anti-correlated", -returns),
        ("Same as meta-model", copy(meta_model)),
    ]
    
    for (desc, predictions) in test_cases
        tc_broken = calculate_tc(predictions, meta_model, returns)
        tc_fixed = calculate_tc_fixed(predictions, meta_model, returns)
        
        println("$desc:")
        println("  Broken TC:  $(round(tc_broken, digits=4))")
        println("  Fixed TC:   $(round(tc_fixed, digits=4))")
    end
end

test_quantile_function()
test_fixed_gaussianize()
test_tc_with_fixed_gaussianize()