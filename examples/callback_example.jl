#!/usr/bin/env julia

"""
Example script demonstrating callback support for training progress reporting.

This script shows how to:
1. Create various types of callbacks (logging, progress, dashboard)
2. Pass callbacks to model training
3. Monitor training progress in real-time

Usage:
    julia --project=. examples/callback_example.jl
"""

using Pkg
Pkg.activate(".")

# Add the src directory to the load path to access internal modules
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using DataFrames
using Random
using Statistics

# Import our modules
include("../src/ml/models.jl")
using .Models

include("../src/ml/callbacks.jl")
using .Callbacks

function create_sample_data(n_samples=1000, n_features=50)
    """Create sample training data for demonstration."""
    Random.seed!(42)
    
    # Generate random features
    X = randn(n_samples, n_features)
    
    # Create a target with some signal
    signal_features = X[:, 1:5]  # First 5 features contain signal
    y = 0.1 * sum(signal_features, dims=2) + 0.05 * randn(n_samples, 1)
    y = vec(y)
    
    # Normalize target to [0, 1] range
    y = (y .- minimum(y)) ./ (maximum(y) - minimum(y))
    
    return X, y
end

function demo_basic_callback()
    """Demonstrate basic callback functionality."""
    println("🔬 Demo 1: Basic Callback Functionality")
    println("=" ^ 50)
    
    # Create sample data
    X_train, y_train = create_sample_data(1000, 50)
    X_val, y_val = create_sample_data(200, 50)
    
    # Create a simple progress callback
    progress_callback = create_progress_callback(
        function(info::CallbackInfo)
            println("  📊 [$(info.model_name)] Epoch $(info.epoch)/$(info.total_epochs) - Progress: $(round(info.epoch/info.total_epochs*100))%")
            if info.eta !== nothing
                eta_str = info.eta < 60 ? "$(round(Int, info.eta))s" : "$(round(info.eta/60, digits=1))m"
                println("    ⏱️  ETA: $eta_str")
            end
            return CONTINUE
        end,
        frequency=1,  # Report every iteration/epoch
        name="demo_progress"
    )
    
    # Create logging callback
    logging_callback = create_logging_callback(frequency=5, verbose=true)
    
    callbacks = [progress_callback, logging_callback]
    
    # Test with XGBoost
    println("\n🚀 Training XGBoost model with callbacks...")
    xgb_model = XGBoostModel("demo_xgb", num_rounds=50)
    
    train!(xgb_model, X_train, y_train,
           X_val=X_val, y_val=y_val,
           verbose=false,  # Let callbacks handle output
           callbacks=callbacks)
    
    println("✅ XGBoost training completed!")
    
    # Test predictions
    predictions = predict(xgb_model, X_val)
    corr = cor(predictions, y_val)
    println("📈 Validation correlation: $(round(corr, digits=4))")
end

function demo_lightgbm_callback()
    """Demonstrate LightGBM with callbacks."""
    println("\n🔬 Demo 2: LightGBM with Callbacks")
    println("=" ^ 50)
    
    # Create sample data
    X_train, y_train = create_sample_data(1000, 50)
    X_val, y_val = create_sample_data(200, 50)
    
    # Create a custom callback that tracks the best score
    best_score = Ref(0.0)
    
    tracking_callback = create_progress_callback(
        function(info::CallbackInfo)
            if info.val_score !== nothing && info.val_score > best_score[]
                best_score[] = info.val_score
                println("  🎯 New best validation score: $(round(info.val_score, digits=6))")
            end
            
            # Print periodic updates
            if info.iteration % 10 == 0 || info.epoch % 10 == 0
                progress_pct = info.total_epochs > 0 ? 
                    round(info.epoch/info.total_epochs*100) : 
                    (info.total_iterations !== nothing ? round(info.iteration/info.total_iterations*100) : 0)
                println("  📊 [$(info.model_name)] Progress: $(progress_pct)%")
            end
            
            return CONTINUE
        end,
        frequency=1,
        name="score_tracker"
    )
    
    callbacks = [tracking_callback]
    
    # Test with LightGBM
    println("\n🚀 Training LightGBM model with custom callbacks...")
    lgbm_model = LightGBMModel("demo_lgbm", n_estimators=100)
    
    train!(lgbm_model, X_train, y_train,
           X_val=X_val, y_val=y_val,
           verbose=false,
           callbacks=callbacks)
    
    println("✅ LightGBM training completed!")
    println("🏆 Best validation score achieved: $(round(best_score[], digits=6))")
    
    # Test predictions
    predictions = predict(lgbm_model, X_val)
    corr = cor(predictions, y_val)
    println("📈 Final validation correlation: $(round(corr, digits=4))")
end

