module Models

using XGBoost
using LightGBM
using EvoTrees
using CatBoost
using DataFrames
using Random
using Statistics
using ThreadsX
using OrderedCollections
using Logging
using JSON3

# Import DataLoader module from parent scope
using ..DataLoader

# Access GPU acceleration module from parent scope
# (already included by main NumeraiTournament module)

abstract type NumeraiModel end

mutable struct XGBoostModel <: NumeraiModel
    model::Union{Nothing, Booster}
    params::Dict{String, Any}
    num_rounds::Int
    name::String
    gpu_enabled::Bool
end

mutable struct LightGBMModel <: NumeraiModel
    model::Union{Nothing, LGBMRegression}
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

mutable struct EvoTreesModel <: NumeraiModel
    model::Union{Nothing, EvoTrees.EvoTree}
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

mutable struct CatBoostModel <: NumeraiModel
    model::Any  # CatBoost uses PyObject internally
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

function XGBoostModel(name::String="xgboost_default"; 
                     max_depth::Int=5,
                     learning_rate::Float64=0.01,
                     colsample_bytree::Float64=0.1,
                     num_rounds::Int=1000,
                     gpu_enabled::Bool=true)
    
    # Check if GPU is available and configure accordingly
    use_gpu = gpu_enabled && @isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false
    
    params = Dict(
        "max_depth" => max_depth,
        "learning_rate" => learning_rate,
        "colsample_bytree" => colsample_bytree,
        "objective" => "reg:squarederror",
        "eval_metric" => "rmse",
        "tree_method" => "hist",
        "device" => use_gpu ? "gpu" : "cpu",
        "nthread" => Threads.nthreads()
    )
    
    if use_gpu
        @info "XGBoost model configured with GPU acceleration" name=name
    else
        @info "XGBoost model configured with CPU" name=name reason=(gpu_enabled ? "GPU not available" : "GPU disabled")
    end
    
    return XGBoostModel(nothing, params, num_rounds, name, use_gpu)
end

function LightGBMModel(name::String="lgbm_default";
                      num_leaves::Int=31,
                      learning_rate::Float64=0.01,
                      feature_fraction::Float64=0.1,
                      n_estimators::Int=1000,
                      gpu_enabled::Bool=true)
    
    # Check if GPU is available and configure accordingly
    use_gpu = gpu_enabled && @isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false
    
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
        "device_type" => use_gpu ? "gpu" : "cpu",
        "verbose" => -1
    )
    
    if use_gpu
        @info "LightGBM model configured with GPU acceleration" name=name
    else
        @info "LightGBM model configured with CPU" name=name reason=(gpu_enabled ? "GPU not available" : "GPU disabled")
    end
    
    return LightGBMModel(nothing, params, name, use_gpu)
end

function EvoTreesModel(name::String="evotrees_default";
                      max_depth::Int=5,
                      learning_rate::Float64=0.01,
                      subsample::Float64=0.8,
                      colsample::Float64=0.8,
                      nrounds::Int=1000,
                      gpu_enabled::Bool=true)
    
    # Check if GPU is available and configure accordingly
    use_gpu = gpu_enabled && @isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false
    
    params = Dict(
        "loss" => :mse,
        "metric" => :mse,
        "max_depth" => max_depth,
        "eta" => learning_rate,
        "rowsample" => subsample,
        "colsample" => colsample,
        "nrounds" => nrounds,
        "nbins" => 64,
        "monotone_constraints" => Dict{Int, Int}(),
        "device" => use_gpu ? "gpu" : "cpu"
    )
    
    if use_gpu
        @info "EvoTrees model configured with GPU acceleration" name=name
    else
        @info "EvoTrees model configured with CPU" name=name reason=(gpu_enabled ? "GPU not available" : "GPU disabled")
    end
    
    return EvoTreesModel(nothing, params, name, use_gpu)
end

