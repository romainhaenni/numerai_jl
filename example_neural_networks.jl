#!/usr/bin/env julia

"""
Example usage of Neural Networks in the Numerai Tournament ML Pipeline

This script demonstrates:
1. Training neural network models
2. Ensemble with traditional models (XGBoost, LightGBM)
3. GPU acceleration (when available)
4. Cross-validation
5. Model comparison and selection
"""

using Pkg
Pkg.activate(".")

# Load modules
include("src/ml/neural_networks.jl")
include("src/ml/models.jl")
include("src/ml/ensemble.jl")

using .NeuralNetworks
using .Models
using .Ensemble
using Random
using Statistics
using DataFrames
using Logging

# Set up logging
global_logger(ConsoleLogger(stdout, Logging.Info))

function generate_numerai_like_data(n_samples=5000, n_features=200)
    """Generate synthetic data similar to Numerai tournament data"""
    Random.seed!(42)
    
    # Generate features with some correlation structure
    X = randn(Float64, n_samples, n_features)
    
    # Add some correlation between features (like real Numerai data)
    for i in 1:10
        factor = randn(n_samples)
        for j in ((i-1)*20+1):min(i*20, n_features)
            X[:, j] += 0.3 * factor
        end
    end
    
    # Create a complex non-linear target
    # Use subset of features with interactions
    important_features = X[:, 1:50]
    y = (
        0.3 * sum(important_features[:, 1:10], dims=2) +
        0.2 * sum(important_features[:, 11:20] .* important_features[:, 21:30], dims=2) +
        0.1 * sum(sin.(important_features[:, 31:40]), dims=2) +
        0.05 * randn(n_samples)
    )
    y = vec(y)
    
    # Normalize target to [0, 1] range (like Numerai)
    y = (y .- minimum(y)) ./ (maximum(y) - minimum(y))
    
    # Create eras (time-based splits)
    n_eras = 50
    era_size = n_samples ÷ n_eras
    eras = repeat(1:n_eras, inner=era_size)[1:n_samples]
    
    return X, y, eras
end

