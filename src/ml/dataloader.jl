module DataLoader

using DataFrames
using CSV
using Parquet
using Statistics
using ProgressMeter
using JSON3

function load_training_data(path::String; sample_pct::Float64=1.0)::DataFrame
    if !isfile(path)
        error("Training data file not found: $path")
    end
    
    ext = splitext(path)[2]
    
    if ext == ".csv"
        df = CSV.read(path, DataFrame)
    elseif ext == ".parquet"
        df = DataFrame(Parquet.read_parquet(path))
    else
        error("Unsupported file format: $ext")
    end
    
    if sample_pct < 1.0
        n_samples = size(df, 1)
        sample_size = Int(floor(n_samples * sample_pct))
        sample_indices = rand(1:n_samples, sample_size)
        df = df[sample_indices, :]
    end
    
    return df
end

function load_live_data(path::String)::DataFrame
    if !isfile(path)
        error("Live data file not found: $path")
    end
    
    ext = splitext(path)[2]
    
    if ext == ".csv"
        df = CSV.read(path, DataFrame)
    elseif ext == ".parquet"
        df = DataFrame(Parquet.read_parquet(path))
    else
        error("Unsupported file format: $ext")
    end
    
    return df
end

function get_feature_columns(df::DataFrame, feature_names::Vector{String})::DataFrame
    missing_features = setdiff(feature_names, names(df))
    
    if !isempty(missing_features)
        error("Missing features in dataframe: $missing_features")
    end
    
    return df[!, feature_names]
end

function get_feature_columns(df::DataFrame)::DataFrame
    feature_cols = filter(name -> startswith(name, "feature_"), names(df))
    
    if isempty(feature_cols)
        error("No feature columns found in dataframe")
    end
    
    return df[!, feature_cols]
end

function get_target_column(df::DataFrame, target_name::String)::Vector{Float64}
    if !(target_name in names(df))
        error("Target column '$target_name' not found in dataframe")
    end
    
    target = Float64.(df[!, target_name])
    
    missing_mask = ismissing.(df[!, target_name])
    if any(missing_mask)
        @warn "Found $(sum(missing_mask)) missing values in target column"
        target[missing_mask] .= 0.5
    end
    
    return target
end

function get_target_columns(df::DataFrame)::DataFrame
    target_cols = filter(name -> startswith(name, "target_"), names(df))
    
    if isempty(target_cols)
        error("No target columns found in dataframe")
    end
    
    return df[!, target_cols]
end

function get_era_column(df::DataFrame)::Vector{Int}
    if !("era" in names(df))
        error("Era column not found in dataframe")
    end
    
    if eltype(df.era) <: Number
        return Int.(df.era)
    else
        era_str = String.(df.era)
        era_nums = [parse(Int, replace(e, "era" => "")) for e in era_str]
        return era_nums
    end
end

function split_by_era(df::DataFrame, train_eras::Vector{Int}, val_eras::Vector{Int})::Tuple{DataFrame, DataFrame}
    eras = get_era_column(df)
    
    train_mask = in.(eras, Ref(train_eras))
    val_mask = in.(eras, Ref(val_eras))
    
    train_df = df[train_mask, :]
    val_df = df[val_mask, :]
    
    return train_df, val_df
end

function create_submission_dataframe(ids::Vector, predictions::Vector{Float64})::DataFrame
    if length(ids) != length(predictions)
        error("Number of IDs must match number of predictions")
    end
    
    return DataFrame(
        id = ids,
        prediction = predictions
    )
end

function save_predictions(df::DataFrame, output_path::String)
    mkpath(dirname(output_path))
    
    CSV.write(output_path, df)
    
    println("Predictions saved to $output_path")
end

function load_features_metadata(path::String)::Dict{String, Any}
    if !isfile(path)
        error("Features metadata file not found: $path")
    end
    
    return JSON3.read(read(path, String))
end

function get_feature_groups(metadata::Dict{String, Any})::Dict{String, Vector{String}}
    groups = Dict{String, Vector{String}}()
    
    for (feature, info) in metadata["feature_stats"]
        group = get(info, "group", "default")
        if !haskey(groups, group)
            groups[group] = String[]
        end
        push!(groups[group], feature)
    end
    
    return groups
end

function validate_data(df::DataFrame; check_features::Bool=true, check_targets::Bool=false)::Bool
    if size(df, 1) == 0
        error("Dataframe is empty")
    end
    
    if check_features
        feature_cols = filter(name -> startswith(name, "feature_"), names(df))
        if isempty(feature_cols)
            error("No feature columns found")
        end
        
        for col in feature_cols
            if any(ismissing, df[!, col])
                @warn "Missing values found in feature column: $col"
            end
            
            values = skipmissing(df[!, col])
            if all(v -> v == first(values), values)
                @warn "Feature column has constant value: $col"
            end
        end
    end
    
    if check_targets
        target_cols = filter(name -> startswith(name, "target_"), names(df))
        if isempty(target_cols)
            error("No target columns found")
        end
    end
    
    if "era" in names(df)
        eras = get_era_column(df)
        if length(unique(eras)) < 2
            @warn "Only $(length(unique(eras))) unique eras found"
        end
    end
    
    return true
end

function combine_predictions(predictions_dict::Dict{String, Vector{Float64}}, 
                           weights::Union{Nothing, Dict{String, Float64}}=nothing)::Vector{Float64}
    model_names = collect(keys(predictions_dict))
    n_samples = length(first(values(predictions_dict)))
    
    for (name, preds) in predictions_dict
        if length(preds) != n_samples
            error("All predictions must have the same length")
        end
    end
    
    if weights === nothing
        weights = Dict(name => 1.0/length(model_names) for name in model_names)
    end
    
    weight_sum = sum(values(weights))
    normalized_weights = Dict(k => v/weight_sum for (k, v) in weights)
    
    combined = zeros(n_samples)
    for (name, preds) in predictions_dict
        weight = get(normalized_weights, name, 0.0)
        combined .+= weight .* preds
    end
    
    return combined
end

export load_training_data, load_live_data, get_feature_columns, get_target_column,
       get_target_columns, get_era_column, split_by_era, create_submission_dataframe,
       save_predictions, load_features_metadata, get_feature_groups, validate_data,
       combine_predictions

end