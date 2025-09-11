module Ensemble

using Statistics
using Random
using ThreadsX
using ..Models
using ..Preprocessor: check_memory_before_allocation, safe_matrix_allocation

mutable struct ModelEnsemble
    models::Vector{<:Models.NumeraiModel}
    weights::Vector{Float64}
    name::String
    feature_indices::Union{Nothing, Vector{Vector{Int}}}  # For bagging: which features each model uses
end

function ModelEnsemble(models::Vector{<:Models.NumeraiModel}; 
                      weights::Union{Nothing, Vector{Float64}}=nothing,
                      name::String="ensemble",
                      feature_indices::Union{Nothing, Vector{Vector{Int}}}=nothing)
    n_models = length(models)
    
    if weights === nothing
        weights = fill(1.0 / n_models, n_models)
    else
        if length(weights) != n_models
            error("Number of weights must match number of models")
        end
        weights = weights ./ sum(weights)
    end
    
    return ModelEnsemble(models, weights, name, feature_indices)
end

function train_ensemble!(ensemble::ModelEnsemble, X_train::Matrix{Float64}, y_train::Vector{Float64};
                        X_val::Union{Nothing, Matrix{Float64}}=nothing,
                        y_val::Union{Nothing, Vector{Float64}}=nothing,
                        parallel::Bool=true,
                        verbose::Bool=false)
    
    if parallel && Threads.nthreads() > 1
        ThreadsX.foreach(ensemble.models) do model
            if verbose
                println("Training $(model.name)...")
            end
            Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
        end
    else
        for model in ensemble.models
            if verbose
                println("Training $(model.name)...")
            end
            Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
        end
    end
    
    return ensemble
end

# Multi-target overload
function train_ensemble!(ensemble::ModelEnsemble, X_train::Matrix{Float64}, y_train::Matrix{Float64};
                        X_val::Union{Nothing, Matrix{Float64}}=nothing,
                        y_val::Union{Nothing, Matrix{Float64}}=nothing,
                        parallel::Bool=true,
                        verbose::Bool=false)
    
    if parallel && Threads.nthreads() > 1
        ThreadsX.foreach(ensemble.models) do model
            if verbose
                println("Training $(model.name)...")
            end
            Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
        end
    else
        for model in ensemble.models
            if verbose
                println("Training $(model.name)...")
            end
            Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
        end
    end
    
    return ensemble
end

function predict_ensemble(ensemble::ModelEnsemble, X::Matrix{Float64}; 
                         return_individual::Bool=false)::Union{Vector{Float64}, Matrix{Float64}, Tuple{Union{Vector{Float64}, Matrix{Float64}}, Array{Float64}}}
    n_samples = size(X, 1)
    n_models = length(ensemble.models)
    
    # Get prediction from first model to determine output shape
    # Handle feature subsetting for bagged models
    X_first = if ensemble.feature_indices !== nothing && length(ensemble.feature_indices) >= 1
        X[:, ensemble.feature_indices[1]]
    else
        X
    end
    first_prediction = Models.predict(ensemble.models[1], X_first)
    is_multi_target = first_prediction isa Matrix
    n_targets = is_multi_target ? size(first_prediction, 2) : 1
    
    if is_multi_target
        # Multi-target case: 3D array (samples, targets, models)
        predictions_array = Array{Float64}(undef, n_samples, n_targets, n_models)
        predictions_array[:, :, 1] = first_prediction
        
        # Get predictions from remaining models
        ThreadsX.foreach(2:n_models) do i
            X_i = if ensemble.feature_indices !== nothing && length(ensemble.feature_indices) >= i
                X[:, ensemble.feature_indices[i]]
            else
                X
            end
            model_pred = Models.predict(ensemble.models[i], X_i)
            # Validate prediction dimensions
            if size(model_pred, 1) != n_samples
                error("Model $(i) returned $(size(model_pred, 1)) predictions, expected $(n_samples)")
            end
            if model_pred isa Matrix && size(model_pred, 2) != n_targets
                error("Model $(i) returned $(size(model_pred, 2)) targets, expected $(n_targets)")
            end
            predictions_array[:, :, i] = model_pred isa Matrix ? model_pred : reshape(model_pred, n_samples, 1)
        end
        
        # Weighted average across models for each target
        weighted_predictions = Matrix{Float64}(undef, n_samples, n_targets)
        for t in 1:n_targets
            target_predictions = predictions_array[:, t, :]
            weighted_predictions[:, t] = target_predictions * ensemble.weights
        end
        
        if return_individual
            return weighted_predictions, predictions_array
        else
            return weighted_predictions
        end
    else
        # Single target case: 2D matrix (samples, models)
        predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
        predictions_matrix[:, 1] = first_prediction
        
        ThreadsX.foreach(2:n_models) do i
            X_i = if ensemble.feature_indices !== nothing && length(ensemble.feature_indices) >= i
                X[:, ensemble.feature_indices[i]]
            else
                X
            end
            model_pred = Models.predict(ensemble.models[i], X_i)
            # Validate prediction dimensions
            if length(model_pred) != n_samples
                error("Model $(i) returned $(length(model_pred)) predictions, expected $(n_samples)")
            end
            predictions_matrix[:, i] = model_pred isa Vector ? model_pred : vec(model_pred)
        end
        
        weighted_predictions = predictions_matrix * ensemble.weights
        
        if return_individual
            return weighted_predictions, predictions_matrix
        else
            return weighted_predictions
        end
    end