function train_neural_models()
    """Train different neural network architectures"""
    @info "=== Training Neural Network Models ==="
    
    X, y, eras = generate_numerai_like_data()
    @info "Generated dataset" n_samples=size(X, 1) n_features=size(X, 2) n_eras=length(unique(eras))
    
    # Split data
    n_train = Int(0.7 * length(y))
    train_indices = 1:n_train
    val_indices = (n_train+1):length(y)
    
    X_train = X[train_indices, :]
    y_train = y[train_indices]
    X_val = X[val_indices, :]
    y_val = y[val_indices]
    
    models = Dict()
    
    # 1. MLP Model - good baseline
    @info "Training MLP model..."
    models["mlp"] = MLPModel("numerai_mlp",
                            hidden_layers=[128, 64, 32],
                            dropout_rate=0.3,
                            learning_rate=0.001,
                            epochs=50,
                            batch_size=256,
                            early_stopping_patience=10,
                            gpu_enabled=false)  # CPU for stability
    
    train!(models["mlp"], X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
    
    # 2. ResNet Model - good for deep networks
    @info "Training ResNet model..."
    models["resnet"] = ResNetModel("numerai_resnet",
                                  hidden_layers=[128, 128, 64],
                                  dropout_rate=0.2,
                                  learning_rate=0.001,
                                  epochs=50,
                                  batch_size=256,
                                  early_stopping_patience=10,
                                  gpu_enabled=false)
    
    train!(models["resnet"], X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
    
    # 3. TabNet Model - designed for tabular data
    @info "Training TabNet model..."
    models["tabnet"] = TabNetModel("numerai_tabnet",
                                  n_d=64,
                                  n_a=64,
                                  n_steps=3,
                                  learning_rate=0.02,
                                  epochs=50,
                                  batch_size=512,
                                  early_stopping_patience=10,
                                  gpu_enabled=false)
    
    train!(models["tabnet"], X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
    
    # Evaluate models
    @info "=== Neural Network Model Results ==="
    results = Dict()
    for (name, model) in models
        predictions = predict(model, X_val)
        correlation = cor(predictions, y_val)
        results[name] = correlation
        @info "Model performance" model=name correlation=round(correlation, digits=4)
    end
    
    return models, X_train, y_train, X_val, y_val, results
end

function train_traditional_models(X_train, y_train, X_val, y_val)
    """Train traditional models for comparison"""
    @info "=== Training Traditional Models ==="
    
    models = Dict()
    
    # XGBoost
    @info "Training XGBoost..."
    models["xgboost"] = XGBoostModel("numerai_xgb",
                                    max_depth=6,
                                    learning_rate=0.01,
                                    colsample_bytree=0.3,
                                    num_rounds=500,
                                    gpu_enabled=false)
    
    train!(models["xgboost"], X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
    
    # LightGBM
    @info "Training LightGBM..."
    models["lightgbm"] = LightGBMModel("numerai_lgb",
                                      num_leaves=63,
                                      learning_rate=0.01,
                                      feature_fraction=0.3,
                                      n_estimators=500,
                                      gpu_enabled=false)
    
    train!(models["lightgbm"], X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
    
    # Evaluate models
    @info "=== Traditional Model Results ==="
    results = Dict()
    for (name, model) in models
        predictions = predict(model, X_val)
        correlation = cor(predictions, y_val)
        results[name] = correlation
        @info "Model performance" model=name correlation=round(correlation, digits=4)
    end
    
    return models, results
end

function create_ensemble_with_neural_networks(nn_models, traditional_models, X_val, y_val)
    """Create ensemble combining neural networks and traditional models"""
    @info "=== Creating Ensemble Models ==="
    
    # Combine all models
    all_models = NumeraiModel[]
    model_names = String[]
    
    for (name, model) in nn_models
        push!(all_models, model)
        push!(model_names, "NN_$name")
    end
    
    for (name, model) in traditional_models
        push!(all_models, model)
        push!(model_names, "TRAD_$name")
    end
    
    # Create ensemble
    ensemble = ModelEnsemble(all_models, name="numerai_mixed_ensemble")
    
    # Optimize ensemble weights
    @info "Optimizing ensemble weights..."
    optimal_weights = optimize_weights(ensemble, X_val, y_val, n_iterations=1000)
    ensemble.weights = optimal_weights
    
    # Evaluate ensemble
    ensemble_predictions = predict_ensemble(ensemble, X_val)
    ensemble_correlation = cor(ensemble_predictions, y_val)
    
    @info "=== Ensemble Results ==="
    @info "Ensemble performance" correlation=round(ensemble_correlation, digits=4)
    
    # Show individual model weights
    for (i, (weight, name)) in enumerate(zip(optimal_weights, model_names))
        @info "Model weight" model=name weight=round(weight, digits=4)
    end
    
    return ensemble, ensemble_correlation
end

function cross_validate_neural_networks(X, y, eras)
    """Demonstrate cross-validation with neural networks"""
    @info "=== Cross-Validation with Neural Networks ==="
    
    # Test MLP cross-validation
    mlp_scores = cross_validate_neural_network(
        () -> MLPModel("cv_mlp", hidden_layers=[64, 32], epochs=20, gpu_enabled=false),
        X, y, eras, n_splits=5
    )
    
    # Test ResNet cross-validation
    resnet_scores = cross_validate_neural_network(
        () -> ResNetModel("cv_resnet", hidden_layers=[64, 64], epochs=20, gpu_enabled=false),
        X, y, eras, n_splits=5
    )
    
    @info "Cross-validation results" mlp_mean=round(mean(mlp_scores), digits=4) mlp_std=round(std(mlp_scores), digits=4)
    @info "Cross-validation results" resnet_mean=round(mean(resnet_scores), digits=4) resnet_std=round(std(resnet_scores), digits=4)
    
    return mlp_scores, resnet_scores
end

function demonstrate_neural_network_features()
    """Demonstrate specific neural network features"""
    @info "=== Neural Network Feature Demonstration ==="
    
    # Generate small dataset for demonstration
    X_demo, y_demo, _ = generate_numerai_like_data(1000, 50)
    
    # Test custom loss functions
    @info "Testing custom loss functions..."
    y_pred = randn(Float32, 100)
    y_true = randn(Float32, 100)
    
    corr_loss = correlation_loss(y_pred, y_true)
    mse_corr_loss = mse_correlation_loss(y_pred, y_true)
    
    @info "Loss function results" correlation_loss=corr_loss mse_correlation_loss=mse_corr_loss
    
    # Test data preprocessing
    @info "Testing data preprocessing..."
    X_proc, y_proc, _, means, stds = preprocess_for_neural_network(X_demo, y_demo, use_gpu=false)
    @info "Preprocessing results" input_shape=size(X_proc) output_shape=size(y_proc) n_means=length(means)
    
    # Test training history
    model = MLPModel("demo_mlp", hidden_layers=[32, 16], epochs=10, gpu_enabled=false)
    train!(model, X_demo[1:800, :], y_demo[1:800], 
           X_val=X_demo[801:end, :], y_val=y_demo[801:end], verbose=false)
    
    history = get_training_history(model)
    @info "Training history" n_epochs=length(history) final_correlation=round(history[end]["val_correlation"], digits=4)
    
    return true
end

function main()
    """Main demonstration function"""
    @info "🚀 Starting Numerai Neural Networks Demonstration"
    
    try
        # 1. Train neural network models
        nn_models, X_train, y_train, X_val, y_val, nn_results = train_neural_models()
        
        # 2. Train traditional models for comparison
        traditional_models, trad_results = train_traditional_models(X_train, y_train, X_val, y_val)
        
        # 3. Create ensemble combining both types
        ensemble, ensemble_corr = create_ensemble_with_neural_networks(
            nn_models, traditional_models, X_val, y_val
        )
        
        # 4. Cross-validation demonstration
        X, y, eras = generate_numerai_like_data(2000, 100)  # Smaller dataset for CV
        mlp_cv, resnet_cv = cross_validate_neural_networks(X, y, eras)
        
        # 5. Feature demonstrations
        demonstrate_neural_network_features()
        
        # Final summary
        @info "=== Final Performance Summary ==="
        @info "Best Neural Network" model=argmax(nn_results) correlation=round(maximum(values(nn_results)), digits=4)
        @info "Best Traditional Model" model=argmax(trad_results) correlation=round(maximum(values(trad_results)), digits=4)
        @info "Ensemble Performance" correlation=round(ensemble_corr, digits=4)
        
        @info "✅ Neural Networks Demonstration Completed Successfully!"
        
        return 0
        
    catch e
        @error "Demonstration failed" exception=e
        return 1
    end
end

# Run demonstration if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end