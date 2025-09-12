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

# Import Callbacks module
include("callbacks.jl")
using .Callbacks

# Access GPU acceleration module from parent scope
# (already included by main NumeraiTournament module)

abstract type NumeraiModel end

mutable struct XGBoostModel <: NumeraiModel
    model::Union{Nothing, Booster, Vector{Booster}}  # Single model or vector of models for multi-target
    params::Dict{String, Any}
    num_rounds::Int
    name::String
    gpu_enabled::Bool
end

mutable struct LightGBMModel <: NumeraiModel
    model::Union{Nothing, LGBMRegression, Vector{LGBMRegression}}  # Single model or vector of models for multi-target
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

mutable struct EvoTreesModel <: NumeraiModel
    model::Union{Nothing, EvoTrees.EvoTree, Vector{EvoTrees.EvoTree}}  # Single model or vector of models for multi-target
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
end

mutable struct CatBoostModel <: NumeraiModel
    model::Union{Nothing, Any, Vector{Any}}  # Single model or vector of models for multi-target
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
                      early_stopping_rounds::Int=10,
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
        "early_stopping_rounds" => early_stopping_rounds,
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
    use_gpu = gpu_enabled && @isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :has_metal_gpu) ? MetalAcceleration.has_metal_gpu() : false
    
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
    
    # Configure GPU parameters if available
    if use_gpu
        params["task_type"] = "GPU"
        params["devices"] = "0"  # Use first GPU device
        @info "CatBoost model configured with GPU acceleration" name=name
    else
        @info "CatBoost model configured with CPU" name=name reason="GPU support disabled for CatBoost"
    end
    
    return CatBoostModel(nothing, params, name, use_gpu)
end

function train!(model::XGBoostModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false,
               preprocess_gpu::Bool=true,
               callbacks::Vector{TrainingCallback}=TrainingCallback[])
    
    # Detect multi-target case and set up appropriate parameters
    is_multitarget = y_train isa Matrix{Float64}
    n_targets = is_multitarget ? size(y_train, 2) : 1
    
    if is_multitarget
        @info "Training XGBoost with multi-target support (using multiple single-target models)" n_targets=n_targets model_name=model.name
        # XGBoost doesn't natively support multi-target regression, so we'll train multiple models
        # Keep single-target parameters
        model.params["objective"] = "reg:squarederror"
        model.params["eval_metric"] = "rmse"
        # Store target information for later use in prediction
        model.params["n_targets"] = n_targets
        # Remove num_class if it exists
        if haskey(model.params, "num_class")
            delete!(model.params, "num_class")
        end
    else
        @info "Training XGBoost with single-target" model_name=model.name
        # Ensure single-target parameters are set correctly
        model.params["objective"] = "reg:squarederror"
        model.params["eval_metric"] = "rmse"
        # Remove multi-target parameters if they exist
        if haskey(model.params, "num_class")
            delete!(model.params, "num_class")
        end
        if haskey(model.params, "n_targets")
            delete!(model.params, "n_targets")
        end
    end
    
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
    
    # Process validation data with same preprocessing if available
    X_val_processed = nothing
    if X_val !== nothing
        if model.gpu_enabled && preprocess_gpu
            X_val_processed = copy(X_val)
            (@isdefined(MetalAcceleration) && isdefined(MetalAcceleration, :gpu_standardize!)) ? MetalAcceleration.gpu_standardize!(X_val_processed) : nothing
        else
            X_val_processed = X_val
        end
    end
    
    # Initialize callback tracking
    start_time = time()
    
    # Add default logging callback if verbose and no callbacks provided
    if verbose && isempty(callbacks)
        push!(callbacks, create_logging_callback(frequency=max(1, model.num_rounds ÷ 10)))
    end
    
    if is_multitarget
        # For multi-target, train separate models for each target
        models = Booster[]
        
        for target_idx in 1:n_targets
            @info "Training model for target $target_idx/$n_targets"
            
            # Call callbacks for target start
            for callback in callbacks
                target_name = "$(model.name)_target_$(target_idx)"
                info = create_callback_info(target_name, 0, n_targets, target_idx, n_targets, start_time)
                call_callback!(callback, info)
            end
            
            y_target = y_train[:, target_idx]
            dtrain = DMatrix(X_train_processed, label=y_target)
            
            # Prepare validation data for this target if available
            dval_target = nothing
            if X_val !== nothing && y_val isa Matrix{Float64}
                y_val_target = y_val[:, target_idx]
                dval_target = DMatrix(X_val_processed, label=y_val_target)
            elseif X_val !== nothing && y_val isa Vector{Float64} && target_idx == 1
                # Use single-target validation for first target only
                dval_target = DMatrix(X_val_processed, label=y_val)
            end
            
            # Train model for this target
            target_model = if dval_target !== nothing
                watchlist = OrderedDict("train" => dtrain, "eval" => dval_target)
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
                
                # Add interaction constraints if available
                if interaction_constraints !== nothing && !isempty(interaction_constraints)
                    params[:interaction_constraints] = JSON3.write(interaction_constraints)
                end
                
                xgboost(dtrain; params...)
            else
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
                
                # Add interaction constraints if available
                if interaction_constraints !== nothing && !isempty(interaction_constraints)
                    params[:interaction_constraints] = JSON3.write(interaction_constraints)
                end
                
                xgboost(dtrain; params...)
            end
            
            # Call callbacks for target completion
            for callback in callbacks
                target_name = "$(model.name)_target_$(target_idx)"
                info = create_callback_info(target_name, target_idx, n_targets, model.num_rounds, model.num_rounds, start_time)
                call_callback!(callback, info)
            end
            
            push!(models, target_model)
        end
        
        model.model = models
        return model
    else
        # Single-target training
        dtrain = DMatrix(X_train_processed, label=y_train)
    end
    
    # Single-target training logic (only reached if not multi-target)
    # Call callbacks for training start
    for callback in callbacks
        info = create_callback_info(model.name, 0, 1, 0, model.num_rounds, start_time)
        call_callback!(callback, info)
    end
    
    if X_val !== nothing && y_val !== nothing
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
    
    # Call callbacks for training completion
    for callback in callbacks
        info = create_callback_info(model.name, 1, 1, model.num_rounds, model.num_rounds, start_time)
        call_callback!(callback, info)
    end
    
    return model
