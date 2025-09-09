module DataLoader

using DataFrames
using Parquet2
using CSV
using JSON3
using ProgressMeter

struct TournamentData
    train::DataFrame
    validation::DataFrame
    live::DataFrame
    features::Vector{String}
    target_names::Vector{String}
end

function load_parquet(filepath::String; show_progress::Bool=true)::DataFrame
    if !isfile(filepath)
        error("File not found: $filepath")
    end
    
    if show_progress
        println("Loading $(basename(filepath))...")
    end
    
    df = DataFrame(read_parquet(filepath))
    
    if show_progress
        println("Loaded $(nrow(df)) rows, $(ncol(df)) columns")
    end
    
    return df
end

function load_features_json(filepath::String)::Tuple{Vector{String}, Vector{String}}
    if !isfile(filepath)
        error("Features file not found: $filepath")
    end
    
    features_data = JSON3.read(read(filepath, String))
    
    feature_names = features_data.feature_sets.medium
    target_names = collect(keys(features_data.targets))
    
    return feature_names, String.(target_names)
end

function load_tournament_data(data_dir::String; show_progress::Bool=true)::TournamentData
    train_path = joinpath(data_dir, "train.parquet")
    val_path = joinpath(data_dir, "validation.parquet")
    live_path = joinpath(data_dir, "live.parquet")
    features_path = joinpath(data_dir, "features.json")
    
    if show_progress
        println("Loading tournament data from $data_dir")
    end
    
    train_df = load_parquet(train_path, show_progress=show_progress)
    val_df = load_parquet(val_path, show_progress=show_progress)
    live_df = load_parquet(live_path, show_progress=show_progress)
    
    features, targets = load_features_json(features_path)
    
    return TournamentData(train_df, val_df, live_df, features, targets)
end

function filter_by_era(df::DataFrame, era_col::Symbol, start_era::Int, end_era::Int)::DataFrame
    return df[start_era .<= df[!, era_col] .<= end_era, :]
end

function get_feature_columns(df::DataFrame, features::Vector{String})::DataFrame
    available_features = intersect(names(df), features)
    if length(available_features) < length(features)
        missing = setdiff(features, available_features)
        @warn "Missing features: $missing"
    end
    return df[!, available_features]
end

function get_target_column(df::DataFrame, target_name::String)::Vector{Float64}
    if !(target_name in names(df))
        error("Target $target_name not found in dataframe")
    end
    return Float64.(df[!, target_name])
end

function split_by_era(df::DataFrame; validation_split::Float64=0.2)::Tuple{DataFrame, DataFrame}
    eras = unique(df.era)
    n_eras = length(eras)
    
    split_point = Int(floor(n_eras * (1 - validation_split)))
    train_eras = eras[1:split_point]
    val_eras = eras[split_point+1:end]
    
    train_df = df[in.(df.era, Ref(train_eras)), :]
    val_df = df[in.(df.era, Ref(val_eras)), :]
    
    return train_df, val_df
end

function save_predictions(predictions::DataFrame, output_path::String)
    CSV.write(output_path, predictions)
    println("Predictions saved to $output_path")
end

function create_submission_dataframe(ids::Vector, predictions::Vector{Float64})::DataFrame
    return DataFrame(
        id = ids,
        prediction = predictions
    )
end

export TournamentData, load_tournament_data, load_parquet, get_feature_columns,
       get_target_column, split_by_era, save_predictions, create_submission_dataframe,
       filter_by_era

end