end

function optimize_weights(ensemble::ModelEnsemble, X_val::Matrix{Float64}, y_val::Vector{Float64};
                         metric::Function=cor, n_iterations::Int=1000)::Vector{Float64}
    n_models = length(ensemble.models)
    n_samples = size(X_val, 1)
    
    # Check memory before allocation
    predictions_matrix = safe_matrix_allocation(n_samples, n_models)
    
    for (i, model) in enumerate(ensemble.models)
        model_pred = Models.predict(model, X_val)
        # Validate prediction dimensions
        if length(model_pred) != n_samples
            error("Model $(i) returned $(length(model_pred)) predictions, expected $(n_samples)")
        end
        predictions_matrix[:, i] = model_pred
    end
    
    best_weights = ensemble.weights
    best_score = metric(predictions_matrix * best_weights, y_val)
    
    for _ in 1:n_iterations
        trial_weights = rand(n_models)
        trial_weights = trial_weights ./ sum(trial_weights)
        
        trial_predictions = predictions_matrix * trial_weights
        trial_score = metric(trial_predictions, y_val)
        
        if trial_score > best_score
            best_score = trial_score
            best_weights = trial_weights
        end
    end
    
    return best_weights
end

# Multi-target overload for optimize_weights
function optimize_weights(ensemble::ModelEnsemble, X_val::Matrix{Float64}, y_val::Matrix{Float64};
                         metric::Function=cor, n_iterations::Int=1000)::Matrix{Float64}
    n_models = length(ensemble.models)
    n_samples = size(X_val, 1)
    n_targets = size(y_val, 2)
    
    # For multi-target, optimize weights independently for each target
    best_weights = safe_matrix_allocation(n_models, n_targets)
    
    for target_idx in 1:n_targets
        # Optimize weights for this specific target
        best_target_weights = ensemble.weights
        best_score = -Inf
        
        for _ in 1:n_iterations
            trial_weights = rand(n_models)
            trial_weights = trial_weights ./ sum(trial_weights)
            
            # Calculate weighted predictions for this target
            predictions_matrix = safe_matrix_allocation(n_samples, n_models)
            for (i, model) in enumerate(ensemble.models)
                model_pred = Models.predict(model, X_val)
                # Validate prediction dimensions
                if size(model_pred, 1) != n_samples
                    error("Model $(i) returned $(size(model_pred, 1)) predictions, expected $(n_samples)")
                end
                if model_pred isa Matrix
                    if size(model_pred, 2) < target_idx
                        error("Model $(i) returned $(size(model_pred, 2)) targets, expected at least $(target_idx)")
                    end
                    predictions_matrix[:, i] = model_pred[:, target_idx]
                else
                    predictions_matrix[:, i] = model_pred
                end
            end
            trial_predictions = predictions_matrix * trial_weights
            trial_score = metric(trial_predictions, y_val[:, target_idx])
            
            if trial_score > best_score
                best_score = trial_score
                best_target_weights = trial_weights
            end
        end
        
        best_weights[:, target_idx] = best_target_weights
    end
    
    return best_weights
