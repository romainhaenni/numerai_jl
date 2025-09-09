module Preprocessor

using DataFrames
using Statistics
using StatsBase
using Distributions

function fillna(df::DataFrame, value::Float64=0.5)::DataFrame
    df_filled = copy(df)
    
    for col in names(df_filled)
        if any(ismissing, df_filled[!, col])
            df_filled[!, col] = coalesce.(df_filled[!, col], value)
        end
    end
    
    return df_filled
end

function clip_predictions(predictions::Vector{Float64}; 
                        min_val::Float64=0.0001, max_val::Float64=0.9999)::Vector{Float64}
    return clamp.(predictions, min_val, max_val)
end

function normalize_predictions(predictions::Vector{Float64})::Vector{Float64}
    min_pred = minimum(predictions)
    max_pred = maximum(predictions)
    
    if min_pred == max_pred
        return fill(0.5, length(predictions))
    end
    
    normalized = (predictions .- min_pred) ./ (max_pred - min_pred)
    
    return normalized
end

function rank_predictions(predictions::Vector{Float64})::Vector{Float64}
    n = length(predictions)
    ranks = ordinalrank(predictions)
    
    return (ranks .- 0.5) ./ n
end

function gaussian_rank(predictions::Vector{Float64})::Vector{Float64}
    n = length(predictions)
    ranks = ordinalrank(predictions)
    
    uniform_ranks = ranks ./ (n + 1)
    
    gaussian_ranks = quantile.(Normal(0.5, 0.15), uniform_ranks)
    
    return clamp.(gaussian_ranks, 0.0001, 0.9999)
end

function power_transform(predictions::Vector{Float64}; power::Float64=0.5)::Vector{Float64}
    min_pred = minimum(predictions)
    
    if min_pred < 0
        shifted = predictions .- min_pred .+ 1e-6
    else
        shifted = predictions .+ 1e-6
    end
    
    transformed = shifted .^ power
    
    return normalize_predictions(transformed)
end

function standardize(features::Matrix{Float64}; 
                    center::Bool=true, scale::Bool=true)::Tuple{Matrix{Float64}, Vector{Float64}, Vector{Float64}}
    n_features = size(features, 2)
    
    means = center ? vec(mean(features, dims=1)) : zeros(n_features)
    stds = scale ? vec(std(features, dims=1)) : ones(n_features)
    
    stds[stds .== 0] .= 1.0
    
    standardized = copy(features)
    for j in 1:n_features
        if center
            standardized[:, j] .-= means[j]
        end
        if scale
            standardized[:, j] ./= stds[j]
        end
    end
    
    return standardized, means, stds
end

function apply_standardization(features::Matrix{Float64}, 
                             means::Vector{Float64}, stds::Vector{Float64})::Matrix{Float64}
    standardized = copy(features)
    n_features = size(features, 2)
    
    for j in 1:n_features
        standardized[:, j] = (standardized[:, j] .- means[j]) ./ stds[j]
    end
    
    return standardized
end

function reduce_memory_precision(df::DataFrame)::DataFrame
    df_reduced = copy(df)
    
    for col in names(df_reduced)
        if eltype(df_reduced[!, col]) <: AbstractFloat
            df_reduced[!, col] = Float32.(df_reduced[!, col])
        end
    end
    
    return df_reduced
end

function create_era_weights(eras::Vector{Int}; 
                          recent_weight::Float64=2.0, 
                          decay_rate::Float64=0.95)::Vector{Float64}
    unique_eras = sort(unique(eras))
    n_eras = length(unique_eras)
    
    era_to_weight = Dict{Int, Float64}()
    for (i, era) in enumerate(unique_eras)
        age = n_eras - i
        weight = recent_weight * (decay_rate ^ age)
        era_to_weight[era] = weight
    end
    
    weights = [era_to_weight[era] for era in eras]
    
    weights ./= mean(weights)
    
    return weights
end

function remove_outliers(predictions::Vector{Float64}; 
                        n_std::Float64=3.0)::Vector{Float64}
    mean_pred = mean(predictions)
    std_pred = std(predictions)
    
    lower_bound = mean_pred - n_std * std_pred
    upper_bound = mean_pred + n_std * std_pred
    
    cleaned = clamp.(predictions, lower_bound, upper_bound)
    
    return cleaned
end

function quantile_transform(features::Matrix{Float64}; n_quantiles::Int=100)::Matrix{Float64}
    n_samples, n_features = size(features)
    transformed = zeros(Float64, n_samples, n_features)
    
    for j in 1:n_features
        col = features[:, j]
        
        quantiles = quantile(col, range(0, 1, length=n_quantiles))
        
        for i in 1:n_samples
            val = col[i]
            q_idx = searchsortedfirst(quantiles, val)
            transformed[i, j] = (q_idx - 1) / (n_quantiles - 1)
        end
    end
    
    return transformed
end

function add_feature_interactions(features::Matrix{Float64}; 
                                 max_interactions::Int=10)::Matrix{Float64}
    n_samples, n_features = size(features)
    
    interactions = Matrix{Float64}(undef, n_samples, 0)
    
    n_interactions = 0
    for i in 1:n_features
        for j in (i+1):n_features
            if n_interactions >= max_interactions
                break
            end
            
            interaction = features[:, i] .* features[:, j]
            interactions = hcat(interactions, interaction)
            n_interactions += 1
        end
        
        if n_interactions >= max_interactions
            break
        end
    end
    
    return hcat(features, interactions)
end

function create_polynomial_features(features::Matrix{Float64}; degree::Int=2)::Matrix{Float64}
    n_samples, n_features = size(features)
    
    poly_features = copy(features)
    
    for d in 2:degree
        power_features = features .^ d
        poly_features = hcat(poly_features, power_features)
    end
    
    return poly_features
end

function balance_target_distribution(y::Vector{Float64}, sample_weights::Vector{Float64})::Vector{Float64}
    quintiles = quantile(y, [0.2, 0.4, 0.6, 0.8])
    
    quintile_weights = zeros(length(y))
    for i in 1:length(y)
        if y[i] <= quintiles[1]
            quintile_weights[i] = 1.2
        elseif y[i] <= quintiles[2]
            quintile_weights[i] = 1.1
        elseif y[i] <= quintiles[3]
            quintile_weights[i] = 1.0
        elseif y[i] <= quintiles[4]
            quintile_weights[i] = 1.1
        else
            quintile_weights[i] = 1.2
        end
    end
    
    return sample_weights .* quintile_weights
end

export fillna, clip_predictions, normalize_predictions, rank_predictions,
       gaussian_rank, power_transform, standardize, apply_standardization,
       reduce_memory_precision, create_era_weights, remove_outliers,
       quantile_transform, add_feature_interactions, create_polynomial_features,
       balance_target_distribution

end