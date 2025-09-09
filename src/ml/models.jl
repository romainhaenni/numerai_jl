module Models

using XGBoost
using LightGBM
using DataFrames
using Random
using Statistics
using ThreadsX

abstract type NumeraiModel end

mutable struct XGBoostModel <: NumeraiModel
    model::Union{Nothing, Booster}
    params::Dict{String, Any}
    num_rounds::Int
    name::String
end

mutable struct LightGBMModel <: NumeraiModel
    model::Union{Nothing, LGBMRegression}
    params::Dict{String, Any}
    name::String
end

function XGBoostModel(name::String="xgboost_default"; 
                     max_depth::Int=5,
                     learning_rate::Float64=0.01,
                     colsample_bytree::Float64=0.1,
                     num_rounds::Int=1000)
    params = Dict(
        "max_depth" => max_depth,
        "learning_rate" => learning_rate,
        "colsample_bytree" => colsample_bytree,
        "objective" => "reg:squarederror",
        "eval_metric" => "rmse",
        "tree_method" => "hist",
        "device" => "cpu",
        "nthread" => Threads.nthreads()
    )
    
    return XGBoostModel(nothing, params, num_rounds, name)
end

function LightGBMModel(name::String="lgbm_default";
                      num_leaves::Int=31,
                      learning_rate::Float64=0.01,
                      feature_fraction::Float64=0.1,
                      n_estimators::Int=1000)
    params = Dict(
        "objective" => "regression",
        "metric" => "rmse",
        "num_leaves" => num_leaves,
        "learning_rate" => learning_rate,
        "feature_fraction" => feature_fraction,
        "bagging_fraction" => 0.8,
        "bagging_freq" => 5,
        "n_estimators" => n_estimators,
        "num_threads" => Threads.nthreads(),
        "verbose" => -1
    )
    
    return LightGBMModel(nothing, params, name)
end

function train!(model::XGBoostModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               verbose::Bool=false)
    
    dtrain = DMatrix(X_train, label=y_train)
    
    eval_set = []
    if X_val !== nothing && y_val !== nothing
        dval = DMatrix(X_val, label=y_val)
        push!(eval_set, dval)
    end
    
    verbose_eval = verbose ? 1 : 0
    
    if !isempty(eval_set)
        model.model = xgboost(
            dtrain;
            num_round=model.num_rounds,
            params=model.params,
            watchlist=eval_set,
            verbose_eval=verbose_eval
        )
    else
        model.model = xgboost(
            dtrain;
            num_round=model.num_rounds,
            params=model.params,
            verbose_eval=verbose_eval
        )
    end
    
    return model
end

function train!(model::LightGBMModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               verbose::Bool=false)
    
    estimator = LGBMRegression(;
        objective=model.params["objective"],
        metric=[model.params["metric"]],
        num_leaves=model.params["num_leaves"],
        learning_rate=model.params["learning_rate"],
        feature_fraction=model.params["feature_fraction"],
        bagging_fraction=model.params["bagging_fraction"],
        bagging_freq=model.params["bagging_freq"],
        num_iterations=model.params["n_estimators"],
        num_threads=model.params["num_threads"],
        verbosity=verbose ? 1 : -1
    )
    
    # Use the correct parameter names for LightGBM.jl v2.0.0
    if X_val !== nothing && y_val !== nothing
        LightGBM.fit!(estimator, X_train, y_train, (X_val, y_val);
                     verbosity=verbose ? 1 : -1,
                     is_row_major=false,
                     weights=Float32[],
                     init_score=Float64[],
                     group=Int64[],
                     truncate_booster=false)
    else
        LightGBM.fit!(estimator, X_train, y_train;
                     verbosity=verbose ? 1 : -1,
                     is_row_major=false,
                     weights=Float32[],
                     init_score=Float64[],
                     group=Int64[],
                     truncate_booster=false)
    end
    
    model.model = estimator
    
    return model
end

function predict(model::XGBoostModel, X::Matrix{Float64})::Vector{Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    dtest = DMatrix(X)
    predictions = XGBoost.predict(model.model, dtest)
    
    return predictions
end

function predict(model::LightGBMModel, X::Matrix{Float64})::Vector{Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    predictions = LightGBM.predict(model.model, X)
    
    # Convert to Vector if it's a Matrix (LightGBM.jl v2.0.0 sometimes returns Matrix)
    if predictions isa Matrix
        return vec(predictions)
    else
        return predictions
    end
end

function cross_validate(model_constructor::Function, X::Matrix{Float64}, y::Vector{Float64}, 
                       eras::Vector{Int}; n_splits::Int=5)::Vector{Float64}
    unique_eras = unique(eras)
    n_eras = length(unique_eras)
    era_size = n_eras ÷ n_splits
    
    cv_scores = Float64[]
    
    for i in 1:n_splits
        val_start = (i - 1) * era_size + 1
        val_end = min(i * era_size, n_eras)
        val_eras = unique_eras[val_start:val_end]
        
        train_mask = .!(in.(eras, Ref(val_eras)))
        val_mask = in.(eras, Ref(val_eras))
        
        X_train = X[train_mask, :]
        y_train = y[train_mask]
        X_val = X[val_mask, :]
        y_val = y[val_mask]
        
        model = model_constructor()
        train!(model, X_train, y_train)
        
        predictions = predict(model, X_val)
        score = cor(predictions, y_val)
        push!(cv_scores, score)
    end
    
    return cv_scores
end

function feature_importance(model::XGBoostModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    importance = XGBoost.importance(model.model)
    return importance
end

function feature_importance(model::LightGBMModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    importance = LightGBM.feature_importance(model.model)
    feature_names = LightGBM.feature_name(model.model)
    
    return Dict(zip(feature_names, importance))
end

function save_model(model::NumeraiModel, filepath::String)
    if model.model === nothing
        error("Model not trained yet")
    end
    
    if model isa XGBoostModel
        XGBoost.save(model.model, filepath)
    elseif model isa LightGBMModel
        LightGBM.savemodel(model.model, filepath)
    end
    
    println("Model saved to $filepath")
end

function load_model!(model::XGBoostModel, filepath::String)
    model.model = Booster(model_file=filepath)
    return model
end

function load_model!(model::LightGBMModel, filepath::String)
    model.model = LightGBM.loadmodel(filepath)
    return model
end

export NumeraiModel, XGBoostModel, LightGBMModel, train!, predict, 
       cross_validate, feature_importance, save_model, load_model!

end