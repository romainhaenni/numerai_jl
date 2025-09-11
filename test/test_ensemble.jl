using Test
using NumeraiTournament
using NumeraiTournament.Ensemble: ModelEnsemble, train_ensemble!, predict_ensemble, optimize_weights, bagging_ensemble, stacking_ensemble, diversity_score
using NumeraiTournament.Models: XGBoostModel, create_model
using NumeraiTournament.LinearModels: RidgeModel
using Random
using Statistics

@testset "Ensemble Tests" begin
    Random.seed!(42)
    
    # Generate synthetic data
    n_samples = 100
    n_features = 10
    n_targets = 3
    
    X_train = randn(n_samples, n_features)
    y_train_single = randn(n_samples)
    y_train_multi = randn(n_samples, n_targets)
    
    X_val = randn(50, n_features)
    y_val_single = randn(50)
    y_val_multi = randn(50, n_targets)
    
    @testset "ModelEnsemble Basic" begin
        # Create ensemble with different model types
        models = [
            create_model("xgboost", "model1", max_depth=3, iterations=10),
            create_model("xgboost", "model2", max_depth=5, iterations=10),
            create_model("xgboost", "model3", max_depth=7, iterations=10)
        ]
        
        ensemble = ModelEnsemble(models)
        
        @test length(ensemble.models) == 3
        @test length(ensemble.weights) == 3
        @test sum(ensemble.weights) ≈ 1.0
        @test ensemble.name == "ensemble"
    end
    
    @testset "Train and Predict Ensemble" begin
        @testset "Single Target" begin
            models = [
                create_model("xgboost", "xgb1", max_depth=3, iterations=10),
                create_model("xgboost", "xgb2", max_depth=5, iterations=10)
            ]
            
            ensemble = ModelEnsemble(models)
            
            # Train ensemble
            train_ensemble!(ensemble, X_train, y_train_single, X_val=X_val, y_val=y_val_single, verbose=false)
            
            # Make predictions
            predictions = predict_ensemble(ensemble, X_val)
            @test size(predictions) == (50,)
            @test predictions isa Vector{Float64}
            
            # Test with individual predictions
            preds_with_individual = predict_ensemble(ensemble, X_val, return_individual=true)
            @test preds_with_individual isa Tuple
            @test length(preds_with_individual) == 2
            ensemble_pred, individual_preds = preds_with_individual
            @test size(individual_preds) == (50, 2)  # 50 samples, 2 models
        end
        
        @testset "Multi Target" begin
            # Create models that support multi-target
            models = [
                RidgeModel("ridge1", alpha=1.0),
                RidgeModel("ridge2", alpha=0.5)
            ]
            
            ensemble = ModelEnsemble(models)
            
            # Train ensemble with multi-target
            train_ensemble!(ensemble, X_train, y_train_multi, X_val=X_val, y_val=y_val_multi, verbose=false)
            
            # Make predictions
            predictions = predict_ensemble(ensemble, X_val)
            @test size(predictions) == (50, n_targets)
            @test predictions isa Matrix{Float64}
            
            # Test with individual predictions
            preds_with_individual = predict_ensemble(ensemble, X_val, return_individual=true)
            ensemble_pred, individual_preds = preds_with_individual
            @test size(individual_preds) == (50, n_targets, 2)  # 50 samples, 3 targets, 2 models
        end
    end
    
    @testset "Optimize Weights" begin
        @testset "Single Target" begin
            models = [
                create_model("xgboost", "opt1", max_depth=3, iterations=10),
                create_model("xgboost", "opt2", max_depth=5, iterations=10),
                create_model("xgboost", "opt3", max_depth=7, iterations=10)
            ]
            
            ensemble = ModelEnsemble(models)
            train_ensemble!(ensemble, X_train, y_train_single, verbose=false)
            
            # Optimize weights
            optimized_weights = optimize_weights(ensemble, X_val, y_val_single, n_iterations=100)
            
            @test length(optimized_weights) == 3
            @test sum(optimized_weights) ≈ 1.0
            @test all(w >= 0 for w in optimized_weights)
            
            # Update ensemble weights
            ensemble.weights = optimized_weights
            
            # Predictions should be better with optimized weights
            predictions = predict_ensemble(ensemble, X_val)
            @test size(predictions) == (50,)
        end
        
        @testset "Multi Target" begin
            models = [
                RidgeModel("opt_ridge1", alpha=1.0),
                RidgeModel("opt_ridge2", alpha=0.5)
            ]
            
            ensemble = ModelEnsemble(models)
            train_ensemble!(ensemble, X_train, y_train_multi, verbose=false)
            
            # Optimize weights for multi-target
            optimized_weights = optimize_weights(ensemble, X_val, y_val_multi, n_iterations=100)
            
            @test size(optimized_weights) == (2, n_targets)  # 2 models, 3 targets
            
            # Each target should have normalized weights
            for i in 1:n_targets
                @test sum(optimized_weights[:, i]) ≈ 1.0
                @test all(w >= 0 for w in optimized_weights[:, i])
            end
        end
    end
    
    @testset "Bagging Ensemble" begin
        # Create bagging ensemble
        n_models = 3
        ensemble = bagging_ensemble(
            () -> create_model("xgboost", "bagged", max_depth=3, iterations=10),
            n_models,
            X_train,
            y_train_single,
            sample_ratio=0.8,
            feature_ratio=0.8,
            verbose=false
        )
        
        @test length(ensemble.models) == n_models
        @test ensemble.name == "bagging_ensemble"
        
        # Make predictions
        predictions = predict_ensemble(ensemble, X_val)
        @test size(predictions) == (50,)
        
        # Test with multi-target
        ensemble_multi = bagging_ensemble(
            () -> RidgeModel("bagged_ridge", alpha=1.0),
            n_models,
            X_train,
            y_train_multi,
            sample_ratio=0.8,
            feature_ratio=0.8,
            verbose=false
        )
        
        predictions_multi = predict_ensemble(ensemble_multi, X_val)
        @test size(predictions_multi) == (50, n_targets)
    end
    
    @testset "Stacking Ensemble" begin
        @testset "Single Target" begin
            # Create base models
            base_models = [
                create_model("xgboost", "base1", max_depth=3, iterations=10),
                create_model("xgboost", "base2", max_depth=5, iterations=10)
            ]
            
            # Create meta model
            meta_model = RidgeModel("meta", alpha=1.0)
            
            # Create stacking function
            stacked_predict = stacking_ensemble(
                base_models,
                meta_model,
                X_train,
                y_train_single,
                X_val,
                y_val_single
            )
            
            # Make predictions
            predictions = stacked_predict(X_val)
            @test size(predictions) == (50,)
            @test predictions isa Vector{Float64}
        end
        
        @testset "Multi Target" begin
            # Create base models
            base_models = [
                RidgeModel("base_ridge1", alpha=1.0),
                RidgeModel("base_ridge2", alpha=0.5)
            ]
            
            # Create meta model
            meta_model = RidgeModel("meta_ridge", alpha=0.1)
            
            # Create stacking function for multi-target
            stacked_predict_multi = stacking_ensemble(
                base_models,
                meta_model,
                X_train,
                y_train_multi,
                X_val,
                y_val_multi
            )
            
            # Make predictions
            predictions = stacked_predict_multi(X_val)
            @test size(predictions) == (50, n_targets)
            @test predictions isa Matrix{Float64}
        end
    end
    
    @testset "Diversity Score" begin
        # Create prediction matrix from different models
        n_models = 3
        predictions_matrix = randn(50, n_models)
        
        # Add some correlation between models
        predictions_matrix[:, 2] = 0.8 * predictions_matrix[:, 1] + 0.2 * randn(50)
        
        score = diversity_score(predictions_matrix)
        
        @test score >= 0.0
        @test score <= 1.0
        
        # Identical predictions should have low diversity
        identical_matrix = repeat(randn(50), 1, 3)
        identical_score = diversity_score(identical_matrix)
        @test identical_score < 0.1
        
        # Independent predictions should have high diversity
        independent_matrix = randn(50, 3)
        independent_score = diversity_score(independent_matrix)
        @test independent_score > identical_score
    end
    
    @testset "Mixed Model Types" begin
        # Test ensemble with different model types
        models = [
            create_model("xgboost", "xgb_mixed", max_depth=3, iterations=10),
            RidgeModel("ridge_mixed", alpha=1.0)
        ]
        
        ensemble = ModelEnsemble(models, weights=[0.6, 0.4])
        
        # Train with single target
        train_ensemble!(ensemble, X_train, y_train_single, verbose=false)
        
        predictions = predict_ensemble(ensemble, X_val)
        @test size(predictions) == (50,)
        
        # Test custom weights
        @test ensemble.weights[1] == 0.6
        @test ensemble.weights[2] == 0.4
    end
    
    @testset "Edge Cases" begin
        @testset "Single Model Ensemble" begin
            models = [create_model("xgboost", "single", max_depth=3, iterations=10)]
            ensemble = ModelEnsemble(models)
            
            @test length(ensemble.models) == 1
            @test ensemble.weights == [1.0]
            
            train_ensemble!(ensemble, X_train, y_train_single, verbose=false)
            predictions = predict_ensemble(ensemble, X_val)
            @test size(predictions) == (50,)
        end
        
        @testset "Empty Predictions" begin
            # Test with zero samples
            models = [RidgeModel("empty", alpha=1.0)]
            ensemble = ModelEnsemble(models)
            train_ensemble!(ensemble, X_train, y_train_single, verbose=false)
            
            X_empty = Matrix{Float64}(undef, 0, n_features)
            predictions = predict_ensemble(ensemble, X_empty)
            @test size(predictions) == (0,)
        end
    end
end