end

function train!(model::LightGBMModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false,
               callbacks::Vector{TrainingCallback}=TrainingCallback[])
    
    # Detect multi-target case and set up appropriate parameters
    is_multitarget = y_train isa Matrix{Float64}
    n_targets = is_multitarget ? size(y_train, 2) : 1
    
    if is_multitarget
        @info "Training LightGBM with multi-target support (using multiple single-target models)" n_targets=n_targets model_name=model.name
        # LightGBM doesn't natively support multi-target regression, so we'll train multiple models
        # Store target information for later use in prediction
        model.params["n_targets"] = n_targets
    else
        @info "Training LightGBM with single-target" model_name=model.name
        # Remove multi-target parameters if they exist
        if haskey(model.params, "n_targets")
            delete!(model.params, "n_targets")
        end
    end
    
    # Initialize callback tracking
    start_time = time()
    
    # Add default logging callback if verbose and no callbacks provided
    if verbose && isempty(callbacks)
        push!(callbacks, create_logging_callback(frequency=max(1, model.params["n_estimators"] ÷ 10)))
    end
    
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
    
    if is_multitarget
        # For multi-target, train separate models for each target
        models = LGBMRegression[]
        
        for target_idx in 1:n_targets
            @info "Training LightGBM model for target $target_idx/$n_targets"
            
            # Call callbacks for target start
            for callback in callbacks
                target_name = "$(model.name)_target_$(target_idx)"
                info = create_callback_info(target_name, 0, n_targets, target_idx, n_targets, start_time)
                call_callback!(callback, info)
            end
            
            y_target = y_train[:, target_idx]
            
            # Build parameters dictionary for this target
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
                if verbose && target_idx == 1  # Only log once to avoid spam
                    @info "Applied interaction constraints to LightGBM" constraints=interaction_constraints
                end
            end
            
            estimator = LGBMRegression(; lgbm_params...)
            
            # Train model for this target with appropriate validation data
            if X_val !== nothing && y_val isa Matrix{Float64}
                y_val_target = y_val[:, target_idx]
                LightGBM.fit!(estimator, X_train, y_target, (X_val, y_val_target);
                             verbosity=verbose ? 1 : -1,
                             is_row_major=false,
                             weights=Float32[],
                             init_score=Float64[],
                             group=Int64[],
                             truncate_booster=false)
            elseif X_val !== nothing && y_val isa Vector{Float64} && target_idx == 1
                # Use single-target validation for first target only
                LightGBM.fit!(estimator, X_train, y_target, (X_val, y_val);
                             verbosity=verbose ? 1 : -1,
                             is_row_major=false,
                             weights=Float32[],
                             init_score=Float64[],
                             group=Int64[],
                             truncate_booster=false)
            else
                LightGBM.fit!(estimator, X_train, y_target;
                             verbosity=verbose ? 1 : -1,
                             is_row_major=false,
                             weights=Float32[],
                             init_score=Float64[],
                             group=Int64[],
                             truncate_booster=false)
            end
            
            # Call callbacks for target completion
            for callback in callbacks
                target_name = "$(model.name)_target_$(target_idx)"
                info = create_callback_info(target_name, target_idx, n_targets, model.params["n_estimators"], model.params["n_estimators"], start_time)
                call_callback!(callback, info)
            end
            
            push!(models, estimator)
        end
        
        model.model = models
        return model
    else
        # Single-target training
        # Call callbacks for training start
        for callback in callbacks
            info = create_callback_info(model.name, 0, 1, 0, model.params["n_estimators"], start_time)
            call_callback!(callback, info)
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
        
        # Call callbacks for training completion
        for callback in callbacks
            info = create_callback_info(model.name, 1, 1, model.params["n_estimators"], model.params["n_estimators"], start_time)
            call_callback!(callback, info)
        end
        
        model.model = estimator
        
        return model
    end
end