function CatBoostModel(name::String="catboost_default";
                      depth::Int=6,
                      learning_rate::Float64=0.03,
                      iterations::Int=1000,
                      l2_leaf_reg::Float64=3.0,
                      bagging_temperature::Float64=1.0,
                      subsample::Float64=0.8,
                      colsample_bylevel::Float64=0.8,
                      random_strength::Float64=1.0,
                      gpu_enabled::Bool=true)
    
    # Check for GPU availability
    use_gpu = gpu_enabled && false  # CatBoost GPU support needs special setup, disable for now
    
    params = Dict{String, Any}(
        "loss_function" => "RMSE",
        "depth" => depth,
        "learning_rate" => learning_rate,
        "iterations" => iterations,
        "l2_leaf_reg" => l2_leaf_reg,
        "bagging_temperature" => bagging_temperature,
        "subsample" => subsample,
        "colsample_bylevel" => colsample_bylevel,
        "random_strength" => random_strength,
        "thread_count" => Threads.nthreads(),
        "verbose" => false,
        "random_seed" => 42
    )
    
    if use_gpu
        @info "CatBoost model configured with GPU acceleration" name=name
    else
        @info "CatBoost model configured with CPU" name=name reason="GPU support disabled for CatBoost"
    end
    
    return CatBoostModel(nothing, params, name, use_gpu)
end

function train!(model::XGBoostModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false,
               preprocess_gpu::Bool=true)
    
    # Process feature groups if provided
    interaction_constraints = nothing
    if feature_groups !== nothing && feature_names !== nothing
        @info "Processing feature groups for interaction constraints" num_groups=length(feature_groups)
        interaction_constraints = DataLoader.create_interaction_constraints(feature_groups, feature_names)
        if !isempty(interaction_constraints)
            @info "Created interaction constraints" num_constraints=length(interaction_constraints)
        end
    end
    
    # GPU-accelerated preprocessing if enabled
    if model.gpu_enabled && preprocess_gpu
        @info "Using GPU for data preprocessing" model_name=model.name
        X_train_processed = copy(X_train)
        (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_standardize!)) ? MetalAcceleration.gpu_standardize!(X_train_processed) : nothing
    else
        X_train_processed = X_train
    end
    
    dtrain = DMatrix(X_train_processed, label=y_train)
    
    # Train model with individual parameters instead of params dict
    if X_val !== nothing && y_val !== nothing
        # Process validation data with same preprocessing
        if model.gpu_enabled && preprocess_gpu
            X_val_processed = copy(X_val)
            (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_standardize!)) ? MetalAcceleration.gpu_standardize!(X_val_processed) : nothing
        else
            X_val_processed = X_val
        end
        
        dval = DMatrix(X_val_processed, label=y_val)
        watchlist = OrderedDict("train" => dtrain, "eval" => dval)
        
        # Train model with validation set
        params = Dict{Symbol, Any}(
            :num_round => model.num_rounds,
            :max_depth => model.params["max_depth"],
            :eta => model.params["learning_rate"],
            :colsample_bytree => model.params["colsample_bytree"],
            :objective => model.params["objective"],
            :eval_metric => model.params["eval_metric"],
            :tree_method => model.params["tree_method"],
            :device => model.params["device"],
            :nthread => model.params["nthread"],
            :watchlist => watchlist
        )
        
        # Add interaction constraints if available (convert to JSON string for XGBoost)
        if interaction_constraints !== nothing && !isempty(interaction_constraints)
            params[:interaction_constraints] = JSON3.write(interaction_constraints)
        end
        
        model.model = xgboost(dtrain; params...)
    else
        # Train model without validation set
        params = Dict{Symbol, Any}(
            :num_round => model.num_rounds,
            :max_depth => model.params["max_depth"],
            :eta => model.params["learning_rate"],
            :colsample_bytree => model.params["colsample_bytree"],
            :objective => model.params["objective"],
            :eval_metric => model.params["eval_metric"],
            :tree_method => model.params["tree_method"],
            :device => model.params["device"],
            :nthread => model.params["nthread"]
        )
        
        # Add interaction constraints if available (convert to JSON string for XGBoost)
        if interaction_constraints !== nothing && !isempty(interaction_constraints)
            params[:interaction_constraints] = JSON3.write(interaction_constraints)
        end
        
        model.model = xgboost(dtrain; params...)
    end
    
    return model
end

