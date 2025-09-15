module Pipeline

using DataFrames
using Statistics
using ProgressMeter
using JLD2
using ..DataLoader
using ..Preprocessor
using ..Models
using ..Models: RidgeModel, LassoModel, ElasticNetModel
using ..Models.Callbacks
using ..NeuralNetworks: MLPModel, ResNetModel
using ..Ensemble
using ..Neutralization
using ..Metrics
using ..HyperOpt
using Flux: relu  # Import relu activation function from Flux

# Helper function to resolve features from groups
function resolve_features_from_groups(
    feature_cols::Union{Vector{String}, Nothing},
    feature_groups::Union{Dict{String, Vector{String}}, Nothing},
    features_metadata::Union{Dict{String, Any}, Nothing},
    group_names::Union{Vector{String}, Nothing}
)::Vector{String}
    
    # Case 1: feature_cols provided - use directly (backward compatibility)
    if feature_cols !== nothing
        return feature_cols
    end
    
    # Case 2: group_names provided with feature_groups
    if group_names !== nothing && feature_groups !== nothing
        resolved_features = String[]
        for group_name in group_names
            if haskey(feature_groups, group_name)
                append!(resolved_features, feature_groups[group_name])
            else
                @warn "Group '$group_name' not found in feature_groups"
            end
        end
        return unique(resolved_features)
    end
    
    # Case 3: group_names provided with features_metadata (parse groups first)
    if group_names !== nothing && features_metadata !== nothing
        parsed_groups = DataLoader.get_feature_groups(features_metadata)
        resolved_features = String[]
        for group_name in group_names
            if haskey(parsed_groups, group_name)
                append!(resolved_features, parsed_groups[group_name])
            else
                @warn "Group '$group_name' not found in features metadata"
            end
        end
        return unique(resolved_features)
    end
    
    # Case 4: No valid feature specification
    error("Must provide either 'feature_cols', or 'group_names' with 'feature_groups'/'features_metadata'")
end

# Configuration struct for model creation
struct ModelConfig
    type::String  # "xgboost", "lightgbm", "evotrees", "mlp", "resnet"
    name::String  # Optional model name
    params::Dict{Symbol, Any}  # Model-specific parameters
    
    function ModelConfig(type::String, params::Dict=Dict(); name::String="")
        if name == ""
            name = "$(type)_model_$(rand(1000:9999))"
        end
        new(lowercase(type), name, params)
    end
end

mutable struct MLPipeline
    config::Dict{Symbol, Any}
    model::Models.NumeraiModel
    model_config::ModelConfig  # Store configuration
    feature_cols::Vector{String}
    target_cols::Vector{String}  # Support multiple targets
    target_mode::Symbol  # :single or :multi
    multi_target_models::Union{Nothing, Dict{String, Models.NumeraiModel}}  # Single model per target for multi-target mode
    # Feature groups support
    feature_groups::Union{Nothing, Dict{String, Vector{String}}}
    features_metadata::Union{Nothing, Dict{String, Any}}
    # Multi-target support flags
    is_multi_target::Bool
    n_targets::Int
    # Ensemble support
    models::Vector{Models.NumeraiModel}  # Collection of models for ensemble
    ensemble::Union{Nothing, Ensemble.ModelEnsemble}  # Ensemble wrapper
end

function MLPipeline(;
    feature_cols::Union{Vector{String}, Nothing}=nothing,
    target_col::Union{String, Vector{String}, Nothing}=nothing,
    target_cols::Union{Vector{String}, Nothing}=nothing,
    neutralize::Bool=true,
    neutralize_proportion::Float64=0.5,
    model::Union{Models.NumeraiModel, Nothing}=nothing,
    model_config::Union{ModelConfig, Nothing}=nothing,
    # Backward compatibility: accept old model_configs parameter
    model_configs::Union{Vector{ModelConfig}, Nothing}=nothing,
    # Feature groups parameters
    feature_groups::Union{Dict{String, Vector{String}}, Nothing}=nothing,
    features_metadata::Union{Dict{String, Any}, Nothing}=nothing,
    group_names::Union{Vector{String}, Nothing}=nothing)
    
    # Handle target specification - backward compatible
    if target_col !== nothing && target_cols !== nothing
        error("Specify either target_col or target_cols, not both")
    elseif target_col !== nothing
        # Handle both String and Vector{String} for target_col
        if target_col isa String
            target_cols_vec = [target_col]
            target_mode = :single
        else  # target_col isa Vector{String}
            target_cols_vec = target_col
            target_mode = length(target_col) == 1 ? :single : :multi
        end
    elseif target_cols !== nothing
        # Multi-target mode
        target_cols_vec = target_cols
        target_mode = length(target_cols) == 1 ? :single : :multi
    else
        # Default single target
        target_cols_vec = ["target_cyrus_v4_20"]
        target_mode = :single
    end
    
    # Determine if this is multi-target
    is_multi_target = target_mode == :multi
    n_targets = length(target_cols_vec)
    
    # Handle backward compatibility for model_configs parameter
    if model_configs !== nothing && model_config !== nothing
        error("Specify either model_config or model_configs, not both")
    elseif model_configs !== nothing && !isempty(model_configs)
        # Use first model config for backward compatibility
        model_config = model_configs[1]
        if length(model_configs) > 1
            @warn "Multiple model configs provided but only the first one will be used. Use ensemble functionality for multiple models."
        end
    end
    
    config = Dict(
        :neutralize => neutralize,
        :neutralize_proportion => neutralize_proportion,
        :clip_predictions => true,
        :normalize_predictions => true,
        :is_multi_target => is_multi_target,
        :n_targets => n_targets
    )
    
    # Create model if not provided
    if model_config !== nothing
        model = create_model_from_config(model_config)
        final_config = model_config
    elseif model !== nothing
        # Use provided model and create default config
        final_config = ModelConfig("xgboost", name=model.name)
    else
        # Default XGBoost model with max_depth=8 as specified
        final_config = ModelConfig("xgboost", 
                                 Dict(:max_depth=>8, :learning_rate=>0.01, :colsample_bytree=>0.1), 
                                 name="xgb_best")
        model = Models.XGBoostModel("xgb_best", max_depth=8, learning_rate=0.01, colsample_bytree=0.1)
    end
    
    # Resolve features from groups if needed, or use default
    if feature_cols !== nothing || feature_groups !== nothing || group_names !== nothing
        resolved_features = resolve_features_from_groups(
            feature_cols, feature_groups, features_metadata, group_names
        )
    else
        # Default features for basic testing
        resolved_features = ["feature_1", "feature_2", "feature_3"]
    end
    
    # Initialize multi_target_models based on mode
    multi_target_models = target_mode == :multi ? Dict{String, Models.NumeraiModel}() : nothing
    
    # Initialize ensemble support fields
    initial_models = Models.NumeraiModel[model]  # Start with single model
    initial_ensemble = nothing  # No ensemble initially
    
    return MLPipeline(config, model, final_config, resolved_features, target_cols_vec, 
                     target_mode, multi_target_models, feature_groups, features_metadata, 
                     is_multi_target, n_targets, initial_models, initial_ensemble)
