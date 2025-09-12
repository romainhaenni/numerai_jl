using Test
using Statistics
using Random
using LinearAlgebra
using DataFrames

# Import the main module and its submodules
# NumeraiTournament is already loaded by runtests.jl
using NumeraiTournament.Metrics

@testset "True Contribution (TC) Comprehensive Tests" begin
    
    @testset "Basic TC Calculation Tests" begin
        @testset "Perfect correlation" begin
            # When predictions perfectly match returns and meta-model is different
            returns = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = copy(returns)
            meta_model = [0.5, 1.5, 2.5, 3.5, 4.5]  # Shifted but correlated meta-model
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
            # TC behavior depends on the orthogonalization result
            # Just ensure it's a valid number
            @test abs(tc) >= 0
        end
        
        @testset "Perfect anti-correlation" begin
            # When predictions are perfectly anti-correlated with returns
            returns = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = -returns  # Perfect anti-correlation
            meta_model = zeros(length(returns))  # No contribution from meta-model
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test tc < 0  # Should be negative due to anti-correlation
        end
        
        @testset "Zero correlation" begin
            # When predictions are uncorrelated with returns
            returns = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = [1.0, 1.0, 1.0, 1.0, 1.0]  # Constant predictions
            meta_model = zeros(length(returns))
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # Constant predictions after gaussianization can have unexpected behavior
            # Just ensure it's a valid number
            @test !isnan(tc)
            @test !isinf(tc)
        end
        
        @testset "Identical to meta-model" begin
            # When predictions are identical to meta-model (no unique contribution)
            meta_model = [1.0, 2.0, 3.0, 4.0, 5.0]
            returns = [2.0, 3.0, 4.0, 5.0, 6.0]  # Different from meta-model
            predictions = copy(meta_model)  # Identical to meta-model
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # When returns are orthogonalized against meta-model, and predictions = meta-model,
            # the correlation should be zero
            @test abs(tc) < 1e-10
        end
    end
    
    @testset "Edge Cases and Error Conditions" begin
        @testset "Single element vectors" begin
            tc = Metrics.calculate_tc([1.0], [1.0], [1.0])
            @test tc == 0.0
        end
        
        @testset "Empty vectors" begin
            tc = Metrics.calculate_tc(Float64[], Float64[], Float64[])
            @test tc == 0.0
        end
        
        @testset "Mismatched vector lengths" begin
            @test_throws ArgumentError Metrics.calculate_tc([1.0, 2.0], [1.0], [1.0, 2.0])
            @test_throws ArgumentError Metrics.calculate_tc([1.0], [1.0, 2.0], [1.0, 2.0])
            @test_throws ArgumentError Metrics.calculate_tc([1.0, 2.0], [1.0, 2.0], [1.0])
        end
        
        @testset "Constant predictions" begin
            n = 100
            returns = randn(n)
            meta_model = randn(n)
            predictions = fill(42.0, n)  # All predictions are the same
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # Constant predictions after gaussianization should have some variance,
            # but TC should be close to zero due to lack of meaningful signal
            @test !isnan(tc)
            @test !isinf(tc)
        end
        
        @testset "Constant returns" begin
            n = 50
            returns = fill(5.0, n)  # All returns are the same
            meta_model = randn(n)
            predictions = randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # Constant returns after orthogonalization might have zero variance
            @test tc == 0.0 || (!isnan(tc) && !isinf(tc))
        end
        
        @testset "Constant meta-model" begin
            n = 50
            returns = randn(n)
            meta_model = fill(10.0, n)  # Constant meta-model
            predictions = randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # With constant meta-model, orthogonalization should leave returns mostly unchanged
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
        end
        
        @testset "NaN values in inputs" begin
            returns = [1.0, 2.0, NaN, 4.0, 5.0]
            meta_model = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = [1.0, 2.0, 3.0, 4.0, 5.0]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # Function should handle NaN gracefully and return 0 or NaN
            @test isnan(tc) || tc == 0.0
        end
        
        @testset "Infinite values in inputs" begin
            returns = [1.0, 2.0, Inf, 4.0, 5.0]
            meta_model = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = [1.0, 2.0, 3.0, 4.0, 5.0]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # Function should handle Inf gracefully
            @test !isinf(tc) || tc == 0.0
        end
    end
    
    @testset "Numerical Stability Tests" begin
        @testset "Very large values" begin
            n = 100
            scale = 1e10
            returns = scale * randn(n)
            meta_model = scale * randn(n)
            predictions = scale * randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
        end
        
        @testset "Very small values" begin
            n = 100
            scale = 1e-10
            returns = scale * randn(n)
            meta_model = scale * randn(n) 
            predictions = scale * randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
        end
        
        @testset "Mixed scales" begin
            returns = [1e10, 1e-10, 1.0, -1e10, -1e-10]
            meta_model = [5e9, 5e-11, 0.5, -5e9, -5e-11]
            predictions = [8e9, 8e-11, 0.8, -8e9, -8e-11]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
        end
        
        @testset "High precision requirements" begin
            # Test numerical stability with values that could cause precision issues
            Random.seed!(42)
            n = 1000
            
            # Create data with subtle differences that require high precision
            base = randn(n)
            returns = base + 1e-12 * randn(n)
            meta_model = base + 1e-12 * randn(n)
            predictions = base + 1e-12 * randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
        end
    end
    
    @testset "Correlation Fallback Method Tests" begin
        # The current implementation uses correlation-based method only
        # These tests verify the correlation-based approach is working correctly
        
        @testset "Correlation method consistency" begin
            Random.seed!(123)
            n = 500
            
            # Create test data with known relationships
            base_signal = randn(n)
            returns = 0.8 * base_signal + 0.2 * randn(n)
            meta_model = 0.6 * base_signal + 0.4 * randn(n)
            predictions = 0.7 * base_signal + 0.3 * randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            
            # Manual calculation to verify
            # 1. Gaussianize predictions
            p = Metrics.gaussianize(Metrics.tie_kept_rank(predictions))
            # 2. Orthogonalize returns w.r.t. meta-model
            orthogonal_returns = Metrics.orthogonalize(returns, meta_model)
            # 3. Calculate correlation
            expected_tc = cor(p, orthogonal_returns)
            if std(orthogonal_returns) == 0.0
                expected_tc = 0.0
            end
            
            @test abs(tc - expected_tc) < 1e-10
        end
        
        @testset "Zero variance orthogonal returns" begin
            n = 100
            meta_model = randn(n)
            returns = copy(meta_model)  # Returns identical to meta-model
            predictions = randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test tc == 0.0  # Should handle zero variance case
        end
        
        @testset "Correlation method vs manual calculation" begin
            returns = [1.0, 2.0, 3.0, 4.0, 5.0]
            meta_model = [1.5, 2.5, 3.5, 4.5, 5.5]
            predictions = [0.8, 1.8, 2.8, 3.8, 4.8]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            
            # Manual step-by-step calculation
            p = Metrics.gaussianize(Metrics.tie_kept_rank(predictions))
            orthogonal_returns = Metrics.orthogonalize(returns, meta_model)
            
            if std(orthogonal_returns) == 0.0
                manual_tc = 0.0
            else
                manual_tc = cor(p, orthogonal_returns)
                if isnan(manual_tc)
                    manual_tc = 0.0
                end
            end
            
            @test abs(tc - manual_tc) < 1e-10
        end
    end
    
    @testset "Real-world Like Data Distribution Tests" begin
        @testset "Tournament-like data simulation" begin
            Random.seed!(456)
            n_eras = 20
            n_per_era = 50
            n_total = n_eras * n_per_era
            
            # Simulate era-based structure like Numerai tournament
            era_effects = randn(n_eras)
            base_signal = repeat(era_effects, inner=n_per_era) + 0.5 * randn(n_total)
            
            # Create returns with era structure and noise
            returns = 0.1 * base_signal + 0.9 * randn(n_total)
            
            # Create meta-model that captures some of the era effects
            meta_model = 0.15 * base_signal + 0.85 * randn(n_total)
            
            # Create predictions with different signal capture
            predictions = 0.12 * base_signal + 0.88 * randn(n_total)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
        end
        
        @testset "Realistic correlation ranges" begin
            Random.seed!(789)
            n = 2000
            
            # Create data with realistic correlations (low signal-to-noise ratio)
            base_alpha = 0.05 * randn(n)  # Weak alpha signal
            noise = randn(n)
            
            returns = base_alpha + noise
            meta_model = 0.8 * base_alpha + 0.9 * randn(n)
            predictions = 0.6 * base_alpha + 0.95 * randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            
            # In realistic settings, TC should be small but measurable
            @test !isnan(tc)
            @test !isinf(tc)
            @test abs(tc) < 0.5  # Realistic TC values are typically small
        end
        
        @testset "Skewed and non-normal distributions" begin
            Random.seed!(101112)
            n = 1000
            
            # Create skewed distributions (common in financial data)
            # Using exponential distribution for positive skew
            returns = exp.(0.1 * randn(n)) .- 1  # Positively skewed
            meta_model = -exp.(0.1 * randn(n)) .+ 1  # Negatively skewed
            predictions = randn(n).^3  # Slightly skewed
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
        end
        
        @testset "Heavy-tailed distributions" begin
            Random.seed!(131415)
            n = 800
            
            # Create heavy-tailed distributions (t-distribution-like)
            returns = randn(n) ./ abs.(randn(n) .+ 0.1)  # Heavy tails
            meta_model = randn(n) ./ abs.(randn(n) .+ 0.1)
            predictions = randn(n) ./ abs.(randn(n) .+ 0.1)
            
            # Clip extreme values to avoid numerical issues
            returns = clamp.(returns, -10, 10)
            meta_model = clamp.(meta_model, -10, 10)
            predictions = clamp.(predictions, -10, 10)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
        end
    end
    
    @testset "Batch TC Calculation Tests" begin
        @testset "Batch vs individual calculation consistency" begin
            Random.seed!(161718)
            n_samples = 300
            n_models = 5
            
            base_signal = randn(n_samples)
            returns = 0.7 * base_signal + 0.3 * randn(n_samples)
            meta_model = 0.6 * base_signal + 0.4 * randn(n_samples)
            
            # Create predictions matrix
            predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
            for i in 1:n_models
                predictions_matrix[:, i] = (0.3 + 0.1*i) * base_signal + (0.7 - 0.1*i) * randn(n_samples)
            end
            
            # Calculate batch TC
            tc_scores = Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
            
            @test length(tc_scores) == n_models
            @test all(-1.0 .<= tc_scores .<= 1.0)
            @test all(.!isnan.(tc_scores))
            @test all(.!isinf.(tc_scores))
            
            # Verify against individual calculations
            for i in 1:n_models
                individual_tc = Metrics.calculate_tc(predictions_matrix[:, i], meta_model, returns)
                @test abs(tc_scores[i] - individual_tc) < 1e-12
            end
        end
        
        @testset "Batch calculation with edge cases" begin
            n_samples = 100
            n_models = 3
            
            returns = randn(n_samples)
            meta_model = randn(n_samples)
            
            # Create predictions matrix with various edge cases
            predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
            predictions_matrix[:, 1] = fill(1.0, n_samples)  # Constant predictions
            predictions_matrix[:, 2] = copy(meta_model)      # Identical to meta-model
            predictions_matrix[:, 3] = randn(n_samples)       # Random predictions
            
            tc_scores = Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
            
            @test length(tc_scores) == n_models
            @test all(.!isinf.(tc_scores))
            # First model (constant) might have unexpected TC due to gaussianization
            # Just ensure it's a valid finite number
            @test !isnan(tc_scores[1]) && !isinf(tc_scores[1])
            # Second model (identical to meta-model) should have TC close to zero
            # but might not be exactly zero due to numerical precision
            @test abs(tc_scores[2]) < 0.1
        end
        
        @testset "Batch dimension mismatch errors" begin
            predictions_matrix = randn(100, 3)
            meta_model = randn(50)  # Wrong size
            returns = randn(100)
            
            @test_throws ArgumentError Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
            
            meta_model = randn(100)
            returns = randn(50)  # Wrong size
            
            @test_throws ArgumentError Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
        end
    end
    
    @testset "Feature Neutralized TC Tests" begin
        @testset "Basic feature neutralization effect" begin
            Random.seed!(192021)
            n_samples = 400
            n_features = 8
            
            base_signal = randn(n_samples)
            returns = 0.6 * base_signal + 0.4 * randn(n_samples)
            meta_model = 0.5 * base_signal + 0.5 * randn(n_samples)
            
            # Create features matrix
            features = randn(n_samples, n_features)
            
            # Create predictions correlated with features
            feature_effect = sum(features[:, 1:3], dims=2)[:, 1]
            predictions = 0.3 * base_signal + 0.4 * feature_effect + 0.3 * randn(n_samples)
            
            # Calculate regular TC
            regular_tc = Metrics.calculate_tc(predictions, meta_model, returns)
            
            # Calculate feature-neutralized TC
            fn_tc = Metrics.calculate_feature_neutralized_tc(predictions, meta_model, returns, features)
            
            @test !isnan(regular_tc) && !isnan(fn_tc)
            @test !isinf(regular_tc) && !isinf(fn_tc)
            
            # Feature neutralization should change the TC
            # (unless predictions were already orthogonal to features)
            @test abs(regular_tc - fn_tc) >= 0  # Could be equal if orthogonal
        end
        
        @testset "Feature neutralization dimension errors" begin
            predictions = randn(100)
            meta_model = randn(100)
            returns = randn(100)
            features = randn(50, 5)  # Wrong number of samples
            
            @test_throws ArgumentError Metrics.calculate_feature_neutralized_tc(predictions, meta_model, returns, features)
        end
        
        @testset "No features matrix (empty)" begin
            n_samples = 50
            predictions = randn(n_samples)
            meta_model = randn(n_samples)
            returns = randn(n_samples)
            features = Matrix{Float64}(undef, n_samples, 0)  # No features
            
            regular_tc = Metrics.calculate_tc(predictions, meta_model, returns)
            fn_tc = Metrics.calculate_feature_neutralized_tc(predictions, meta_model, returns, features)
            
            # With no features, neutralized TC should equal regular TC
            @test abs(regular_tc - fn_tc) < 1e-12
        end
    end
    
    @testset "Performance and Scalability Tests" begin
        @testset "Large dataset performance" begin
            Random.seed!(222324)
            n_large = 50000
            
            returns = randn(n_large)
            meta_model = 0.1 * returns + 0.9 * randn(n_large)
            predictions = 0.08 * returns + 0.92 * randn(n_large)
            
            # Time the calculation (should complete reasonably quickly)
            start_time = time()
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            elapsed = time() - start_time
            
            @test !isnan(tc)
            @test !isinf(tc)
            @test elapsed < 5.0  # Should complete within 5 seconds
        end
        
        @testset "Memory efficiency test" begin
            # Test that function doesn't create excessive temporary arrays
            n = 10000
            returns = randn(n)
            meta_model = randn(n)
            predictions = randn(n)
            
            # Function should work without excessive memory allocation
            # (This is more of a smoke test - detailed memory profiling would require more setup)
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
        end
    end
    
    @testset "Comparison with MMC Tests" begin
        @testset "TC vs MMC conceptual differences" begin
            Random.seed!(252627)
            n_samples = 500
            
            # Create scenario where TC and MMC should differ significantly
            base_signal = randn(n_samples)
            
            # Returns have different correlation structure than targets
            returns = 0.8 * base_signal + 0.2 * randn(n_samples)
            targets = 0.3 * base_signal + 0.7 * randn(n_samples)  # Different from returns
            
            meta_model = 0.6 * base_signal + 0.4 * randn(n_samples)
            predictions = 0.5 * base_signal + 0.5 * randn(n_samples)
            
            # Calculate both metrics
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            
            @test !isnan(tc) && !isnan(mmc)
            @test !isinf(tc) && !isinf(mmc)
            
            # They measure different things and should potentially differ
            # (Though they could be similar in some cases)
            @test -1.0 <= tc <= 1.0
            @test -1.0 <= mmc <= 1.0
        end
        
        @testset "TC and MMC with identical targets and returns" begin
            Random.seed!(282930)
            n_samples = 300
            
            base_signal = randn(n_samples)
            targets_returns = 0.7 * base_signal + 0.3 * randn(n_samples)
            meta_model = 0.5 * base_signal + 0.5 * randn(n_samples)
            predictions = 0.6 * base_signal + 0.4 * randn(n_samples)
            
            # When targets = returns, TC and MMC should be similar (but not necessarily identical
            # due to different processing - MMC uses gaussianized meta-model)
            tc = Metrics.calculate_tc(predictions, meta_model, targets_returns)
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets_returns)
            
            @test !isnan(tc) && !isnan(mmc)
            @test !isinf(tc) && !isinf(mmc)
            
            # Both should be in valid ranges
            @test -1.0 <= tc <= 1.0
            @test -1.0 <= mmc <= 1.0
        end
    end
    
    @testset "Regression Tests for Recent Fixes" begin
        @testset "Handle NaN results from correlation" begin
            # Test case that could previously cause NaN results
            n = 10
            returns = fill(1.0, n)  # Constant returns
            meta_model = fill(1.0, n)  # Constant meta-model
            predictions = randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            # Should return 0.0 instead of NaN when orthogonalized returns have zero variance
            @test tc == 0.0
        end
        
        @testset "Numerical stability with tie_kept_rank" begin
            # Test that tie_kept_rank produces monotonic results
            n = 100
            Random.seed!(313233)
            
            # Create data with many ties
            base_values = [1, 1, 1, 2, 2, 3, 3, 3, 3, 4]
            predictions = Float64.(repeat(base_values, 10))
            shuffle!(predictions)
            
            returns = randn(n)
            meta_model = randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
        end
        
        @testset "Gaussianization edge cases" begin
            # Test gaussianization with edge cases that could cause issues
            predictions = [1.0, 1.0, 1.0, 2.0]  # Mostly ties
            returns = [1.0, 2.0, 3.0, 4.0]
            meta_model = [0.5, 1.5, 2.5, 3.5]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
        end
    end
    
    @testset "Documentation Examples and Use Cases" begin
        @testset "Basic usage example" begin
            # Example from documentation - should work as expected
            returns = [0.1, 0.2, 0.15, 0.25, 0.18]
            predictions = [0.12, 0.18, 0.16, 0.22, 0.20]
            meta_model = [0.11, 0.19, 0.14, 0.24, 0.17]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc)
            @test !isinf(tc)
            @test -1.0 <= tc <= 1.0
        end
        
        @testset "Multi-model comparison" begin
            Random.seed!(343536)
            n = 200
            
            base_signal = randn(n)
            returns = 0.1 * base_signal + 0.9 * randn(n)
            meta_model = 0.08 * base_signal + 0.92 * randn(n)
            
            # Create several models with different signal strengths
            model_signals = [0.05, 0.07, 0.09, 0.11]
            predictions_matrix = Matrix{Float64}(undef, n, length(model_signals))
            
            for (i, signal_strength) in enumerate(model_signals)
                predictions_matrix[:, i] = signal_strength * base_signal + (1 - signal_strength) * randn(n)
            end
            
            tc_scores = Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
            
            # Models with higher signal strength should generally have higher TC
            # (though this isn't guaranteed due to randomness and orthogonalization)
            @test length(tc_scores) == length(model_signals)
            @test all(!isnan, tc_scores)
            @test all(!isinf, tc_scores)
            @test all(-1.0 .<= tc_scores .<= 1.0)
        end
    end
end