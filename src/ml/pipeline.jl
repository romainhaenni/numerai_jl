module Pipeline

using DataFrames
using Statistics
using ProgressMeter
using ..DataLoader
using ..Preprocessor
using ..Models
using ..NeuralNetworks
using ..Ensemble
using ..Neutralization
using ..Metrics
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
    type::String  # "xgboost", "lightgbm", "evotrees", "mlp", "resnet", "tabnet"
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
    models::Vector{Models.NumeraiModel}
    model_configs::Vector{ModelConfig}  # Store configurations
    ensemble::Union{Nothing, Ensemble.ModelEnsemble}
    feature_cols::Vector{String}
    target_col::Union{String, Vector{String}}  # Support both single and multi-target
    # Feature groups support
    feature_groups::Union{Nothing, Dict{String, Vector{String}}}
    features_metadata::Union{Nothing, Dict{String, Any}}
    # Multi-target support
    is_multi_target::Bool
    n_targets::Int
end

function MLPipeline(;
    feature_cols::Union{Vector{String}, Nothing}=nothing,
    target_col::Union{String, Vector{String}}="target_cyrus_v4_20",  # Support multi-target
    neutralize::Bool=true,
    neutralize_proportion::Float64=0.5,
    ensemble_type::Symbol=:weighted,
    models::Vector{Models.NumeraiModel}=Models.NumeraiModel[],
    model_configs::Vector{ModelConfig}=ModelConfig[],
    # Feature groups parameters
    feature_groups::Union{Dict{String, Vector{String}}, Nothing}=nothing,
    features_metadata::Union{Dict{String, Any}, Nothing}=nothing,
    group_names::Union{Vector{String}, Nothing}=nothing)
    
    # Determine if this is multi-target
    is_multi_target = target_col isa Vector{String}
    n_targets = is_multi_target ? length(target_col) : 1
    
    config = Dict(
        :neutralize => neutralize,
        :neutralize_proportion => neutralize_proportion,
        :ensemble_type => ensemble_type,
        :clip_predictions => true,
        :normalize_predictions => true,
        :is_multi_target => is_multi_target,
        :n_targets => n_targets
    )
    
    # If model_configs provided, create models from them
    if !isempty(model_configs)
        models = create_models_from_configs(model_configs)
    elseif isempty(models)
        # Default models if none provided - traditional models only (neural networks disabled for now)
        models = [
            Models.XGBoostModel("xgb_default", max_depth=6, learning_rate=0.01, colsample_bytree=0.1),
            Models.LightGBMModel("lgbm_default", num_leaves=31, learning_rate=0.01, feature_fraction=0.1),
            Models.EvoTreesModel("evotrees_default", max_depth=6, learning_rate=0.01, colsample=0.1)
        ]
        # Create configs from existing models for consistency
        model_configs = [
            ModelConfig("xgboost", Dict(:max_depth=>6, :learning_rate=>0.01, :colsample_bytree=>0.1), name="xgb_default"),
            ModelConfig("lightgbm", Dict(:num_leaves=>31, :learning_rate=>0.01, :feature_fraction=>0.1), name="lgbm_default"),
            ModelConfig("evotrees", Dict(:max_depth=>6, :learning_rate=>0.01, :colsample=>0.1), name="evotrees_default")
        ]
    end
    
    # Resolve features from groups if needed
    resolved_features = resolve_features_from_groups(
        feature_cols, feature_groups, features_metadata, group_names
    )
    
    return MLPipeline(config, models, model_configs, nothing, resolved_features, target_col, 
                     feature_groups, features_metadata, is_multi_target, n_targets)
end

# Helper function to create models from configs
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
        # Neural network models temporarily disabled
        elseif config.type in ["mlp", "resnet", "tabnet"]
            @warn "Neural network models ($(config.type)) are temporarily disabled due to type hierarchy issues. Skipping $(config.name)."
        else
            @warn "Unknown model type: $(config.type), skipping"
        end
    end
    
    return models
end

