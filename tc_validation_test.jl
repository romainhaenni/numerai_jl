#!/usr/bin/env julia
"""
Simple validation test for TC (True Contribution) calculation
to verify implementation against expected behavior.
"""

using Pkg
Pkg.activate(".")

using NumeraiTournament.Metrics
using Random
using Statistics
using LinearAlgebra

function test_tc_basic_properties()
    """Test basic mathematical properties of TC calculation"""
    println("=== Basic TC Properties Test ===")
    
    Random.seed!(42)
    n = 1000
    
    # Create base data
    base_signal = randn(n)
    returns = 0.8 * base_signal + 0.2 * randn(n)
    meta_model = 0.6 * base_signal + 0.4 * randn(n)
    
    # Test case 1: Perfect predictions should have positive TC
    perfect_predictions = copy(returns)
    tc_perfect = Metrics.calculate_tc(perfect_predictions, meta_model, returns)
    println("Perfect predictions TC: $(round(tc_perfect, digits=4))")
    
    # Test case 2: Anti-correlated predictions should have negative TC  
    anti_predictions = -returns
    tc_anti = Metrics.calculate_tc(anti_predictions, meta_model, returns)
    println("Anti-correlated predictions TC: $(round(tc_anti, digits=4))")
    
    # Test case 3: Random predictions should have TC near zero
    random_predictions = randn(n)
    tc_random = Metrics.calculate_tc(random_predictions, meta_model, returns)
    println("Random predictions TC: $(round(tc_random, digits=4))")
    
    # Test case 4: Identical to meta-model should have TC near zero
    identical_predictions = copy(meta_model)
    tc_identical = Metrics.calculate_tc(identical_predictions, meta_model, returns)
    println("Identical to meta-model TC: $(round(tc_identical, digits=4))")
    
    println("\nValidation:")
    println("✓ Perfect predictions should have positive TC" * (tc_perfect > 0 ? " ✓" : " ✗"))
    println("✓ Anti-correlated should have negative TC" * (tc_anti < 0 ? " ✓" : " ✗"))
    println("✓ Random should have TC near zero" * (abs(tc_random) < 0.1 ? " ✓" : " ✗"))
    println("✓ Identical to meta-model should have TC near zero" * (abs(tc_identical) < 0.1 ? " ✓" : " ✗"))
    println()
end

function test_tc_vs_mmc_differences()
    """Test that TC and MMC measure different things"""
    println("=== TC vs MMC Differences Test ===")
    
    Random.seed!(123)
    n = 1000
    
    # Create scenario where TC and MMC should differ
    base_signal = randn(n)
    returns = 0.9 * base_signal + 0.1 * randn(n)
    meta_model = 0.5 * base_signal + 0.5 * randn(n)
    
    # Model that's good at predicting returns but different from meta-model
    predictions = 0.8 * returns + 0.1 * meta_model + 0.1 * randn(n)
    
    tc = Metrics.calculate_tc(predictions, meta_model, returns)
    mmc = Metrics.calculate_mmc(predictions, meta_model, returns)
    
    println("TC: $(round(tc, digits=4))")
    println("MMC: $(round(mmc, digits=4))")
    println("Difference: $(round(abs(tc - mmc), digits=4))")
    
    println("\nValidation:")
    println("✓ TC and MMC should be different" * (abs(tc - mmc) > 0.01 ? " ✓" : " ✗"))
    println("✓ Both should be valid numbers" * (!isnan(tc) && !isnan(mmc) && !isinf(tc) && !isinf(mmc) ? " ✓" : " ✗"))
    println()
end