end

# Helper function to create single model from config
function create_model_from_config(config::ModelConfig)::Models.NumeraiModel
    if config.type == "xgboost"
        return Models.XGBoostModel(
            config.name;
            max_depth=get(config.params, :max_depth, 6),
            learning_rate=get(config.params, :learning_rate, 0.01),
            num_rounds=get(config.params, :n_estimators, 100),  # Map n_estimators to num_rounds
            colsample_bytree=get(config.params, :colsample_bytree, 0.1)
            # Note: XGBoost doesn't accept subsample in constructor
        )
    elseif config.type == "lightgbm"
        return Models.LightGBMModel(
            config.name;
            num_leaves=get(config.params, :num_leaves, 31),
            learning_rate=get(config.params, :learning_rate, 0.01),
            n_estimators=get(config.params, :n_estimators, 100),
            feature_fraction=get(config.params, :feature_fraction, 0.1),
            bagging_fraction=get(config.params, :bagging_fraction, 0.8)
        )
    elseif config.type == "evotrees"
        return Models.EvoTreesModel(
            config.name;
            max_depth=get(config.params, :max_depth, 6),
            learning_rate=get(config.params, :learning_rate, 0.01),
            nrounds=get(config.params, :n_estimators, 100),  # Map n_estimators to nrounds
            colsample=get(config.params, :colsample, 0.1),
            subsample=get(config.params, :subsample, 0.8)
        )
    elseif config.type == "catboost"
        return Models.CatBoostModel(
            config.name;
            depth=get(config.params, :depth, 6),
            learning_rate=get(config.params, :learning_rate, 0.03),
            iterations=get(config.params, :iterations, 1000),
            l2_leaf_reg=get(config.params, :l2_leaf_reg, 3.0),
            bagging_temperature=get(config.params, :bagging_temperature, 1.0),
            subsample=get(config.params, :subsample, 0.8),
            colsample_bylevel=get(config.params, :colsample_bylevel, 0.8),
            random_strength=get(config.params, :random_strength, 1.0),
            gpu_enabled=get(config.params, :gpu_enabled, false)
        )
    elseif config.type == "mlp"
        return MLPModel(
            config.name;
            hidden_layers=get(config.params, :hidden_layers, [128, 64, 32]),
            dropout_rate=get(config.params, :dropout_rate, 0.2),
            learning_rate=get(config.params, :learning_rate, 0.001),
            batch_size=get(config.params, :batch_size, 512),
            epochs=get(config.params, :epochs, 100),
            early_stopping_patience=get(config.params, :early_stopping_patience, 10),
            gpu_enabled=get(config.params, :gpu_enabled, true)
        )
    elseif config.type == "resnet"
        return ResNetModel(
            config.name;
            hidden_layers=get(config.params, :hidden_layers, [256, 256, 256, 128]),
            dropout_rate=get(config.params, :dropout_rate, 0.1),
            learning_rate=get(config.params, :learning_rate, 0.001),
            batch_size=get(config.params, :batch_size, 512),
            epochs=get(config.params, :epochs, 150),
            early_stopping_patience=get(config.params, :early_stopping_patience, 15),
            gpu_enabled=get(config.params, :gpu_enabled, true)
        )
    elseif config.type == "ridge"
        return RidgeModel(
            config.name;
            alpha=get(config.params, :alpha, 1.0),
            fit_intercept=get(config.params, :fit_intercept, true),
            max_iter=get(config.params, :max_iter, 1000),
            tol=get(config.params, :tol, 1e-4)
        )
    elseif config.type == "lasso"
        return LassoModel(
            config.name;
            alpha=get(config.params, :alpha, 1.0),
            fit_intercept=get(config.params, :fit_intercept, true),
            max_iter=get(config.params, :max_iter, 1000),
            tol=get(config.params, :tol, 1e-4)
        )
    elseif config.type == "elasticnet"
        return ElasticNetModel(
            config.name;
            alpha=get(config.params, :alpha, 1.0),
            l1_ratio=get(config.params, :l1_ratio, 0.5),
            fit_intercept=get(config.params, :fit_intercept, true),
            max_iter=get(config.params, :max_iter, 1000),
            tol=get(config.params, :tol, 1e-4)
        )
    else
        @warn "Unknown model type: $(config.type), falling back to XGBoost"
        return Models.XGBoostModel(config.name)
    end
end

