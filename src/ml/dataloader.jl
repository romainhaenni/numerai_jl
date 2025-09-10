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
        # Convert feature to String if it's a Symbol (JSON3 may parse keys as Symbols)
        feature_str = string(feature)
        
        # Get group, converting to string if necessary
        group_raw = get(info, "group", "default")
        group = string(group_raw)
        
        if !haskey(groups, group)
            groups[group] = String[]
        end
        push!(groups[group], feature_str)
    end
    
    return groups
end

"""
    create_interaction_constraints(feature_groups, feature_names)

Convert feature groups to interaction constraint indices for tree-based models.
This ensures features only interact within their logical groups.
"""
function create_interaction_constraints(feature_groups::Dict{String, Vector{String}}, 
                                       feature_names::Vector{String})::Vector{Vector{Int}}
    constraints = Vector{Vector{Int}}()
    
    for (group_name, group_features) in feature_groups
        if length(group_features) > 1  
            indices = Int[]
            for feat in group_features
                idx = findfirst(==(feat), feature_names)
                if idx !== nothing
                    push!(indices, idx - 1)  # XGBoost uses 0-based indexing
                end
            end
            if length(indices) > 1
                push!(constraints, indices)
            end
        end
    end
    
    return constraints
end

"""
    group_based_column_sampling(feature_groups, sample_fraction)

Create feature weights for group-proportional sampling.
Ensures balanced sampling across different feature groups.
"""
function group_based_column_sampling(feature_groups::Dict{String, Vector{String}}, 
                                    sample_fraction::Float64=0.1)::Dict{String, Float64}
    feature_weights = Dict{String, Float64}()
    num_groups = length(feature_groups)
    
    for (group_name, group_features) in feature_groups
        group_weight = sample_fraction / num_groups  
        feature_weight = group_weight / length(group_features)   
        
        for feature in group_features
            feature_weights[feature] = feature_weight
        end
    end
    
    return feature_weights
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

# Tournament data structure for comprehensive data loading
struct TournamentData
    train::DataFrame
    validation::DataFrame
    live::DataFrame
    features::Vector{String}
    targets::Vector{String}
end

# Load features.json file to get feature and target names
function load_features_json(filepath::String; feature_set::String="medium")
    if !isfile(filepath)
        error("Features file not found: $filepath")
    end
    
    features_data = JSON3.read(read(filepath, String))
    
    # Validate feature_set parameter
    valid_feature_sets = ["small", "medium", "large"]
    if !(feature_set in valid_feature_sets)
        error("Invalid feature_set '$feature_set'. Must be one of: $(join(valid_feature_sets, ", "))")
    end
    
    # Get features based on the specified feature set
    if feature_set == "small"
        feature_names = features_data.feature_sets.small
    elseif feature_set == "medium"
        feature_names = features_data.feature_sets.medium
    elseif feature_set == "large"
        feature_names = features_data.feature_sets.large
    end
    
    target_names = collect(keys(features_data.targets))
    
    return feature_names, String.(target_names)
end

# Load all tournament data files at once
function load_tournament_data(data_dir::String; 
                            show_progress::Bool=true, 
                            feature_set::String="medium",
                            group_names::Union{Vector{String}, Nothing}=nothing)::TournamentData
    train_path = joinpath(data_dir, "train.parquet")
    val_path = joinpath(data_dir, "validation.parquet")
    live_path = joinpath(data_dir, "live.parquet")
    features_path = joinpath(data_dir, "features.json")
    
    if show_progress
        if group_names !== nothing
            println("Loading tournament data from $data_dir with feature groups: $(join(group_names, ", "))")
        else
            println("Loading tournament data from $data_dir with feature set: $feature_set")
        end
    end
    
    # Use existing load functions
    train_df = load_training_data(train_path, sample_pct=1.0)
    val_df = load_training_data(val_path, sample_pct=1.0)  # validation uses same format as training
    live_df = load_live_data(live_path)
    
    # Load features metadata
    features_metadata = load_features_metadata(features_path)
    
    # Determine features to use
    if group_names !== nothing
        # Use feature groups
        feature_groups = get_feature_groups(features_metadata)
        selected_features = String[]
        for group_name in group_names
            if haskey(feature_groups, group_name)
                append!(selected_features, feature_groups[group_name])
            else
                @warn "Group '$group_name' not found in features metadata"
            end
        end
        features = unique(selected_features)
    else
        # Use feature set (existing behavior)
        features, _ = load_features_json(features_path; feature_set=feature_set)
    end
    
    # Always load all targets
    _, targets = load_features_json(features_path; feature_set=feature_set)
    
    return TournamentData(train_df, val_df, live_df, features, targets)
end

export load_training_data, load_live_data, get_feature_columns, get_target_column,
       get_target_columns, get_era_column, split_by_era, create_submission_dataframe,
       save_predictions, load_features_metadata, get_feature_groups, validate_data,
       create_interaction_constraints, group_based_column_sampling,
       combine_predictions, TournamentData, load_tournament_data, load_features_json

end