function test_orthogonalization_correctness()
    """Test the orthogonalization step in TC calculation"""
    println("=== Orthogonalization Correctness Test ===")
    
    Random.seed!(456)
    n = 500
    
    # Create correlated data
    meta_model = randn(n)
    returns = 0.8 * meta_model + 0.2 * randn(n)
    
    # Orthogonalize returns against meta-model
    orthogonal_returns = Metrics.orthogonalize(returns, meta_model)
    
    # Check correlation is near zero
    correlation = cor(orthogonal_returns, meta_model .- mean(meta_model))
    
    println("Correlation after orthogonalization: $(round(correlation, digits=6))")
    println("Original correlation: $(round(cor(returns, meta_model), digits=4))")
    
    println("\nValidation:")
    println("✓ Orthogonalized returns should be uncorrelated with meta-model" * (abs(correlation) < 1e-10 ? " ✓" : " ✗"))
    println()
end

function test_gaussianization()
    """Test the gaussianization step in TC calculation"""
    println("=== Gaussianization Test ===")
    
    Random.seed!(789)
    n = 1000
    
    # Create non-normal data
    uniform_data = rand(n)
    exponential_data = -log.(rand(n))
    
    # Gaussianize
    gauss_uniform = Metrics.gaussianize(uniform_data)
    gauss_exponential = Metrics.gaussianize(exponential_data)
    
    println("Uniform data - Mean: $(round(mean(gauss_uniform), digits=4)), Std: $(round(std(gauss_uniform), digits=4))")
    println("Exponential data - Mean: $(round(mean(gauss_exponential), digits=4)), Std: $(round(std(gauss_exponential), digits=4))")
    
    println("\nValidation:")
    mean_ok = abs(mean(gauss_uniform)) < 0.1 && abs(mean(gauss_exponential)) < 0.1
    std_ok = abs(std(gauss_uniform) - 1.0) < 0.1 && abs(std(gauss_exponential) - 1.0) < 0.1
    
    println("✓ Gaussianized data should have mean ≈ 0" * (mean_ok ? " ✓" : " ✗"))
    println("✓ Gaussianized data should have std ≈ 1" * (std_ok ? " ✓" : " ✗"))
    println()
end

function test_edge_cases()
    """Test edge cases that might cause issues"""
    println("=== Edge Cases Test ===")
    
    # Test with constant data
    n = 100
    constant_returns = fill(5.0, n)
    constant_meta = fill(3.0, n)
    predictions = randn(n)
    
    tc_constant = Metrics.calculate_tc(predictions, constant_meta, constant_returns)
    println("TC with constant returns: $(tc_constant)")
    
    # Test with very small data
    small_returns = [1.0, 2.0, 3.0]
    small_meta = [1.5, 2.5, 3.5]
    small_pred = [1.2, 2.2, 3.2]
    
    tc_small = Metrics.calculate_tc(small_pred, small_meta, small_returns)
    println("TC with small dataset: $(tc_small)")
    
    # Test with extreme values
    extreme_returns = [1e6, -1e6, 1e-6, -1e-6, 0.0]
    extreme_meta = [5e5, -5e5, 5e-7, -5e-7, 1e-10]
    extreme_pred = [8e5, -8e5, 8e-7, -8e-7, 2e-10]
    
    tc_extreme = Metrics.calculate_tc(extreme_pred, extreme_meta, extreme_returns)
    println("TC with extreme values: $(tc_extreme)")
    
    println("\nValidation:")
    println("✓ Constant data should not crash" * (!isnan(tc_constant) && !isinf(tc_constant) ? " ✓" : " ✗"))
    println("✓ Small dataset should not crash" * (!isnan(tc_small) && !isinf(tc_small) ? " ✓" : " ✗"))
    println("✓ Extreme values should not crash" * (!isnan(tc_extreme) && !isinf(tc_extreme) ? " ✓" : " ✗"))
    println()
end

function main()
    """Run all validation tests"""
    println("🔍 TC (True Contribution) Validation Tests")
    println("=" ^ 50)
    println()
    
    test_tc_basic_properties()
    test_tc_vs_mmc_differences()
    test_orthogonalization_correctness()
    test_gaussianization()
    test_edge_cases()
    
    println("✅ All validation tests completed!")
    println("\nIf any tests show ✗, there may be issues with the TC implementation.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end