# Helper function to create models from configs (keeping for backward compatibility)
function create_models_from_configs(configs::Vector{ModelConfig})::Vector{Models.NumeraiModel}
    models = Models.NumeraiModel[]
    
    for config in configs
        if config.type == "xgboost"
            push!(models, Models.XGBoostModel(
                config.name;
                max_depth=get(config.params, :max_depth, 6),
                learning_rate=get(config.params, :learning_rate, 0.01),
                num_rounds=get(config.params, :n_estimators, 100),  # Map n_estimators to num_rounds
                colsample_bytree=get(config.params, :colsample_bytree, 0.1)
                # Note: XGBoost doesn't accept subsample in constructor
            ))
        elseif config.type == "lightgbm"
            push!(models, Models.LightGBMModel(
                config.name;
                num_leaves=get(config.params, :num_leaves, 31),
                learning_rate=get(config.params, :learning_rate, 0.01),
                n_estimators=get(config.params, :n_estimators, 100),
                feature_fraction=get(config.params, :feature_fraction, 0.1),
                bagging_fraction=get(config.params, :bagging_fraction, 0.8)
            ))
        elseif config.type == "evotrees"
            push!(models, Models.EvoTreesModel(
                config.name;
                max_depth=get(config.params, :max_depth, 6),
                learning_rate=get(config.params, :learning_rate, 0.01),
                nrounds=get(config.params, :n_estimators, 100),  # Map n_estimators to nrounds
                colsample=get(config.params, :colsample, 0.1),
                subsample=get(config.params, :subsample, 0.8)
            ))
        elseif config.type == "catboost"
            push!(models, Models.CatBoostModel(
                config.name;
                depth=get(config.params, :depth, 6),
                learning_rate=get(config.params, :learning_rate, 0.03),
                iterations=get(config.params, :iterations, 1000),
                l2_leaf_reg=get(config.params, :l2_leaf_reg, 3.0),
                bagging_temperature=get(config.params, :bagging_temperature, 1.0),
                subsample=get(config.params, :subsample, 0.8),
                colsample_bylevel=get(config.params, :colsample_bylevel, 0.8),
                random_strength=get(config.params, :random_strength, 1.0),
                gpu_enabled=get(config.params, :gpu_enabled, false)
            ))
        elseif config.type == "mlp"
            push!(models, MLPModel(
                config.name;
                hidden_layers=get(config.params, :hidden_layers, [128, 64, 32]),
                dropout_rate=get(config.params, :dropout_rate, 0.2),
                learning_rate=get(config.params, :learning_rate, 0.001),
                batch_size=get(config.params, :batch_size, 512),
                epochs=get(config.params, :epochs, 100),
                early_stopping_patience=get(config.params, :early_stopping_patience, 10),
                gpu_enabled=get(config.params, :gpu_enabled, true)
            ))
        elseif config.type == "resnet"
            push!(models, ResNetModel(
                config.name;
                hidden_layers=get(config.params, :hidden_layers, [256, 256, 256, 128]),
                dropout_rate=get(config.params, :dropout_rate, 0.1),
                learning_rate=get(config.params, :learning_rate, 0.001),
                batch_size=get(config.params, :batch_size, 512),
                epochs=get(config.params, :epochs, 150),
                early_stopping_patience=get(config.params, :early_stopping_patience, 15),
                gpu_enabled=get(config.params, :gpu_enabled, true)
            ))
        elseif config.type == "ridge"
            push!(models, RidgeModel(
                config.name;
                alpha=get(config.params, :alpha, 1.0),
                fit_intercept=get(config.params, :fit_intercept, true),
                max_iter=get(config.params, :max_iter, 1000),
                tol=get(config.params, :tol, 1e-4)
            ))
        elseif config.type == "lasso"
            push!(models, LassoModel(
                config.name;
                alpha=get(config.params, :alpha, 1.0),
                fit_intercept=get(config.params, :fit_intercept, true),
                max_iter=get(config.params, :max_iter, 1000),
                tol=get(config.params, :tol, 1e-4)
            ))
        elseif config.type == "elasticnet"
            push!(models, ElasticNetModel(
                config.name;
                alpha=get(config.params, :alpha, 1.0),
                l1_ratio=get(config.params, :l1_ratio, 0.5),
                fit_intercept=get(config.params, :fit_intercept, true),
                max_iter=get(config.params, :max_iter, 1000),
                tol=get(config.params, :tol, 1e-4)
            ))
        else
            @warn "Unknown model type: $(config.type), skipping"
        end
    end
    
    return models
end

function prepare_data(pipeline::MLPipeline, df::DataFrame)
    feature_data = DataLoader.get_feature_columns(df, pipeline.feature_cols)
    
    feature_data = Preprocessor.fillna(feature_data, 0.5)
    
    X = Matrix{Float64}(feature_data)
    
    # Handle single vs multi-target
    if pipeline.target_mode == :single
        y = DataLoader.get_target_column(df, pipeline.target_cols[1])
        eras = Int.(df.era)
        return X, y, eras
    else
        # Multi-target mode: collect targets into a matrix
        n_samples = size(X, 1)
        n_targets = length(pipeline.target_cols)
        y_matrix = Matrix{Float64}(undef, n_samples, n_targets)
        
        for (i, target_col) in enumerate(pipeline.target_cols)
            if target_col in names(df)
                y_matrix[:, i] = Vector{Float64}(df[!, target_col])
            else
                @warn "Target column $target_col not found in dataframe, filling with zeros"
                y_matrix[:, i] .= 0.0
            end
        end
        eras = Int.(df.era)
        return X, y_matrix, eras
    end
end

