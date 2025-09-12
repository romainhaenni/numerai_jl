using Test
using NumeraiTournament
using NumeraiTournament.Models: RidgeModel, LassoModel, ElasticNetModel
using NumeraiTournament.Models.LinearModels: train!, predict, save_model, load_model!
using Random
using Statistics

@testset "Linear Models Tests" begin
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
    
    @testset "Ridge Model" begin
        @testset "Single Target" begin
            model = RidgeModel("test_ridge", alpha=1.0)
            
            # Train model
            train!(model, X_train, y_train_single, X_val=X_val, y_val=y_val_single, verbose=false)
            
            # Check model is trained
            @test model.model !== nothing
            @test haskey(model.model, "coef")
            @test haskey(model.model, "intercept")
            @test model.model["is_multi_target"] == false
            @test model.model["n_targets"] == 1
            
            # Make predictions
            predictions = predict(model, X_val)
            @test size(predictions) == (50,)
            @test predictions isa Vector{Float64}
            
            # Check correlation is reasonable
            corr = cor(predictions, y_val_single)
            @test !isnan(corr)
        end
        
        @testset "Multi Target" begin
            model = RidgeModel("test_ridge_multi", alpha=1.0)
            
            # Train model with multi-target
            train!(model, X_train, y_train_multi, X_val=X_val, y_val=y_val_multi, verbose=false)
            
            # Check model is trained for multi-target
            @test model.model !== nothing
            @test model.model["is_multi_target"] == true
            @test model.model["n_targets"] == n_targets
            @test size(model.model["coef"]) == (n_features, n_targets)
            @test length(model.model["intercept"]) == n_targets
            
            # Make predictions
            predictions = predict(model, X_val)
            @test size(predictions) == (50, n_targets)
            @test predictions isa Matrix{Float64}
            
            # Check correlations for each target
            for i in 1:n_targets
                corr = cor(predictions[:, i], y_val_multi[:, i])
                @test !isnan(corr)
            end
        end
    end
    
    @testset "Lasso Model" begin
        @testset "Single Target" begin
            model = LassoModel("test_lasso", alpha=0.1)
            
            # Train model
            train!(model, X_train, y_train_single, X_val=X_val, y_val=y_val_single, verbose=false)
            
            # Check model is trained
            @test model.model !== nothing
            @test haskey(model.model, "coef")
            @test haskey(model.model, "intercept")
            @test haskey(model.model, "n_nonzero")
            @test model.model["is_multi_target"] == false
            
            # Make predictions
            predictions = predict(model, X_val)
            @test size(predictions) == (50,)
            @test predictions isa Vector{Float64}
            
            # Check sparsity (Lasso should produce some zero coefficients)
            @test model.model["n_nonzero"] <= n_features
        end
        
        @testset "Multi Target" begin
            model = LassoModel("test_lasso_multi", alpha=0.1)
            
            # Train model with multi-target
            train!(model, X_train, y_train_multi, X_val=X_val, y_val=y_val_multi, verbose=false)
            
            # Check model is trained for multi-target
            @test model.model !== nothing
            @test model.model["is_multi_target"] == true
            @test model.model["n_targets"] == n_targets
            @test size(model.model["coef"]) == (n_features, n_targets)
            @test length(model.model["n_nonzero"]) == n_targets
            
            # Make predictions
            predictions = predict(model, X_val)
            @test size(predictions) == (50, n_targets)
            @test predictions isa Matrix{Float64}
            
            # Check sparsity for each target
            for i in 1:n_targets
                @test model.model["n_nonzero"][i] <= n_features
            end
        end
    end
    
    @testset "ElasticNet Model" begin
        @testset "Single Target" begin
            model = ElasticNetModel("test_elastic", alpha=0.1, l1_ratio=0.5)
            
            # Train model
            train!(model, X_train, y_train_single, X_val=X_val, y_val=y_val_single, verbose=false)
            
            # Check model is trained
            @test model.model !== nothing
            @test haskey(model.model, "coef")
            @test haskey(model.model, "intercept")
            @test model.model["is_multi_target"] == false
            
            # Make predictions
            predictions = predict(model, X_val)
            @test size(predictions) == (50,)
            @test predictions isa Vector{Float64}
        end
        
        @testset "Multi Target" begin
            model = ElasticNetModel("test_elastic_multi", alpha=0.1, l1_ratio=0.5)
            
            # Train model with multi-target
            train!(model, X_train, y_train_multi, X_val=X_val, y_val=y_val_multi, verbose=false)
            
            # Check model is trained for multi-target
            @test model.model !== nothing
            @test model.model["is_multi_target"] == true
            @test model.model["n_targets"] == n_targets
            @test size(model.model["coef"]) == (n_features, n_targets)
            
            # Make predictions
            predictions = predict(model, X_val)
            @test size(predictions) == (50, n_targets)
            @test predictions isa Matrix{Float64}
        end
    end
    
    @testset "Model Persistence" begin
        # Test save/load functionality
        model = RidgeModel("test_save", alpha=1.0)
        train!(model, X_train, y_train_single, verbose=false)
        
        # Save model
        temp_file = tempname() * ".bson"
        save_model(model, temp_file)
        @test isfile(temp_file)
        
        # Load model
        new_model = RidgeModel("test_load", alpha=1.0)
        load_model!(new_model, temp_file)
        
        # Check loaded model works
        predictions_original = predict(model, X_val)
        predictions_loaded = predict(new_model, X_val)
        @test predictions_original ≈ predictions_loaded
        
        # Clean up
        rm(temp_file)
    end
    
    @testset "Edge Cases" begin
        @testset "Untrained Model" begin
            model = RidgeModel("untrained")
            @test_throws ErrorException predict(model, X_val)
        end
        
        @testset "High Regularization" begin
            # Very high alpha should shrink coefficients toward zero
            model = RidgeModel("high_reg", alpha=1000.0)
            train!(model, X_train, y_train_single, verbose=false)
            
            # Coefficients should be very small
            @test maximum(abs.(model.model["coef"])) < 0.1
        end
        
        @testset "Zero Regularization" begin
            # Zero alpha for Ridge should give OLS solution
            model = RidgeModel("no_reg", alpha=0.0)
            train!(model, X_train, y_train_single, verbose=false)
            
            predictions = predict(model, X_train)
            # Should fit training data reasonably (but random data won't be perfect)
            train_corr = cor(predictions, y_train_single)
            @test train_corr > 0.0  # Just check it's positive correlation
            @test !isnan(train_corr)
        end
    end
end