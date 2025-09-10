module HyperOpt

using ..Logger
using ..Models
using ..Metrics
using DataFrames
using Statistics
using Random
using Distributed
using ProgressMeter
using JSON3

export HyperOptConfig, GridSearchOptimizer, RandomSearchOptimizer, BayesianOptimizer,
       optimize_hyperparameters, evaluate_params, get_best_params,
       create_param_grid, create_param_distributions, OptimizationResult

# Helper function for time series data splitting
function split_time_series_data(
    data::Dict{String,DataFrame},
    split_idx::Int,
    n_splits::Int,
    validation_eras::Vector{Int}
)
    train_data = Dict{String,DataFrame}()
    val_data = Dict{String,DataFrame}()
    
    for (target, df) in data
        if hascol(df, :era)
            # Time series split based on eras
            unique_eras = sort(unique(df.era))
            n_eras = length(unique_eras)
            
            # Calculate split points
            val_size = n_eras ÷ n_splits
            val_start_idx = (split_idx - 1) * val_size + 1
            val_end_idx = min(split_idx * val_size, n_eras)
            
            # Get validation eras
            if !isempty(validation_eras)
                val_eras = validation_eras
            else
                val_eras = unique_eras[val_start_idx:val_end_idx]
            end
            
            # Split data
            train_mask = .!(df.era .∈ Ref(val_eras))
            val_mask = df.era .∈ Ref(val_eras)
            
            train_data[target] = df[train_mask, :]
            val_data[target] = df[val_mask, :]
        else
            # Simple percentage split if no era column
            n_rows = nrow(df)
            val_size = n_rows ÷ n_splits
            val_start = (split_idx - 1) * val_size + 1
            val_end = min(split_idx * val_size, n_rows)
            
            train_indices = vcat(1:val_start-1, val_end+1:n_rows)
            val_indices = val_start:val_end
            
            train_data[target] = df[train_indices, :]
            val_data[target] = df[val_indices, :]
        end
    end
    
    return train_data, val_data
end

# Optimization result structure
struct OptimizationResult
    best_params::Dict{Symbol,Any}
    best_score::Float64
    all_results::DataFrame
    optimization_history::Vector{Dict{Symbol,Any}}
    cross_validation_scores::Vector{Float64}
    training_time::Float64
end

# Configuration for hyperparameter optimization
struct HyperOptConfig
    model_type::Symbol
    objective::Symbol  # :correlation, :sharpe, :mmc, :tc, :multi_objective
    n_splits::Int  # Number of cross-validation splits
    validation_eras::Vector{Int}  # Eras to use for validation
    early_stopping_rounds::Int
    verbose::Bool
    parallel::Bool  # Use parallel processing
    seed::Int
    
    function HyperOptConfig(;
        model_type::Symbol,
        objective::Symbol=:correlation,
        n_splits::Int=3,
        validation_eras::Vector{Int}=Int[],
        early_stopping_rounds::Int=10,
        verbose::Bool=true,
        parallel::Bool=true,
        seed::Int=42
    )
        new(model_type, objective, n_splits, validation_eras, 
            early_stopping_rounds, verbose, parallel, seed)
    end
end

# Abstract type for all optimizers
abstract type HyperOptimizer end

# Grid Search Optimizer
struct GridSearchOptimizer <: HyperOptimizer
    param_grid::Dict{Symbol,Vector}
    config::HyperOptConfig
end

# Random Search Optimizer
struct RandomSearchOptimizer <: HyperOptimizer
    param_distributions::Dict{Symbol,Any}
    n_iter::Int
    config::HyperOptConfig
end

# Bayesian Optimizer using Gaussian Processes
struct BayesianOptimizer <: HyperOptimizer
    param_bounds::Dict{Symbol,Tuple{Float64,Float64}}
    n_initial::Int  # Number of random initial points
    n_iter::Int  # Number of optimization iterations
    acquisition_function::Symbol  # :ei (expected improvement), :ucb (upper confidence bound)
    config::HyperOptConfig