function train!(pipeline::MLPipeline, train_df::DataFrame, val_df::DataFrame;
               verbose::Bool=true, parallel::Bool=true, data_dir::Union{Nothing, String}=nothing,
               callbacks::Vector{Callbacks.TrainingCallback}=Callbacks.TrainingCallback[])
    
    if verbose
        println("Preparing training data...")
    end
    X_train, y_train, train_eras = prepare_data(pipeline, train_df)
    X_val, y_val, val_eras = prepare_data(pipeline, val_df)
    
    if verbose
        println("Training data: $(size(X_train, 1)) samples, $(size(X_train, 2)) features")
        println("Validation data: $(size(X_val, 1)) samples")
    end
    
    # Load feature groups if available
    feature_groups = nothing
    if data_dir !== nothing
        metadata_path = joinpath(data_dir, "features.json")
        if isfile(metadata_path)
            try
                metadata = DataLoader.load_features_metadata(metadata_path)
                feature_groups = DataLoader.get_feature_groups(metadata)
                if verbose
                    println("📊 Loaded feature groups: $(length(feature_groups)) groups with $(sum(length(v) for v in values(feature_groups))) features")
                end
            catch e
                @warn "Failed to load feature groups" error=e
            end
        end
    end
    
    # Handle training based on target mode
    if pipeline.target_mode == :single
        # Single target mode with single model
        if verbose
            println("\n🤖 Training model $(pipeline.model.name) for target: $(pipeline.target_cols[1])")
        end
        
        Models.train!(pipeline.model, X_train, y_train, 
                     X_val=X_val, y_val=y_val, 
                     feature_names=pipeline.feature_cols,
                     feature_groups=feature_groups,
                     verbose=verbose,
                     callbacks=callbacks)
    else
        # Multi-target mode - train separate model per target
        if verbose
            println("\n🎯 Training models for $(length(pipeline.target_cols)) targets...")
        end
        
        for (target_idx, target_col) in enumerate(pipeline.target_cols)
            # Clone model for this target using model config
            target_model = create_model_from_config(pipeline.model_config)
            target_model.name = "$(target_model.name)_$(target_col)"
            
            if verbose
                println("Training $(target_model.name)")
            end
            
            # Extract the appropriate column from the target matrix
            y_train_target = y_train[:, target_idx]
            y_val_target = y_val[:, target_idx]
            
            Models.train!(target_model, X_train, y_train_target, 
                         X_val=X_val, y_val=y_val_target, 
                         feature_names=pipeline.feature_cols,
                         feature_groups=feature_groups,
                         verbose=verbose,
                         callbacks=callbacks)
            
            # Store model for this target
            pipeline.multi_target_models[target_col] = target_model
        end
    end
    
    if verbose
        val_predictions = predict(pipeline, val_df)
        if pipeline.is_multi_target
            # For multi-target, calculate average correlation across targets
            if val_predictions isa Dict
                val_scores = [cor(val_predictions[target], y_val[:, target_idx]) 
                             for (target_idx, target) in enumerate(pipeline.target_cols)]
                val_score = mean(val_scores)
                println("\nValidation correlations: $(round.(val_scores, digits=4))")
                println("Average correlation: $(round(val_score, digits=4))")
            else
                val_score = 0.0
                println("\nWarning: Could not calculate multi-target validation score")
            end
        else
            # Single target
            val_score = cor(val_predictions, y_val)
            println("\nValidation correlation: $(round(val_score, digits=4))")
        end
    end
    
    return pipeline
end

function predict(pipeline::MLPipeline, df::DataFrame; 
                return_raw::Bool=false, verbose::Bool=false, target::Union{String, Nothing}=nothing)
    
    if verbose
        println("Preparing prediction data...")
    end
    
    feature_data = DataLoader.get_feature_columns(df, pipeline.feature_cols)
    feature_data = Preprocessor.fillna(feature_data, 0.5)
    X = Matrix{Float64}(feature_data)
    
    if pipeline.target_mode == :single
        # Single target mode with single model
        if verbose
            println("Generating predictions for $(size(X, 1)) samples using $(pipeline.model.name)...")
        end
        
        predictions = Models.predict(pipeline.model, X)
    else
        # Multi-target mode
        if pipeline.multi_target_models === nothing || isempty(pipeline.multi_target_models)
            error("Pipeline not trained yet. Call train! first.")
        end
        
        # If specific target requested, predict only for that target
        if target !== nothing
            if !(target in pipeline.target_cols)
                error("Target $target not found in pipeline targets: $(pipeline.target_cols)")
            end
            
            if verbose
                println("Generating predictions for target: $target")
            end
            
            predictions = Models.predict(pipeline.multi_target_models[target], X)
        else
            # Return predictions for all targets as a Dict
            if verbose
                println("Generating predictions for $(length(pipeline.target_cols)) targets...")
            end
            
            predictions_dict = Dict{String, Vector{Float64}}()
            for target_col in pipeline.target_cols
                predictions_dict[target_col] = Models.predict(pipeline.multi_target_models[target_col], X)
            end
            
            # For this multi-target all predictions case, return the dict directly
            if !return_raw
                # Apply post-processing to each target's predictions
                eras = "era" in names(df) ? Int.(df.era) : ones(Int, size(X, 1))
                for (target_col, preds) in predictions_dict
                    if pipeline.config[:neutralize]
                        predictions_dict[target_col] = Neutralization.smart_neutralize(
                            preds, X, eras,
                            proportion=pipeline.config[:neutralize_proportion]
                        )
                    end
                    
                    if pipeline.config[:clip_predictions]
                        predictions_dict[target_col] = clamp.(predictions_dict[target_col], 0.0, 1.0)
                    end
                    
                    if pipeline.config[:normalize_predictions]
                        predictions_dict[target_col] = Preprocessor.rank_normalize(predictions_dict[target_col])
                    end
                end
            end
            
            return predictions_dict
        end
    end
    
    if pipeline.config[:neutralize] && !return_raw
        if verbose
            println("Applying feature neutralization...")
        end
        
        eras = "era" in names(df) ? Int.(df.era) : ones(Int, size(X, 1))
        predictions = Neutralization.smart_neutralize(
            predictions, X, eras,
            proportion=pipeline.config[:neutralize_proportion]
        )
    end
    
    if pipeline.config[:normalize_predictions] && !return_raw
        predictions = Preprocessor.normalize_predictions(predictions)
    end
    
    if pipeline.config[:clip_predictions] && !return_raw
        predictions = Preprocessor.clip_predictions(predictions)
    end
    
    return predictions
end

