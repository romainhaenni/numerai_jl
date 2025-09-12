#!/usr/bin/env julia

"""
Hyperparameter Optimization Example

This example demonstrates how to:
1. Set up hyperparameter search spaces
2. Run different optimization strategies (grid, random, Bayesian)
3. Track and compare results
4. Select the best model configuration

This is useful for finding optimal model parameters for the tournament.
"""

using Pkg
Pkg.activate(@__DIR__ * "/..")

using NumeraiTournament
using DataFrames
using Statistics
using Random

function hyperopt_demo()
    println("🚀 Starting Hyperparameter Optimization Example")
    println("=" ^ 50)
    
    # Set random seed for reproducibility
    Random.seed!(42)
    
    # Load configuration
    config = NumeraiTournament.load_config("config.toml")
    data_dir = get(config, "data_dir", "data")
    
    # Load data (using a sample for faster optimization)
    println("📊 Loading data...")
    train_data = NumeraiTournament.DataLoader.load_training_data(data_dir)
    val_data = NumeraiTournament.DataLoader.load_validation_data(data_dir)
    
    # Sample data for faster iteration
    sample_size = min(10000, nrow(train_data))
    train_sample = train_data[1:sample_size, :]
    println("   Using $(nrow(train_sample)) training samples")
    println("   Using $(nrow(val_data)) validation samples")
    
    # Define hyperparameter search space
    println("\n🔍 Defining Search Space...")
    
    # XGBoost hyperparameter space
    xgb_search_space = Dict(
        :max_depth => [3, 5, 7, 9],
        :eta => [0.01, 0.05, 0.1, 0.2],
        :subsample => [0.6, 0.7, 0.8, 0.9],
        :colsample_bytree => [0.6, 0.7, 0.8, 0.9],
        :num_round => [50, 100, 150, 200]
    )
    
    # Calculate total combinations
    total_combinations = prod(length(v) for v in values(xgb_search_space))
    println("   Total parameter combinations: $total_combinations")
    
    # Method 1: Grid Search (exhaustive but expensive)
    println("\n🔲 Method 1: Grid Search")
    println("   (Using subset due to computational cost)")
    
    # Use smaller grid for demo
    small_grid = Dict(
        :max_depth => [3, 5],
        :eta => [0.05, 0.1],
        :subsample => [0.7, 0.8],
        :colsample_bytree => [0.8],
        :num_round => [50]
    )
    
    grid_results = run_grid_search(train_sample, val_data, small_grid)
    
    # Method 2: Random Search (more efficient)
    println("\n🎲 Method 2: Random Search")
    n_random_trials = 20
    
    random_results = run_random_search(
        train_sample, 
        val_data, 
        xgb_search_space, 
        n_random_trials
    )
    
    # Method 3: Bayesian Optimization (most efficient)
    println("\n🧠 Method 3: Bayesian-inspired Optimization")
    n_bayes_trials = 15
    
    bayes_results = run_bayesian_optimization(
        train_sample,
        val_data,
        xgb_search_space,
        n_bayes_trials
    )
    
    # Compare results
    println("\n📊 Optimization Results Comparison:")
    println("=" ^ 50)
    
    best_grid = grid_results[argmax([r[:score] for r in grid_results])]
    best_random = random_results[argmax([r[:score] for r in random_results])]
    best_bayes = bayes_results[argmax([r[:score] for r in bayes_results])]
    
    println("\n🏆 Best Models:")
    println("   Grid Search:     $(round(best_grid[:score], digits=4))")
    println("   Random Search:   $(round(best_random[:score], digits=4))")
    println("   Bayesian Search: $(round(best_bayes[:score], digits=4))")
    
    # Show best parameters
    overall_best = best_bayes  # Usually Bayesian is best
    println("\n⚙️  Best Parameters Found:")
    for (key, value) in overall_best[:params]
        println("   $key: $value")
    end
    
    # Train final model with best parameters
    println("\n🏋️ Training Final Model with Best Parameters...")
    
    final_config = Dict(
        :model_type => "xgboost",
        :model_params => overall_best[:params],
        :features => "medium",
        :neutralization_proportion => 0.5
    )
    
    final_pipeline = NumeraiTournament.Pipeline.MLPipeline(final_config)
    
    # Train on full dataset
    NumeraiTournament.Pipeline.train!(final_pipeline, train_data)
    
    # Final evaluation
    final_metrics = NumeraiTournament.Pipeline.evaluate(final_pipeline, val_data)
    
    println("\n📈 Final Model Performance:")
    println("   Correlation: $(round(final_metrics[:correlation], digits=4))")
    println("   Sharpe: $(round(final_metrics[:sharpe], digits=2))")
    println("   Max Drawdown: $(round(final_metrics[:max_drawdown], digits=4))")
    
    # Save hyperopt results
    results_df = DataFrame(
        method = String[],
        score = Float64[],
        params = String[]
    )
    
    for r in grid_results
        push!(results_df, ("grid", r[:score], string(r[:params])))
    end
    for r in random_results
        push!(results_df, ("random", r[:score], string(r[:params])))
    end
    for r in bayes_results
        push!(results_df, ("bayes", r[:score], string(r[:params])))
    end
    
    output_file = joinpath(data_dir, "hyperopt_results.csv")
    CSV.write(output_file, results_df)
    println("\n💾 Results saved to $output_file")
    
    println("\n✅ Hyperparameter optimization completed!")
    
    return final_pipeline, overall_best
