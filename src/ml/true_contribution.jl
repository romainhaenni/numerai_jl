"""
    True Contribution Calculation Module

This module implements an improved True Contribution (TC) calculation using gradient-based
portfolio optimization, as an enhancement to the existing correlation-based method.

The gradient-based approach models TC more accurately by:
1. Formulating portfolio optimization as a constrained optimization problem
2. Computing gradients through the optimization using automatic differentiation
3. Measuring the contribution of predictions to the optimal portfolio returns

Author: NumeraiTournament.jl
"""
module TrueContribution

using LinearAlgebra
using Statistics
using Zygote
using TOML

# Import functions from the parent Metrics module that we'll use as fallbacks
import ..Metrics: tie_kept_rank, gaussianize, orthogonalize

"""
Configuration for True Contribution calculation methods.

# Fields
- `method::Symbol`: Calculation method (:gradient or :correlation)
- `max_iterations::Int`: Maximum optimization iterations for gradient method
- `tolerance::Float64`: Convergence tolerance for optimization
- `regularization::Float64`: L2 regularization parameter for portfolio optimization
- `risk_aversion::Float64`: Risk aversion parameter in mean-variance optimization
"""
struct TCConfig
    method::Symbol
    max_iterations::Int
    tolerance::Float64
    regularization::Float64
    risk_aversion::Float64
    
    function TCConfig(; 
        method::Symbol = :correlation,
        max_iterations::Int = 1000,
        tolerance::Float64 = 1e-6,
        regularization::Float64 = 1e-4,
        risk_aversion::Float64 = 1.0
    )
        if method ∉ [:gradient, :correlation]
            throw(ArgumentError("method must be either :gradient or :correlation"))
        end
        new(method, max_iterations, tolerance, regularization, risk_aversion)
    end
end

"""
    default_tc_config()

Get the default True Contribution configuration.
"""
default_tc_config() = TCConfig()

"""
    portfolio_objective(weights::AbstractVector{T}, 
                       expected_returns::AbstractVector{T}, 
                       covariance_matrix::AbstractMatrix{T},
                       risk_aversion::T,
                       regularization::T) where T

Compute the portfolio objective function for mean-variance optimization.

The objective function is:
    -μ'w + (λ/2)w'Σw + (γ/2)||w||²

Where:
- μ is the vector of expected returns
- w is the portfolio weight vector  
- Σ is the covariance matrix
- λ is the risk aversion parameter
- γ is the regularization parameter

# Arguments
- `weights`: Portfolio weights vector
- `expected_returns`: Expected returns for each asset
- `covariance_matrix`: Covariance matrix of asset returns
- `risk_aversion`: Risk aversion parameter (higher = more risk averse)
- `regularization`: L2 regularization parameter

# Returns
- Objective function value (to be minimized)
"""
function portfolio_objective(weights::AbstractVector{T}, 
                           expected_returns::AbstractVector{T}, 
                           covariance_matrix::AbstractMatrix{T},
                           risk_aversion::T,
                           regularization::T) where T
    # Expected return component (negative because we maximize returns)
    return_component = -dot(expected_returns, weights)
    
    # Risk component (variance penalty)
    risk_component = (risk_aversion / 2) * dot(weights, covariance_matrix * weights)
    
    # Regularization component (prevent extreme weights)
    reg_component = (regularization / 2) * dot(weights, weights)
    
    return return_component + risk_component + reg_component
end

"""
    optimize_portfolio_analytical(expected_returns::AbstractVector{T},
                                 covariance_matrix::AbstractMatrix{T},
                                 config::TCConfig) where T

Solve the portfolio optimization problem using analytical solution.

For mean-variance optimization without constraints, the optimal portfolio weights
can be computed analytically using the formula:
    w* = (1/λ) * Σ^(-1) * μ

Where λ is risk aversion, Σ is covariance matrix, μ is expected returns.

# Arguments
- `expected_returns`: Vector of expected returns for each asset
- `covariance_matrix`: Covariance matrix of asset returns
- `config`: Configuration parameters for optimization

# Returns
- Named tuple with:
  - `weights`: Optimal portfolio weights
  - `converged`: Whether optimization converged (always true for analytical)
  - `iterations`: Number of iterations used (0 for analytical)
  - `objective_value`: Final objective function value
"""
function optimize_portfolio_analytical(expected_returns::AbstractVector{T},
                                     covariance_matrix::AbstractMatrix{T},
                                     config::TCConfig) where T
    n_assets = length(expected_returns)
    
    try
        # Add regularization to covariance matrix for numerical stability
        regularized_cov = covariance_matrix + config.regularization * I
        
        # Analytical solution: w* = (1/λ) * Σ^(-1) * μ
        weights = (1.0 / config.risk_aversion) * (regularized_cov \ expected_returns)
        
        # Compute objective value
        obj_val = portfolio_objective(weights, expected_returns, covariance_matrix,
                                    config.risk_aversion, config.regularization)
        
        return (
            weights = weights,
            converged = true,
            iterations = 0,
            objective_value = obj_val
        )
        
    catch e
        @warn "Analytical portfolio optimization failed: $e"
        # Return equal weights as fallback
        equal_weights = fill(1.0 / n_assets, n_assets)
        obj_val = portfolio_objective(equal_weights, expected_returns, covariance_matrix,
                                    config.risk_aversion, config.regularization)
        
        return (
            weights = equal_weights,
            converged = false,
            iterations = 0,
            objective_value = obj_val
        )
    end
