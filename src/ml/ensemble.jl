module Ensemble

using Statistics
using Random
using ThreadsX
using ..Models
using ..Preprocessor: check_memory_before_allocation, safe_matrix_allocation

struct ModelEnsemble
    models::Vector{<:Models.NumeraiModel}
    weights::Vector{Float64}
    name::String
end

function ModelEnsemble(models::Vector{<:Models.NumeraiModel}; 
                      weights::Union{Nothing, Vector{Float64}}=nothing,
                      name::String="ensemble")
    n_models = length(models)
    
    if weights === nothing
        weights = fill(1.0 / n_models, n_models)
    else
        if length(weights) != n_models
            error("Number of weights must match number of models")
        end
        weights = weights ./ sum(weights)
    end
    
    return ModelEnsemble(models, weights, name)
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

function predict_ensemble(ensemble::ModelEnsemble, X::Matrix{Float64}; 
                         return_individual::Bool=false)::Union{Vector{Float64}, Matrix{Float64}, Tuple{Union{Vector{Float64}, Matrix{Float64}}, Array{Float64}}}
    n_samples = size(X, 1)
    n_models = length(ensemble.models)
    
    # Get prediction from first model to determine output shape
    first_prediction = Models.predict(ensemble.models[1], X)
    is_multi_target = first_prediction isa Matrix
    n_targets = is_multi_target ? size(first_prediction, 2) : 1
    
    if is_multi_target
        # Multi-target case: 3D array (samples, targets, models)
        predictions_array = Array{Float64}(undef, n_samples, n_targets, n_models)
        predictions_array[:, :, 1] = first_prediction
        
        # Get predictions from remaining models
        ThreadsX.foreach(2:n_models) do i
            model_pred = Models.predict(ensemble.models[i], X)
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
            model_pred = Models.predict(ensemble.models[i], X)
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
        predictions_matrix[:, i] = Models.predict(model, X_val)
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

function bagging_ensemble(model_constructor::Function, n_models::Int, 
                         X_train::Matrix{Float64}, y_train::Vector{Float64};
                         sample_ratio::Float64=0.8,
                         feature_ratio::Float64=0.8,
                         parallel::Bool=true)::ModelEnsemble
    n_samples = size(X_train, 1)
    n_features = size(X_train, 2)
    
    n_sample_subset = Int(floor(n_samples * sample_ratio))
    n_feature_subset = Int(floor(n_features * feature_ratio))
    
    models = Models.NumeraiModel[]
    
    train_func = function(i)
        Random.seed!(i)
        
        sample_indices = randperm(n_samples)[1:n_sample_subset]
        feature_indices = randperm(n_features)[1:n_feature_subset]
        
        X_subset = X_train[sample_indices, feature_indices]
        y_subset = y_train[sample_indices]
        
        model = model_constructor()
        Models.train!(model, X_subset, y_subset, verbose=false)
        
        return model
    end
    
    if parallel && Threads.nthreads() > 1
        models = ThreadsX.map(train_func, 1:n_models)
    else
        models = [train_func(i) for i in 1:n_models]
    end
    
    return ModelEnsemble(models, name="bagging_ensemble")
end

function stacking_ensemble(base_models::Vector{<:Models.NumeraiModel}, 
                          meta_model::Models.NumeraiModel,
                          X_train::Matrix{Float64}, y_train::Vector{Float64},
                          X_val::Matrix{Float64}, y_val::Vector{Float64})::Function
    
    n_base = length(base_models)
    meta_features_train = Matrix{Float64}(undef, size(X_train, 1), n_base)
    meta_features_val = Matrix{Float64}(undef, size(X_val, 1), n_base)
    
    for (i, model) in enumerate(base_models)
        Models.train!(model, X_train, y_train, verbose=false)
        meta_features_train[:, i] = Models.predict(model, X_train)
        meta_features_val[:, i] = Models.predict(model, X_val)
    end
    
    Models.train!(meta_model, meta_features_train, y_train, 
                 X_val=meta_features_val, y_val=y_val, verbose=false)
    
    function stacked_predict(X::Matrix{Float64})::Vector{Float64}
        meta_features = Matrix{Float64}(undef, size(X, 1), n_base)
        for (i, model) in enumerate(base_models)
            meta_features[:, i] = Models.predict(model, X)
        end
        return Models.predict(meta_model, meta_features)
    end
    
    return stacked_predict
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