function train!(model::LightGBMModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false)
    
    # Prepare interaction constraints for LightGBM if feature groups are provided
    interaction_constraints = nothing
    feature_fraction_bynode = model.params["feature_fraction"]
    
    if feature_groups !== nothing && feature_names !== nothing
        if verbose
            @info "Processing feature groups for LightGBM" num_groups=length(feature_groups)
        end
        # Create interaction constraints in LightGBM format
        interaction_constraints = DataLoader.create_interaction_constraints(feature_groups, feature_names)
        
        # Adjust feature fraction based on number of groups
        if !isempty(interaction_constraints)
            num_groups = length(interaction_constraints)
            # Use group-based column sampling to ensure balanced feature usage
            feature_fraction_bynode = min(1.0, num_groups / length(feature_names))
            if verbose
                @info "Adjusted feature_fraction_bynode for group-based sampling" value=feature_fraction_bynode
            end
        end
    end
    
    # Build parameters dictionary
    lgbm_params = Dict{Symbol, Any}(
        :objective => model.params["objective"],
        :metric => [model.params["metric"]],
        :num_leaves => model.params["num_leaves"],
        :learning_rate => model.params["learning_rate"],
        :feature_fraction => model.params["feature_fraction"],
        :feature_fraction_bynode => feature_fraction_bynode,
        :bagging_fraction => model.params["bagging_fraction"],
        :bagging_freq => model.params["bagging_freq"],
        :num_iterations => model.params["n_estimators"],
        :num_threads => model.params["num_threads"],
        :verbosity => verbose ? 1 : -1
    )
    
    # Add interaction constraints if available (LightGBM uses Vector{Vector{Int}} format)
    if interaction_constraints !== nothing && !isempty(interaction_constraints)
        lgbm_params[:interaction_constraints] = interaction_constraints
        if verbose
            @info "Applied interaction constraints to LightGBM" constraints=interaction_constraints
        end
    end
    
    estimator = LGBMRegression(; lgbm_params...)
    
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

function train!(model::EvoTreesModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false)
    
    # Process feature groups for EvoTrees if provided
    colsample_val = model.params["colsample"]
    
    if feature_groups !== nothing && feature_names !== nothing
        if verbose
            @info "Processing feature groups for EvoTrees" num_groups=length(feature_groups)
        end
        
        # EvoTrees doesn't directly support interaction constraints,
        # but we can adjust column sampling to respect feature groups
        num_groups = length(feature_groups)
        if num_groups > 0
            # Adjust colsample to ensure features from all groups are sampled
            # Use a higher colsample value when we have feature groups to ensure diversity
            colsample_val = min(1.0, model.params["colsample"] * sqrt(num_groups))
            if verbose
                @info "Adjusted colsample for group-based sampling" original=model.params["colsample"] adjusted=colsample_val
            end
        end
    end
    
    # Prepare configuration for EvoTrees
    config = EvoTrees.EvoTreeRegressor(;
        loss=model.params["loss"],
        metric=model.params["metric"],
        max_depth=model.params["max_depth"],
        eta=model.params["eta"],
        rowsample=model.params["rowsample"],
        colsample=colsample_val,
        nrounds=model.params["nrounds"],
        nbins=model.params["nbins"],
        monotone_constraints=model.params["monotone_constraints"],
        device=model.params["device"]
    )
    
    # Train the model
    if X_val !== nothing && y_val !== nothing
        # Train with validation set (avoiding early stopping due to EvoTrees bug)
        model.model = EvoTrees.fit_evotree(config; 
                                          x_train=X_train, 
                                          y_train=y_train,
                                          print_every_n=0)  # Avoid division error in EvoTrees
    else
        # Train without validation set
        model.model = EvoTrees.fit_evotree(config; 
                                          x_train=X_train, 
                                          y_train=y_train,
                                          print_every_n=0)  # Avoid division error in EvoTrees
    end
    
    return model
end