end

# Create parameter grid for different model types
function create_param_grid(model_type::Symbol)
    if model_type == :XGBoost
        return Dict(
            :max_depth => [3, 5, 7, 10],
            :learning_rate => [0.001, 0.01, 0.05, 0.1],
            :n_estimators => [100, 200, 500, 1000],
            :colsample_bytree => [0.1, 0.3, 0.5, 0.7],
            :subsample => [0.5, 0.7, 0.9, 1.0],
            :min_child_weight => [1, 3, 5],
            :gamma => [0, 0.1, 0.3, 0.5],
            :reg_alpha => [0, 0.001, 0.01, 0.1],
            :reg_lambda => [0, 0.001, 0.01, 0.1]
        )
    elseif model_type == :LightGBM
        return Dict(
            :num_leaves => [15, 31, 63, 127],
            :learning_rate => [0.001, 0.01, 0.05, 0.1],
            :n_estimators => [100, 200, 500, 1000],
            :feature_fraction => [0.1, 0.3, 0.5, 0.7],
            :bagging_fraction => [0.5, 0.7, 0.9, 1.0],
            :bagging_freq => [0, 1, 5],
            :min_data_in_leaf => [10, 20, 50, 100],
            :lambda_l1 => [0, 0.001, 0.01, 0.1],
            :lambda_l2 => [0, 0.001, 0.01, 0.1]
        )
    elseif model_type == :EvoTrees
        return Dict(
            :max_depth => [3, 5, 7, 10],
            :eta => [0.001, 0.01, 0.05, 0.1],
            :nrounds => [100, 200, 500, 1000],
            :subsample => [0.5, 0.7, 0.9, 1.0],
            :colsample => [0.1, 0.3, 0.5, 0.7],
            :gamma => [0, 0.1, 0.3, 0.5],
            :lambda => [0, 0.001, 0.01, 0.1],
            :alpha => [0, 0.001, 0.01, 0.1]
        )
    elseif model_type == :CatBoost
        return Dict(
            :depth => [3, 5, 7, 10],
            :learning_rate => [0.001, 0.01, 0.05, 0.1],
            :iterations => [100, 200, 500, 1000],
            :l2_leaf_reg => [1, 3, 5, 10],
            :bagging_temperature => [0, 0.5, 1.0],
            :random_strength => [0, 0.5, 1.0, 2.0],
            :border_count => [32, 64, 128, 254]
        )
    elseif model_type == :Ridge
        return Dict(
            :alpha => [0.001, 0.01, 0.1, 1.0, 10.0, 100.0, 1000.0]
        )
    elseif model_type == :Lasso
        return Dict(
            :alpha => [0.0001, 0.001, 0.01, 0.1, 1.0, 10.0, 100.0]
        )
    elseif model_type == :ElasticNet
        return Dict(
            :alpha => [0.001, 0.01, 0.1, 1.0, 10.0],
            :l1_ratio => [0.1, 0.3, 0.5, 0.7, 0.9]
        )
    elseif model_type == :NeuralNetwork
        return Dict(
            :hidden_layers => [[128, 64], [256, 128, 64], [512, 256, 128], [128, 64, 32]],
            :learning_rate => [0.0001, 0.001, 0.01, 0.1],
            :batch_size => [256, 512, 1024, 2048],
            :epochs => [10, 20, 50, 100],
            :dropout_rate => [0.0, 0.1, 0.2, 0.3],
            :activation => [:relu, :tanh, :sigmoid]
        )
    else
        error("Unknown model type: $model_type")
    end
end