end

function bagging_ensemble(model_constructor::Function, n_models::Int, 
                         X_train::Matrix{Float64}, y_train::Vector{Float64};
                         sample_ratio::Float64=0.8,
                         feature_ratio::Float64=0.8,
                         parallel::Bool=true,
                         verbose::Bool=false)::ModelEnsemble
    n_samples = size(X_train, 1)
    n_features = size(X_train, 2)
    
    n_sample_subset = Int(floor(n_samples * sample_ratio))
    n_feature_subset = Int(floor(n_features * feature_ratio))
    
    models = Models.NumeraiModel[]
    feature_indices_list = Vector{Vector{Int}}()
    
    train_func = function(i)
        Random.seed!(i)
        
        sample_indices = randperm(n_samples)[1:n_sample_subset]
        feature_indices = randperm(n_features)[1:n_feature_subset]
        
        X_subset = X_train[sample_indices, feature_indices]
        y_subset = y_train[sample_indices]
        
        model = model_constructor()
        Models.train!(model, X_subset, y_subset, verbose=verbose)
        
        return (model, feature_indices)
    end
    
    if parallel && Threads.nthreads() > 1
        results = ThreadsX.map(train_func, 1:n_models)
    else
        results = [train_func(i) for i in 1:n_models]
    end
    
    # Unpack models and feature indices
    for (model, feature_indices) in results
        push!(models, model)
        push!(feature_indices_list, feature_indices)
    end
    
    return ModelEnsemble(models, name="bagging_ensemble", feature_indices=feature_indices_list)
end

# Multi-target overload for bagging_ensemble
function bagging_ensemble(model_constructor::Function, n_models::Int, 
                         X_train::Matrix{Float64}, y_train::Matrix{Float64};
                         sample_ratio::Float64=0.8,
                         feature_ratio::Float64=0.8,
                         parallel::Bool=true,
                         verbose::Bool=false)::ModelEnsemble
    n_samples = size(X_train, 1)
    n_features = size(X_train, 2)
    
    n_sample_subset = Int(floor(n_samples * sample_ratio))
    n_feature_subset = Int(floor(n_features * feature_ratio))
    
    models = Models.NumeraiModel[]
    feature_indices_list = Vector{Vector{Int}}()
    
    train_func = function(i)
        Random.seed!(i)
        
        sample_indices = randperm(n_samples)[1:n_sample_subset]
        feature_indices = randperm(n_features)[1:n_feature_subset]
        
        X_subset = X_train[sample_indices, feature_indices]
        y_subset = y_train[sample_indices, :]  # Select all targets for the sample subset
        
        model = model_constructor()
        Models.train!(model, X_subset, y_subset, verbose=verbose)
        
        return (model, feature_indices)
    end
    
    if parallel && Threads.nthreads() > 1
        results = ThreadsX.map(train_func, 1:n_models)
    else
        results = [train_func(i) for i in 1:n_models]
    end
    
    # Unpack models and feature indices
    for (model, feature_indices) in results
        push!(models, model)
        push!(feature_indices_list, feature_indices)
    end
    
    return ModelEnsemble(models, name="bagging_ensemble", feature_indices=feature_indices_list)
end