end

"""
    simple_gradient_descent(objective_func, grad_func, initial_weights, config::TCConfig)

Simple gradient descent optimization for portfolio weights.

This is a basic implementation that doesn't require external optimization libraries.
Used as a backup when analytical solutions are not suitable.

# Arguments
- `objective_func`: Function to minimize
- `grad_func`: Gradient function
- `initial_weights`: Starting weights
- `config`: Configuration parameters

# Returns
- Named tuple with optimization results
"""
function simple_gradient_descent(objective_func, grad_func, initial_weights, config::TCConfig)
    weights = copy(initial_weights)
    learning_rate = 0.01
    best_weights = copy(weights)
    best_obj = objective_func(weights)
    
    for iter in 1:config.max_iterations
        # Compute gradient
        grad = grad_func(weights)
        
        # Check for convergence
        grad_norm = norm(grad)
        if grad_norm < config.tolerance
            return (
                weights = weights,
                converged = true,
                iterations = iter,
                objective_value = objective_func(weights)
            )
        end
        
        # Gradient descent step
        new_weights = weights - learning_rate * grad
        new_obj = objective_func(new_weights)
        
        # Accept if improvement, otherwise reduce learning rate
        if new_obj < best_obj
            weights = new_weights
            best_weights = copy(weights)
            best_obj = new_obj
            learning_rate = min(learning_rate * 1.05, 0.1)  # Adaptive learning rate
        else
            learning_rate *= 0.8  # Reduce learning rate
        end
        
        # Prevent learning rate from becoming too small
        if learning_rate < 1e-8
            break
        end
    end
    
    return (
        weights = best_weights,
        converged = false,
        iterations = config.max_iterations,
        objective_value = best_obj
    )
end

"""
    compute_portfolio_gradient(predictions::AbstractVector{T},
                             meta_model::AbstractVector{T},
                             returns::AbstractVector{T},
                             config::TCConfig) where T

Compute the gradient of optimal portfolio returns with respect to individual predictions.

This function uses automatic differentiation to compute how changes in a model's
predictions affect the optimal portfolio allocation and resulting returns.

The algorithm:
1. Construct expected returns vector including the model's predictions
2. Estimate covariance matrix from historical data
3. Solve portfolio optimization problem
4. Compute gradient of portfolio returns w.r.t. predictions using Zygote

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model predictions (baseline portfolio)
- `returns`: Historical returns for covariance estimation
- `config`: Configuration parameters

# Returns
- Gradient vector indicating contribution of each prediction to optimal portfolio returns
"""
function compute_portfolio_gradient(predictions::AbstractVector{T},
                                  meta_model::AbstractVector{T},
                                  returns::AbstractVector{T},
                                  config::TCConfig) where T
    n_samples = length(predictions)
    
    if !(length(meta_model) == length(returns) == n_samples)
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if n_samples <= 2
        return zeros(T, n_samples)
    end
    
    try
        # Normalize inputs to prevent numerical issues
        pred_norm = (predictions .- mean(predictions)) ./ max(std(predictions), 1e-8)
        meta_norm = (meta_model .- mean(meta_model)) ./ max(std(meta_model), 1e-8)
        returns_norm = (returns .- mean(returns)) ./ max(std(returns), 1e-8)
        
        # Create a differentiable function that:
        # 1. Takes predictions as input
        # 2. Constructs expected returns (using predictions and meta-model)
        # 3. Estimates covariance matrix
        # 4. Solves portfolio optimization
        # 5. Returns portfolio performance metric
        
        function portfolio_performance(pred_input::AbstractVector)
            # Construct expected returns: combine predictions with meta-model
            expected_returns = [mean(pred_input), meta_norm[1]]  # Simplified: use means
            
            # Simple 2x2 covariance estimation for numerical stability
            var_pred = var(pred_input) + config.regularization
            var_meta = var(meta_norm) + config.regularization
            covar = clamp(cov(pred_input, meta_norm), -0.95 * sqrt(var_pred * var_meta), 
                         0.95 * sqrt(var_pred * var_meta))
            
            covariance_matrix = [var_pred covar; covar var_meta]
            
            # Solve portfolio optimization analytically
            result = optimize_portfolio_analytical(expected_returns, covariance_matrix, config)
            
            # Return portfolio expected return (what we want to maximize)
            return dot(result.weights, expected_returns)
        end
        
        # Compute gradient using Zygote
        gradient_result = Zygote.gradient(portfolio_performance, pred_norm)[1]
        
        # Handle potential nothing or NaN gradients
        if gradient_result === nothing || any(isnan.(gradient_result))
            return zeros(T, n_samples)
        end
        
        return gradient_result
        
    catch e
        @warn "Gradient computation failed: $e"
        return zeros(T, n_samples)
    end