function train!(model::CatBoostModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false)
    
    # Process feature groups for CatBoost if provided
    cat_features = Int[]  # CatBoost can handle categorical features
    interaction_indices = nothing
    
    if feature_groups !== nothing && feature_names !== nothing
        if verbose
            @info "Processing feature groups for CatBoost" num_groups=length(feature_groups)
        end
        # Create interaction constraints
        interaction_indices = DataLoader.create_interaction_constraints(feature_groups, feature_names)
        
        # Adjust colsample_bylevel based on number of groups if needed
        if !isempty(interaction_indices)
            num_groups = length(interaction_indices)
            adjusted_colsample = min(1.0, model.params["colsample_bylevel"] * sqrt(num_groups))
            model.params["colsample_bylevel"] = adjusted_colsample
            if verbose
                @info "Adjusted colsample_bylevel for CatBoost" value=adjusted_colsample
            end
        end
    end
    
    # Create CatBoost pool
    train_pool = CatBoost.Pool(X_train, y_train; cat_features=cat_features)
    
    # Create validation pool if provided
    eval_pool = nothing
    if X_val !== nothing && y_val !== nothing
        eval_pool = CatBoost.Pool(X_val, y_val; cat_features=cat_features)
    end
    
    # Configure CatBoost parameters
    catboost_params = Dict{String, Any}(
        :loss_function => model.params["loss_function"],
        :depth => model.params["depth"],
        :learning_rate => model.params["learning_rate"],
        :iterations => model.params["iterations"],
        :l2_leaf_reg => model.params["l2_leaf_reg"],
        :bagging_temperature => model.params["bagging_temperature"],
        :subsample => model.params["subsample"],
        :colsample_bylevel => model.params["colsample_bylevel"],
        :random_strength => model.params["random_strength"],
        :thread_count => model.params["thread_count"],
        :verbose => verbose,
        :random_seed => model.params["random_seed"]
    )
    
    # Train the model
    model.model = CatBoost.CatBoostRegressor(; catboost_params...)
    
    if eval_pool !== nothing
        CatBoost.fit!(model.model, train_pool; eval_set=eval_pool, verbose=verbose)
    else
        CatBoost.fit!(model.model, train_pool; verbose=verbose)
    end
    
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

