module Pipeline

using DataFrames
using Statistics
using ProgressMeter
using ..DataLoader
using ..Preprocessor
using ..Models
using ..Ensemble
using ..Neutralization

# Configuration struct for model creation
struct ModelConfig
    type::String  # "xgboost", "lightgbm", "evotrees"
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
    target_col::String
end

function MLPipeline(;
    feature_cols::Vector{String},
    target_col::String="target_cyrus_v4_20",
    neutralize::Bool=true,
    neutralize_proportion::Float64=0.5,
    ensemble_type::Symbol=:weighted,
    models::Vector{Models.NumeraiModel}=Models.NumeraiModel[],
    model_configs::Vector{ModelConfig}=ModelConfig[])
    
    config = Dict(
        :neutralize => neutralize,
        :neutralize_proportion => neutralize_proportion,
        :ensemble_type => ensemble_type,
        :clip_predictions => true,
        :normalize_predictions => true
    )
    
    # If model_configs provided, create models from them
    if !isempty(model_configs)
        models = create_models_from_configs(model_configs)
    elseif isempty(models)
        # Default models if none provided
        models = [
            Models.XGBoostModel("xgb_deep", max_depth=8, learning_rate=0.01, colsample_bytree=0.1),
            Models.XGBoostModel("xgb_shallow", max_depth=4, learning_rate=0.02, colsample_bytree=0.2),
            Models.LightGBMModel("lgbm_small", num_leaves=31, learning_rate=0.01, feature_fraction=0.1),
            Models.LightGBMModel("lgbm_large", num_leaves=63, learning_rate=0.005, feature_fraction=0.15)
        ]
        # Create configs from existing models for consistency
        model_configs = [
            ModelConfig("xgboost", Dict(:max_depth=>8, :learning_rate=>0.01, :colsample_bytree=>0.1), name="xgb_deep"),
            ModelConfig("xgboost", Dict(:max_depth=>4, :learning_rate=>0.02, :colsample_bytree=>0.2), name="xgb_shallow"),
            ModelConfig("lightgbm", Dict(:num_leaves=>31, :learning_rate=>0.01, :feature_fraction=>0.1), name="lgbm_small"),
            ModelConfig("lightgbm", Dict(:num_leaves=>63, :learning_rate=>0.005, :feature_fraction=>0.15), name="lgbm_large")
        ]
    end
    
    return MLPipeline(config, models, model_configs, nothing, feature_cols, target_col)
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
                n_estimators=get(config.params, :n_estimators, 100),
                colsample_bytree=get(config.params, :colsample_bytree, 0.1),
                subsample=get(config.params, :subsample, 0.8)
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
                nrounds=get(config.params, :nrounds, 100),
                colsample=get(config.params, :colsample, 0.1),
                subsample=get(config.params, :subsample, 0.8)
            ))
        else
            @warn "Unknown model type: $(config.type), skipping"
        end
    end
    
    return models
end

function prepare_data(pipeline::MLPipeline, df::DataFrame)::Tuple{Matrix{Float64}, Vector{Float64}, Vector{Int}}
    feature_data = DataLoader.get_feature_columns(df, pipeline.feature_cols)
    
    feature_data = Preprocessor.fillna(feature_data, 0.5)
    
    X = Matrix{Float64}(feature_data)
    
    y = DataLoader.get_target_column(df, pipeline.target_col)
    
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
        Models.train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=false)
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
        val_score = cor(val_predictions, y_val)
        println("\nValidation correlation: $(round(val_score, digits=4))")
    end
    
    return pipeline
end

function predict(pipeline::MLPipeline, df::DataFrame; 
                return_raw::Bool=false, verbose::Bool=false)::Vector{Float64}
    
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
            ensemble_type=pipeline.config[:ensemble_type]
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

export MLPipeline, ModelConfig, train!, predict, evaluate, save_predictions, cross_validate_pipeline, create_models_from_configs

end