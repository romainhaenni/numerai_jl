module HyperOpt

using ..Logger
using ..Models
using ..Metrics
using DataFrames
using Statistics: mean, std, cor
using Random
using Distributed
using ProgressMeter
using JSON3
using Dates: now
using LinearAlgebra: dot, cholesky, Symmetric, I, norm
using Distributions: Normal, cdf, pdf

export HyperOptConfig, GridSearchOptimizer, RandomSearchOptimizer, BayesianOptimizer,
       optimize_hyperparameters, evaluate_params, get_best_params,
       create_param_grid, create_param_distributions, OptimizationResult,
       calculate_expected_improvement, calculate_upper_confidence_bound

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
        if "era" in names(df)
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
        Logger.@log_error "Error evaluating parameters: $e"
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
            if haskey(val_data, target) && target in names(predictions)
                corr = cor(
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
            if haskey(val_data, target) && target in names(predictions)
                corr = cor(
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
            if haskey(val_data, target) && target in names(predictions)
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
            if haskey(val_data, target) && target in names(predictions)
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
    Logger.@log_info("Starting Grid Search with $n_combinations parameter combinations")
    
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
            best_score = update_best_params!(
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
            
            best_score = update_best_params!(
                params, score, cv_scores,
                best_params, best_score, best_cv_scores,
                optimization_history, all_results
            )
            
            next!(progress)
            
            if optimizer.config.verbose && length(optimization_history) % 10 == 0
                Logger.@log_info("Current best score: $best_score")
            end
        end
    end
    
    training_time = time() - start_time
    
    Logger.@log_info("Grid Search completed in $(round(training_time, digits=2)) seconds")
    Logger.@log_info("Best score: $best_score")
    Logger.@log_info("Best parameters: $best_params")
    
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
    
    Logger.@log_info("Starting Random Search with $(optimizer.n_iter) iterations")
    
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
            best_score = update_best_params!(
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
            
            best_score = update_best_params!(
                params, score, cv_scores,
                best_params, best_score, best_cv_scores,
                optimization_history, all_results
            )
            
            next!(progress)
            
            if optimizer.config.verbose && iter % 10 == 0
                Logger.@log_info("Iteration $iter/$optimizer.n_iter - Best score: $best_score")
            end
        end
    end
    
    training_time = time() - start_time
    
    Logger.@log_info("Random Search completed in $(round(training_time, digits=2)) seconds")
    Logger.@log_info("Best score: $best_score")
    Logger.@log_info("Best parameters: $best_params")
    
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
    
    Logger.@log_info("Starting Bayesian Optimization with $(optimizer.n_iter) iterations")
    
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
        
        best_score = update_best_params!(
            params, score, cv_scores,
            best_params, best_score, best_cv_scores,
            optimization_history, all_results
        )
        
        next!(progress)
        
        if optimizer.config.verbose
            Logger.@log_info("Initial sampling $i/$(optimizer.n_initial) - Score: $score")
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
        
        best_score = update_best_params!(
            params, score, cv_scores,
            best_params, best_score, best_cv_scores,
            optimization_history, all_results
        )
        
        next!(progress)
        
        if optimizer.config.verbose && iter % 5 == 0
            Logger.@log_info("Iteration $iter/$(optimizer.n_iter) - Best score: $best_score")
        end
    end
    
    training_time = time() - start_time
    
    Logger.@log_info("Bayesian Optimization completed in $(round(training_time, digits=2)) seconds")
    Logger.@log_info("Best score: $best_score")
    Logger.@log_info("Best parameters: $best_params")
    
    return OptimizationResult(
        best_params,
        best_score,
        all_results,
        optimization_history,
        best_cv_scores,
        training_time
    )
end

# Gaussian Process implementation for Bayesian optimization
struct SimpleGaussianProcess
    kernel_func::Function
    noise::Float64
    length_scale::Float64
end

function SimpleGaussianProcess(; noise=1e-6, length_scale=1.0)
    # RBF (Radial Basis Function) kernel
    kernel_func = (x1, x2, l) -> exp(-0.5 * sum(((x1 .- x2) ./ l).^2))
    return SimpleGaussianProcess(kernel_func, noise, length_scale)
end

# Compute kernel matrix
function compute_kernel_matrix(gp::SimpleGaussianProcess, X::Vector{Vector{Float64}})
    n = length(X)
    K = zeros(n, n)
    for i in 1:n
        for j in 1:n
            K[i, j] = gp.kernel_func(X[i], X[j], gp.length_scale)
        end
        K[i, i] += gp.noise  # Add noise to diagonal
    end
    return K
end

# GP prediction with proper mean and variance
function gp_predict(gp::SimpleGaussianProcess, X_train::Vector{Vector{Float64}}, 
                   y_train::Vector{Float64}, X_test::Vector{Float64})
    if isempty(X_train)
        return 0.0, 1.0
    end
    
    # Compute kernel matrices
    K = compute_kernel_matrix(gp, X_train)
    k_star = [gp.kernel_func(X_test, x_train, gp.length_scale) for x_train in X_train]
    k_star_star = gp.kernel_func(X_test, X_test, gp.length_scale) + gp.noise
    
    # Compute mean and variance using Cholesky decomposition for numerical stability
    try
        L = cholesky(Symmetric(K)).L
        alpha = L' \ (L \ y_train)
        mean = dot(k_star, alpha)
        
        v = L \ k_star
        variance = k_star_star - dot(v, v)
        variance = max(variance, 1e-6)  # Ensure positive variance
        
        return mean, variance
    catch e
        # Fallback to simple inverse if Cholesky fails
        K_inv = inv(K + I * 1e-4)  # Add regularization
        mean = dot(k_star, K_inv * y_train)
        variance = k_star_star - dot(k_star, K_inv * k_star)
        variance = max(variance, 1e-6)
        return mean, variance
    end
end

# Select next point using acquisition function with proper GP
function select_next_point(
    observed_params::Vector{Vector{Float64}},
    observed_scores::Vector{Float64},
    param_ranges::Vector{Tuple{Float64,Float64}},
    acquisition_function::Symbol
)
    # Initialize Gaussian Process
    gp = SimpleGaussianProcess(noise=1e-6, length_scale=1.0)
    
    # Normalize parameters to [0, 1] for better GP performance
    normalized_params = normalize_params(observed_params, param_ranges)
    
    # Standardize scores for better GP performance
    mean_score = isempty(observed_scores) ? 0.0 : mean(observed_scores)
    std_score = isempty(observed_scores) ? 1.0 : std(observed_scores)
    std_score = std_score == 0 ? 1.0 : std_score
    normalized_scores = (observed_scores .- mean_score) ./ std_score
    
    n_candidates = 2000  # Increased for better optimization
    best_candidate = nothing
    best_acquisition = -Inf
    
    # Latin Hypercube Sampling for better coverage
    candidates = generate_lhs_samples(n_candidates, param_ranges)
    
    for candidate in candidates
        # Normalize candidate
        norm_candidate = normalize_param(candidate, param_ranges)
        
        # Get GP predictions
        mean_pred, var_pred = gp_predict(gp, normalized_params, normalized_scores, norm_candidate)
        
        # Denormalize predictions
        mean_pred = mean_pred * std_score + mean_score
        var_pred = var_pred * std_score^2
        
        # Calculate acquisition value
        if acquisition_function == :ei
            acquisition = calculate_expected_improvement_gp(
                mean_pred, sqrt(var_pred),
                observed_scores
            )
        elseif acquisition_function == :ucb
            acquisition = calculate_upper_confidence_bound_gp(
                mean_pred, sqrt(var_pred),
                beta=2.0
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

# Latin Hypercube Sampling for better space exploration
function generate_lhs_samples(n_samples::Int, param_ranges::Vector{Tuple{Float64,Float64}})
    n_dims = length(param_ranges)
    samples = Vector{Vector{Float64}}()
    
    # Create Latin Hypercube grid
    for i in 1:n_samples
        sample = Float64[]
        for (low, high) in param_ranges
            # Stratified sampling within each dimension
            val = (i - 1 + rand()) / n_samples
            push!(sample, low + val * (high - low))
        end
        push!(samples, sample)
    end
    
    # Shuffle within each dimension for better randomization
    for dim in 1:n_dims
        perm = randperm(n_samples)
        for i in 1:n_samples
            samples[i][dim], samples[perm[i]][dim] = samples[perm[i]][dim], samples[i][dim]
        end
    end
    
    return samples
end

# Normalize parameters to [0, 1] range
function normalize_params(params::Vector{Vector{Float64}}, ranges::Vector{Tuple{Float64,Float64}})
    return [normalize_param(p, ranges) for p in params]
end

function normalize_param(param::Vector{Float64}, ranges::Vector{Tuple{Float64,Float64}})
    return [(p - r[1]) / (r[2] - r[1]) for (p, r) in zip(param, ranges)]
end

# Expected Improvement with proper Gaussian Process
function calculate_expected_improvement_gp(
    mean::Float64,
    std::Float64,
    observed_scores::Vector{Float64}
)
    if isempty(observed_scores) || std < 1e-9
        return 0.0
    end
    
    current_best = maximum(observed_scores)
    z = (mean - current_best) / std
    
    # Use the cumulative distribution function (CDF) and probability density function (PDF)
    # of the standard normal distribution
    dist = Normal(0, 1)
    ei = std * (z * cdf(dist, z) + pdf(dist, z))
    
    return ei
end

# Upper Confidence Bound with proper Gaussian Process
function calculate_upper_confidence_bound_gp(
    mean::Float64,
    std::Float64;
    beta::Float64=2.0
)
    # UCB = mean + beta * std
    return mean + beta * std
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
    # Find previous best score from history (excluding the current entry we just added)
    previous_best_score = length(optimization_history) <= 1 ? -Inf : maximum(h[:score] for h in optimization_history[1:end-1])
    
    if score > previous_best_score
        empty!(best_params)
        merge!(best_params, params)
        previous_best_score = score
        empty!(best_cv_scores)
        append!(best_cv_scores, cv_scores)
    end
    
    # Return the actual current best score (the one we should be tracking)
    current_best_score = length(optimization_history) == 1 ? score : max(previous_best_score, score)
    
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
    
    return current_best_score
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
    
    Logger.@log_info("Optimization results saved to $filepath")
end

# Load optimization results from file
function load_optimization_results(filepath::String)
    results_dict = JSON3.read(read(filepath, String), Dict{String,Any})
    
    # Convert string keys back to symbols in history
    history = Vector{Dict{Symbol,Any}}()
    for hist_item in results_dict["optimization_history"]
        hist_dict = Dict{Symbol,Any}()
        for (k, v) in hist_item
            if k == "params" && v isa Dict
                # Convert params dict keys to symbols
                hist_dict[Symbol(k)] = Dict(Symbol(pk) => pv for (pk, pv) in v)
            else
                hist_dict[Symbol(k)] = v
            end
        end
        push!(history, hist_dict)
    end
    
    return OptimizationResult(
        Dict(Symbol(k) => v for (k, v) in results_dict["best_params"]),
        results_dict["best_score"],
        DataFrame(),  # All results not saved for space
        history,
        results_dict["cv_scores"],
        results_dict["training_time"]
    )
end

# Wrapper functions for test compatibility - these provide the expected interface
function calculate_expected_improvement(
    candidate::Vector{Float64},
    observed_params::Vector{Vector{Float64}},
    observed_scores::Vector{Float64}
)
    # Initialize GP for prediction
    gp = SimpleGaussianProcess(noise=1e-6, length_scale=1.0)
    
    # Standardize scores
    if isempty(observed_scores)
        return 0.0
    end
    
    mean_score = mean(observed_scores)
    std_score = std(observed_scores)
    std_score = std_score == 0 ? 1.0 : std_score
    normalized_scores = (observed_scores .- mean_score) ./ std_score
    
    # Get GP predictions
    mean_pred, var_pred = gp_predict(gp, observed_params, normalized_scores, candidate)
    
    # Denormalize predictions
    mean_pred = mean_pred * std_score + mean_score
    var_pred = var_pred * std_score^2
    
    # Calculate Expected Improvement
    return calculate_expected_improvement_gp(mean_pred, sqrt(var_pred), observed_scores)
end

function calculate_upper_confidence_bound(
    candidate::Vector{Float64},
    observed_params::Vector{Vector{Float64}},
    observed_scores::Vector{Float64};
    beta::Float64 = 2.0
)
    # Initialize GP for prediction
    gp = SimpleGaussianProcess(noise=1e-6, length_scale=1.0)
    
    # Standardize scores
    if isempty(observed_scores)
        return 0.0
    end
    
    mean_score = mean(observed_scores)
    std_score = std(observed_scores)
    std_score = std_score == 0 ? 1.0 : std_score
    normalized_scores = (observed_scores .- mean_score) ./ std_score
    
    # Get GP predictions
    mean_pred, var_pred = gp_predict(gp, observed_params, normalized_scores, candidate)
    
    # Denormalize predictions
    mean_pred = mean_pred * std_score + mean_score
    var_pred = var_pred * std_score^2
    
    # Calculate Upper Confidence Bound
    return calculate_upper_confidence_bound_gp(mean_pred, sqrt(var_pred), beta=beta)
end

end # module HyperOpt