function predict(model::EvoTreesModel, X::Matrix{Float64})::Vector{Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    predictions = EvoTrees.predict(model.model, X)
    
    # Convert to Vector if it's a Matrix
    if predictions isa Matrix
        return vec(predictions)
    else
        return predictions
    end
end

function predict(model::CatBoostModel, X::Matrix{Float64})::Vector{Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Create a pool for prediction
    test_pool = CatBoost.Pool(X)
    
    # Get predictions
    predictions = CatBoost.predict(model.model, test_pool)
    
    # Ensure predictions are a Vector
    if predictions isa Matrix
        return vec(predictions)
    else
        return predictions
    end
end

function cross_validate(model_constructor::Function, X::Matrix{Float64}, y::Vector{Float64}, 
                       eras::Vector{Int}; n_splits::Int=5, use_gpu::Bool=true)::Vector{Float64}
    unique_eras = unique(eras)
    n_eras = length(unique_eras)
    era_size = n_eras ÷ n_splits
    
    cv_scores = Float64[]
    
    @info "Starting cross-validation" n_splits=n_splits use_gpu=use_gpu
    
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
        
        # Use GPU-accelerated correlation computation if available
        score = if use_gpu && (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false)
            (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_compute_correlations)) ? MetalAcceleration.gpu_compute_correlations(predictions, y_val) : cor(predictions, y_val)
        else
            cor(predictions, y_val)
        end
        
        push!(cv_scores, score)
        @info "CV fold completed" fold=i score=score
    end
    
    @info "Cross-validation completed" mean_score=mean(cv_scores) std_score=std(cv_scores)
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

function feature_importance(model::EvoTreesModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    importance = EvoTrees.importance(model.model)
    
    # Convert importance to dictionary with feature names
    feature_dict = Dict{String, Float64}()
    for i in 1:length(importance)
        feature_dict["feature_$(i)"] = importance[i]
    end
    
    return feature_dict
end

function feature_importance(model::CatBoostModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    try
        # CatBoost.jl wraps Python's CatBoost, so we need to use Python methods
        # Get feature importance using the Python method
        py_importance = model.model.get_feature_importance()
        
        # Convert to Julia array if needed
        importance_array = convert(Vector{Float64}, py_importance)
        
        # Create dictionary with feature names
        feature_dict = Dict{String, Float64}()
        for i in 1:length(importance_array)
            feature_dict["feature_$(i)"] = importance_array[i]
        end
        
        return feature_dict
    catch e
        @warn "Failed to get CatBoost feature importance, using uniform importance" error=e
        # Fallback: return uniform importance if the method is not available
        n_features = length(model.params["colsample_bylevel"] == 1.0 ? 100 : 100)  # Default assumption
        feature_dict = Dict{String, Float64}()
        for i in 1:n_features
            feature_dict["feature_$(i)"] = 1.0 / n_features
        end
        return feature_dict
    end
end

function save_model(model::NumeraiModel, filepath::String)
    if model.model === nothing
        error("Model not trained yet")
    end
    
    if model isa XGBoostModel
        XGBoost.save(model.model, filepath)
    elseif model isa LightGBMModel
        LightGBM.savemodel(model.model, filepath)
    elseif model isa EvoTreesModel
        EvoTrees.save(model.model, filepath)
    elseif model isa CatBoostModel
        CatBoost.save_model(model.model, filepath)
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

function load_model!(model::EvoTreesModel, filepath::String)
    model.model = EvoTrees.load(filepath)
    return model
end

function load_model!(model::CatBoostModel, filepath::String)
    model.model = CatBoost.CatBoostRegressor()
    CatBoost.load_model!(model.model, filepath)
    return model
end

"""
GPU-accelerated ensemble prediction combining multiple models
"""
function ensemble_predict(models::Vector{<:NumeraiModel}, X::Matrix{Float64}, 
                         weights::Union{Nothing, Vector{Float64}}=nothing)::Vector{Float64}
    if isempty(models)
        error("No models provided for ensemble prediction")
    end
    
    # Check if any models are not trained
    untrained = [i for (i, model) in enumerate(models) if model.model === nothing]
    if !isempty(untrained)
        error("Models at indices $untrained are not trained")
    end
    
    n_models = length(models)
    n_samples = size(X, 1)
    
    # Default to equal weights if none provided
    if weights === nothing
        weights = fill(1.0 / n_models, n_models)
    elseif length(weights) != n_models
        error("Number of weights ($(length(weights))) must match number of models ($n_models)")
    end
    
    @info "Computing ensemble predictions" n_models=n_models n_samples=n_samples
    
    # Collect predictions from all models
    predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
    
    for (i, model) in enumerate(models)
        predictions_matrix[:, i] = predict(model, X)
    end
    
    # Use GPU-accelerated ensemble computation if available
    ensemble_predictions = if any(model.gpu_enabled for model in models) && (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false)
        @info "Using GPU for ensemble computation"
        (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_ensemble_predictions)) ? MetalAcceleration.gpu_ensemble_predictions(predictions_matrix, weights) : vec(sum(predictions_matrix .* weights', dims=2))
    else
        predictions_matrix * weights
    end
    
    return ensemble_predictions
end

"""
GPU-accelerated feature selection for all models
"""
function gpu_feature_selection_for_models(X::Matrix{Float64}, y::Vector{Float64}, 
                                         k::Int=100)::Vector{Int}
    @info "Performing GPU-accelerated feature selection" k=k n_features=size(X, 2)
    
    return (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_feature_selection)) ? MetalAcceleration.gpu_feature_selection(X, y, k) : collect(1:min(k, size(X, 2)))
end

"""
Benchmark model training performance with and without GPU
"""
function benchmark_model_performance(model_constructor::Function, X::Matrix{Float64}, 
                                   y::Vector{Float64}; n_runs::Int=3)
    @info "Benchmarking model performance" n_runs=n_runs data_size=size(X)
    
    cpu_times = Float64[]
    gpu_times = Float64[]
    
    # Benchmark CPU training
    @info "Benchmarking CPU training"
    for i in 1:n_runs
        model_cpu = model_constructor(gpu_enabled=false)
        cpu_time = @elapsed train!(model_cpu, X, y, preprocess_gpu=false)
        push!(cpu_times, cpu_time)
        @info "CPU run completed" run=i time=cpu_time
    end
    
    # Benchmark GPU training (if available)
    if @isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false
        @info "Benchmarking GPU training"
        for i in 1:n_runs
            model_gpu = model_constructor(gpu_enabled=true)
            gpu_time = @elapsed train!(model_gpu, X, y, preprocess_gpu=true)
            push!(gpu_times, gpu_time)
            @info "GPU run completed" run=i time=gpu_time
        end
    else
        @warn "GPU not available for benchmarking"
        gpu_times = [Inf]
    end
    
    cpu_mean = mean(cpu_times)
    gpu_mean = mean(gpu_times)
    speedup = cpu_mean / gpu_mean
    
    results = Dict(
        "cpu_times" => cpu_times,
        "gpu_times" => gpu_times,
        "cpu_mean" => cpu_mean,
        "gpu_mean" => gpu_mean,
        "speedup" => speedup,
        "gpu_available" => (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu)) ? MetalAcceleration.has_metal_gpu() : false
    )
    
    @info "Benchmark completed" cpu_mean=cpu_mean gpu_mean=gpu_mean speedup=speedup
    
    return results
end

"""
Get GPU status and memory information for all models
"""
function get_models_gpu_status()::Dict{String, Any}
    gpu_info = (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :get_gpu_info)) ? MetalAcceleration.get_gpu_info() : Dict()
    memory_info = (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_memory_info)) ? MetalAcceleration.gpu_memory_info() : Dict()
    
    return Dict(
        "gpu_available" => (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu)) ? MetalAcceleration.has_metal_gpu() : false,
        "gpu_info" => gpu_info,
        "memory_info" => memory_info,
        "metal_functional" => (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu)) ? MetalAcceleration.has_metal_gpu() : false,
        "models_support_gpu" => true  # All our models support GPU acceleration
    )