function evaluate(pipeline::MLPipeline, df::DataFrame; 
                 metrics::Vector{Symbol}=[:corr, :sharpe, :max_drawdown], target::Union{String, Nothing}=nothing)
    
    X, y_data, eras = prepare_data(pipeline, df)
    
    if pipeline.target_mode == :single
        predictions = predict(pipeline, df)
        y = y_data
    else
        # Multi-target mode
        if target !== nothing
            # Evaluate specific target
            target_idx = findfirst(==(target), pipeline.target_cols)
            if target_idx === nothing
                error("Target $target not found in pipeline targets: $(pipeline.target_cols)")
            end
            predictions = predict(pipeline, df, target=target)
            y = y_data[:, target_idx]
        else
            # Evaluate all targets and return aggregated results
            all_results = Dict{String, Dict{Symbol, Float64}}()
            
            for (target_idx, target_col) in enumerate(pipeline.target_cols)
                target_predictions = predict(pipeline, df, target=target_col)
                target_y = y_data[:, target_idx]
                
                target_results = Dict{Symbol, Float64}()
                
                if :corr in metrics
                    target_results[:corr] = cor(target_predictions, target_y)
                end
                
                if :sharpe in metrics
                    returns = diff(target_predictions)
                    target_results[:sharpe] = mean(returns) / std(returns) * sqrt(252)
                end
                
                if :max_drawdown in metrics
                    cumulative = cumsum(target_predictions .- mean(target_predictions))
                    running_max = accumulate(max, cumulative)
                    drawdown = running_max .- cumulative
                    target_results[:max_drawdown] = maximum(drawdown)
                end
                
                if :rmse in metrics
                    target_results[:rmse] = sqrt(mean((target_predictions .- target_y).^2))
                end
                
                if :mae in metrics
                    target_results[:mae] = mean(abs.(target_predictions .- target_y))
                end
                
                all_results[target_col] = target_results
            end
            
            # Return aggregate statistics across all targets
            aggregate_results = Dict{Symbol, Float64}()
            for metric in metrics
                values = [res[metric] for res in values(all_results) if haskey(res, metric)]
                if !isempty(values)
                    aggregate_results[Symbol("mean_$metric")] = mean(values)
                    aggregate_results[Symbol("std_$metric")] = std(values)
                    aggregate_results[Symbol("min_$metric")] = minimum(values)
                    aggregate_results[Symbol("max_$metric")] = maximum(values)
                end
            end
            
            return aggregate_results
        end
    end
    
    results = Dict{Symbol, Float64}()
    
    if :corr in metrics
        results[:corr] = cor(predictions, y)
    end
    
    if :sharpe in metrics
        era_returns = Float64[]
        for era in unique(eras)
            era_mask = eras .== era
            if sum(era_mask) > 0
                era_corr = cor(predictions[era_mask], y[era_mask])
                push!(era_returns, era_corr)
            end
        end
        
        if length(era_returns) > 1
            results[:sharpe] = mean(era_returns) / std(era_returns)
        else
            results[:sharpe] = 0.0
        end
    end
    
    if :max_drawdown in metrics
        era_returns = Float64[]
        for era in unique(eras)
            era_mask = eras .== era
            if sum(era_mask) > 0
                era_corr = cor(predictions[era_mask], y[era_mask])
                push!(era_returns, era_corr)
            end
        end
        
        cumsum_returns = cumsum(era_returns)
        running_max = accumulate(max, cumsum_returns)
        drawdowns = cumsum_returns .- running_max
        results[:max_drawdown] = minimum(drawdowns)
    end
    
    if :fnc in metrics && pipeline.config[:neutralize]
        fnc = Neutralization.feature_neutral_correlation(predictions, X, y)
        results[:fnc] = fnc
    end
    
    return results
end

# Note: Ensemble-related functions have been removed as the pipeline now uses a single model

"""
    optimize_hyperparameters(pipeline::MLPipeline, train_df::DataFrame;
                            model_type::Symbol, optimization_method::Symbol=:grid,
                            objective::Symbol=:correlation, n_splits::Int=3,
                            n_iter::Int=50, verbose::Bool=true)

Optimize hyperparameters for a specific model type.

# Arguments
- `pipeline`: ML pipeline
- `train_df`: Training DataFrame
- `model_type`: Type of model to optimize (:XGBoost, :LightGBM, :EvoTrees, etc.)
- `optimization_method`: :grid, :random, or :bayesian
- `objective`: :correlation, :sharpe, :mmc, :tc, or :multi_objective
- `n_splits`: Number of cross-validation splits
- `n_iter`: Number of iterations for random/bayesian search
- `verbose`: Print progress information

# Returns
- OptimizationResult with best parameters and scores
"""
function optimize_hyperparameters(pipeline::MLPipeline, train_df::DataFrame;
                                 model_type::Symbol, optimization_method::Symbol=:grid,
                                 objective::Symbol=:correlation, n_splits::Int=3,
                                 n_iter::Int=50, verbose::Bool=true)
    
    # Prepare data
    X, y, era_col = prepare_data(pipeline, train_df)
    
    # Create data dict for HyperOpt
    data_dict = Dict{String,DataFrame}()
    for (target_idx, target) in enumerate(pipeline.target_cols)
        # Extract the appropriate target column
        target_y = pipeline.target_mode == :single ? y : y[:, target_idx]
        
        target_df = DataFrame(
            hcat(X, target_y),
            vcat(pipeline.feature_cols, "target")
        )
        if era_col !== nothing
            target_df.era = era_col
        end
        data_dict[target] = target_df
    end
    
    # Get validation eras if available
    validation_eras = era_col !== nothing ? unique(era_col)[end-20:end] : Int[]
    
    # Create HyperOpt configuration
    hyperopt_config = HyperOpt.HyperOptConfig(
        model_type=model_type,
        objective=objective,
        n_splits=n_splits,
        validation_eras=validation_eras,
        verbose=verbose
    )
    
    # Create optimizer based on method
    if optimization_method == :grid
        param_grid = HyperOpt.create_param_grid(model_type)
        optimizer = HyperOpt.GridSearchOptimizer(param_grid, hyperopt_config)
    elseif optimization_method == :random
        param_distributions = HyperOpt.create_param_distributions(model_type)
        optimizer = HyperOpt.RandomSearchOptimizer(param_distributions, n_iter, hyperopt_config)
    elseif optimization_method == :bayesian
        # Create bounds from distributions
        param_distributions = HyperOpt.create_param_distributions(model_type)
        param_bounds = Dict{Symbol,Tuple{Float64,Float64}}()
        
        # Simplified bounds extraction for Bayesian optimization
        if model_type in [:XGBoost, :LightGBM, :EvoTrees, :CatBoost]
            if model_type == :XGBoost
                param_bounds = Dict(
                    :max_depth => (3.0, 15.0),
                    :learning_rate => (0.0001, 0.1),
                    :n_estimators => (100.0, 2000.0),
                    :colsample_bytree => (0.1, 1.0),
                    :subsample => (0.5, 1.0)
                )
            elseif model_type == :LightGBM
                param_bounds = Dict(
                    :num_leaves => (10.0, 200.0),
                    :learning_rate => (0.0001, 0.1),
                    :n_estimators => (100.0, 2000.0),
                    :feature_fraction => (0.1, 1.0),
                    :bagging_fraction => (0.5, 1.0)
                )
            elseif model_type == :EvoTrees
                param_bounds = Dict(
                    :max_depth => (3.0, 15.0),
                    :eta => (0.0001, 0.1),
                    :nrounds => (100.0, 2000.0),
                    :subsample => (0.5, 1.0),
                    :colsample => (0.1, 1.0)
                )
            elseif model_type == :CatBoost
                param_bounds = Dict(
                    :depth => (3.0, 12.0),
                    :learning_rate => (0.0001, 0.1),
                    :iterations => (100.0, 2000.0),
                    :l2_leaf_reg => (1.0, 30.0)
                )
            end
        elseif model_type in [:Ridge, :Lasso]
            param_bounds = Dict(:alpha => (0.001, 1000.0))
        elseif model_type == :ElasticNet
            param_bounds = Dict(
                :alpha => (0.001, 100.0),
                :l1_ratio => (0.1, 0.9)
            )
        end
        
        optimizer = HyperOpt.BayesianOptimizer(
            param_bounds, 
            min(10, n_iter ÷ 3),  # n_initial
            n_iter - min(10, n_iter ÷ 3),  # n_iter for optimization
            :ei,  # Expected Improvement
            hyperopt_config
        )
    else
        error("Unknown optimization method: $optimization_method")
    end
    
    # Run optimization
    result = HyperOpt.optimize_hyperparameters(optimizer, data_dict, pipeline.target_cols)
    
    return result