function train!(model::EvoTreesModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false,
               callbacks::Vector{TrainingCallback}=TrainingCallback[])
    
    # Detect multi-target case and set up appropriate parameters
    is_multitarget = y_train isa Matrix{Float64}
    n_targets = is_multitarget ? size(y_train, 2) : 1
    
    if is_multitarget
        @info "Training EvoTrees with multi-target support (using multiple single-target models)" n_targets=n_targets model_name=model.name
        # EvoTrees doesn't natively support multi-target regression, so we'll train multiple models
        # Store target information for later use in prediction
        model.params["n_targets"] = n_targets
    else
        @info "Training EvoTrees with single-target" model_name=model.name
        # Remove multi-target parameters if they exist
        if haskey(model.params, "n_targets")
            delete!(model.params, "n_targets")
        end
    end
    
    # Initialize callback tracking
    start_time = time()
    
    # Add default logging callback if verbose and no callbacks provided
    if verbose && isempty(callbacks)
        push!(callbacks, create_logging_callback(frequency=max(1, model.params["nrounds"] ÷ 10)))
    end
    
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
    
    if is_multitarget
        # For multi-target, train separate models for each target
        models = EvoTrees.EvoTree[]
        
        for target_idx in 1:n_targets
            @info "Training EvoTrees model for target $target_idx/$n_targets"
            
            # Call callbacks for target start
            for callback in callbacks
                target_name = "$(model.name)_target_$(target_idx)"
                info = create_callback_info(target_name, 0, n_targets, target_idx, n_targets, start_time)
                call_callback!(callback, info)
            end
            
            y_target = y_train[:, target_idx]
            
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
            
            # Train model for this target with appropriate validation data
            target_model = if X_val !== nothing && y_val isa Matrix{Float64}
                y_val_target = y_val[:, target_idx]
                EvoTrees.fit_evotree(config; 
                                    x_train=X_train, 
                                    y_train=y_target,
                                    x_eval=X_val,
                                    y_eval=y_val_target,
                                    print_every_n=100)  # Print progress every 100 iterations
            elseif X_val !== nothing && y_val isa Vector{Float64} && target_idx == 1
                # Use single-target validation for first target only
                EvoTrees.fit_evotree(config; 
                                    x_train=X_train, 
                                    y_train=y_target,
                                    x_eval=X_val,
                                    y_eval=y_val,
                                    print_every_n=100)  # Print progress every 100 iterations
            else
                EvoTrees.fit_evotree(config; 
                                    x_train=X_train, 
                                    y_train=y_target,
                                    print_every_n=100)  # Print progress every 100 iterations
            end
            
            # Call callbacks for target completion
            for callback in callbacks
                target_name = "$(model.name)_target_$(target_idx)"
                info = create_callback_info(target_name, target_idx, n_targets, model.params["nrounds"], model.params["nrounds"], start_time)
                call_callback!(callback, info)
            end
            
            push!(models, target_model)
        end
        
        model.model = models
        return model
    else
        # Single-target training
        # Call callbacks for training start
        for callback in callbacks
            info = create_callback_info(model.name, 0, 1, 0, model.params["nrounds"], start_time)
            call_callback!(callback, info)
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
            early_stopping_rounds=model.params["early_stopping_rounds"],
            nbins=model.params["nbins"],
            monotone_constraints=model.params["monotone_constraints"],
            device=model.params["device"]
        )
        
        # Train the model
        if X_val !== nothing && y_val !== nothing
            # Train with validation set and early stopping enabled
            model.model = EvoTrees.fit_evotree(config; 
                                              x_train=X_train, 
                                              y_train=y_train,
                                              x_eval=X_val,
                                              y_eval=y_val,
                                              print_every_n=100)  # Print progress every 100 iterations
        else
            # Train without validation set
            model.model = EvoTrees.fit_evotree(config; 
                                              x_train=X_train, 
                                              y_train=y_train,
                                              print_every_n=100)  # Print progress every 100 iterations
        end
        
        # Call callbacks for training completion
        for callback in callbacks
            info = create_callback_info(model.name, 1, 1, model.params["nrounds"], model.params["nrounds"], start_time)
            call_callback!(callback, info)
        end
        
        return model
    end
end

