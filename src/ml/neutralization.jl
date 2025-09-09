module Neutralization

using DataFrames
using LinearAlgebra
using Statistics
using StatsBase

function get_feature_exposures(predictions::Vector{Float64}, features::Matrix{Float64})::Vector{Float64}
    if length(predictions) != size(features, 1)
        error("Predictions length must match features rows")
    end
    
    # Use least squares to solve for exposures
    exposures = features \ predictions
    
    return exposures
end

function neutralize(predictions::Vector{Float64}, features::Matrix{Float64}; 
                    proportion::Float64=1.0)::Vector{Float64}
    if proportion < 0.0 || proportion > 1.0
        error("Proportion must be between 0 and 1")
    end
    
    if proportion == 0.0
        return predictions
    end
    
    exposures = get_feature_exposures(predictions, features)
    
    neutralized_component = features * exposures
    
    neutralized = predictions - proportion * neutralized_component
    
    return neutralized
end

function smart_neutralize(predictions::Vector{Float64}, features::Matrix{Float64}, 
                         eras::Vector{Int}; proportion::Float64=0.5)::Vector{Float64}
    unique_eras = unique(eras)
    neutralized = similar(predictions)
    
    for era in unique_eras
        era_mask = eras .== era
        era_indices = findall(era_mask)
        
        if length(era_indices) > 0
            era_predictions = predictions[era_indices]
            era_features = features[era_indices, :]
            
            era_neutralized = neutralize(era_predictions, era_features, proportion=proportion)
            
            neutralized[era_indices] = era_neutralized
        end
    end
    
    return neutralized
end

function feature_neutral_correlation(predictions::Vector{Float64}, features::Matrix{Float64}, 
                                    target::Vector{Float64})::Float64
    neutralized = neutralize(predictions, features, proportion=1.0)
    
    return cor(neutralized, target)
end

function orthogonalize(predictions::Vector{Float64}, reference::Vector{Float64})::Vector{Float64}
    dot_product = dot(predictions, reference)
    norm_squared = dot(reference, reference)
    
    if norm_squared == 0
        return predictions
    end
    
    projection = (dot_product / norm_squared) * reference
    
    return predictions - projection
end

function l2_normalize(predictions::Vector{Float64})::Vector{Float64}
    norm = sqrt(sum(predictions .^ 2))
    
    if norm == 0
        return predictions
    end
    
    return predictions ./ norm
end

function get_feature_neutral_targets(targets::DataFrame, features::Matrix{Float64}, 
                                    eras::Vector{Int})::DataFrame
    neutralized_targets = DataFrame()
    
    for col in names(targets)
        target_values = Float64.(targets[!, col])
        neutralized_values = smart_neutralize(target_values, features, eras, proportion=1.0)
        neutralized_targets[!, col] = neutralized_values
    end
    
    return neutralized_targets
end

function compute_max_feature_exposure(predictions::Vector{Float64}, features::Matrix{Float64})::Float64
    exposures = abs.(get_feature_exposures(predictions, features))
    return maximum(exposures)
end

function iterative_neutralization(predictions::Vector{Float64}, features::Matrix{Float64}; 
                                 max_iterations::Int=10, tolerance::Float64=0.01)::Vector{Float64}
    current_predictions = copy(predictions)
    
    for i in 1:max_iterations
        max_exposure = compute_max_feature_exposure(current_predictions, features)
        
        if max_exposure < tolerance
            break
        end
        
        current_predictions = neutralize(current_predictions, features, proportion=0.1)
    end
    
    return current_predictions
end

export neutralize, smart_neutralize, feature_neutral_correlation, orthogonalize,
       l2_normalize, get_feature_neutral_targets, compute_max_feature_exposure,
       iterative_neutralization, get_feature_exposures

end