end

function run_grid_search(train_data, val_data, search_space)
    results = []
    
    # Generate all combinations
    keys = collect(keys(search_space))
    values = collect(values(search_space))
    
    total = prod(length(v) for v in values)
    count = 0
    
    # Iterate through all combinations
    for combo in Iterators.product(values...)
        count += 1
        params = Dict(zip(keys, combo))
        
        print("\r   Testing combination $count/$total...")
        
        # Train and evaluate
        score = evaluate_params(train_data, val_data, params)
        
        push!(results, Dict(:params => params, :score => score))
    end
    
    println("\r   Tested $total combinations" * " " ^ 20)
    
    return results
end

function run_random_search(train_data, val_data, search_space, n_trials)
    results = []
    
    for i in 1:n_trials
        # Sample random parameters
        params = Dict(
            key => rand(values)
            for (key, values) in search_space
        )
        
        print("\r   Trial $i/$n_trials...")
        
        # Train and evaluate
        score = evaluate_params(train_data, val_data, params)
        
        push!(results, Dict(:params => params, :score => score))
    end
    
    println("\r   Completed $n_trials trials" * " " ^ 20)
    
    return results
end

function run_bayesian_optimization(train_data, val_data, search_space, n_trials)
    results = []
    
    # Start with random exploration
    n_random = min(5, n_trials ÷ 3)
    
    # Initial random samples
    for i in 1:n_random
        params = Dict(
            key => rand(values)
            for (key, values) in search_space
        )
        
        print("\r   Initial exploration $i/$n_random...")
        
        score = evaluate_params(train_data, val_data, params)
        push!(results, Dict(:params => params, :score => score))
    end
    
    # Exploitation phase (simplified Bayesian optimization)
    for i in (n_random + 1):n_trials
        # Find best so far
        best_score = maximum(r[:score] for r in results)
        best_params = results[argmax([r[:score] for r in results])][:params]
        
        # Sample near best parameters with some exploration
        params = Dict{Symbol, Any}()
        for (key, values) in search_space
            if rand() < 0.7  # 70% exploitation, 30% exploration
                # Sample near best
                best_val = best_params[key]
                best_idx = findfirst(==(best_val), values)
                if !isnothing(best_idx)
                    # Sample nearby values
                    range = max(1, best_idx - 1):min(length(values), best_idx + 1)
                    params[key] = values[rand(range)]
                else
                    params[key] = rand(values)
                end
            else
                # Random exploration
                params[key] = rand(values)
            end
        end
        
        print("\r   Bayesian trial $i/$n_trials (best: $(round(best_score, digits=4)))...")
        
        score = evaluate_params(train_data, val_data, params)
        push!(results, Dict(:params => params, :score => score))
    end
    
    println("\r   Completed $n_trials Bayesian trials" * " " ^ 30)
    
    return results
end

function evaluate_params(train_data, val_data, params)
    # Create pipeline with given parameters
    config = Dict(
        :model_type => "xgboost",
        :model_params => params,
        :features => "small",  # Use small features for speed
        :neutralization_proportion => 0.5
    )
    
    try
        pipeline = NumeraiTournament.Pipeline.MLPipeline(config)
        NumeraiTournament.Pipeline.train!(pipeline, train_data)
        
        # Generate predictions
        predictions = NumeraiTournament.Pipeline.predict(pipeline, val_data)
        
        # Calculate correlation
        score = cor(predictions, val_data.target)
        
        return isnan(score) ? 0.0 : score
    catch e
        # Return low score if training fails
        return 0.0
    end
end

# Run the example
if abspath(PROGRAM_FILE) == @__FILE__
    pipeline, best_params = hyperopt_demo()
end