# Create parameter distributions for random search
function create_param_distributions(model_type::Symbol)
    if model_type == :XGBoost
        return Dict(
            :max_depth => () -> rand(3:15),
            :learning_rate => () -> 10.0^(rand(-4:-1)),
            :n_estimators => () -> rand(100:2000),
            :colsample_bytree => () -> rand(0.1:0.1:1.0),
            :subsample => () -> rand(0.5:0.1:1.0),
            :min_child_weight => () -> rand(1:10),
            :gamma => () -> rand(0:0.1:1.0),
            :reg_alpha => () -> 10.0^(rand(-4:0)),
            :reg_lambda => () -> 10.0^(rand(-4:0))
        )
    elseif model_type == :LightGBM
        return Dict(
            :num_leaves => () -> rand(10:200),
            :learning_rate => () -> 10.0^(rand(-4:-1)),
            :n_estimators => () -> rand(100:2000),
            :feature_fraction => () -> rand(0.1:0.1:1.0),
            :bagging_fraction => () -> rand(0.5:0.1:1.0),
            :bagging_freq => () -> rand(0:10),
            :min_data_in_leaf => () -> rand(5:200),
            :lambda_l1 => () -> 10.0^(rand(-4:0)),
            :lambda_l2 => () -> 10.0^(rand(-4:0))
        )
    elseif model_type == :EvoTrees
        return Dict(
            :max_depth => () -> rand(3:15),
            :eta => () -> 10.0^(rand(-4:-1)),
            :nrounds => () -> rand(100:2000),
            :subsample => () -> rand(0.5:0.1:1.0),
            :colsample => () -> rand(0.1:0.1:1.0),
            :gamma => () -> rand(0:0.1:1.0),
            :lambda => () -> 10.0^(rand(-4:0)),
            :alpha => () -> 10.0^(rand(-4:0))
        )
    elseif model_type == :CatBoost
        return Dict(
            :depth => () -> rand(3:12),
            :learning_rate => () -> 10.0^(rand(-4:-1)),
            :iterations => () -> rand(100:2000),
            :l2_leaf_reg => () -> rand(1:30),
            :bagging_temperature => () -> rand(0:0.1:2.0),
            :random_strength => () -> rand(0:0.1:3.0),
            :border_count => () -> rand([32, 64, 128, 254])
        )
    elseif model_type == :Ridge
        return Dict(
            :alpha => () -> 10.0^(rand(-3:3))
        )
    elseif model_type == :Lasso
        return Dict(
            :alpha => () -> 10.0^(rand(-4:2))
        )
    elseif model_type == :ElasticNet
        return Dict(
            :alpha => () -> 10.0^(rand(-3:2)),
            :l1_ratio => () -> rand()
        )
    elseif model_type == :NeuralNetwork
        return Dict(
            :hidden_layers => () -> begin
                n_layers = rand(2:4)
                layers = Int[]
                prev_size = 512
                for i in 1:n_layers
                    size = rand(32:prev_size)
                    push!(layers, size)
                    prev_size = size
                end
                layers
            end,
            :learning_rate => () -> 10.0^(rand(-4:-1)),
            :batch_size => () -> 2^rand(8:11),
            :epochs => () -> rand(10:100),
            :dropout_rate => () -> rand(0:0.05:0.5),
            :activation => () -> rand([:relu, :tanh, :sigmoid])
        )
    else
        error("Unknown model type: $model_type")
    end
end

# Evaluate parameters using cross-validation
function evaluate_params(
    params::Dict{Symbol,Any},
    data::Dict{String,DataFrame},
    config::HyperOptConfig,
    targets::Vector{String}
)
    try
        scores = Float64[]
        
        # Perform cross-validation
        for split_idx in 1:config.n_splits
            # Split data by eras for time series cross-validation
            # Simple time-series split implementation
            train_data, val_data = split_time_series_data(
                data, 
                split_idx, 
                config.n_splits,
                config.validation_eras
            )
            
            # Create and train model
            model = Models.create_model(config.model_type, params)
            Models.train!(model, train_data)
            
            # Make predictions
            predictions = Models.predict(model, val_data)
            
            # Calculate objective score
            score = calculate_objective_score(
                predictions,
                val_data,
                config.objective,
                targets
            )
            
            push!(scores, score)
        end
        
        # Return mean score across folds
        return mean(scores), scores
        
    catch e
        Logger.log_error("Error evaluating parameters: $e")
        return -Inf, Float64[]  # Return worst possible score on error
    end