function train!(model::CatBoostModel, X_train::Matrix{Float64}, y_train::Union{Vector{Float64}, Matrix{Float64}};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}, Matrix{Float64}}=nothing,
               feature_names::Union{Nothing, Vector{String}}=nothing,
               feature_groups::Union{Nothing, Dict{String, Vector{String}}}=nothing,
               verbose::Bool=false,
               callbacks::Vector{TrainingCallback}=TrainingCallback[])
    
    # Detect multi-target case and set up appropriate parameters
    is_multitarget = y_train isa Matrix{Float64}
    n_targets = is_multitarget ? size(y_train, 2) : 1
    
    # Store number of features for later use in feature importance
    model.params["n_features"] = size(X_train, 2)
    
    if is_multitarget
        @info "Training CatBoost with multi-target support (using multiple single-target models)" n_targets=n_targets model_name=model.name
        # CatBoost doesn't natively support multi-target regression, so we'll train multiple models
        # Store target information for later use in prediction
        model.params["n_targets"] = n_targets
    else
        @info "Training CatBoost with single-target" model_name=model.name
        # Remove multi-target parameters if they exist
        if haskey(model.params, "n_targets")
            delete!(model.params, "n_targets")
        end
    end
    
    # Initialize callback tracking
    start_time = time()
    
    # Add default logging callback if verbose and no callbacks provided
    if verbose && isempty(callbacks)
        push!(callbacks, create_logging_callback(frequency=max(1, model.params["iterations"] ÷ 10)))
    end
    
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
    
    if is_multitarget
        # For multi-target, train separate models for each target
        models = Any[]
        
        for target_idx in 1:n_targets
            @info "Training CatBoost model for target $target_idx/$n_targets"
            y_target = y_train[:, target_idx]
            
            # Create CatBoost pool for this target (convert to numpy arrays)
            np = CatBoost.pyimport("numpy")
            X_train_np = np.array(X_train)
            y_target_np = np.array(y_target)
            cat_features_np = np.array(cat_features)
            train_pool = CatBoost.Pool(X_train_np; label=y_target_np, cat_features=cat_features_np)
            
            # Create validation pool for this target if provided
            eval_pool = nothing
            if X_val !== nothing && y_val isa Matrix{Float64}
                y_val_target = y_val[:, target_idx]
                X_val_np = np.array(X_val)
                y_val_target_np = np.array(y_val_target)
                eval_pool = CatBoost.Pool(X_val_np; label=y_val_target_np, cat_features=cat_features_np)
            elseif X_val !== nothing && y_val isa Vector{Float64} && target_idx == 1
                # Use single-target validation for first target only
                X_val_np = np.array(X_val)
                y_val_np = np.array(y_val)
                eval_pool = CatBoost.Pool(X_val_np; label=y_val_np, cat_features=cat_features_np)
            end
            
            # Configure CatBoost parameters for this target
            catboost_params = Dict{String, Any}(
                "loss_function" => model.params["loss_function"],
                "depth" => model.params["depth"],
                "learning_rate" => model.params["learning_rate"],
                "iterations" => model.params["iterations"],
                "l2_leaf_reg" => model.params["l2_leaf_reg"],
                "bagging_temperature" => model.params["bagging_temperature"],
                "subsample" => model.params["subsample"],
                "colsample_bylevel" => model.params["colsample_bylevel"],
                "random_strength" => model.params["random_strength"],
                "thread_count" => model.params["thread_count"],
                "verbose" => verbose,
                "random_seed" => model.params["random_seed"]
            )
            
            # Train model for this target
            target_model = CatBoost.CatBoostRegressor(
                loss_function=catboost_params["loss_function"],
                depth=catboost_params["depth"],
                learning_rate=catboost_params["learning_rate"],
                iterations=catboost_params["iterations"],
                l2_leaf_reg=catboost_params["l2_leaf_reg"],
                bagging_temperature=catboost_params["bagging_temperature"],
                subsample=catboost_params["subsample"],
                colsample_bylevel=catboost_params["colsample_bylevel"],
                random_strength=catboost_params["random_strength"],
                thread_count=catboost_params["thread_count"],
                verbose=catboost_params["verbose"],
                random_seed=catboost_params["random_seed"]
            )
            
            if eval_pool !== nothing
                CatBoost.fit!(target_model, train_pool; eval_set=eval_pool, verbose=verbose)
            else
                CatBoost.fit!(target_model, train_pool; verbose=verbose)
            end
            
            push!(models, target_model)
        end
        
        model.model = models
        return model
    else
        # Single-target training
        # Create CatBoost pool (convert to numpy arrays)
        np = CatBoost.pyimport("numpy")
        X_train_np = np.array(X_train)
        y_train_np = np.array(y_train)
        cat_features_np = np.array(cat_features)
        train_pool = CatBoost.Pool(X_train_np; label=y_train_np, cat_features=cat_features_np)
        
        # Create validation pool if provided
        eval_pool = nothing
        if X_val !== nothing && y_val !== nothing
            X_val_np = np.array(X_val)
            y_val_np = np.array(y_val)
            eval_pool = CatBoost.Pool(X_val_np; label=y_val_np, cat_features=cat_features_np)
        end
        
        # Configure CatBoost parameters
        catboost_params = Dict{String, Any}(
            "loss_function" => model.params["loss_function"],
            "depth" => model.params["depth"],
            "learning_rate" => model.params["learning_rate"],
            "iterations" => model.params["iterations"],
            "l2_leaf_reg" => model.params["l2_leaf_reg"],
            "bagging_temperature" => model.params["bagging_temperature"],
            "subsample" => model.params["subsample"],
            "colsample_bylevel" => model.params["colsample_bylevel"],
            "random_strength" => model.params["random_strength"],
            "thread_count" => model.params["thread_count"],
            "verbose" => verbose,
            "random_seed" => model.params["random_seed"]
        )
        
        # Train the model
        model.model = CatBoost.CatBoostRegressor(
            loss_function=catboost_params["loss_function"],
            depth=catboost_params["depth"],
            learning_rate=catboost_params["learning_rate"],
            iterations=catboost_params["iterations"],
            l2_leaf_reg=catboost_params["l2_leaf_reg"],
            bagging_temperature=catboost_params["bagging_temperature"],
            subsample=catboost_params["subsample"],
            colsample_bylevel=catboost_params["colsample_bylevel"],
            random_strength=catboost_params["random_strength"],
            thread_count=catboost_params["thread_count"],
            verbose=catboost_params["verbose"],
            random_seed=catboost_params["random_seed"]
        )
        
        if eval_pool !== nothing
            CatBoost.fit!(model.model, train_pool; eval_set=eval_pool, verbose=verbose)
        else
            CatBoost.fit!(model.model, train_pool; verbose=verbose)
        end
        
        return model
    end
end

