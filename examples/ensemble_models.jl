#!/usr/bin/env julia

"""
Ensemble Models Example

This example demonstrates how to:
1. Train multiple different model types
2. Create an ensemble of models
3. Combine predictions with different weights
4. Evaluate ensemble performance

This is a more advanced example showing the power of model ensembling.
"""

using Pkg
Pkg.activate(@__DIR__ * "/..")

using NumeraiTournament
using DataFrames
using Statistics

function train_ensemble()
    println("🚀 Starting Ensemble Models Example")
    
    # Load configuration
    config = NumeraiTournament.load_config("config.toml")
    data_dir = get(config, "data_dir", "data")
    
    # Load training data
    println("📊 Loading training data...")
    train_data = NumeraiTournament.DataLoader.load_training_data(data_dir)
    val_data = NumeraiTournament.DataLoader.load_validation_data(data_dir)
    
    # Define different model configurations
    model_configs = [
        # XGBoost - good for capturing non-linear patterns
        Dict(
            :name => "xgboost_deep",
            :model_type => "xgboost",
            :model_params => Dict(
                :max_depth => 7,
                :eta => 0.05,
                :subsample => 0.7,
                :colsample_bytree => 0.7,
                :num_round => 200
            ),
            :features => "medium",
            :neutralization_proportion => 0.5
        ),
        
        # LightGBM - fast and efficient
        Dict(
            :name => "lightgbm_balanced",
            :model_type => "lightgbm",
            :model_params => Dict(
                :num_leaves => 31,
                :learning_rate => 0.05,
                :feature_fraction => 0.8,
                :bagging_fraction => 0.8,
                :bagging_freq => 5,
                :num_iterations => 150
            ),
            :features => "medium",
            :neutralization_proportion => 0.3
        ),
        
        # EvoTrees - pure Julia implementation
        Dict(
            :name => "evotrees_robust",
            :model_type => "evotrees",
            :model_params => Dict(
                :nrounds => 100,
                :max_depth => 6,
                :eta => 0.1,
                :subsample => 0.8,
                :colsample => 0.8
            ),
            :features => "small",
            :neutralization_proportion => 0.7
        ),
        
        # Ridge regression - simple linear baseline
        Dict(
            :name => "ridge_baseline",
            :model_type => "ridge",
            :model_params => Dict(
                :lambda => 1.0
            ),
            :features => "small",
            :neutralization_proportion => 0.0
        )
    ]
    
    # Train all models
    pipelines = Dict{String, Any}()
    val_predictions = Dict{String, Vector{Float64}}()
    val_scores = Dict{String, Float64}()
    
    for config in model_configs
        name = config[:name]
        println("\n🤖 Training $name...")
        
        # Create pipeline
        pipeline = NumeraiTournament.Pipeline.MLPipeline(config)
        
        # Train model
        start_time = time()
        NumeraiTournament.Pipeline.train!(pipeline, train_data)
        training_time = time() - start_time
        
        # Evaluate on validation
        metrics = NumeraiTournament.Pipeline.evaluate(pipeline, val_data)
        val_score = metrics[:correlation]
        
        # Generate validation predictions
        preds = NumeraiTournament.Pipeline.predict(pipeline, val_data)
        
        # Store results
        pipelines[name] = pipeline
        val_predictions[name] = preds
        val_scores[name] = val_score
        
        println("✅ $name trained in $(round(training_time, digits=1))s")
        println("   Validation correlation: $(round(val_score, digits=4))")
    end
    
    # Analyze individual model performance
    println("\n📊 Individual Model Performance:")
    for (name, score) in sort(collect(val_scores), by=x->x[2], rev=true)
        println("   $name: $(round(score, digits=4))")
    end
    
    # Create ensemble predictions with different weighting schemes
    println("\n🎯 Creating Ensemble Predictions...")
    
    # Method 1: Equal weighted ensemble
    equal_weights = ones(length(model_configs)) / length(model_configs)
    equal_ensemble = create_ensemble(val_predictions, equal_weights)
    equal_corr = cor(equal_ensemble, val_data.target)
    println("   Equal weighted: $(round(equal_corr, digits=4))")
    
    # Method 2: Performance weighted ensemble
    scores_array = [val_scores[config[:name]] for config in model_configs]
    perf_weights = scores_array / sum(scores_array)
    perf_ensemble = create_ensemble(val_predictions, perf_weights)
    perf_corr = cor(perf_ensemble, val_data.target)
    println("   Performance weighted: $(round(perf_corr, digits=4))")
    
    # Method 3: Optimized weights (simple grid search)
    best_weights, best_corr = optimize_ensemble_weights(val_predictions, val_data.target)
    opt_ensemble = create_ensemble(val_predictions, best_weights)
    println("   Optimized weights: $(round(best_corr, digits=4))")
    
    # Show optimal weights
    println("\n🎯 Optimal Ensemble Weights:")
    for (i, config) in enumerate(model_configs)
        println("   $(config[:name]): $(round(best_weights[i], digits=3))")
    end
    
    # Generate final predictions for live data
    println("\n🔮 Generating Live Predictions...")
    live_data = NumeraiTournament.DataLoader.load_live_data(data_dir)
    
    live_predictions = Dict{String, Vector{Float64}}()
    for (name, pipeline) in pipelines
        live_predictions[name] = NumeraiTournament.Pipeline.predict(pipeline, live_data)
    end
    
    # Create final ensemble predictions
    final_predictions = create_ensemble(live_predictions, best_weights)
    
    # Save predictions
    predictions_df = DataFrame(
        id = live_data.id,
        prediction = final_predictions
    )
    
    # Also save individual model predictions for analysis
    for (name, preds) in live_predictions
        predictions_df[!, Symbol(name)] = preds
    end
    
    output_file = joinpath(data_dir, "ensemble_predictions.csv")
    CSV.write(output_file, predictions_df)
    println("💾 Ensemble predictions saved to $output_file")
    
    println("\n🎉 Ensemble example completed successfully!")
    
    return pipelines, best_weights
end

function create_ensemble(predictions_dict::Dict{String, Vector{Float64}}, 
                        weights::Vector{Float64})
    # Convert dict to array of predictions
    preds_array = [preds for (_, preds) in predictions_dict]
    
    # Weighted average
    ensemble = zeros(length(preds_array[1]))
    for (i, preds) in enumerate(preds_array)
        ensemble .+= preds .* weights[i]
    end
    
    return ensemble
end

function optimize_ensemble_weights(predictions_dict::Dict{String, Vector{Float64}}, 
                                  target::Vector{Float64};
                                  n_trials::Int=100)
    n_models = length(predictions_dict)
    best_weights = ones(n_models) / n_models
    best_score = -Inf
    
    # Simple random search
    for _ in 1:n_trials
        # Generate random weights
        weights = rand(n_models)
        weights = weights / sum(weights)
        
        # Create ensemble
        ensemble = create_ensemble(predictions_dict, weights)
        
        # Evaluate
        score = cor(ensemble, target)
        
        if score > best_score
            best_score = score
            best_weights = weights
        end
    end
    
    return best_weights, best_score
end

# Run the example
if abspath(PROGRAM_FILE) == @__FILE__
    pipelines, weights = train_ensemble()
end