end

# Calculate objective score based on specified metric
function calculate_objective_score(
    predictions::DataFrame,
    val_data::Dict{String,DataFrame},
    objective::Symbol,
    targets::Vector{String}
)
    if objective == :correlation
        # Average correlation across all targets
        correlations = Float64[]
        for target in targets
            if haskey(val_data, target) && hascol(predictions, target)
                corr = Metrics.calculate_correlation(
                    predictions[!, target],
                    val_data[target][!, "target"]
                )
                push!(correlations, corr)
            end
        end
        return isempty(correlations) ? -Inf : mean(correlations)
        
    elseif objective == :sharpe
        # Calculate Sharpe ratio
        returns = Float64[]
        for target in targets
            if haskey(val_data, target) && hascol(predictions, target)
                corr = Metrics.calculate_correlation(
                    predictions[!, target],
                    val_data[target][!, "target"]
                )
                push!(returns, corr)
            end
        end
        return isempty(returns) ? -Inf : Metrics.calculate_sharpe(returns)
        
    elseif objective == :mmc
        # Calculate Meta Model Contribution
        mmc_scores = Float64[]
        for target in targets
            if haskey(val_data, target) && hascol(predictions, target)
                # Get era information
                eras = unique(val_data[target][!, "era"])
                era_mmc = Float64[]
                
                for era in eras
                    era_mask = val_data[target][!, "era"] .== era
                    era_preds = predictions[era_mask, target]
                    era_targets = val_data[target][era_mask, "target"]
                    
                    # Calculate MMC (requires meta model predictions)
                    # For now, use correlation as proxy if meta model not available
                    mmc = Metrics.calculate_mmc(era_preds, era_targets)
                    push!(era_mmc, mmc)
                end
                
                push!(mmc_scores, mean(era_mmc))
            end
        end
        return isempty(mmc_scores) ? -Inf : mean(mmc_scores)
        
    elseif objective == :tc
        # Calculate True Contribution
        tc_scores = Float64[]
        for target in targets
            if haskey(val_data, target) && hascol(predictions, target)
                tc = Metrics.calculate_tc(
                    predictions[!, target],
                    val_data[target][!, "target"]
                )
                push!(tc_scores, tc)
            end
        end
        return isempty(tc_scores) ? -Inf : mean(tc_scores)
        
    elseif objective == :multi_objective
        # Weighted combination of multiple objectives
        corr_score = calculate_objective_score(predictions, val_data, :correlation, targets)
        sharpe_score = calculate_objective_score(predictions, val_data, :sharpe, targets)
        
        # Normalize and combine (can be adjusted)
        return 0.7 * corr_score + 0.3 * sharpe_score
        
    else
        error("Unknown objective: $objective")
    end
end

