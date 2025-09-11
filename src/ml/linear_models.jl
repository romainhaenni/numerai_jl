module LinearModels

using GLM
using DataFrames
using Statistics
using LinearAlgebra
using StatsBase
using Logging
using BSON

# Import the abstract type from Models module
using ..Models: NumeraiModel

export RidgeModel, LassoModel, ElasticNetModel, train!, predict, save_model, load_model!, feature_importance

mutable struct RidgeModel <: NumeraiModel
    model::Any  # GLM model
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

mutable struct LassoModel <: NumeraiModel
    model::Any  # GLM model
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

mutable struct ElasticNetModel <: NumeraiModel
    model::Any  # GLM model
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

"""
    RidgeModel(name::String="ridge_default"; alpha::Float64=1.0, fit_intercept::Bool=true)

Create a Ridge regression model with L2 regularization.
"""
function RidgeModel(name::String="ridge_default"; 
                   alpha::Float64=1.0,
                   fit_intercept::Bool=true,
                   max_iter::Int=1000,
                   tol::Float64=1e-4,
                   gpu_enabled::Bool=false)
    
    params = Dict{String, Any}(
        "alpha" => alpha,
        "fit_intercept" => fit_intercept,
        "max_iter" => max_iter,
        "tol" => tol
    )
    
    @info "Ridge model configured" name=name alpha=alpha
    
    return RidgeModel(nothing, params, name, false)  # Linear models don't use GPU
end

"""
    LassoModel(name::String="lasso_default"; alpha::Float64=1.0, fit_intercept::Bool=true)

Create a Lasso regression model with L1 regularization.
"""
function LassoModel(name::String="lasso_default"; 
                   alpha::Float64=1.0,
                   fit_intercept::Bool=true,
                   max_iter::Int=1000,
                   tol::Float64=1e-4,
                   gpu_enabled::Bool=false)
    
    params = Dict{String, Any}(
        "alpha" => alpha,
        "fit_intercept" => fit_intercept,
        "max_iter" => max_iter,
        "tol" => tol
    )
    
    @info "Lasso model configured" name=name alpha=alpha
    
    return LassoModel(nothing, params, name, false)  # Linear models don't use GPU
end

"""
    ElasticNetModel(name::String="elasticnet_default"; alpha::Float64=1.0, l1_ratio::Float64=0.5)

Create an ElasticNet regression model with combined L1 and L2 regularization.
"""
function ElasticNetModel(name::String="elasticnet_default"; 
                        alpha::Float64=1.0,
                        l1_ratio::Float64=0.5,
                        fit_intercept::Bool=true,
                        max_iter::Int=1000,
                        tol::Float64=1e-4,
                        gpu_enabled::Bool=false)
    
    params = Dict{String, Any}(
        "alpha" => alpha,
        "l1_ratio" => l1_ratio,
        "fit_intercept" => fit_intercept,
        "max_iter" => max_iter,
        "tol" => tol
    )
    
    @info "ElasticNet model configured" name=name alpha=alpha l1_ratio=l1_ratio
    
    return ElasticNetModel(nothing, params, name, false)  # Linear models don't use GPU
end