end

"""
    create_optimized_model(pipeline::MLPipeline, model_type::Symbol, 
                          optimization_result::HyperOpt.OptimizationResult;
                          model_name::String="")

Create a new model with optimized hyperparameters.

# Arguments
- `pipeline`: ML pipeline
- `model_type`: Type of model to create
- `optimization_result`: Result from hyperparameter optimization
- `model_name`: Optional custom name for the model

# Returns
- New model instance with optimized parameters
"""
function create_optimized_model(pipeline::MLPipeline, model_type::Symbol,
                               optimization_result::HyperOpt.OptimizationResult;
                               model_name::String="")
    
    best_params = HyperOpt.get_best_params(optimization_result)
    
    if model_name == ""
        model_name = "$(model_type)_optimized_$(rand(1000:9999))"
    end
    
    # Create model with optimized parameters
    if model_type == :XGBoost
        return Models.XGBoostModel(model_name; best_params...)
    elseif model_type == :LightGBM
        return Models.LightGBMModel(model_name; best_params...)
    elseif model_type == :EvoTrees
        return Models.EvoTreesModel(model_name; best_params...)
    elseif model_type == :CatBoost
        return Models.CatBoostModel(model_name; best_params...)
    elseif model_type == :Ridge
        return RidgeModel(model_name; best_params...)
    elseif model_type == :Lasso
        return LassoModel(model_name; best_params...)
    elseif model_type == :ElasticNet
        return ElasticNetModel(model_name; best_params...)
    elseif model_type == :NeuralNetwork
        # Handle neural network parameters specially
        hidden_layers = get(best_params, :hidden_layers, [128, 64, 32])
        epochs = get(best_params, :epochs, 50)
        learning_rate = get(best_params, :learning_rate, 0.001)
        batch_size = get(best_params, :batch_size, 512)
        dropout_rate = get(best_params, :dropout_rate, 0.1)
        
        return MLPModel(
            model_name,
            hidden_layers=hidden_layers,
            epochs=epochs,
            learning_rate=learning_rate,
            batch_size=batch_size,
            dropout_rate=dropout_rate
        )
    else
        error("Unknown model type: $model_type")
    end
end

"""
    add_optimized_model!(pipeline::MLPipeline, model::Models.NumeraiModel)

Add an optimized model to the pipeline.

# Arguments
- `pipeline`: ML pipeline to add model to
- `model`: Optimized model to add
"""
function add_optimized_model!(pipeline::MLPipeline, model::Models.NumeraiModel)
    push!(pipeline.models, model)
    
    # Re-create ensemble if it exists
    if pipeline.ensemble !== nothing
        # Preserve existing weights and add new model with equal weight
        existing_weights = pipeline.ensemble.weights
        n_models = length(existing_weights)
        new_weight = 1.0 / (n_models + 1)
        
        # Rescale existing weights
        scaled_weights = existing_weights .* (1.0 - new_weight)
        push!(scaled_weights, new_weight)
        
        # Create new ensemble
        pipeline.ensemble = Ensemble.ModelEnsemble(
            pipeline.models,
            scaled_weights,
            pipeline.config[:ensemble_type]
        )
    end
end

"""
    predict_individual_models(pipeline::MLPipeline, df::DataFrame)

Get predictions from each model in the ensemble individually.

# Arguments
- `pipeline`: Trained ML pipeline with ensemble
- `df`: DataFrame to predict on

# Returns
- Matrix where each column contains predictions from one model
"""
function predict_individual_models(pipeline::MLPipeline, df::DataFrame)::Matrix{Float64}
    X, _, _ = prepare_data(pipeline, df)
    
    if pipeline.ensemble === nothing
        # Single model case
        predictions = Models.predict(pipeline.model, X)
        return reshape(predictions, :, 1)
    end
    
    # Ensemble case
    n_samples = size(X, 1)
    n_models = length(pipeline.models)
    predictions = Matrix{Float64}(undef, n_samples, n_models)
    
    for (i, model) in enumerate(pipeline.models)
        predictions[:, i] = Models.predict(model, X)
    end
    
    return predictions