# Grid Search implementation
function optimize_hyperparameters(
    optimizer::GridSearchOptimizer,
    data::Dict{String,DataFrame},
    targets::Vector{String}
)
    start_time = time()
    
    # Generate all parameter combinations
    param_names = collect(keys(optimizer.param_grid))
    param_values = [optimizer.param_grid[name] for name in param_names]
    param_combinations = vec(collect(Iterators.product(param_values...)))
    
    n_combinations = length(param_combinations)
    Logger.log_info("Starting Grid Search with $n_combinations parameter combinations")
    
    # Storage for results
    all_results = DataFrame()
    optimization_history = Vector{Dict{Symbol,Any}}()
    best_score = -Inf
    best_params = Dict{Symbol,Any}()
    best_cv_scores = Float64[]
    
    # Progress meter
    progress = Progress(n_combinations, desc="Grid Search: ", showspeed=true)
    
    # Evaluate each combination
    if optimizer.config.parallel && nworkers() > 1
        # Parallel evaluation
        results = pmap(param_combinations) do combination
            params = Dict(zip(param_names, combination))
            score, cv_scores = evaluate_params(params, data, optimizer.config, targets)
            return (params=params, score=score, cv_scores=cv_scores)
        end
        
        for result in results
            update_best_params!(
                result.params, result.score, result.cv_scores,
                best_params, best_score, best_cv_scores,
                optimization_history, all_results
            )
            next!(progress)
        end
    else
        # Sequential evaluation
        for combination in param_combinations
            params = Dict(zip(param_names, combination))
            score, cv_scores = evaluate_params(params, data, optimizer.config, targets)
            
            update_best_params!(
                params, score, cv_scores,
                best_params, best_score, best_cv_scores,
                optimization_history, all_results
            )
            
            next!(progress)
            
            if optimizer.config.verbose && length(optimization_history) % 10 == 0
                Logger.log_info("Current best score: $best_score")
            end
        end
    end
    
    training_time = time() - start_time
    
    Logger.log_info("Grid Search completed in $(round(training_time, digits=2)) seconds")
    Logger.log_info("Best score: $best_score")
    Logger.log_info("Best parameters: $best_params")
    
    return OptimizationResult(
        best_params,
        best_score,
        all_results,
        optimization_history,
        best_cv_scores,
        training_time
    )
end

# Random Search implementation
function optimize_hyperparameters(
    optimizer::RandomSearchOptimizer,
    data::Dict{String,DataFrame},
    targets::Vector{String}
)
    start_time = time()
    Random.seed!(optimizer.config.seed)
    
    Logger.log_info("Starting Random Search with $(optimizer.n_iter) iterations")
    
    # Storage for results
    all_results = DataFrame()
    optimization_history = Vector{Dict{Symbol,Any}}()
    best_score = -Inf
    best_params = Dict{Symbol,Any}()
    best_cv_scores = Float64[]
    
    # Progress meter
    progress = Progress(optimizer.n_iter, desc="Random Search: ", showspeed=true)
    
    # Generate and evaluate random parameter combinations
    if optimizer.config.parallel && nworkers() > 1
        # Generate all random combinations first
        param_combinations = [
            Dict(name => dist() for (name, dist) in optimizer.param_distributions)
            for _ in 1:optimizer.n_iter
        ]
        
        # Parallel evaluation
        results = pmap(param_combinations) do params
            score, cv_scores = evaluate_params(params, data, optimizer.config, targets)
            return (params=params, score=score, cv_scores=cv_scores)
        end
        
        for result in results
            update_best_params!(
                result.params, result.score, result.cv_scores,
                best_params, best_score, best_cv_scores,
                optimization_history, all_results
            )
            next!(progress)
        end
    else
        # Sequential evaluation
        for iter in 1:optimizer.n_iter
            # Sample random parameters
            params = Dict(
                name => dist() 
                for (name, dist) in optimizer.param_distributions
            )
            
            score, cv_scores = evaluate_params(params, data, optimizer.config, targets)
            
            update_best_params!(
                params, score, cv_scores,
                best_params, best_score, best_cv_scores,
                optimization_history, all_results
            )
            
            next!(progress)
            
            if optimizer.config.verbose && iter % 10 == 0
                Logger.log_info("Iteration $iter/$optimizer.n_iter - Best score: $best_score")
            end
        end
    end
    
    training_time = time() - start_time
    
    Logger.log_info("Random Search completed in $(round(training_time, digits=2)) seconds")
    Logger.log_info("Best score: $best_score")
    Logger.log_info("Best parameters: $best_params")
    
    return OptimizationResult(
        best_params,
        best_score,
        all_results,
        optimization_history,
        best_cv_scores,
        training_time
    )
end

