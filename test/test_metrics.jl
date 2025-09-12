using Test
using Statistics
using Random
using DataFrames
using LinearAlgebra

# Import the main module and its submodules
# NumeraiTournament is already loaded by runtests.jl
using NumeraiTournament.Models
using NumeraiTournament.Ensemble
using NumeraiTournament.Pipeline
using NumeraiTournament.Metrics

@testset "Metrics Module Tests" begin
    
    @testset "tie_kept_rank function" begin
        @testset "Basic ranking" begin
            # Test simple increasing sequence
            x = [1.0, 2.0, 3.0, 4.0]
            ranks = Metrics.tie_kept_rank(x)
            @test ranks == [1.0, 2.0, 3.0, 4.0]
            
            # Test decreasing sequence
            x = [4.0, 3.0, 2.0, 1.0]
            ranks = Metrics.tie_kept_rank(x)
            @test ranks == [4.0, 3.0, 2.0, 1.0]
        end
        
        @testset "Ties handling" begin
            # Test ties - should maintain original order
            x = [1.0, 2.0, 2.0, 3.0]
            ranks = Metrics.tie_kept_rank(x)
            @test ranks == [1.0, 2.0, 3.0, 4.0]  # First 2.0 gets rank 2, second gets rank 3
            
            # Test all same values
            x = [5.0, 5.0, 5.0]
            ranks = Metrics.tie_kept_rank(x)
            @test ranks == [1.0, 2.0, 3.0]
        end
        
        @testset "Edge cases" begin
            # Test empty vector
            x = Float64[]
            ranks = Metrics.tie_kept_rank(x)
            @test isempty(ranks)
            
            # Test single element
            x = [42.0]
            ranks = Metrics.tie_kept_rank(x)
            @test ranks == [1.0]
        end
        
        @testset "Matrix ranking" begin
            # Test matrix ranking (each column ranked independently)
            X = [1.0 3.0; 2.0 1.0; 3.0 2.0]
            ranked = Metrics.tie_kept_rank(X)
            expected = [1.0 3.0; 2.0 1.0; 3.0 2.0]
            @test ranked == expected
        end
    end
    
    @testset "gaussianize function" begin
        @testset "Basic gaussianization" begin
            # Test that gaussianized data has approximately mean=0, std=1
            Random.seed!(42)
            x = randn(1000)  # Already normal, but test the process
            gauss_x = Metrics.gaussianize(x)
            
            @test abs(mean(gauss_x)) < 0.1  # Should be close to 0
            @test abs(std(gauss_x) - 1.0) < 0.1  # Should be close to 1
        end
        
        @testset "Uniform to normal transformation" begin
            # Test transforming uniform distribution to normal
            Random.seed!(123)
            x = rand(1000)  # Uniform [0,1]
            gauss_x = Metrics.gaussianize(x)
            
            @test abs(mean(gauss_x)) < 0.1
            @test abs(std(gauss_x) - 1.0) < 0.1
        end
        
        @testset "Edge cases" begin
            # Test single element
            x = [5.0]
            gauss_x = Metrics.gaussianize(x)
            @test gauss_x == [5.0]  # Should return unchanged
            
            # Test empty vector
            x = Float64[]
            gauss_x = Metrics.gaussianize(x)
            @test isempty(gauss_x)
        end
        
        @testset "Matrix gaussianization" begin
            Random.seed!(456)
            X = rand(100, 3)  # 3 columns of uniform data
            gauss_X = Metrics.gaussianize(X)
            
            # Each column should be gaussianized
            for col in 1:size(gauss_X, 2)
                @test abs(mean(gauss_X[:, col])) < 0.2
                @test abs(std(gauss_X[:, col]) - 1.0) < 0.2
            end
        end
    end
    
    @testset "orthogonalize function" begin
        @testset "Perfect orthogonalization" begin
            # Test orthogonalizing against itself should give zero vector
            x = [1.0, 2.0, 3.0, 4.0]
            ortho = Metrics.orthogonalize(x, x)
            @test all(abs.(ortho) .< 1e-10)  # Should be approximately zero
        end
        
        @testset "Orthogonal vectors" begin
            # Test already orthogonal vectors
            x = [1.0, 0.0, 0.0]
            ref = [0.0, 1.0, 0.0]
            ortho = Metrics.orthogonalize(x, ref)
            
            # Should remain centered and still be orthogonal to reference
            @test abs(cor(ortho, ref .- mean(ref))) < 1e-10
        end
        
        @testset "Correlation check" begin
            Random.seed!(789)
            x = randn(100)
            ref = randn(100)
            
            # Add some correlation
            x = x + 0.5 * ref
            
            # After orthogonalization, correlation should be near zero
            ortho = Metrics.orthogonalize(x, ref)
            correlation = cor(ortho, ref .- mean(ref))
            @test abs(correlation) < 1e-10
        end
        
        @testset "Edge cases" begin
            # Test with zero reference vector
            x = [1.0, 2.0, 3.0]
            ref = [0.0, 0.0, 0.0]
            ortho = Metrics.orthogonalize(x, ref)
            @test ortho ≈ x  # Should return x unchanged
            
            # Test mismatched lengths
            x = [1.0, 2.0]
            ref = [1.0, 2.0, 3.0]
            @test_throws ArgumentError Metrics.orthogonalize(x, ref)
        end
        
        @testset "Matrix orthogonalization" begin
            Random.seed!(101112)
            X = randn(50, 3)
            ref = randn(50)
            
            ortho_X = Metrics.orthogonalize(X, ref)
            
            # Each column should be orthogonal to reference
            for col in 1:size(ortho_X, 2)
                correlation = cor(ortho_X[:, col], ref .- mean(ref))
                @test abs(correlation) < 1e-10
            end
        end
    end
    
    @testset "create_stake_weighted_ensemble function" begin
        @testset "Basic ensemble creation" begin
            # Test simple ensemble
            predictions = [1.0 2.0; 3.0 4.0; 5.0 6.0]  # 3 samples, 2 models
            stakes = [0.6, 0.4]
            
            ensemble = Metrics.create_stake_weighted_ensemble(predictions, stakes)
            expected = predictions * stakes
            @test ensemble ≈ expected
        end
        
        @testset "Equal weights" begin
            predictions = [1.0 2.0 3.0; 4.0 5.0 6.0]  # 2 samples, 3 models
            stakes = [1.0, 1.0, 1.0]  # Equal weights
            
            ensemble = Metrics.create_stake_weighted_ensemble(predictions, stakes)
            # Should be average of predictions
            expected = mean(predictions, dims=2)[:, 1]
            @test ensemble ≈ expected
        end
        
        @testset "Error cases" begin
            predictions = [1.0 2.0; 3.0 4.0]
            
            # Mismatched dimensions
            stakes = [0.5]  # Only 1 stake for 2 models
            @test_throws ArgumentError Metrics.create_stake_weighted_ensemble(predictions, stakes)
            
            # Negative stakes
            stakes = [0.5, -0.5]
            @test_throws ArgumentError Metrics.create_stake_weighted_ensemble(predictions, stakes)
            
            # Zero total stake
            stakes = [0.0, 0.0]
            @test_throws ArgumentError Metrics.create_stake_weighted_ensemble(predictions, stakes)
        end
    end
    
    @testset "calculate_mmc function" begin
        @testset "Perfect correlation MMC" begin
            # When predictions perfectly match targets and meta-model is different
            targets = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = copy(targets)
            meta_model = [0.5, 1.5, 2.5, 3.5, 4.5]  # Shifted but correlated meta-model
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            @test !isnan(mmc) && !isinf(mmc)  # Should be a valid number
        end
        
        @testset "Anti-correlation MMC" begin
            # When predictions are anti-correlated with targets
            targets = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = -targets
            meta_model = zeros(length(targets))
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            @test mmc < 0  # Should be negative
        end
        
        @testset "Zero MMC cases" begin
            # When predictions are identical to meta-model
            targets = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = [2.0, 3.0, 4.0, 5.0, 6.0]
            meta_model = copy(predictions)
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            @test abs(mmc) < 1e-10  # Should be approximately zero
        end
        
        @testset "Realistic MMC calculation" begin
            Random.seed!(131415)
            n = 1000
            
            # Create correlated but different predictions
            targets = randn(n)
            meta_model = 0.8 * targets + 0.2 * randn(n)
            predictions = 0.6 * targets + 0.4 * randn(n)
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            
            # MMC should be meaningful but not extreme
            @test -1.0 < mmc < 1.0
            @test !isnan(mmc)
            @test !isinf(mmc)
        end
        
        @testset "Edge cases" begin
            # Single element
            mmc = Metrics.calculate_mmc([1.0], [1.0], [1.0])
            @test mmc == 0.0
            
            # Mismatched lengths
            @test_throws ArgumentError Metrics.calculate_mmc([1.0, 2.0], [1.0], [1.0, 2.0])
        end
    end
    
    @testset "calculate_mmc_batch function" begin
        @testset "Batch MMC calculation" begin
            Random.seed!(161718)
            n_samples = 500
            n_models = 4
            
            targets = randn(n_samples)
            meta_model = 0.7 * targets + 0.3 * randn(n_samples)
            
            # Create predictions matrix
            predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
            for i in 1:n_models
                predictions_matrix[:, i] = 0.5 * targets + 0.5 * randn(n_samples)
            end
            
            mmc_scores = Metrics.calculate_mmc_batch(predictions_matrix, meta_model, targets)
            
            @test length(mmc_scores) == n_models
            @test all(-1.0 .< mmc_scores .< 1.0)
            @test all(.!isnan.(mmc_scores))
            @test all(.!isinf.(mmc_scores))
            
            # Verify against individual calculations
            for i in 1:n_models
                individual_mmc = Metrics.calculate_mmc(predictions_matrix[:, i], meta_model, targets)
                @test abs(mmc_scores[i] - individual_mmc) < 1e-10
            end
        end
    end
    
    @testset "calculate_contribution_score function" begin
        @testset "Perfect correlation" begin
            targets = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = copy(targets)
            
            score = Metrics.calculate_contribution_score(predictions, targets)
            @test abs(score - 1.0) < 1e-10
        end
        
        @testset "Perfect anti-correlation" begin
            targets = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = -targets
            
            score = Metrics.calculate_contribution_score(predictions, targets)
            @test abs(score - (-1.0)) < 1e-10
        end
        
        @testset "Zero correlation" begin
            targets = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = [1.0, 1.0, 1.0, 1.0, 1.0]  # Constant predictions
            
            score = Metrics.calculate_contribution_score(predictions, targets)
            @test isnan(score) || abs(score) < 1e-10  # Should be NaN or ~0 for constant predictions
        end
    end
    
    @testset "calculate_feature_neutralized_mmc function" begin
        @testset "Feature neutralization effect" begin
            Random.seed!(192021)
            n_samples = 300
            n_features = 5
            
            targets = randn(n_samples)
            meta_model = 0.6 * targets + 0.4 * randn(n_samples)
            
            # Create features matrix
            features = randn(n_samples, n_features)
            
            # Create predictions that are correlated with features
            predictions = 0.4 * targets + 0.3 * sum(features, dims=2)[:, 1] + 0.3 * randn(n_samples)
            
            # Calculate regular MMC
            regular_mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            
            # Calculate feature-neutralized MMC
            fn_mmc = Metrics.calculate_feature_neutralized_mmc(predictions, meta_model, targets, features)
            
            # Feature neutralization should change the MMC
            @test abs(regular_mmc - fn_mmc) > 1e-6
            @test !isnan(fn_mmc)
            @test !isinf(fn_mmc)
        end
        
        @testset "Dimension mismatch errors" begin
            predictions = randn(100)
            meta_model = randn(100)
            targets = randn(100)
            features = randn(50, 3)  # Wrong number of samples
            
            @test_throws ArgumentError Metrics.calculate_feature_neutralized_mmc(predictions, meta_model, targets, features)
        end
    end
    
    @testset "calculate_tc function" begin
        @testset "Perfect correlation TC" begin
            # When predictions perfectly match returns and meta-model is different
            returns = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = copy(returns)
            meta_model = [0.5, 1.5, 2.5, 3.5, 4.5]  # Shifted but correlated meta-model
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test !isnan(tc) && !isinf(tc)  # Should be a valid number
        end
        
        @testset "Anti-correlation TC" begin
            # When predictions are anti-correlated with returns
            returns = [1.0, 2.0, 3.0, 4.0, 5.0]
            predictions = -returns
            meta_model = zeros(length(returns))
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test tc < 0  # Should be negative
        end
        
        @testset "Zero TC cases" begin
            # When returns are identical to meta-model (no orthogonal component)
            meta_model = [1.0, 2.0, 3.0, 4.0, 5.0]
            returns = copy(meta_model)
            predictions = [2.0, 3.0, 4.0, 5.0, 6.0]
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test abs(tc) < 1e-10  # Should be approximately zero
        end
        
        @testset "Realistic TC calculation" begin
            Random.seed!(131415)
            n = 1000
            
            # Create correlated but different predictions and returns
            base_signal = randn(n)
            returns = 0.8 * base_signal + 0.2 * randn(n)
            meta_model = 0.6 * base_signal + 0.4 * randn(n)
            predictions = 0.7 * base_signal + 0.3 * randn(n)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            
            # TC should be meaningful but not extreme
            @test -1.0 < tc < 1.0
            @test !isnan(tc)
            @test !isinf(tc)
        end
        
        @testset "Edge cases" begin
            # Single element
            tc = Metrics.calculate_tc([1.0], [1.0], [1.0])
            @test tc == 0.0
            
            # Mismatched lengths
            @test_throws ArgumentError Metrics.calculate_tc([1.0, 2.0], [1.0], [1.0, 2.0])
            
            # Constant orthogonalized returns (should return 0)
            returns = [1.0, 1.0, 1.0, 1.0]
            meta_model = copy(returns)
            predictions = [2.0, 3.0, 4.0, 5.0]
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            @test tc == 0.0
        end
    end
    
    @testset "calculate_tc_batch function" begin
        @testset "Batch TC calculation" begin
            Random.seed!(161718)
            n_samples = 500
            n_models = 4
            
            base_signal = randn(n_samples)
            returns = 0.7 * base_signal + 0.3 * randn(n_samples)
            meta_model = 0.6 * base_signal + 0.4 * randn(n_samples)
            
            # Create predictions matrix
            predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
            for i in 1:n_models
                predictions_matrix[:, i] = 0.5 * base_signal + 0.5 * randn(n_samples)
            end
            
            tc_scores = Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
            
            @test length(tc_scores) == n_models
            @test all(-1.0 .< tc_scores .< 1.0)
            @test all(.!isnan.(tc_scores))
            @test all(.!isinf.(tc_scores))
            
            # Verify against individual calculations
            for i in 1:n_models
                individual_tc = Metrics.calculate_tc(predictions_matrix[:, i], meta_model, returns)
                @test abs(tc_scores[i] - individual_tc) < 1e-10
            end
        end
    end
    
    @testset "calculate_feature_neutralized_tc function" begin
        @testset "Feature neutralization effect on TC" begin
            Random.seed!(192021)
            n_samples = 300
            n_features = 5
            
            base_signal = randn(n_samples)
            returns = 0.6 * base_signal + 0.4 * randn(n_samples)
            meta_model = 0.5 * base_signal + 0.5 * randn(n_samples)
            
            # Create features matrix
            features = randn(n_samples, n_features)
            
            # Create predictions that are correlated with features
            predictions = 0.4 * base_signal + 0.3 * sum(features, dims=2)[:, 1] + 0.3 * randn(n_samples)
            
            # Calculate regular TC
            regular_tc = Metrics.calculate_tc(predictions, meta_model, returns)
            
            # Calculate feature-neutralized TC
            fn_tc = Metrics.calculate_feature_neutralized_tc(predictions, meta_model, returns, features)
            
            # Feature neutralization should change the TC
            @test abs(regular_tc - fn_tc) > 1e-6
            @test !isnan(fn_tc)
            @test !isinf(fn_tc)
        end
        
        @testset "TC vs MMC differences" begin
            Random.seed!(242526)
            n_samples = 400
            
            # Create data where TC and MMC should differ
            base_signal = randn(n_samples)
            returns = 0.8 * base_signal + 0.2 * randn(n_samples)
            meta_model = 0.6 * base_signal + 0.4 * randn(n_samples)
            
            # Create predictions with different correlation to returns vs meta_model
            predictions = 0.7 * returns + 0.1 * meta_model + 0.2 * randn(n_samples)
            
            tc = Metrics.calculate_tc(predictions, meta_model, returns)
            mmc = Metrics.calculate_mmc(predictions, meta_model, returns)
            
            # TC and MMC should be different since they measure different things
            @test abs(tc - mmc) > 1e-3
            @test !isnan(tc) && !isnan(mmc)
            @test !isinf(tc) && !isinf(mmc)
        end
        
        @testset "Dimension mismatch errors" begin
            predictions = randn(100)
            meta_model = randn(100)
            returns = randn(100)
            features = randn(50, 3)  # Wrong number of samples
            
            @test_throws ArgumentError Metrics.calculate_feature_neutralized_tc(predictions, meta_model, returns, features)
        end
    end
    
    @testset "Integration with ML Pipeline" begin
        @testset "MMC calculation in pipeline context" begin
            # Create synthetic data for testing
            Random.seed!(222324)
            n_samples = 200
            n_features = 10
            
            # Create feature matrix
            X = randn(n_samples, n_features)
            
            # Create targets with some correlation to features
            y = 0.3 * sum(X[:, 1:3], dims=2)[:, 1] + 0.7 * randn(n_samples)
            
            # Create eras (sequential)
            eras = repeat(1:20, inner=10)
            
            # Create DataFrame
            feature_names = ["feature_$i" for i in 1:n_features]
            df = DataFrame()
            for (i, name) in enumerate(feature_names)
                df[!, name] = X[:, i]
            end
            df[!, "target_cyrus_v4_20"] = y
            df[!, "era"] = eras
            df[!, "id"] = 1:n_samples
            
            # Create and train pipeline (using only tree-based models to avoid GPU issues)
            # Use single model with current API
            model = Models.XGBoostModel("xgb_shallow", max_depth=4, learning_rate=0.02, colsample_bytree=0.2)
            pipeline = Pipeline.MLPipeline(
                feature_cols=feature_names,
                target_col="target_cyrus_v4_20",
                neutralize=false,  # Disable neutralization for testing
                model=model
            )
            
            # Split data for training
            train_df = df[1:150, :]
            val_df = df[151:end, :]
            
            # Train pipeline
            Pipeline.train!(pipeline, train_df, val_df, verbose=false)
            
            # Test basic evaluation (compatible with simplified architecture)
            results = Pipeline.evaluate(pipeline, val_df, metrics=[:corr])
            @test haskey(results, :corr)
            @test results[:corr] isa Float64
            
            # Test that predictions work
            predictions = Pipeline.predict(pipeline, val_df)
            @test length(predictions) == nrow(val_df)
            @test all(!isnan, predictions)
            @test all(!isinf, predictions)
        end
    end
    
    @testset "Numerical stability and edge cases" begin
        @testset "Large scale data" begin
            Random.seed!(252627)
            n_large = 10000
            
            targets = randn(n_large)
            meta_model = 0.8 * targets + 0.2 * randn(n_large)
            predictions = 0.6 * targets + 0.4 * randn(n_large)
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            @test !isnan(mmc)
            @test !isinf(mmc)
            @test -1.0 < mmc < 1.0
        end
        
        @testset "Extreme values" begin
            # Test with extreme values
            targets = [1e6, -1e6, 1e-6, -1e-6, 0.0]
            meta_model = [5e5, -5e5, 5e-7, -5e-7, 1e-10]
            predictions = [8e5, -8e5, 8e-7, -8e-7, 2e-10]
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            @test !isnan(mmc)
            @test !isinf(mmc)
        end
        
        @testset "Constant inputs" begin
            # Test with constant values
            n = 100
            targets = fill(5.0, n)
            meta_model = fill(3.0, n)
            predictions = fill(7.0, n)
            
            mmc = Metrics.calculate_mmc(predictions, meta_model, targets)
            # Should handle gracefully (might be NaN or 0, both acceptable)
            @test isnan(mmc) || abs(mmc) < 1e-10
        end
    end
end