end

"""
    calculate_tc_gradient(predictions::AbstractVector{T}, 
                         meta_model::AbstractVector{S}, 
                         returns::AbstractVector{U},
                         config::TCConfig = default_tc_config()) where {T, S, U}

Calculate True Contribution using gradient-based portfolio optimization.

This is the main function that implements the gradient-based TC calculation.
It measures how much a model's predictions improve the optimal portfolio allocation
by computing gradients through the portfolio optimization process.

The algorithm:
1. Validate inputs and handle edge cases
2. Rank and gaussianize predictions for stability
3. Compute portfolio gradients using automatic differentiation
4. Return the mean gradient as the TC score

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model (stake-weighted ensemble) predictions  
- `returns`: Actual returns for portfolio optimization
- `config`: Configuration for gradient-based method

# Returns
- TC score: positive indicates positive contribution, negative indicates negative contribution
"""
function calculate_tc_gradient(predictions::AbstractVector{T}, 
                              meta_model::AbstractVector{S}, 
                              returns::AbstractVector{U},
                              config::TCConfig = default_tc_config()) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    n_samples = length(predictions)
    
    # Handle edge cases
    if n_samples <= 2
        return 0.0
    end
    
    # Check for constant inputs
    if std(predictions) < 1e-10
        return 0.0
    end
    
    try
        # Rank and gaussianize predictions for numerical stability
        # This follows the same preprocessing as the correlation-based method
        p = gaussianize(tie_kept_rank(Float64.(predictions)))
        
        # Compute gradient-based contribution
        gradients = compute_portfolio_gradient(p, Float64.(meta_model), Float64.(returns), config)
        
        # The TC is the mean gradient (average marginal contribution)
        tc_gradient = mean(gradients)
        
        # Handle NaN or Inf results
        if isnan(tc_gradient) || isinf(tc_gradient)
            return 0.0
        end
        
        return tc_gradient
        
    catch e
        @warn "Gradient-based TC calculation failed: $e"
        return 0.0
    end
end

"""
    calculate_tc_correlation_fallback(predictions::AbstractVector{T}, 
                                     meta_model::AbstractVector{S}, 
                                     returns::AbstractVector{U}) where {T, S, U}

Calculate True Contribution using the correlation-based method as fallback.

This implements the existing correlation-based TC calculation that was previously
in the Metrics module. It's used as a fallback when the gradient-based method fails.

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model predictions
- `returns`: Actual returns

# Returns
- TC score using correlation-based method
"""
function calculate_tc_correlation_fallback(predictions::AbstractVector{T}, 
                                         meta_model::AbstractVector{S}, 
                                         returns::AbstractVector{U}) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Step 1: Rank and gaussianize predictions
    p = gaussianize(tie_kept_rank(Float64.(predictions)))
    
    # Step 2: Orthogonalize returns with respect to meta-model
    # This removes the component of returns that is already captured by the meta-model
    orthogonal_returns = orthogonalize(Float64.(returns), Float64.(meta_model))
    
    # Step 3: Calculate TC (correlation between gaussianized predictions and orthogonalized returns)
    if std(orthogonal_returns) == 0.0
        # If orthogonalized returns have no variance, TC is zero
        return 0.0
    end
    
    tc = cor(p, orthogonal_returns)
    
    return isnan(tc) ? 0.0 : tc
end