# Bayesian Optimization implementation
function optimize_hyperparameters(
    optimizer::BayesianOptimizer,
    data::Dict{String,DataFrame},
    targets::Vector{String}
)
    start_time = time()
    Random.seed!(optimizer.config.seed)
    
    Logger.log_info("Starting Bayesian Optimization with $(optimizer.n_iter) iterations")
    
    # Storage for results
    all_results = DataFrame()
    optimization_history = Vector{Dict{Symbol,Any}}()
    best_score = -Inf
    best_params = Dict{Symbol,Any}()
    best_cv_scores = Float64[]
    
    # Observed points and scores for Gaussian Process
    observed_params = Vector{Vector{Float64}}()
    observed_scores = Float64[]
    
    # Parameter names and bounds
    param_names = collect(keys(optimizer.param_bounds))
    param_ranges = [optimizer.param_bounds[name] for name in param_names]
    
    # Progress meter
    total_iters = optimizer.n_initial + optimizer.n_iter
    progress = Progress(total_iters, desc="Bayesian Optimization: ", showspeed=true)
    
    # Initial random sampling phase
    for i in 1:optimizer.n_initial
        # Sample random parameters within bounds
        param_vector = [
            rand() * (bounds[2] - bounds[1]) + bounds[1]
            for bounds in param_ranges
        ]
        
        params = Dict(zip(param_names, param_vector))
        score, cv_scores = evaluate_params(params, data, optimizer.config, targets)
        
        push!(observed_params, param_vector)
        push!(observed_scores, score)
        
        update_best_params!(
            params, score, cv_scores,
            best_params, best_score, best_cv_scores,
            optimization_history, all_results
        )
        
        next!(progress)
        
        if optimizer.config.verbose
            Logger.log_info("Initial sampling $i/$(optimizer.n_initial) - Score: $score")
        end
    end
    
    # Bayesian optimization phase
    for iter in 1:optimizer.n_iter
        # Find next point to evaluate using acquisition function
        next_params = select_next_point(
            observed_params,
            observed_scores,
            param_ranges,
            optimizer.acquisition_function
        )
        
        params = Dict(zip(param_names, next_params))
        score, cv_scores = evaluate_params(params, data, optimizer.config, targets)
        
        push!(observed_params, next_params)
        push!(observed_scores, score)
        
        update_best_params!(
            params, score, cv_scores,
            best_params, best_score, best_cv_scores,
            optimization_history, all_results
        )
        
        next!(progress)
        
        if optimizer.config.verbose && iter % 5 == 0
            Logger.log_info("Iteration $iter/$(optimizer.n_iter) - Best score: $best_score")
        end
    end
    
    training_time = time() - start_time
    
    Logger.log_info("Bayesian Optimization completed in $(round(training_time, digits=2)) seconds")
    Logger.log_info("Best score: $best_score")
    Logger.log_info("Best parameters: $best_params")
    
    return OptimizationResult(
        best_params,
        best_score,
        all_results,
        optimization_history,
        best_cv_scores,
        training_time
    )
end

# Select next point using acquisition function (simplified implementation)
function select_next_point(
    observed_params::Vector{Vector{Float64}},
    observed_scores::Vector{Float64},
    param_ranges::Vector{Tuple{Float64,Float64}},
    acquisition_function::Symbol
)
    # This is a simplified implementation
    # In production, you would use a proper Gaussian Process library
    
    n_candidates = 1000
    best_candidate = nothing
    best_acquisition = -Inf
    
    # Generate random candidates
    for _ in 1:n_candidates
        candidate = [
            rand() * (bounds[2] - bounds[1]) + bounds[1]
            for bounds in param_ranges
        ]
        
        # Calculate acquisition value (simplified)
        if acquisition_function == :ei
            # Expected Improvement (simplified)
            acquisition = calculate_expected_improvement(
                candidate,
                observed_params,
                observed_scores
            )
        elseif acquisition_function == :ucb
            # Upper Confidence Bound (simplified)
            acquisition = calculate_upper_confidence_bound(
                candidate,
                observed_params,
                observed_scores
            )
        else
            error("Unknown acquisition function: $acquisition_function")
        end
        
        if acquisition > best_acquisition
            best_acquisition = acquisition
            best_candidate = candidate
        end
    end
    
    return best_candidate