end

"""
    calculate_ensemble_mmc(pipeline::MLPipeline, df::DataFrame;
                          stakes::Union{Nothing, Vector{Float64}}=nothing)

Calculate Meta-Model Contribution (MMC) for ensemble models.

# Arguments
- `pipeline`: Trained ML pipeline with ensemble
- `df`: DataFrame to evaluate on
- `stakes`: Optional stake weights for MMC calculation

# Returns
- Dictionary mapping model names to MMC scores
"""
function calculate_ensemble_mmc(pipeline::MLPipeline, df::DataFrame;
                               stakes::Union{Nothing, Vector{Float64}}=nothing)::Dict{String, Float64}
    
    if pipeline.ensemble === nothing
        # Single model case
        predictions = predict(pipeline, df)
        _, y, _ = prepare_data(pipeline, df)
        mmc = Metrics.calculate_mmc(predictions, zeros(length(y)), y)
        return Dict(pipeline.model.name => mmc)
    end
    
    # Get individual model predictions
    individual_predictions = predict_individual_models(pipeline, df)
    _, y, _ = prepare_data(pipeline, df)
    
    mmc_scores = Dict{String, Float64}()
    
    for (i, model) in enumerate(pipeline.models)
        # Create meta-model from other models
        other_indices = setdiff(1:length(pipeline.models), i)
        if !isempty(other_indices)
            other_predictions = individual_predictions[:, other_indices]
            other_weights = pipeline.ensemble.weights[other_indices]
            other_weights = other_weights ./ sum(other_weights)  # Renormalize
            meta_model = other_predictions * other_weights
        else
            meta_model = zeros(length(y))
        end
        
        # Calculate MMC for this model
        model_predictions = individual_predictions[:, i]
        mmc = Metrics.calculate_mmc(model_predictions, meta_model, y)
        mmc_scores[model.name] = mmc
    end
    
    return mmc_scores
end

"""
    calculate_ensemble_tc(pipeline::MLPipeline, df::DataFrame;
                         stakes::Union{Nothing, Vector{Float64}}=nothing)

Calculate True Contribution (TC) for ensemble models.

# Arguments
- `pipeline`: Trained ML pipeline with ensemble
- `df`: DataFrame to evaluate on
- `stakes`: Optional stake weights for TC calculation

# Returns
- Dictionary mapping model names to TC scores
"""
function calculate_ensemble_tc(pipeline::MLPipeline, df::DataFrame;
                              stakes::Union{Nothing, Vector{Float64}}=nothing)::Dict{String, Float64}
    
    if pipeline.ensemble === nothing
        # Single model case
        predictions = predict(pipeline, df)
        _, y, _ = prepare_data(pipeline, df)
        tc = Metrics.calculate_tc(predictions, zeros(length(y)), y)
        return Dict(pipeline.model.name => tc)
    end
    
    # Get individual model predictions
    individual_predictions = predict_individual_models(pipeline, df)
    _, y, _ = prepare_data(pipeline, df)
    
    tc_scores = Dict{String, Float64}()
    
    for (i, model) in enumerate(pipeline.models)
        # Create meta-model from other models
        other_indices = setdiff(1:length(pipeline.models), i)
        if !isempty(other_indices)
            other_predictions = individual_predictions[:, other_indices]
            other_weights = pipeline.ensemble.weights[other_indices]
            other_weights = other_weights ./ sum(other_weights)  # Renormalize
            meta_model = other_predictions * other_weights
        else
            meta_model = zeros(length(y))
        end
        
        # Calculate TC for this model
        model_predictions = individual_predictions[:, i]
        tc = Metrics.calculate_tc(model_predictions, meta_model, y)
        tc_scores[model.name] = tc
    end
    
    return tc_scores
end

"""
    evaluate_with_mmc(pipeline::MLPipeline, df::DataFrame; 
                      metrics::Vector{Symbol}=[:corr, :sharpe, :max_drawdown, :mmc],
                      stakes::Union{Nothing, Vector{Float64}}=nothing)

Enhanced evaluation function that includes MMC calculation.

# Arguments
- `pipeline`: Trained ML pipeline
- `df`: DataFrame to evaluate on
- `metrics`: List of metrics to calculate
- `stakes`: Optional stake weights for MMC calculation

# Returns
- Dictionary with evaluation results including MMC scores
"""
function evaluate_with_mmc(pipeline::MLPipeline, df::DataFrame; 
                          metrics::Vector{Symbol}=[:corr, :sharpe, :max_drawdown, :mmc],
                          stakes::Union{Nothing, Vector{Float64}}=nothing)::Dict{Symbol, Any}
    
    # Get standard evaluation metrics
    standard_metrics = filter(m -> !(m in [:mmc, :tc]), metrics)
    results = evaluate(pipeline, df, metrics=standard_metrics)
    
    # Convert to Any to allow mixed types
    results_any = Dict{Symbol, Any}(results)
    
    # Add MMC if requested
    if :mmc in metrics
        mmc_scores = calculate_ensemble_mmc(pipeline, df, stakes=stakes)
        results_any[:mmc] = mmc_scores
        
        # Also add ensemble MMC (average of individual MMCs weighted by ensemble weights)
        if pipeline.ensemble !== nothing
            ensemble_mmc = sum(collect(values(mmc_scores)) .* pipeline.ensemble.weights)
            results_any[:ensemble_mmc] = ensemble_mmc
        end
    end
    
    # Add TC if requested
    if :tc in metrics
        tc_scores = calculate_ensemble_tc(pipeline, df, stakes=stakes)
        results_any[:tc] = tc_scores
        
        # Also add ensemble TC (average of individual TCs weighted by ensemble weights)
        if pipeline.ensemble !== nothing
            ensemble_tc = sum(collect(values(tc_scores)) .* pipeline.ensemble.weights)
            results_any[:ensemble_tc] = ensemble_tc
        end
    end
    
    return results_any