function predict(model::XGBoostModel, X::Matrix{Float64})::Union{Vector{Float64}, Matrix{Float64}}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{Booster}
        n_targets = model.params["n_targets"]
        n_samples = size(X, 1)
        predictions_matrix = Matrix{Float64}(undef, n_samples, n_targets)
        
        dtest = DMatrix(X)
        
        # Get predictions from each target model
        for (target_idx, target_model) in enumerate(model.model)
            target_predictions = XGBoost.predict(target_model, dtest)
            predictions_matrix[:, target_idx] = convert(Vector{Float64}, target_predictions)
        end
        
        return predictions_matrix
    else
        # Single-target prediction
        dtest = DMatrix(X)
        predictions = XGBoost.predict(model.model, dtest)
        return convert(Vector{Float64}, predictions)
    end
end

function predict(model::LightGBMModel, X::Matrix{Float64})::Union{Vector{Float64}, Matrix{Float64}}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{LGBMRegression}
        n_targets = model.params["n_targets"]
        n_samples = size(X, 1)
        predictions_matrix = Matrix{Float64}(undef, n_samples, n_targets)
        
        # Get predictions from each target model
        for (target_idx, target_model) in enumerate(model.model)
            target_predictions = LightGBM.predict(target_model, X)
            
            # Convert to Vector if it's a Matrix (LightGBM.jl v2.0.0 sometimes returns Matrix)
            if target_predictions isa Matrix
                predictions_matrix[:, target_idx] = vec(target_predictions)
            else
                predictions_matrix[:, target_idx] = target_predictions
            end
        end
        
        return predictions_matrix
    else
        # Single-target prediction
        predictions = LightGBM.predict(model.model, X)
        
        # Convert to Vector if it's a Matrix (LightGBM.jl v2.0.0 sometimes returns Matrix)
        if predictions isa Matrix
            return vec(predictions)
        else
            return predictions
        end
    end
end

function predict(model::EvoTreesModel, X::Matrix{Float64})::Union{Vector{Float64}, Matrix{Float64}}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{EvoTrees.EvoTree}
        n_targets = model.params["n_targets"]
        n_samples = size(X, 1)
        predictions_matrix = Matrix{Float64}(undef, n_samples, n_targets)
        
        # Get predictions from each target model
        for (target_idx, target_model) in enumerate(model.model)
            target_predictions = EvoTrees.predict(target_model, X)
            
            # Convert to Vector if it's a Matrix and ensure Float64
            if target_predictions isa Matrix
                predictions_matrix[:, target_idx] = convert(Vector{Float64}, vec(target_predictions))
            else
                predictions_matrix[:, target_idx] = convert(Vector{Float64}, target_predictions)
            end
        end
        
        return predictions_matrix
    else
        # Single-target prediction
        predictions = EvoTrees.predict(model.model, X)
        
        # Convert to Vector if it's a Matrix and ensure Float64
        if predictions isa Matrix
            return convert(Vector{Float64}, vec(predictions))
        else
            return convert(Vector{Float64}, predictions)
        end
    end
end

function predict(model::CatBoostModel, X::Matrix{Float64})::Union{Vector{Float64}, Matrix{Float64}}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{Any}
        n_targets = model.params["n_targets"]
        n_samples = size(X, 1)
        predictions_matrix = Matrix{Float64}(undef, n_samples, n_targets)
        
        # Get predictions from each target model
        for (target_idx, target_model) in enumerate(model.model)
            # Create a pool for prediction (convert to numpy array)
            np = CatBoost.pyimport("numpy")
            X_np = np.array(X)
            test_pool = CatBoost.Pool(X_np)
            
            # Get predictions from this target model
            target_predictions = CatBoost.predict(target_model, test_pool)
            
            # Ensure predictions are a Vector and convert to Float64
            if target_predictions isa Matrix
                predictions_matrix[:, target_idx] = convert(Vector{Float64}, vec(target_predictions))
            else
                predictions_matrix[:, target_idx] = convert(Vector{Float64}, target_predictions)
            end
        end
        
        return predictions_matrix
    else
        # Single-target prediction
        # Create a pool for prediction (convert to numpy array)
        np = CatBoost.pyimport("numpy")
        X_np = np.array(X)
        test_pool = CatBoost.Pool(X_np)
        
        # Get predictions
        predictions = CatBoost.predict(model.model, test_pool)
        
        # Ensure predictions are a Vector
        if predictions isa Matrix
            return convert(Vector{Float64}, vec(predictions))
        else
            return convert(Vector{Float64}, predictions)
        end
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
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector
        # For multi-target, average feature importance across all target models
        n_targets = length(model.model)
        
        # Get importance from first model to initialize
        first_importance = XGBoost.importance(model.model[1])
        
        # Initialize accumulator with first model's importance
        feature_dict = Dict{String, Float64}()
        for (feature_name, importance_value) in first_importance
            feature_dict[feature_name] = importance_value
        end
        
        # Add importance from other target models
        for i in 2:n_targets
            target_importance = XGBoost.importance(model.model[i])
            for (feature_name, importance_value) in target_importance
                if haskey(feature_dict, feature_name)
                    feature_dict[feature_name] += importance_value
                else
                    feature_dict[feature_name] = importance_value
                end
            end
        end
        
        # Average the importance scores
        for feature_name in keys(feature_dict)
            feature_dict[feature_name] /= n_targets
        end
        
        # Normalize to sum to 1
        total_importance = sum(values(feature_dict))
        if total_importance > 0
            for feature_name in keys(feature_dict)
                feature_dict[feature_name] /= total_importance
            end
        end
        
        return feature_dict
    else
        # Single-target case
        importance = XGBoost.importance(model.model)
        return importance
    end
