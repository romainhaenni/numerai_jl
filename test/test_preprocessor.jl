using Test
using DataFrames
using Statistics
using StatsBase
using LinearAlgebra
using Distributions
using Random

# Include the preprocessor module
include("../src/data/preprocessor.jl")
using .Preprocessor

@testset "Preprocessor Module Tests" begin
    
    @testset "fillna and fillna!" begin
        # Create test DataFrame with missing values
        df = DataFrame(
            a = [1.0, missing, 3.0, missing, 5.0],
            b = [missing, 2.0, missing, 4.0, 5.0],
            c = [1.0, 2.0, 3.0, 4.0, 5.0]
        )
        
        # Test fillna (non-mutating)
        df_filled = Preprocessor.fillna(df, 0.0)
        @test !any(ismissing, df_filled.a)
        @test !any(ismissing, df_filled.b)
        @test df_filled.a == [1.0, 0.0, 3.0, 0.0, 5.0]
        @test df_filled.b == [0.0, 2.0, 0.0, 4.0, 5.0]
        @test df_filled.c == [1.0, 2.0, 3.0, 4.0, 5.0]
        
        # Original should be unchanged
        @test ismissing(df.a[2])
        @test ismissing(df.b[1])
        
        # Test fillna! (mutating)
        df_mut = DataFrame(
            x = [1.0, missing, 3.0],
            y = [missing, 2.0, missing]
        )
        Preprocessor.fillna!(df_mut, -1.0)
        @test df_mut.x == [1.0, -1.0, 3.0]
        @test df_mut.y == [-1.0, 2.0, -1.0]
    end
    
    @testset "rank_normalize" begin
        # Test basic ranking
        values = [1.0, 5.0, 3.0, 2.0, 4.0]
        ranked = Preprocessor.rank_normalize(values)
        
        @test length(ranked) == length(values)
        @test minimum(ranked) > 0
        @test maximum(ranked) < 1
        @test issorted(ranked[sortperm(values)])
        
        # Test with identical values
        identical = [2.0, 2.0, 2.0, 2.0]
        ranked_identical = Preprocessor.rank_normalize(identical)
        @test length(unique(ranked_identical)) > 1  # StatsBase handles ties
        
        # Test with negative values
        neg_values = [-5.0, -1.0, 0.0, 1.0, 5.0]
        ranked_neg = Preprocessor.rank_normalize(neg_values)
        @test all(0 .< ranked_neg .< 1)
    end
    
    @testset "rank_predictions" begin
        predictions = rand(100)
        ranked = Preprocessor.rank_predictions(predictions)
        
        @test length(ranked) == length(predictions)
        @test all(0 .< ranked .< 1)
        @test mean(ranked) ≈ 0.5 atol=0.1
    end
    
    @testset "gaussianize" begin
        # Test gaussianization
        Random.seed!(42)
        values = rand(1000)
        gaussianized = Preprocessor.gaussianize(values)
        
        @test length(gaussianized) == length(values)
        @test mean(gaussianized) ≈ 0.0 atol=0.1
        @test std(gaussianized) ≈ 1.0 atol=0.2
        
        # Test that values are roughly normally distributed
        @test minimum(gaussianized) > -4
        @test maximum(gaussianized) < 4
        
        # Test with small sample
        small_values = [1.0, 2.0, 3.0, 4.0, 5.0]
        small_gauss = Preprocessor.gaussianize(small_values)
        @test length(small_gauss) == 5
        @test !any(isnan, small_gauss)
        @test !any(isinf, small_gauss)
    end
    
    @testset "neutralize_series" begin
        # Test neutralization
        series = [1.0, 2.0, 3.0, 4.0, 5.0]
        by = reshape([1.0, 1.0, 1.0, 1.0, 1.0], 5, 1)  # Neutralize by constant
        
        neutralized = Preprocessor.neutralize_series(series, by)
        @test length(neutralized) == length(series)
        @test mean(neutralized) ≈ 0.0 atol=1e-10
        
        # Test with multiple features
        by_multi = rand(10, 3)
        series_multi = rand(10)
        neutralized_multi = Preprocessor.neutralize_series(series_multi, by_multi)
        @test length(neutralized_multi) == 10
        
        # Test error on dimension mismatch
        @test_throws ErrorException Preprocessor.neutralize_series([1.0, 2.0], reshape([1.0], 1, 1))
    end
    
    @testset "normalize_predictions" begin
        # Test normalization
        predictions = [0.1, 0.5, 0.9, 0.3, 0.7]
        normalized = Preprocessor.normalize_predictions(predictions)
        
        @test minimum(normalized) >= 0.001
        @test maximum(normalized) <= 0.999
        @test issorted(normalized[sortperm(predictions)])
        
        # Test with identical values
        identical = [0.5, 0.5, 0.5, 0.5]
        norm_identical = Preprocessor.normalize_predictions(identical)
        @test all(norm_identical .== 0.5)
        
        # Test with extreme values
        extreme = [-100.0, 0.0, 100.0]
        norm_extreme = Preprocessor.normalize_predictions(extreme)
        @test norm_extreme[1] ≈ 0.001
        @test norm_extreme[3] ≈ 0.999
        @test 0.001 <= norm_extreme[2] <= 0.999
    end
    
    @testset "feature_importance_filter" begin
        # Create correlated features
        Random.seed!(42)
        n = 100
        y = rand(n)
        X = DataFrame(
            good_feature = y .+ 0.1 .* randn(n),  # High correlation
            bad_feature = randn(n),  # No correlation
            medium_feature = 0.5 .* y .+ 0.5 .* randn(n)  # Medium correlation
        )
        
        # Test with different thresholds
        important_high = Preprocessor.feature_importance_filter(X, y, threshold=0.5)
        @test "good_feature" in important_high
        @test !("bad_feature" in important_high)
        
        important_low = Preprocessor.feature_importance_filter(X, y, threshold=0.0)
        @test length(important_low) >= length(important_high)
        
        # Test with no correlation
        X_random = DataFrame(a = randn(100), b = randn(100))
        y_random = randn(100)
        important_none = Preprocessor.feature_importance_filter(X_random, y_random, threshold=0.9)
        @test length(important_none) == 0
    end
    
    @testset "create_era_weighted_features" begin
        # Create test data with eras
        df = DataFrame(
            era = repeat(["era1", "era2", "era3"], inner=3),
            feature1 = 1.0:9.0,
            feature2 = 9.0:-1.0:1.0
        )
        
        # Test non-mutating version
        weighted = Preprocessor.create_era_weighted_features(df, :era)
        @test size(weighted) == size(df)
        @test weighted.era == df.era
        @test weighted.feature1 != df.feature1  # Should be modified
        
        # Test that weighting is applied correctly
        era1_mask = df.era .== "era1"
        era1_weight = sqrt(1.0 / sum(era1_mask))
        @test weighted.feature1[era1_mask] ≈ df.feature1[era1_mask] .* era1_weight
        
        # Test mutating version
        df_mut = copy(df)
        Preprocessor.create_era_weighted_features!(df_mut, :era)
        @test df_mut.feature1 != df.feature1
        @test df_mut.era == df.era
    end
    
    @testset "clip_predictions" begin
        predictions = [0.0001, 0.5, 0.9999, -0.1, 1.1]
        
        # Test default clipping
        clipped = Preprocessor.clip_predictions(predictions)
        @test minimum(clipped) >= 0.0003
        @test maximum(clipped) <= 0.9997
        @test clipped[2] == 0.5  # Middle value unchanged
        
        # Test custom bounds
        clipped_custom = Preprocessor.clip_predictions(predictions, lower=0.1, upper=0.9)
        @test minimum(clipped_custom) >= 0.1
        @test maximum(clipped_custom) <= 0.9
        @test clipped_custom[2] == 0.5
    end
    
    @testset "ensemble_predictions" begin
        # Create test predictions
        pred1 = [0.1, 0.2, 0.3]
        pred2 = [0.4, 0.5, 0.6]
        pred3 = [0.7, 0.8, 0.9]
        
        # Test equal weighting
        ensemble = Preprocessor.ensemble_predictions([pred1, pred2, pred3])
        @test length(ensemble) == 3
        @test ensemble ≈ [0.4, 0.5, 0.6]  # Mean of each position
        
        # Test custom weights
        weights = [0.5, 0.3, 0.2]
        ensemble_weighted = Preprocessor.ensemble_predictions([pred1, pred2, pred3], weights=weights)
        expected = pred1 .* 0.5 .+ pred2 .* 0.3 .+ pred3 .* 0.2
        @test ensemble_weighted ≈ expected
        
        # Test weight normalization
        unnormalized_weights = [1.0, 2.0, 3.0]
        ensemble_unnorm = Preprocessor.ensemble_predictions([pred1, pred2], weights=unnormalized_weights[1:2])
        @test sum(ensemble_unnorm) > 0  # Should produce valid output
        
        # Test error handling
        @test_throws MethodError Preprocessor.ensemble_predictions([])  # Empty array has type Vector{Any}
        @test_throws ErrorException Preprocessor.ensemble_predictions([pred1, pred2], weights=[0.5])  # Wrong number of weights
    end
    
    @testset "reduce_memory_usage" begin
        # Create test DataFrame with different types
        df = DataFrame(
            small_int = Int64[1, 2, 3, 4, 5],
            large_int = Int64[1000000, 2000000, 3000000, 4000000, 5000000],
            small_float = Float64[1.1, 2.2, 3.3, 4.4, 5.5],
            large_float = Float64[1e10, 2e10, 3e10, 4e10, 5e10],
            text = ["a", "b", "c", "d", "e"]
        )
        
        reduced = Preprocessor.reduce_memory_usage(df)
        
        # Check that small integers are converted to smaller types
        @test eltype(reduced.small_int) <: Integer
        @test sizeof(reduced.small_int[1]) <= sizeof(df.small_int[1])
        
        # Check that small floats might be converted to Float32
        @test eltype(reduced.small_float) <: Real
        
        # Text should remain unchanged
        @test reduced.text == df.text
        
        # Test with missing values
        df_missing = DataFrame(
            a = [1, missing, 3],
            b = [1.0, missing, 3.0]
        )
        reduced_missing = Preprocessor.reduce_memory_usage(df_missing)
        # Note: reduce_memory_usage coalesces missing to 0
        @test !any(ismissing, reduced_missing.a)  # Missings should be handled
    end
    
    @testset "Memory allocation functions" begin
        # Test check_memory_before_allocation
        @test Preprocessor.check_memory_before_allocation(1000)  # Small allocation should succeed
        
        # Test with huge allocation (should throw)
        huge_bytes = Int(min(10 * Sys.total_memory(), typemax(Int)))  # 10x total memory, but within Int range
        @test_throws OutOfMemoryError Preprocessor.check_memory_before_allocation(huge_bytes)
        
        # Test safe_matrix_allocation
        small_matrix = Preprocessor.safe_matrix_allocation(10, 10, dtype=Float32)
        @test size(small_matrix) == (10, 10)
        @test eltype(small_matrix) == Float32
        
        # Test with different types
        int_matrix = Preprocessor.safe_matrix_allocation(5, 5, dtype=Int32)
        @test size(int_matrix) == (5, 5)
        @test eltype(int_matrix) == Int32
        
        # Test 3D allocation
        tensor = Preprocessor.safe_matrix_allocation(3, 4, 5, dtype=Float64)
        @test size(tensor) == (3, 4, 5)
        @test eltype(tensor) == Float64
    end
    
    @testset "Edge cases and error handling" begin
        # Empty arrays
        @test_nowarn Preprocessor.rank_normalize(Float64[])
        @test Preprocessor.normalize_predictions(Float64[]) == Float64[]
        @test Preprocessor.clip_predictions(Float64[]) == Float64[]
        
        # Single element
        @test length(Preprocessor.rank_normalize([5.0])) == 1
        @test Preprocessor.normalize_predictions([5.0]) == [0.5]
        
        # NaN and Inf handling
        with_nan = [1.0, NaN, 3.0]
        @test_nowarn Preprocessor.normalize_predictions(filter(!isnan, with_nan))
        
        with_inf = [1.0, Inf, 3.0]
        @test_nowarn Preprocessor.clip_predictions(filter(!isinf, with_inf))
        
        # Very large arrays
        large_array = rand(10000)
        @test length(Preprocessor.rank_normalize(large_array)) == 10000
        @test length(Preprocessor.gaussianize(large_array)) == 10000
        
        # DataFrame with no numeric columns
        df_text = DataFrame(a = ["x", "y", "z"], b = ["1", "2", "3"])
        weighted_text = Preprocessor.create_era_weighted_features(df_text, :a)
        @test weighted_text == df_text  # Should remain unchanged
    end
    
    @testset "Integration tests" begin
        # Test a typical preprocessing pipeline
        Random.seed!(42)
        
        # Create realistic data
        n_samples = 1000
        df = DataFrame(
            era = repeat(["era$(i)" for i in 1:10], inner=100),
            feature1 = randn(n_samples),
            feature2 = randn(n_samples),
            feature3 = randn(n_samples),
            target = rand(n_samples)
        )
        
        # Add some missing values
        df.feature1[rand(1:n_samples, 50)] .= missing
        df.feature2[rand(1:n_samples, 30)] .= missing
        
        # Pipeline
        # 1. Fill missing values
        Preprocessor.fillna!(df, 0.0)
        @test !any(ismissing, df.feature1)
        @test !any(ismissing, df.feature2)
        
        # 2. Feature selection
        feature_cols = [:feature1, :feature2, :feature3]
        X = df[!, feature_cols]
        y = df.target
        important = Preprocessor.feature_importance_filter(X, y, threshold=0.01)
        @test length(important) >= 0
        
        # 3. Era weighting
        Preprocessor.create_era_weighted_features!(df, :era)
        @test !isnothing(df)
        
        # 4. Generate and process predictions
        predictions = rand(n_samples)
        predictions_ranked = Preprocessor.rank_predictions(predictions)
        predictions_normalized = Preprocessor.normalize_predictions(predictions_ranked)
        predictions_clipped = Preprocessor.clip_predictions(predictions_normalized)
        
        @test length(predictions_clipped) == n_samples
        @test all(0.0003 .<= predictions_clipped .<= 0.9997)
        
        # 5. Ensemble multiple models
        model_preds = [rand(100) for _ in 1:3]
        ensemble = Preprocessor.ensemble_predictions(model_preds)
        @test length(ensemble) == 100
        @test all(0 .<= ensemble .<= 1)
    end
end

println("✅ All Preprocessor tests passed!")