end

"""
    calculate_model_contribution(pipeline::MLPipeline, df::DataFrame, model_name::String;
                                other_models_stakes::Union{Nothing, Vector{Float64}}=nothing)

Calculate how much a specific model contributes to the ensemble performance.

# Arguments
- `pipeline`: Trained ML pipeline
- `df`: DataFrame to evaluate on
- `model_name`: Name of the model to analyze
- `other_models_stakes`: Stakes for other models (excluding the target model)

# Returns
- Dictionary with contribution metrics for the specified model
"""
function calculate_model_contribution(pipeline::MLPipeline, df::DataFrame, model_name::String;
                                    other_models_stakes::Union{Nothing, Vector{Float64}}=nothing)::Dict{Symbol, Float64}
    if pipeline.ensemble === nothing
        error("Pipeline not trained yet. Call train! first.")
    end
    
    # Find the target model
    model_idx = findfirst(m -> m.name == model_name, pipeline.ensemble.models)
    if model_idx === nothing
        error("Model '$model_name' not found in ensemble")
    end
    
    # Get individual predictions and targets
    individual_predictions = predict_individual_models(pipeline, df)
    _, y, _ = prepare_data(pipeline, df)
    
    # Get target model predictions
    target_predictions = individual_predictions[:, model_idx]
    
    # Create ensemble from other models
    other_indices = setdiff(1:length(pipeline.ensemble.models), model_idx)
    other_predictions = individual_predictions[:, other_indices]
    
    if other_models_stakes === nothing
        other_stakes = pipeline.ensemble.weights[other_indices]
    else
        other_stakes = other_models_stakes
    end
    
    # Create meta-model from other models
    if length(other_indices) > 0
        meta_model = Metrics.create_stake_weighted_ensemble(other_predictions, other_stakes)
    else
        # If it's the only model, use zero predictions as meta-model
        meta_model = zeros(length(y))
    end
    
    # Calculate contribution metrics
    results = Dict{Symbol, Float64}()
    
    # Basic correlation
    results[:correlation] = Metrics.calculate_contribution_score(target_predictions, y)
    
    # MMC - how much this model contributes beyond the meta-model
    results[:mmc] = Metrics.calculate_mmc(target_predictions, meta_model, y)
    
    # TC - how much this model contributes to actual returns after accounting for meta-model
    results[:tc] = Metrics.calculate_tc(target_predictions, meta_model, y)
    
    # Compare ensemble performance with and without this model
    full_ensemble = Metrics.create_stake_weighted_ensemble(individual_predictions, pipeline.ensemble.weights)
    full_correlation = Metrics.calculate_contribution_score(full_ensemble, y)
    
    if length(other_indices) > 0
        reduced_correlation = Metrics.calculate_contribution_score(meta_model, y)
        results[:contribution_to_ensemble] = full_correlation - reduced_correlation
    else
        results[:contribution_to_ensemble] = full_correlation
    end
    
    return results
end

function save_predictions(pipeline::MLPipeline, df::DataFrame, output_path::String;
                        model_name::String="numerai_model")
    
    predictions = predict(pipeline, df)
    
    submission_df = DataLoader.create_submission_dataframe(df.id, predictions)
    
    DataLoader.save_predictions(submission_df, output_path)
    
    return output_path
end

function cross_validate_pipeline(pipeline::MLPipeline, df::DataFrame; 
                               n_splits::Int=5, verbose::Bool=true)::Vector{Float64}
    
    X, y, eras = prepare_data(pipeline, df)
    unique_eras = unique(eras)
    n_eras = length(unique_eras)
    era_size = n_eras ÷ n_splits
    
    cv_scores = Float64[]
    
    for i in 1:n_splits
        if verbose
            println("Fold $i/$n_splits")
        end
        
        val_start = (i - 1) * era_size + 1
        val_end = min(i * era_size, n_eras)
        val_eras = unique_eras[val_start:val_end]
        
        train_mask = .!(in.(df.era, Ref(val_eras)))
        val_mask = in.(df.era, Ref(val_eras))
        
        train_df = df[train_mask, :]
        val_df = df[val_mask, :]
        
        fold_pipeline = MLPipeline(
            feature_cols=pipeline.feature_cols,
            target_cols=pipeline.target_cols,
            neutralize=pipeline.config[:neutralize],
            neutralize_proportion=pipeline.config[:neutralize_proportion],
            ensemble_type=pipeline.config[:ensemble_type],
            feature_groups=pipeline.feature_groups,
            features_metadata=pipeline.features_metadata
        )
        
        train!(fold_pipeline, train_df, val_df, verbose=false)
        
        metrics = evaluate(fold_pipeline, val_df, metrics=[:corr])
        push!(cv_scores, metrics[:corr])
        
        if verbose
            println("  Fold $i correlation: $(round(metrics[:corr], digits=4))")
        end
    end
    
    if verbose
        println("\nCV Mean Correlation: $(round(mean(cv_scores), digits=4)) ± $(round(std(cv_scores), digits=4))")
    end
    
    return cv_scores
end

function save_pipeline(pipeline::MLPipeline, path::String)
    """Save trained pipeline to disk using JLD2 format"""
    # Create directory if it doesn't exist
    dir = dirname(path)
    if !isempty(dir) && !isdir(dir)
        mkpath(dir)
    end
    
    # Save the entire pipeline object
    @save path pipeline
    @info "Pipeline saved to $path"
end

function load_pipeline(path::String)::MLPipeline
    """Load trained pipeline from disk"""
    if !isfile(path)
        error("Pipeline file not found: $path")
    end
    
    @load path pipeline
    @info "Pipeline loaded from $path"
    return pipeline
end

export MLPipeline, ModelConfig, train!, predict, evaluate, save_predictions, cross_validate_pipeline, create_model_from_config, save_pipeline, load_pipeline

end