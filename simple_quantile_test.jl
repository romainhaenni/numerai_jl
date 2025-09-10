#!/usr/bin/env julia

using Statistics
using LinearAlgebra
using Distributions

include("simple_tc_test.jl")

println("🔍 Testing Quantile Function")
println("=" ^ 30)

# Test the broken quantile function
percentiles = [0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]

println("Percentile -> Our Quantile:")
our_quantiles = [quantile_normal_approx(p) for p in percentiles]
for (p, q) in zip(percentiles, our_quantiles)
    println("  $p -> $q")
end

# Compare with Julia's built-in
println("\nPercentile -> Julia Quantile:")
normal_dist = Normal(0, 1)
julia_quantiles = [quantile(normal_dist, p) for p in percentiles]
for (p, q) in zip(percentiles, julia_quantiles)
    println("  $p -> $q")
end

# Check monotonicity
println("\nMonotonicity check:")
our_monotonic = all(our_quantiles[i] <= our_quantiles[i+1] for i in 1:length(our_quantiles)-1)
julia_monotonic = all(julia_quantiles[i] <= julia_quantiles[i+1] for i in 1:length(julia_quantiles)-1)
println("Our quantiles monotonic: $our_monotonic")
println("Julia quantiles monotonic: $julia_monotonic")

# Test gaussianization with both
println("\nTesting gaussianization:")
original = [1.0, 2.0, 3.0, 4.0, 5.0]

function gaussianize_with_julia(x)
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

broken_result = gaussianize(original)
fixed_result = gaussianize_with_julia(original)

println("Original: $original")
println("Broken result: $broken_result")
println("Fixed result: $fixed_result")
println("Broken correlation: $(cor(original, broken_result))")
println("Fixed correlation: $(cor(original, fixed_result))")