function stacking_ensemble(base_models::Vector{<:Models.NumeraiModel}, 
                          meta_model::Models.NumeraiModel,
                          X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}},
                          X_val::Matrix{Float64}, y_val::Union{Vector{Float64}, Matrix{Float64}})::Function
    
    n_base = length(base_models)
    is_multi_target = y_train isa Matrix
    n_targets = is_multi_target ? size(y_train, 2) : 1
    
    # Train base models
    for model in base_models
        Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
    end
    
    if is_multi_target
        # Multi-target stacking: train separate meta-models for each target
        meta_models = [deepcopy(meta_model) for _ in 1:n_targets]
        
        for target_idx in 1:n_targets
            # Create meta features for this target
            meta_features_train = Matrix{Float64}(undef, size(X_train, 1), n_base)
            meta_features_val = Matrix{Float64}(undef, size(X_val, 1), n_base)
            
            for (i, model) in enumerate(base_models)
                pred_train = Models.predict(model, X_train)
                pred_val = Models.predict(model, X_val)
                
                # Validate prediction dimensions
                if size(pred_train, 1) != size(X_train, 1)
                    error("Base model $(i) returned $(size(pred_train, 1)) training predictions, expected $(size(X_train, 1))")
                end
                if size(pred_val, 1) != size(X_val, 1)
                    error("Base model $(i) returned $(size(pred_val, 1)) validation predictions, expected $(size(X_val, 1))")
                end
                
                if pred_train isa Matrix
                    if size(pred_train, 2) < target_idx
                        error("Base model $(i) returned $(size(pred_train, 2)) targets, expected at least $(target_idx)")
                    end
                    meta_features_train[:, i] = pred_train[:, target_idx]
                    meta_features_val[:, i] = pred_val[:, target_idx]
                else
                    meta_features_train[:, i] = pred_train
                    meta_features_val[:, i] = pred_val
                end
            end
            
            # Train meta model for this target
            Models.train!(meta_models[target_idx], meta_features_train, y_train[:, target_idx], 
                         X_val=meta_features_val, y_val=y_val[:, target_idx], verbose=false)
        end
        
        function stacked_predict_multi(X::Matrix{Float64})::Matrix{Float64}
            result = Matrix{Float64}(undef, size(X, 1), n_targets)
            
            for target_idx in 1:n_targets
                meta_features = Matrix{Float64}(undef, size(X, 1), n_base)
                for (i, model) in enumerate(base_models)
                    pred = Models.predict(model, X)
                    if pred isa Matrix
                        meta_features[:, i] = pred[:, target_idx]
                    else
                        meta_features[:, i] = pred
                    end
                end
                
                pred = Models.predict(meta_models[target_idx], meta_features)
                result[:, target_idx] = pred isa Vector ? pred : vec(pred)
            end
            
            return result
        end
        
        return stacked_predict_multi
    else
        # Single target stacking - original implementation
        meta_features_train = Matrix{Float64}(undef, size(X_train, 1), n_base)
        meta_features_val = Matrix{Float64}(undef, size(X_val, 1), n_base)
        
        for (i, model) in enumerate(base_models)
            pred_train = Models.predict(model, X_train)
            pred_val = Models.predict(model, X_val)
            
            # Validate prediction dimensions
            if length(pred_train) != size(X_train, 1)
                error("Base model $(i) returned $(length(pred_train)) training predictions, expected $(size(X_train, 1))")
            end
            if length(pred_val) != size(X_val, 1)
                error("Base model $(i) returned $(length(pred_val)) validation predictions, expected $(size(X_val, 1))")
            end
            
            meta_features_train[:, i] = pred_train isa Vector ? pred_train : vec(pred_train)
            meta_features_val[:, i] = pred_val isa Vector ? pred_val : vec(pred_val)
        end
        
        Models.train!(meta_model, meta_features_train, y_train, 
                     X_val=meta_features_val, y_val=y_val, verbose=false)
        
        function stacked_predict(X::Matrix{Float64})::Vector{Float64}
            meta_features = Matrix{Float64}(undef, size(X, 1), n_base)
            for (i, model) in enumerate(base_models)
                pred = Models.predict(model, X)
                meta_features[:, i] = pred isa Vector ? pred : vec(pred)
            end
            pred = Models.predict(meta_model, meta_features)
            return pred isa Vector ? pred : vec(pred)
        end
        
        return stacked_predict
    end
end

function diversity_score(predictions_matrix::Matrix{Float64})::Float64
    n_models = size(predictions_matrix, 2)
    
    if n_models < 2
        return 0.0
    end
    
    correlations = Float64[]
    for i in 1:n_models
        for j in (i+1):n_models
            push!(correlations, cor(predictions_matrix[:, i], predictions_matrix[:, j]))
        end
    end
    
    avg_correlation = mean(correlations)
    
    # Clamp the result to [0, 1] range
    # avg_correlation ranges from -1 to 1, so (1 - avg_correlation) / 2 maps to [0, 1]
    return (1.0 - avg_correlation) / 2.0
end

export ModelEnsemble, train_ensemble!, predict_ensemble, optimize_weights,
       bagging_ensemble, stacking_ensemble, diversity_score

end