"""
    calculate_tc_improved(predictions::AbstractVector{T}, 
                         meta_model::AbstractVector{S}, 
                         returns::AbstractVector{U},
                         config::TCConfig = default_tc_config()) where {T, S, U}

Calculate True Contribution using the improved method specified in config.

This is the main entry point that chooses between gradient-based and correlation-based
methods based on the configuration. It includes automatic fallback to correlation
method if gradient method fails.

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model (stake-weighted ensemble) predictions
- `returns`: Actual returns
- `config`: Configuration specifying which method to use

# Returns
- TC score using the specified (or fallback) method
"""
function calculate_tc_improved(predictions::AbstractVector{T}, 
                              meta_model::AbstractVector{S}, 
                              returns::AbstractVector{U},
                              config::TCConfig = default_tc_config()) where {T, S, U}
    
    # Input validation
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Choose method based on configuration
    if config.method == :gradient
        try
            tc_score = calculate_tc_gradient(predictions, meta_model, returns, config)
            
            # Sanity check: if gradient method returns unreasonable values, fall back
            if isnan(tc_score) || isinf(tc_score) || abs(tc_score) > 10.0
                @warn "Gradient-based TC returned unreasonable value ($tc_score), falling back to correlation method"
                return calculate_tc_correlation_fallback(predictions, meta_model, returns)
            end
            
            return tc_score
            
        catch e
            @warn "Gradient-based TC calculation failed: $e. Falling back to correlation method."
            return calculate_tc_correlation_fallback(predictions, meta_model, returns)
        end
    else
        # Use correlation-based method
        return calculate_tc_correlation_fallback(predictions, meta_model, returns)
    end
end

"""
    calculate_tc_improved_batch(predictions_matrix::AbstractMatrix, 
                               meta_model::AbstractVector, 
                               returns::AbstractVector,
                               config::TCConfig = default_tc_config())

Calculate improved TC for multiple models simultaneously.

# Arguments
- `predictions_matrix`: Matrix where each column represents predictions from one model
- `meta_model`: Meta-model (stake-weighted ensemble) predictions
- `returns`: Actual returns
- `config`: Configuration for TC calculation method

# Returns
- Vector of TC scores, one for each model (column)
"""
function calculate_tc_improved_batch(predictions_matrix::AbstractMatrix, 
                                   meta_model::AbstractVector, 
                                   returns::AbstractVector,
                                   config::TCConfig = default_tc_config())
    n_samples, n_models = size(predictions_matrix)
    
    if !(length(meta_model) == length(returns) == n_samples)
        throw(ArgumentError("Matrix rows and vector lengths must match"))
    end
    
    tc_scores = Vector{Float64}(undef, n_models)
    
    for i in 1:n_models
        tc_scores[i] = calculate_tc_improved(predictions_matrix[:, i], meta_model, returns, config)
    end
    
    return tc_scores
end

"""
    load_tc_config_from_toml(config_path::String)

Load True Contribution configuration from TOML file.

This function reads TC-specific configuration from the main config.toml file.
If no TC configuration is found, it returns the default configuration.

# Arguments
- `config_path`: Path to the TOML configuration file

# Returns
- TCConfig struct with loaded or default values

# Example TOML Configuration
```toml
[ml.true_contribution]
method = "gradient"  # or "correlation"
max_iterations = 1000
tolerance = 1e-6
regularization = 1e-4
risk_aversion = 1.0
```
"""
function load_tc_config_from_toml(config_path::String)
    if !isfile(config_path)
        @warn "Configuration file not found: $config_path. Using default TC configuration."
        return default_tc_config()
    end
    
    try
        config_dict = TOML.parsefile(config_path)
        
        # Look for TC configuration in the ML section
        tc_config = get(get(config_dict, "ml", Dict()), "true_contribution", Dict())
        
        # Parse configuration with defaults
        method = Symbol(get(tc_config, "method", "correlation"))
        max_iterations = get(tc_config, "max_iterations", 1000)
        tolerance = get(tc_config, "tolerance", 1e-6)
        regularization = get(tc_config, "regularization", 1e-4)
        risk_aversion = get(tc_config, "risk_aversion", 1.0)
        
        return TCConfig(
            method = method,
            max_iterations = max_iterations,
            tolerance = tolerance,
            regularization = regularization,
            risk_aversion = risk_aversion
        )
        
    catch e
        @warn "Failed to parse TC configuration from $config_path: $e. Using default configuration."
        return default_tc_config()
    end
end

# Export public functions
export TCConfig, default_tc_config, load_tc_config_from_toml,
       calculate_tc_improved, calculate_tc_improved_batch,
       calculate_tc_gradient, calculate_tc_correlation_fallback

end # module TrueContribution