# Helper function for Ridge regression using normal equations with regularization
function fit_ridge(X::Matrix{Float64}, y::Vector{Float64}, alpha::Float64, fit_intercept::Bool)
    n_samples, n_features = size(X)
    
    # Add intercept if needed
    if fit_intercept
        X_with_intercept = hcat(ones(n_samples), X)
    else
        X_with_intercept = X
    end
    
    # Ridge regression: (X'X + αI)β = X'y
    XtX = X_with_intercept' * X_with_intercept
    n_params = size(XtX, 1)
    
    # Add regularization to diagonal (except intercept if present)
    regularization = alpha * I(n_params)
    if fit_intercept
        regularization[1, 1] = 0  # Don't regularize intercept
    end
    
    # Solve for coefficients
    coefficients = (XtX + regularization) \ (X_with_intercept' * y)
    
    if fit_intercept
        intercept = coefficients[1]
        coef = coefficients[2:end]
    else
        intercept = 0.0
        coef = coefficients
    end
    
    return coef, intercept
end

# Helper function for coordinate descent (used for Lasso and ElasticNet)
function coordinate_descent(X::Matrix{Float64}, y::Vector{Float64}, alpha::Float64, 
                           l1_ratio::Float64, fit_intercept::Bool, max_iter::Int, tol::Float64)
    n_samples, n_features = size(X)
    
    # Initialize coefficients
    coef = zeros(n_features)
    intercept = fit_intercept ? mean(y) : 0.0
    
    # Center X and y if fitting intercept
    if fit_intercept
        X_centered = X .- mean(X, dims=1)
        y_centered = y .- mean(y)
    else
        X_centered = X
        y_centered = y
    end
    
    # Precompute column norms
    col_norms = vec(sum(X_centered.^2, dims=1))
    
    # Coordinate descent iterations
    for iter in 1:max_iter
        coef_old = copy(coef)
        
        # Update each coefficient
        for j in 1:n_features
            if col_norms[j] == 0
                continue
            end
            
            # Compute residual without j-th feature
            residual = y_centered - X_centered * coef + X_centered[:, j] * coef[j]
            
            # Compute gradient
            grad = -X_centered[:, j]' * residual / n_samples
            
            # Soft thresholding for Lasso/ElasticNet
            l1_penalty = alpha * l1_ratio
            l2_penalty = alpha * (1 - l1_ratio)
            
            if grad > l1_penalty
                coef[j] = -(grad - l1_penalty) / (col_norms[j] / n_samples + l2_penalty)
            elseif grad < -l1_penalty
                coef[j] = -(grad + l1_penalty) / (col_norms[j] / n_samples + l2_penalty)
            else
                coef[j] = 0.0
            end
        end
        
        # Check convergence
        if maximum(abs.(coef - coef_old)) < tol
            if iter % 100 == 0
                @info "Converged at iteration $iter"
            end
            break
        end
    end
    
    # Recompute intercept if needed
    if fit_intercept
        intercept = mean(y) - mean(X * coef)
    end
    
    return coef, intercept
end

function train!(model::RidgeModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false)
    
    # Check if multi-target
    is_multi_target = y_train isa Matrix
    n_targets = is_multi_target ? size(y_train, 2) : 1
    
    if verbose
        @info "Training Ridge model" name=model.name alpha=model.params["alpha"] multi_target=is_multi_target targets=n_targets
    end
    
    if is_multi_target
        # Train separate model for each target
        coefs = Matrix{Float64}(undef, size(X_train, 2), n_targets)
        intercepts = Vector{Float64}(undef, n_targets)
        
        for i in 1:n_targets
            coef, intercept = fit_ridge(X_train, y_train[:, i], model.params["alpha"], model.params["fit_intercept"])
            coefs[:, i] = coef
            intercepts[i] = intercept
        end
        
        # Store the model
        model.model = Dict(
            "coef" => coefs,
            "intercept" => intercepts,
            "n_features" => size(X_train, 2),
            "n_targets" => n_targets,
            "is_multi_target" => true
        )
    else
        # Single target
        coef, intercept = fit_ridge(X_train, y_train, model.params["alpha"], model.params["fit_intercept"])
        
        # Store the model
        model.model = Dict(
            "coef" => coef,
            "intercept" => intercept,
            "n_features" => size(X_train, 2),
            "n_targets" => 1,
            "is_multi_target" => false
        )
    end
    
    # Validate if validation set provided
    if X_val !== nothing && y_val !== nothing
        val_predictions = predict(model, X_val)
        if is_multi_target
            # Calculate correlation for each target
            val_scores = [cor(val_predictions[:, i], y_val[:, i]) for i in 1:n_targets]
            val_score = mean(val_scores)
            if verbose
                @info "Validation correlation" mean_score=val_score scores=val_scores
            end
        else
            val_score = cor(val_predictions, y_val)
            if verbose
                @info "Validation correlation" score=val_score
            end
        end
    end
    
    return model
end

function train!(model::LassoModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false)
    
    # Check if multi-target
    is_multi_target = y_train isa Matrix
    n_targets = is_multi_target ? size(y_train, 2) : 1
    
    if verbose
        @info "Training Lasso model" name=model.name alpha=model.params["alpha"] multi_target=is_multi_target targets=n_targets
    end
    
    if is_multi_target
        # Train separate model for each target
        coefs = Matrix{Float64}(undef, size(X_train, 2), n_targets)
        intercepts = Vector{Float64}(undef, n_targets)
        n_nonzeros = Vector{Int}(undef, n_targets)
        
        for i in 1:n_targets
            coef, intercept = coordinate_descent(X_train, y_train[:, i], model.params["alpha"], 1.0,
                                                model.params["fit_intercept"], model.params["max_iter"], 
                                                model.params["tol"])
            coefs[:, i] = coef
            intercepts[i] = intercept
            n_nonzeros[i] = sum(coef .!= 0)
        end
        
        # Store the model
        model.model = Dict(
            "coef" => coefs,
            "intercept" => intercepts,
            "n_features" => size(X_train, 2),
            "n_targets" => n_targets,
            "is_multi_target" => true,
            "n_nonzero" => n_nonzeros
        )
        
        if verbose
            @info "Lasso training complete" mean_n_nonzero_coef=mean(n_nonzeros) n_nonzero_per_target=n_nonzeros
        end
    else
        # Single target
        coef, intercept = coordinate_descent(X_train, y_train, model.params["alpha"], 1.0,
                                            model.params["fit_intercept"], model.params["max_iter"], 
                                            model.params["tol"])
        
        # Store the model
        model.model = Dict(
            "coef" => coef,
            "intercept" => intercept,
            "n_features" => size(X_train, 2),
            "n_targets" => 1,
            "is_multi_target" => false,
            "n_nonzero" => sum(coef .!= 0)
        )
        
        if verbose
            @info "Lasso training complete" n_nonzero_coef=model.model["n_nonzero"]
        end
    end
    
    # Validate if validation set provided
    if X_val !== nothing && y_val !== nothing
        val_predictions = predict(model, X_val)
        if is_multi_target
            # Calculate correlation for each target
            val_scores = [cor(val_predictions[:, i], y_val[:, i]) for i in 1:n_targets]
            val_score = mean(val_scores)
            if verbose
                @info "Validation correlation" mean_score=val_score scores=val_scores
            end
        else
            val_score = cor(val_predictions, y_val)
            if verbose
                @info "Validation correlation" score=val_score
            end
        end
    end
    
    return model
end

function train!(model::ElasticNetModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false)
    
    # Check if multi-target
    is_multi_target = y_train isa Matrix
    n_targets = is_multi_target ? size(y_train, 2) : 1
    
    if verbose
        @info "Training ElasticNet model" name=model.name alpha=model.params["alpha"] l1_ratio=model.params["l1_ratio"] multi_target=is_multi_target targets=n_targets
    end
    
    if is_multi_target
        # Train separate model for each target
        coefs = Matrix{Float64}(undef, size(X_train, 2), n_targets)
        intercepts = Vector{Float64}(undef, n_targets)
        n_nonzeros = Vector{Int}(undef, n_targets)
        
        for i in 1:n_targets
            coef, intercept = coordinate_descent(X_train, y_train[:, i], model.params["alpha"], model.params["l1_ratio"],
                                                model.params["fit_intercept"], model.params["max_iter"], 
                                                model.params["tol"])
            coefs[:, i] = coef
            intercepts[i] = intercept
            n_nonzeros[i] = sum(coef .!= 0)
        end
        
        # Store the model
        model.model = Dict(
            "coef" => coefs,
            "intercept" => intercepts,
            "n_features" => size(X_train, 2),
            "n_targets" => n_targets,
            "is_multi_target" => true,
            "n_nonzero" => n_nonzeros
        )
        
        if verbose
            @info "ElasticNet training complete" mean_n_nonzero_coef=mean(n_nonzeros) n_nonzero_per_target=n_nonzeros
        end
    else
        # Single target
        coef, intercept = coordinate_descent(X_train, y_train, model.params["alpha"], model.params["l1_ratio"],
                                            model.params["fit_intercept"], model.params["max_iter"], 
                                            model.params["tol"])
        
        # Store the model
        model.model = Dict(
            "coef" => coef,
            "intercept" => intercept,
            "n_features" => size(X_train, 2),
            "n_targets" => 1,
            "is_multi_target" => false,
            "n_nonzero" => sum(coef .!= 0)
        )
        
        if verbose
            @info "ElasticNet training complete" n_nonzero_coef=model.model["n_nonzero"]
        end
    end
    
    # Validate if validation set provided
    if X_val !== nothing && y_val !== nothing
        val_predictions = predict(model, X_val)
        if is_multi_target
            # Calculate correlation for each target
            val_scores = [cor(val_predictions[:, i], y_val[:, i]) for i in 1:n_targets]
            val_score = mean(val_scores)
            if verbose
                @info "Validation correlation" mean_score=val_score scores=val_scores
            end
        else
            val_score = cor(val_predictions, y_val)
            if verbose
                @info "Validation correlation" score=val_score
            end
        end
    end
    
    return model
end

# Prediction function for all linear models
function predict(model::Union{RidgeModel, LassoModel, ElasticNetModel}, X::Matrix{Float64})::Union{Vector{Float64}, Matrix{Float64}}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    is_multi_target = get(model.model, "is_multi_target", false)
    
    if is_multi_target
        # Multi-target prediction
        n_targets = model.model["n_targets"]
        predictions = Matrix{Float64}(undef, size(X, 1), n_targets)
        for i in 1:n_targets
            predictions[:, i] = X * model.model["coef"][:, i] .+ model.model["intercept"][i]
        end
        return predictions
    else
        # Single target prediction
        predictions = X * model.model["coef"] .+ model.model["intercept"]
        return predictions
    end
end

# Save/load functions for linear models
function save_model(model::Union{RidgeModel, LassoModel, ElasticNetModel}, filepath::String)
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Save as BSON file
    BSON.@save filepath model
    
    println("Linear model saved to $filepath")
end

function load_model!(model::Union{RidgeModel, LassoModel, ElasticNetModel}, filepath::String)
    loaded = BSON.load(filepath)
    
    # Copy the loaded model's fields
    model.model = loaded[:model].model
    model.params = loaded[:model].params
    
    return model
end

# Feature importance for linear models based on coefficient magnitudes
function feature_importance(model::Union{RidgeModel, LassoModel, ElasticNetModel})::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Get coefficients
    coef = model.model["coef"]
    
    # Use absolute values of coefficients as importance scores
    abs_coef = abs.(coef)
    
    # Normalize to sum to 1 (if there are any non-zero coefficients)
    total = sum(abs_coef)
    if total > 0
        abs_coef = abs_coef ./ total
    end
    
    # Create dictionary with feature names
    feature_dict = Dict{String, Float64}()
    for i in 1:length(abs_coef)
        feature_dict["feature_$(i)"] = abs_coef[i]
    end
    
    return feature_dict
end

end  # module LinearModels