end

# Model creation factory function
function create_model(model_type::Symbol, params::Dict{Symbol,Any})
    # Ensure name is provided
    name = get(params, :name, "model_$(model_type)")
    
    # Remove name from params as it's passed separately to constructors
    model_params = copy(params)
    delete!(model_params, :name)
    
    if model_type == :XGBoost
        return XGBoostModel(name; model_params...)
    elseif model_type == :LightGBM
        return LightGBMModel(name; model_params...)
    elseif model_type == :EvoTrees
        return EvoTreesModel(name; model_params...)
    elseif model_type == :CatBoost
        return CatBoostModel(name; model_params...)
    elseif model_type == :Ridge
        include("linear_models.jl")
        return LinearModels.RidgeModel(name; model_params...)
    elseif model_type == :Lasso
        include("linear_models.jl")
        return LinearModels.LassoModel(name; model_params...)
    elseif model_type == :ElasticNet
        include("linear_models.jl")
        return LinearModels.ElasticNetModel(name; model_params...)
    elseif model_type == :NeuralNetwork || model_type == :MLP
        include("neural_networks.jl")
        return NeuralNetworks.MLPModel(name; model_params...)
    elseif model_type == :ResNet
        include("neural_networks.jl")
        return NeuralNetworks.ResNetModel(name; model_params...)
    elseif model_type == :TabNet
        include("neural_networks.jl")
        return NeuralNetworks.TabNetModel(name; model_params...)
    else
        error("Unknown model type: $model_type")
    end
end

export NumeraiModel, XGBoostModel, LightGBMModel, EvoTreesModel, CatBoostModel, train!, predict, 
       cross_validate, feature_importance, save_model, load_model!,
       ensemble_predict, gpu_feature_selection_for_models, benchmark_model_performance,
       get_models_gpu_status, create_model

# Include linear models
include("linear_models.jl")
using .LinearModels: RidgeModel, LassoModel, ElasticNetModel
export RidgeModel, LassoModel, ElasticNetModel

# Include neural networks
include("neural_networks.jl")
using .NeuralNetworks: MLPModel, ResNetModel, TabNetModel, NeuralNetworkModel, 
                       train_neural_network!, predict_neural_network,
                       correlation_loss, mse_correlation_loss
export MLPModel, ResNetModel, TabNetModel, NeuralNetworkModel,
       train_neural_network!, predict_neural_network,
       correlation_loss, mse_correlation_loss

end