end

# Simplified Expected Improvement calculation
function calculate_expected_improvement(
    candidate::Vector{Float64},
    observed_params::Vector{Vector{Float64}},
    observed_scores::Vector{Float64}
)
    if isempty(observed_scores)
        return 0.0
    end
    
    # Find nearest neighbor (simplified approach)
    min_distance = Inf
    nearest_score = 0.0
    
    for (params, score) in zip(observed_params, observed_scores)
        distance = sqrt(sum((candidate .- params).^2))
        if distance < min_distance
            min_distance = distance
            nearest_score = score
        end
    end
    
    # Simple exploration bonus based on distance
    exploration_bonus = min_distance / 10.0
    
    # Expected improvement (simplified)
    current_best = maximum(observed_scores)
    expected_improvement = max(0, nearest_score - current_best) + exploration_bonus
    
    return expected_improvement
end

# Simplified Upper Confidence Bound calculation
function calculate_upper_confidence_bound(
    candidate::Vector{Float64},
    observed_params::Vector{Vector{Float64}},
    observed_scores::Vector{Float64},
    beta::Float64=2.0
)
    if isempty(observed_scores)
        return 0.0
    end
    
    # Find nearest neighbors
    distances = [sqrt(sum((candidate .- params).^2)) for params in observed_params]
    
    # Weighted average based on distances (simplified GP mean)
    weights = exp.(-distances)
    weights ./= sum(weights)
    mean_prediction = sum(weights .* observed_scores)
    
    # Uncertainty based on distance to nearest point (simplified GP variance)
    min_distance = minimum(distances)
    uncertainty = min_distance / 10.0
    
    # Upper confidence bound
    ucb = mean_prediction + beta * uncertainty
    
    return ucb
end

# Helper function to update best parameters
function update_best_params!(
    params::Dict{Symbol,Any},
    score::Float64,
    cv_scores::Vector{Float64},
    best_params::Dict{Symbol,Any},
    best_score::Float64,
    best_cv_scores::Vector{Float64},
    optimization_history::Vector{Dict{Symbol,Any}},
    all_results::DataFrame
)
    # Update history
    push!(optimization_history, Dict(
        :params => params,
        :score => score,
        :cv_scores => cv_scores,
        :timestamp => now()
    ))
    
    # Update best if improved
    if score > best_score
        empty!(best_params)
        merge!(best_params, params)
        best_score = score
        empty!(best_cv_scores)
        append!(best_cv_scores, cv_scores)
    end
    
    # Add to results DataFrame
    result_row = DataFrame(
        score = score,
        cv_mean = mean(cv_scores),
        cv_std = std(cv_scores)
    )
    
    for (key, value) in params
        result_row[!, key] = [value]
    end
    
    append!(all_results, result_row)
    
    return best_score
end

# Get best parameters from optimization result
function get_best_params(result::OptimizationResult)
    return result.best_params
end

# Save optimization results to file
function save_optimization_results(result::OptimizationResult, filepath::String)
    results_dict = Dict(
        "best_params" => result.best_params,
        "best_score" => result.best_score,
        "cv_scores" => result.cross_validation_scores,
        "training_time" => result.training_time,
        "optimization_history" => result.optimization_history
    )
    
    open(filepath, "w") do io
        JSON3.write(io, results_dict)
    end
    
    Logger.log_info("Optimization results saved to $filepath")
end

# Load optimization results from file
function load_optimization_results(filepath::String)
    results_dict = JSON3.read(read(filepath, String), Dict{String,Any})
    
    return OptimizationResult(
        Dict(Symbol(k) => v for (k, v) in results_dict["best_params"]),
        results_dict["best_score"],
        DataFrame(),  # All results not saved for space
        results_dict["optimization_history"],
        results_dict["cv_scores"],
        results_dict["training_time"]
    )
end

end # module HyperOpt