end

function feature_importance(model::LightGBMModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{LGBMRegression}
        # For multi-target, average feature importance across all target models
        n_targets = length(model.model)
        
        # Get feature names from first model's booster
        feature_names = try
            LightGBM.LGBM_BoosterGetFeatureNames(model.model[1].booster)
        catch
            # Fallback to generic feature names if booster feature names are not available
            n_features = length(LightGBM.gain_importance(model.model[1]))
            ["feature_$i" for i in 1:n_features]
        end
        
        n_features = length(feature_names)
        
        # Initialize importance accumulator
        total_importance = zeros(Float64, n_features)
        
        # Sum importance across all target models
        for target_model in model.model
            target_importance = LightGBM.gain_importance(target_model)
            total_importance .+= target_importance
        end
        
        # Average the importance
        avg_importance = total_importance ./ n_targets
        
        return Dict(zip(feature_names, avg_importance))
    else
        # Single-target model
        importance = LightGBM.gain_importance(model.model)
        
        # Get feature names from booster
        feature_names = try
            LightGBM.LGBM_BoosterGetFeatureNames(model.model.booster)
        catch
            # Fallback to generic feature names if booster feature names are not available
            n_features = length(importance)
            ["feature_$i" for i in 1:n_features]
        end
        
        return Dict(zip(feature_names, importance))
    end
end

function feature_importance(model::EvoTreesModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{EvoTrees.EvoTree}
        # For multi-target, average feature importance across all target models
        n_targets = length(model.model)
        
        # Get importance from first model to determine format and size
        first_importance = EvoTrees.importance(model.model[1])
        
        # EvoTrees.importance returns a Vector{Pair{Symbol, Float64}}
        # Convert to dictionary and sum across targets
        feature_dict = Dict{String, Float64}()
        
        # Initialize feature dictionary with all features from first model
        for (feature_name, importance_value) in first_importance
            feature_dict[string(feature_name)] = importance_value
        end
        
        # Add importance from other target models
        for i in 2:n_targets
            target_importance = EvoTrees.importance(model.model[i])
            for (feature_name, importance_value) in target_importance
                feature_key = string(feature_name)
                if haskey(feature_dict, feature_key)
                    feature_dict[feature_key] += importance_value
                else
                    feature_dict[feature_key] = importance_value
                end
            end
        end
        
        # Average the importance
        for (feature_key, total_importance) in feature_dict
            feature_dict[feature_key] = total_importance / n_targets
        end
        
        return feature_dict
    else
        # Single-target model
        importance = EvoTrees.importance(model.model)
        
        # Convert importance to dictionary with feature names
        feature_dict = Dict{String, Float64}()
        for (feature_name, importance_value) in importance
            feature_dict[string(feature_name)] = importance_value
        end
        
        return feature_dict
    end
end

function feature_importance(model::CatBoostModel)::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Check if this is a multi-target model
    is_multitarget = haskey(model.params, "n_targets") && model.params["n_targets"] > 1
    
    if is_multitarget && model.model isa Vector{Any}
        # For multi-target, average feature importance across all target models
        n_targets = length(model.model)
        feature_dict = Dict{String, Float64}()
        
        for (target_idx, target_model) in enumerate(model.model)
            try
                # Get feature importance for this target model
                py_importance = target_model.get_feature_importance()
                importance_array = collect(py_importance)
                
                # Add to accumulated importance
                for i in 1:length(importance_array)
                    feature_key = "feature_$(i)"
                    if haskey(feature_dict, feature_key)
                        feature_dict[feature_key] += importance_array[i]
                    else
                        feature_dict[feature_key] = importance_array[i]
                    end
                end
            catch e
                @warn "Failed to get CatBoost feature importance for target $target_idx" error=e
                # Use uniform importance for this target as fallback
                n_features = 100  # Default assumption
                for i in 1:n_features
                    feature_key = "feature_$(i)"
                    if haskey(feature_dict, feature_key)
                        feature_dict[feature_key] += 1.0 / n_features
                    else
                        feature_dict[feature_key] = 1.0 / n_features
                    end
                end
            end
        end
        
        # Average the importance across all targets
        for (feature_key, total_importance) in feature_dict
            feature_dict[feature_key] = total_importance / n_targets
        end
        
        return feature_dict
    else
        # Single-target model
        try
            # CatBoost.jl wraps Python's CatBoost, so we need to use Python methods
            # Get feature importance using the Python method
            py_importance = model.model.get_feature_importance()
            
            # Convert to Julia array if needed
            importance_array = collect(py_importance)
            
            # Create dictionary with feature names
            feature_dict = Dict{String, Float64}()
            for i in 1:length(importance_array)
                feature_dict["feature_$(i)"] = importance_array[i]
            end
            
            return feature_dict
        catch e
            @warn "Failed to get CatBoost feature importance, using uniform importance" error=e
            # Fallback: return uniform importance if the method is not available
            # Get number of features from model parameters if available, otherwise use default
            n_features = get(model.params, "n_features", 100)  # Use stored feature count or default to 100
            feature_dict = Dict{String, Float64}()
            for i in 1:n_features
                feature_dict["feature_$(i)"] = 1.0 / n_features
            end
            return feature_dict
        end
    end
end

function save_model(model::NumeraiModel, filepath::String)
    if model.model === nothing
        error("Model not trained yet")
    end
    
    if model isa XGBoostModel
        if model.model isa Vector{Booster}
            # Multi-target XGBoost: save each model with suffix
            for (i, target_model) in enumerate(model.model)
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                XGBoost.save(target_model, target_path)
            end
            # Save metadata about multi-target structure
            metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
            open(metadata_path, "w") do f
                write(f, JSON3.write(Dict("n_targets" => length(model.model), "type" => "XGBoost")))
            end
        else
            XGBoost.save(model.model, filepath)
        end
    elseif model isa LightGBMModel
        if model.model isa Vector{LGBMRegression}
            # Multi-target LightGBM: save each model with suffix
            for (i, target_model) in enumerate(model.model)
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                LightGBM.savemodel(target_model, target_path)
            end
            # Save metadata about multi-target structure
            metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
            open(metadata_path, "w") do f
                write(f, JSON3.write(Dict("n_targets" => length(model.model), "type" => "LightGBM")))
            end
        else
            LightGBM.savemodel(model.model, filepath)
        end
    elseif model isa EvoTreesModel
        if model.model isa Vector{EvoTrees.EvoTree}
            # Multi-target EvoTrees: save each model with suffix
            for (i, target_model) in enumerate(model.model)
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                EvoTrees.save(target_model, target_path)
            end
            # Save metadata about multi-target structure
            metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
            open(metadata_path, "w") do f
                write(f, JSON3.write(Dict("n_targets" => length(model.model), "type" => "EvoTrees")))
            end
        else
            EvoTrees.save(model.model, filepath)
        end
    elseif model isa CatBoostModel
        if model.model isa Vector{Any}
            # Multi-target CatBoost: save each model with suffix
            for (i, target_model) in enumerate(model.model)
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                target_model.save_model(target_path)
            end
            # Save metadata about multi-target structure
            metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
            open(metadata_path, "w") do f
                write(f, JSON3.write(Dict("n_targets" => length(model.model), "type" => "CatBoost")))
            end
        else
            model.model.save_model(filepath)
        end
    end
    
    println("Model saved to $filepath")
end

function load_model!(model::XGBoostModel, filepath::String)
    # Check if this is a multi-target model by looking for metadata file
    metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
    if isfile(metadata_path)
        metadata = JSON3.read(read(metadata_path, String))
        if haskey(metadata, "n_targets") && metadata["n_targets"] > 1
            # Load multi-target models
            n_targets = metadata["n_targets"]
            models = Booster[]
            for i in 1:n_targets
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                push!(models, Booster(model_file=target_path))
            end
            model.model = models
            model.params["n_targets"] = n_targets
        else
            model.model = Booster(model_file=filepath)
        end
    else
        model.model = Booster(model_file=filepath)
    end
    return model
end

function load_model!(model::LightGBMModel, filepath::String)
    # Check if this is a multi-target model by looking for metadata file
    metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
    if isfile(metadata_path)
        metadata = JSON3.read(read(metadata_path, String))
        if haskey(metadata, "n_targets") && metadata["n_targets"] > 1
            # Load multi-target models
            n_targets = metadata["n_targets"]
            models = LGBMRegression[]
            for i in 1:n_targets
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                target_model = LGBMRegression()
                LightGBM.loadmodel!(target_model, target_path)
                push!(models, target_model)
            end
            model.model = models
            model.params["n_targets"] = n_targets
        else
            model.model = LGBMRegression()
            LightGBM.loadmodel!(model.model, filepath)
        end
    else
        model.model = LGBMRegression()
        LightGBM.loadmodel!(model.model, filepath)
    end
    return model
end

function load_model!(model::EvoTreesModel, filepath::String)
    # Check if this is a multi-target model by looking for metadata file
    metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
    if isfile(metadata_path)
        metadata = JSON3.read(read(metadata_path, String))
        if haskey(metadata, "n_targets") && metadata["n_targets"] > 1
            # Load multi-target models
            n_targets = metadata["n_targets"]
            models = EvoTrees.EvoTree[]
            for i in 1:n_targets
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                push!(models, EvoTrees.load(target_path))
            end
            model.model = models
            model.params["n_targets"] = n_targets
        else
            model.model = EvoTrees.load(filepath)
        end
    else
        model.model = EvoTrees.load(filepath)
    end
    return model
end

function load_model!(model::CatBoostModel, filepath::String)
    # Check if this is a multi-target model by looking for metadata file
    metadata_path = replace(filepath, r"(\.[^.]*$)" => "_metadata.json")
    if isfile(metadata_path)
        metadata = JSON3.read(read(metadata_path, String))
        if haskey(metadata, "n_targets") && metadata["n_targets"] > 1
            # Load multi-target models
            n_targets = metadata["n_targets"]
            models = Any[]
            for i in 1:n_targets
                target_path = replace(filepath, r"(\.[^.]*$)" => "_target$(i)\\1")
                target_model = CatBoost.CatBoostRegressor()
                target_model.load_model(target_path)
                push!(models, target_model)
            end
            model.model = models
            model.params["n_targets"] = n_targets
        else
            model.model = CatBoost.CatBoostRegressor()
            model.model.load_model(filepath)
        end
    else
        model.model = CatBoost.CatBoostRegressor()
        model.model.load_model(filepath)
    end
    return model
end

"""
GPU-accelerated ensemble prediction combining multiple models
"""
function ensemble_predict(models::Vector{<:NumeraiModel}, X::Matrix{Float64}, 
                         weights::Union{Nothing, Vector{Float64}}=nothing)::Union{Vector{Float64}, Matrix{Float64}}
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
    
    # First, get a sample prediction to determine output format
    first_prediction = predict(models[1], X)
    is_multitarget = first_prediction isa Matrix{Float64}
    
    if is_multitarget
        n_targets = size(first_prediction, 2)
        @info "Computing multi-target ensemble predictions" n_targets=n_targets
        
        # For multi-target, collect predictions in 3D array: (samples, targets, models)
        predictions_tensor = Array{Float64}(undef, n_samples, n_targets, n_models)
        predictions_tensor[:, :, 1] = first_prediction
        
        for i in 2:n_models
            model_pred = predict(models[i], X)
            if model_pred isa Matrix{Float64}
                predictions_tensor[:, :, i] = model_pred
            else
                # If a model returns single-target, use only the first target
                @warn "Model $(i) returned single-target prediction in multi-target ensemble, using first target only"
                predictions_tensor[:, 1, i] = model_pred
                predictions_tensor[:, 2:end, i] .= 0.0  # Zero out other targets
            end
        end
        
        # Compute weighted average across models for each target
        ensemble_predictions = zeros(Float64, n_samples, n_targets)
        for t in 1:n_targets
            ensemble_predictions[:, t] = predictions_tensor[:, t, :] * weights
        end
    else
        @info "Computing single-target ensemble predictions"
        
        # For single-target, collect predictions in matrix: (samples, models)
        predictions_matrix = Matrix{Float64}(undef, n_samples, n_models)
        predictions_matrix[:, 1] = first_prediction
        
        for i in 2:n_models
            model_pred = predict(models[i], X)
            if model_pred isa Matrix{Float64}
                # If a model returns multi-target, use only the first target
                @warn "Model $(i) returned multi-target prediction in single-target ensemble, using first target only"
                predictions_matrix[:, i] = model_pred[:, 1]
            else
                predictions_matrix[:, i] = model_pred
            end
        end
        
        ensemble_predictions = predictions_matrix * weights
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

# Convenience function for creating models with string type and keyword arguments
function create_model(model_type::String, name::String; kwargs...)
    params = Dict{Symbol,Any}(:name => name)
    for (k, v) in kwargs
        params[k] = v
    end
    return create_model(Symbol(model_type), params)
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
        return LinearModels.RidgeModel(name; model_params...)
    elseif model_type == :Lasso
        return LinearModels.LassoModel(name; model_params...)
    elseif model_type == :ElasticNet
        return LinearModels.ElasticNetModel(name; model_params...)
    elseif model_type == :NeuralNetwork || model_type == :MLP
        # Try to access NeuralNetworks from parent module
        parent_module = parentmodule(@__MODULE__)
        if isdefined(parent_module, :NeuralNetworks)
            nn_module = getfield(parent_module, :NeuralNetworks)
            return nn_module.MLPModel(name; model_params...)
        else
            error("Neural networks not available. MLPModel requires the NeuralNetworks module to be loaded at the main module level.")
        end
    elseif model_type == :ResNet
        # Try to access NeuralNetworks from parent module
        parent_module = parentmodule(@__MODULE__)
        if isdefined(parent_module, :NeuralNetworks)
            nn_module = getfield(parent_module, :NeuralNetworks)
            return nn_module.ResNetModel(name; model_params...)
        else
            error("Neural networks not available. ResNetModel requires the NeuralNetworks module to be loaded at the main module level.")
        end
    else
        error("Unknown model type: $model_type")
    end
end

# Convenience function for creating models with just a type symbol
function create_model(model_type::Symbol)
    return create_model(model_type, Dict{Symbol,Any}())
end

export NumeraiModel, XGBoostModel, LightGBMModel, EvoTreesModel, CatBoostModel, train!, predict, 
       cross_validate, feature_importance, save_model, load_model!,
       ensemble_predict, gpu_feature_selection_for_models, benchmark_model_performance,
       get_models_gpu_status, create_model
       
# Export callback functionality
export Callbacks

# Include linear models
include("linear_models.jl")
using .LinearModels: RidgeModel, LassoModel, ElasticNetModel
export RidgeModel, LassoModel, ElasticNetModel

# Forward train! and predict for linear models
train!(model::Union{RidgeModel, LassoModel, ElasticNetModel}, args...; kwargs...) = LinearModels.train!(model, args...; kwargs...)
predict(model::Union{RidgeModel, LassoModel, ElasticNetModel}, args...; kwargs...) = LinearModels.predict(model, args...; kwargs...)
feature_importance(model::Union{RidgeModel, LassoModel, ElasticNetModel}) = LinearModels.feature_importance(model)
save_model(model::Union{RidgeModel, LassoModel, ElasticNetModel}, filepath::String) = LinearModels.save_model(model, filepath)
load_model!(model::Union{RidgeModel, LassoModel, ElasticNetModel}, filepath::String) = LinearModels.load_model!(model, filepath)

# Neural networks are included separately at main module level to avoid dependency issues
# Exports are handled there

end