function prepare_data(pipeline::MLPipeline, df::DataFrame)::Tuple{Matrix{Float64}, Union{Vector{Float64}, Matrix{Float64}}, Vector{Int}}
    feature_data = DataLoader.get_feature_columns(df, pipeline.feature_cols)
    
    feature_data = Preprocessor.fillna(feature_data, 0.5)
    
    X = Matrix{Float64}(feature_data)
    
    # Handle both single and multi-target cases
    if pipeline.is_multi_target
        # Multi-target: get all target columns and return as matrix
        y_data = Matrix{Float64}(undef, nrow(df), pipeline.n_targets)
        for (i, target_name) in enumerate(pipeline.target_col)
            y_data[:, i] = DataLoader.get_target_column(df, target_name)
        end
        y = y_data
    else
        # Single target: return as vector (backward compatibility)
        y = DataLoader.get_target_column(df, pipeline.target_col)
    end
    
    eras = Int.(df.era)
    
    return X, y, eras
end

function train!(pipeline::MLPipeline, train_df::DataFrame, val_df::DataFrame;
               verbose::Bool=true, parallel::Bool=true)
    
    if verbose
        println("Preparing training data...")
    end
    X_train, y_train, train_eras = prepare_data(pipeline, train_df)
    X_val, y_val, val_eras = prepare_data(pipeline, val_df)
    
    if verbose
        println("Training data: $(size(X_train, 1)) samples, $(size(X_train, 2)) features")
        println("Validation data: $(size(X_val, 1)) samples")
    end
    
    ensemble = Ensemble.ModelEnsemble(pipeline.models)
    
    if verbose
        println("\n🤖 Training $(length(pipeline.models)) models...")
        prog = ProgressMeter.Progress(length(pipeline.models), desc="Training models: ", showspeed=false)
    end
    
    # Train models with progress tracking
    for (i, model) in enumerate(ensemble.models)
        if verbose
            ProgressMeter.update!(prog, i-1, desc="Training $(model.name): ")
        end
        
        # Handle multi-target training - for now all models use first target only for multi-target
        if pipeline.is_multi_target
            # For traditional models, train on first target for now
            # TODO: Implement proper multi-target support for traditional models
            y_train_single = y_train isa Matrix ? y_train[:, 1] : y_train
            y_val_single = y_val isa Matrix ? y_val[:, 1] : y_val
            Models.train!(model, X_train, y_train_single, X_val=X_val, y_val=y_val_single, verbose=false)
            @warn "Multi-target support for $(typeof(model)) is limited. Using first target only." model_name=model.name
        else
            # Single target or neural network (which supports multi-target)
            Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
        end
        
        if verbose
            ProgressMeter.update!(prog, i)
        end
    end
    
    if verbose
        ProgressMeter.finish!(prog)
    end
    
    if pipeline.config[:ensemble_type] == :optimized && !isnothing(X_val)
        if verbose
            println("\nOptimizing ensemble weights...")
        end
        optimized_weights = Ensemble.optimize_weights(ensemble, X_val, y_val)
        ensemble = Ensemble.ModelEnsemble(ensemble.models, weights=optimized_weights)
        if verbose
            println("Optimized weights: $optimized_weights")
        end
    end
    
    pipeline.ensemble = ensemble
    
    if verbose
        val_predictions = predict(pipeline, val_df)
        if pipeline.is_multi_target
            # For multi-target, calculate average correlation across targets
            if val_predictions isa Matrix && y_val isa Matrix
                val_scores = [cor(val_predictions[:, i], y_val[:, i]) for i in 1:size(y_val, 2)]
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
                return_raw::Bool=false, verbose::Bool=false)::Union{Vector{Float64}, Matrix{Float64}}
    
    if pipeline.ensemble === nothing
        error("Pipeline not trained yet. Call train! first.")
    end
    
    if verbose
        println("Preparing prediction data...")
    end
    
    feature_data = DataLoader.get_feature_columns(df, pipeline.feature_cols)
    feature_data = Preprocessor.fillna(feature_data, 0.5)
    X = Matrix{Float64}(feature_data)
    
    if verbose
        println("Generating predictions for $(size(X, 1)) samples...")
    end
    
    predictions = Ensemble.predict_ensemble(pipeline.ensemble, X)
    
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
                 metrics::Vector{Symbol}=[:corr, :sharpe, :max_drawdown])::Dict{Symbol, Float64}
    
    X, y, eras = prepare_data(pipeline, df)
    predictions = predict(pipeline, df)
    
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