function demo_multi_target_callback()
    """Demonstrate callbacks with multi-target training."""
    println("\n🔬 Demo 3: Multi-Target Training with Callbacks")
    println("=" ^ 50)
    
    # Create multi-target sample data
    X_train, y_train_single = create_sample_data(1000, 50)
    X_val, y_val_single = create_sample_data(200, 50)
    
    # Create multiple targets
    y_train_multi = hcat(y_train_single, 
                        0.8 * y_train_single + 0.2 * randn(1000),
                        0.6 * y_train_single + 0.4 * randn(1000))
    y_val_multi = hcat(y_val_single,
                      0.8 * y_val_single + 0.2 * randn(200),
                      0.6 * y_val_single + 0.4 * randn(200))
    
    # Create callback that tracks each target
    target_progress = Dict{String, Int}()
    
    multi_target_callback = create_progress_callback(
        function(info::CallbackInfo)
            if !haskey(target_progress, info.model_name)
                target_progress[info.model_name] = 0
                println("  🎯 Started training $(info.model_name)")
            end
            
            target_progress[info.model_name] = info.epoch
            
            if info.epoch == info.total_epochs
                println("  ✅ Completed $(info.model_name)")
                println("  📋 Progress summary: $(target_progress)")
            end
            
            return CONTINUE
        end,
        frequency=1,
        name="multi_target_tracker"
    )
    
    callbacks = [multi_target_callback]
    
    # Test with XGBoost multi-target
    println("\n🚀 Training multi-target XGBoost model...")
    xgb_model = XGBoostModel("demo_multi_xgb", num_rounds=30)
    
    train!(xgb_model, X_train, y_train_multi,
           X_val=X_val, y_val=y_val_multi,
           verbose=false,
           callbacks=callbacks)
    
    println("✅ Multi-target training completed!")
    
    # Test predictions
    predictions = predict(xgb_model, X_val)
    if predictions isa Matrix
        println("📈 Multi-target predictions shape: $(size(predictions))")
        for target_idx in 1:size(predictions, 2)
            corr = cor(predictions[:, target_idx], y_val_multi[:, target_idx])
            println("  Target $target_idx correlation: $(round(corr, digits=4))")
        end
    end
end

function demo_custom_dashboard_callback()
    """Demonstrate a dashboard-style callback."""
    println("\n🔬 Demo 4: Dashboard-Style Progress Tracking")
    println("=" ^ 50)
    
    # Create sample data
    X_train, y_train = create_sample_data(1000, 50)
    X_val, y_val = create_sample_data(200, 50)
    
    # Simulate dashboard state
    dashboard_state = Dict{Symbol, Any}(
        :is_training => false,
        :model_name => "",
        :progress => 0,
        :current_epoch => 0,
        :total_epochs => 0,
        :loss => 0.0,
        :val_score => 0.0,
        :eta => "N/A"
    )
    
    dashboard_callback = create_dashboard_callback(
        function(info::CallbackInfo)
            # Update dashboard state
            dashboard_state[:is_training] = true
            dashboard_state[:model_name] = info.model_name
            dashboard_state[:current_epoch] = info.epoch
            dashboard_state[:total_epochs] = info.total_epochs
            dashboard_state[:progress] = info.total_epochs > 0 ? 
                round(Int, (info.epoch / info.total_epochs) * 100) : 0
            
            if info.loss !== nothing
                dashboard_state[:loss] = info.loss
            end
            if info.val_score !== nothing
                dashboard_state[:val_score] = info.val_score
            end
            if info.eta !== nothing
                eta_str = if info.eta < 60
                    "$(round(Int, info.eta))s"
                else
                    "$(round(info.eta/60, digits=1))m"
                end
                dashboard_state[:eta] = eta_str
            end
            
            # Print dashboard-style update every 5 epochs
            if info.epoch % 5 == 0 || info.epoch == info.total_epochs
                println("  🖥️  Dashboard Update:")
                println("     Model: $(dashboard_state[:model_name])")
                println("     Progress: $(dashboard_state[:progress])%")
                println("     Epoch: $(dashboard_state[:current_epoch])/$(dashboard_state[:total_epochs])")
                if info.eta !== nothing
                    println("     ETA: $(dashboard_state[:eta])")
                end
                println("     " * "▓" ^ (dashboard_state[:progress] ÷ 5) * "░" ^ (20 - dashboard_state[:progress] ÷ 5))
                println()
            end
            
            return CONTINUE
        end,
        frequency=1,
        name="dashboard_simulator"
    )
    
    callbacks = [dashboard_callback]
    
    # Test with EvoTrees
    println("\n🚀 Training EvoTrees model with dashboard callback...")
    evo_model = EvoTreesModel("demo_evotrees", nrounds=50)
    
    train!(evo_model, X_train, y_train,
           X_val=X_val, y_val=y_val,
           verbose=false,
           callbacks=callbacks)
    
    # Mark training as completed
    dashboard_state[:is_training] = false
    dashboard_state[:progress] = 100
    dashboard_state[:eta] = "Completed"
    
    println("✅ Training completed!")
    println("🖥️  Final Dashboard State:")
    for (key, value) in dashboard_state
        println("  $key: $value")
    end
end

function main()
    """Run all callback demonstrations."""
    println("🎯 Numerai ML Callback System Demonstration")
    println("=" ^ 60)
    println()
    
    try
        demo_basic_callback()
        demo_lightgbm_callback()
        demo_multi_target_callback()
        demo_custom_dashboard_callback()
        
        println("\n" * "=" ^ 60)
        println("🎉 All callback demonstrations completed successfully!")
        println("💡 The callback system allows real-time monitoring of training progress")
        println("   and can be easily integrated with dashboards, logging systems,")
        println("   and other monitoring tools.")
        
    catch e
        println("\n❌ Error during demonstration: $e")
        println("\nStack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Run the demonstration
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end