"""
    predict_individual_models(pipeline::MLPipeline, df::DataFrame)

Get predictions from individual models in the ensemble.

# Arguments
- `pipeline`: Trained ML pipeline
- `df`: DataFrame to predict on

# Returns
- Matrix where each column represents predictions from one model
"""
function predict_individual_models(pipeline::MLPipeline, df::DataFrame)::Matrix{Float64}
    if pipeline.ensemble === nothing
        error("Pipeline not trained yet. Call train! first.")
    end
    
    feature_data = DataLoader.get_feature_columns(df, pipeline.feature_cols)
    feature_data = Preprocessor.fillna(feature_data, 0.5)
    X = Matrix{Float64}(feature_data)
    
    # Get individual predictions
    _, individual_predictions = Ensemble.predict_ensemble(pipeline.ensemble, X, return_individual=true)
    
    return individual_predictions
end

"""
    calculate_ensemble_mmc(pipeline::MLPipeline, df::DataFrame; 
                           stakes::Union{Nothing, Vector{Float64}}=nothing)

Calculate MMC scores for each model in the ensemble.

# Arguments
- `pipeline`: Trained ML pipeline
- `df`: DataFrame with predictions and targets
- `stakes`: Optional stake weights for creating meta-model (defaults to ensemble weights)

# Returns
- Dictionary mapping model names to their MMC scores
"""
function calculate_ensemble_mmc(pipeline::MLPipeline, df::DataFrame; 
                               stakes::Union{Nothing, Vector{Float64}}=nothing)::Dict{String, Float64}
    if pipeline.ensemble === nothing
        error("Pipeline not trained yet. Call train! first.")
    end
    
    # Get individual model predictions
    individual_predictions = predict_individual_models(pipeline, df)
    
    # Get targets
    _, y, _ = prepare_data(pipeline, df)
    
    # Use ensemble weights as stakes if not provided
    if stakes === nothing
        stakes = pipeline.ensemble.weights
    end
    
    # Create stake-weighted meta-model
    meta_model = Metrics.create_stake_weighted_ensemble(individual_predictions, stakes)
    
    # Calculate MMC for each model
    mmc_scores = Metrics.calculate_mmc_batch(individual_predictions, meta_model, y)
    
    # Create dictionary with model names
    mmc_dict = Dict{String, Float64}()
    for (i, model) in enumerate(pipeline.ensemble.models)
        mmc_dict[model.name] = mmc_scores[i]
    end
    
    return mmc_dict
end

"""
    calculate_ensemble_tc(pipeline::MLPipeline, df::DataFrame; 
                          stakes::Union{Nothing, Vector{Float64}}=nothing)

Calculate TC scores for each model in the ensemble.

# Arguments
- `pipeline`: Trained ML pipeline
- `df`: DataFrame with predictions and targets/returns
- `stakes`: Optional stake weights for creating meta-model (defaults to ensemble weights)

# Returns
- Dictionary mapping model names to their TC scores
"""
function calculate_ensemble_tc(pipeline::MLPipeline, df::DataFrame; 
                               stakes::Union{Nothing, Vector{Float64}}=nothing)::Dict{String, Float64}
    if pipeline.ensemble === nothing
        error("Pipeline not trained yet. Call train! first.")
    end
    
    # Get individual model predictions
    individual_predictions = predict_individual_models(pipeline, df)
    
    # Get returns (targets)
    _, returns, _ = prepare_data(pipeline, df)
    
    # Use ensemble weights as stakes if not provided
    if stakes === nothing
        stakes = pipeline.ensemble.weights
    end
    
    # Create stake-weighted meta-model
    meta_model = Metrics.create_stake_weighted_ensemble(individual_predictions, stakes)
    
    # Calculate TC for each model
    tc_scores = Metrics.calculate_tc_batch(individual_predictions, meta_model, returns)
    
    # Create dictionary with model names
    tc_dict = Dict{String, Float64}()
    for (i, model) in enumerate(pipeline.ensemble.models)
        tc_dict[model.name] = tc_scores[i]
    end
    
    return tc_dict
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
            target_col=pipeline.target_col,
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

export MLPipeline, ModelConfig, train!, predict, evaluate, save_predictions, cross_validate_pipeline, create_models_from_configs,
       predict_individual_models, calculate_ensemble_mmc, calculate_ensemble_tc, evaluate_with_mmc, calculate_model_contribution

end