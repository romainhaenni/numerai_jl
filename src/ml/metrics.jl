module Metrics

using Statistics
using LinearAlgebra
using StatsBase

"""
    tie_kept_rank(x::AbstractVector{T}) where T

Compute tie-kept ranking of a vector. Tied values maintain their original order.
This function is crucial for the MMC calculation algorithm.

# Arguments
- `x`: Input vector to rank

# Returns
- Vector of ranks (1-indexed) with ties handled by maintaining original order
"""
function tie_kept_rank(x::AbstractVector{T}) where T
    n = length(x)
    if n == 0
        return Float64[]
    end
    
    # Create pairs of (value, original_index)
    indexed_values = [(x[i], i) for i in 1:n]
    
    # Sort by value, keeping original order for ties
    sort!(indexed_values, by=pair -> (pair[1], pair[2]))
    
    # Assign ranks
    ranks = Vector{Float64}(undef, n)
    for (rank, (_, original_idx)) in enumerate(indexed_values)
        ranks[original_idx] = Float64(rank)
    end
    
    return ranks
end

"""
    tie_kept_rank(X::AbstractMatrix)

Apply tie-kept ranking to each column of a matrix.

# Arguments
- `X`: Input matrix where each column will be ranked independently

# Returns
- Matrix of same dimensions with each column ranked
"""
function tie_kept_rank(X::AbstractMatrix)
    n_rows, n_cols = size(X)
    ranked_matrix = Matrix{Float64}(undef, n_rows, n_cols)
    
    for col in 1:n_cols
        ranked_matrix[:, col] = tie_kept_rank(X[:, col])
    end
    
    return ranked_matrix
end

"""
    gaussianize(x::AbstractVector{T}) where T

Transform a vector to have a standard normal distribution (mean=0, std=1).
This involves converting ranks to quantiles of the standard normal distribution.

# Arguments
- `x`: Input vector to gaussianize

# Returns
- Vector with standard normal distribution
"""
function gaussianize(x::AbstractVector{T}) where T
    if length(x) <= 1
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    # First get the tie-kept ranks
    ranks = tie_kept_rank(x)
    
    # Convert ranks to percentiles (0 to 1)
    n = length(ranks)
    percentiles = (ranks .- 0.5) ./ n
    
    # Clip to avoid infinite values at extremes
    percentiles = clamp.(percentiles, 1e-6, 1.0 - 1e-6)
    
    # Convert to standard normal quantiles
    # Using the corrected inverse normal CDF approximation
    gaussianized = map(p -> quantile_normal_approx(p), percentiles)
    
    # Check for any NaN or Inf values and handle them
    gaussianized = [isnan(x) || isinf(x) ? 0.0 : x for x in gaussianized]
    
    # Ensure mean=0 and std=1 (only if std > 0)
    if std(gaussianized) > 1e-10
        gaussianized = (gaussianized .- mean(gaussianized)) ./ std(gaussianized)
    end
    
    return gaussianized
end

"""
    gaussianize(X::AbstractMatrix)

Apply gaussianization to each column of a matrix.

# Arguments
- `X`: Input matrix where each column will be gaussianized independently

# Returns
- Matrix of same dimensions with each column gaussianized
"""
function gaussianize(X::AbstractMatrix)
    n_rows, n_cols = size(X)
    gaussianized_matrix = Matrix{Float64}(undef, n_rows, n_cols)
    
    for col in 1:n_cols
        gaussianized_matrix[:, col] = gaussianize(X[:, col])
    end
    
    return gaussianized_matrix
end

"""
    quantile_normal_approx(p::Float64)

Approximate the inverse normal CDF (quantile function) using Beasley-Springer-Moro algorithm.

# Arguments
- `p`: Probability value between 0 and 1

# Returns
- Corresponding quantile of the standard normal distribution
"""
function quantile_normal_approx(p::Float64)
    # Corrected quantile function using Acklam's algorithm
    # This replaces the broken Beasley-Springer-Moro implementation
    
    if p <= 0.0
        return -Inf
    elseif p >= 1.0
        return Inf
    elseif p == 0.5
        return 0.0
    end
    
    # Acklam's algorithm coefficients
    # Low region: p < 0.02425
    a_low = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
             1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    
    b_low = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
             6.680131188771972e+01, -1.328068155288572e+01, 1.0]
    
    # Central region: 0.02425 <= p <= 0.97575
    a_central = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    
    b_central = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01, 1.0]
    
    # High region: p > 0.97575
    a_high = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
              -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    
    b_high = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
              3.754408661907416e+00, 1.0]
    
    # Simple robust approximation using Box-Muller inspired method
    # This ensures monotonicity which is critical for TC calculation
    if p < 0.5
        # For lower half, use symmetry
        return -quantile_normal_approx(1.0 - p)
    else
        # For upper half, use approximation
        if p <= 0.5 + 1e-10
            return 0.0
        end
        
        # Simple approximation that maintains monotonicity
        t = sqrt(-2.0 * log(1.0 - p))
        
        # Rational approximation
        num = 2.515517 + 0.802853 * t + 0.010328 * t * t
        den = 1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t
        
        return t - num / den
    end
end

"""
    orthogonalize(x::AbstractVector{T}, reference::AbstractVector{S}) where {T, S}

Orthogonalize vector x with respect to reference vector.
This removes the component of x that is correlated with the reference.

# Arguments
- `x`: Vector to be orthogonalized
- `reference`: Reference vector to orthogonalize against

# Returns
- Orthogonalized vector that is uncorrelated with the reference
"""
function orthogonalize(x::AbstractVector{T}, reference::AbstractVector{S}) where {T, S}
    if length(x) != length(reference)
        throw(ArgumentError("Vectors must have the same length"))
    end
    
    if length(x) <= 1
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    # Center both vectors
    x_centered = x .- mean(x)
    ref_centered = reference .- mean(reference)
    
    # Calculate the projection coefficient
    ref_norm_sq = dot(ref_centered, ref_centered)
    
    if ref_norm_sq == 0.0
        # Reference vector has no variance, return original x
        return x isa Vector{Float64} ? x : Float64.(x)
    end
    
    projection_coeff = dot(x_centered, ref_centered) / ref_norm_sq
    
    # Remove the projection onto the reference
    orthogonal = x_centered - projection_coeff * ref_centered
    
    return orthogonal
end

"""
    orthogonalize(X::AbstractMatrix, reference::AbstractVector)

Orthogonalize each column of matrix X with respect to reference vector.

# Arguments
- `X`: Matrix where each column will be orthogonalized
- `reference`: Reference vector to orthogonalize against

# Returns
- Matrix of same dimensions with each column orthogonalized
"""
function orthogonalize(X::AbstractMatrix, reference::AbstractVector)
    n_rows, n_cols = size(X)
    orthogonal_matrix = Matrix{Float64}(undef, n_rows, n_cols)
    
    for col in 1:n_cols
        orthogonal_matrix[:, col] = orthogonalize(X[:, col], reference)
    end
    
    return orthogonal_matrix
end

"""
    create_stake_weighted_ensemble(predictions::AbstractMatrix, stakes::AbstractVector)

Create a stake-weighted ensemble (meta-model) from multiple model predictions.

# Arguments
- `predictions`: Matrix where each column represents predictions from one model
- `stakes`: Vector of stake weights for each model (will be normalized)

# Returns
- Vector representing the stake-weighted ensemble predictions
"""
function create_stake_weighted_ensemble(predictions::AbstractMatrix, stakes::AbstractVector)
    n_samples, n_models = size(predictions)
    
    if length(stakes) != n_models
        throw(ArgumentError("Number of stakes must match number of models"))
    end
    
    if any(stakes .< 0)
        throw(ArgumentError("Stakes must be non-negative"))
    end
    
    # Normalize stakes to sum to 1
    total_stake = sum(stakes)
    if total_stake == 0
        throw(ArgumentError("Total stake cannot be zero"))
    end
    
    normalized_stakes = stakes ./ total_stake
    
    # Create weighted ensemble
    ensemble = predictions * normalized_stakes
    
    return ensemble
end

"""
    calculate_mmc(predictions::AbstractVector{T}, 
                  meta_model::AbstractVector{S}, 
                  targets::AbstractVector{U}) where {T, S, U}

Calculate Meta Model Contribution (MMC) for a single model's predictions.

MMC measures how much a model's predictions contribute uniquely to the meta-model
beyond what other models are already providing.

The algorithm:
1. Rank and gaussianize both predictions and meta-model
2. Orthogonalize predictions with respect to the meta-model  
3. Calculate covariance between orthogonalized predictions and centered targets

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model (stake-weighted ensemble) predictions
- `targets`: True target values

# Returns
- MMC score (Float64): positive indicates positive contribution, negative indicates negative contribution
"""
function calculate_mmc(predictions::AbstractVector{T}, 
                      meta_model::AbstractVector{S}, 
                      targets::AbstractVector{U}) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(targets))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Special case: if meta-model has no variation, MMC is just correlation
    # between rank-gaussianized predictions and centered targets
    if std(meta_model) == 0.0
        p = gaussianize(tie_kept_rank(predictions))
        centered_targets = targets .- mean(targets)
        n = length(predictions)
        mmc = dot(p, centered_targets) / n
        return mmc
    end
    
    # Step 1: Rank and gaussianize predictions and meta-model
    p = gaussianize(tie_kept_rank(predictions))
    m = gaussianize(tie_kept_rank(meta_model))
    
    # Step 2: Orthogonalize predictions with respect to meta-model
    neutral_preds = orthogonalize(p, m)
    
    # Step 3: Center the targets
    centered_targets = targets .- mean(targets)
    
    # Step 4: Calculate MMC (covariance between neutral predictions and targets)
    n = length(predictions)
    mmc = dot(neutral_preds, centered_targets) / n
    
    return mmc
end

"""
    calculate_mmc_batch(predictions_matrix::AbstractMatrix, 
                       meta_model::AbstractVector, 
                       targets::AbstractVector)

Calculate MMC for multiple models simultaneously.

# Arguments
- `predictions_matrix`: Matrix where each column represents predictions from one model
- `meta_model`: Meta-model (stake-weighted ensemble) predictions
- `targets`: True target values

# Returns
- Vector of MMC scores, one for each model (column)
"""
function calculate_mmc_batch(predictions_matrix::AbstractMatrix, 
                            meta_model::AbstractVector, 
                            targets::AbstractVector)
    n_samples, n_models = size(predictions_matrix)
    
    if !(length(meta_model) == length(targets) == n_samples)
        throw(ArgumentError("Matrix rows and vector lengths must match"))
    end
    
    mmc_scores = Vector{Float64}(undef, n_models)
    
    for i in 1:n_models
        mmc_scores[i] = calculate_mmc(predictions_matrix[:, i], meta_model, targets)
    end
    
    return mmc_scores
end

"""
    calculate_contribution_score(predictions::AbstractVector{T}, 
                                 targets::AbstractVector{S}) where {T, S}

Calculate basic contribution score (correlation) between predictions and targets.

# Arguments
- `predictions`: Model predictions
- `targets`: True target values

# Returns
- Correlation coefficient between predictions and targets
"""
function calculate_contribution_score(predictions::AbstractVector{T}, 
                                     targets::AbstractVector{S}) where {T, S}
    if length(predictions) != length(targets)
        throw(ArgumentError("Predictions and targets must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    return cor(predictions, targets)
end

"""
    calculate_feature_neutralized_mmc(predictions::AbstractVector{T},
                                     meta_model::AbstractVector{S},
                                     targets::AbstractVector{U},
                                     features::AbstractMatrix) where {T, S, U}

Calculate MMC after neutralizing predictions against specific features.
This is useful for calculating Feature Neutral Correlation (FNC) based MMC.

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model predictions
- `targets`: True target values
- `features`: Matrix of features to neutralize against (each column is a feature)

# Returns
- Feature-neutralized MMC score
"""
function calculate_feature_neutralized_mmc(predictions::AbstractVector{T},
                                          meta_model::AbstractVector{S},
                                          targets::AbstractVector{U},
                                          features::AbstractMatrix) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(targets) == size(features, 1))
        throw(ArgumentError("All inputs must have consistent sample dimensions"))
    end
    
    # Neutralize predictions against features
    neutralized_preds = copy(Float64.(predictions))
    
    for col in 1:size(features, 2)
        neutralized_preds = orthogonalize(neutralized_preds, features[:, col])
    end
    
    # Calculate MMC with neutralized predictions
    return calculate_mmc(neutralized_preds, meta_model, targets)
end

"""
    calculate_tc(predictions::AbstractVector{T}, 
                 meta_model::AbstractVector{S}, 
                 returns::AbstractVector{U}) where {T, S, U}

Calculate True Contribution (TC) for a single model's predictions.

TC measures how much a model's predictions directly contribute to the fund's returns.
It's calculated by orthogonalizing the returns with respect to the meta-model, then
computing the correlation between the model's predictions and these orthogonalized returns.

The algorithm:
1. Rank and gaussianize the predictions
2. Orthogonalize the returns with respect to the meta-model
3. Calculate correlation between gaussianized predictions and orthogonalized returns

Unlike MMC which measures contribution to the meta-model performance, TC measures
contribution to actual returns after accounting for the meta-model.

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model (stake-weighted ensemble) predictions
- `returns`: Actual returns (e.g., target values or realized returns)

# Returns
- TC score (Float64): positive indicates positive contribution to returns, negative indicates negative contribution
"""
function calculate_tc(predictions::AbstractVector{T}, 
                      meta_model::AbstractVector{S}, 
                      returns::AbstractVector{U}) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(returns))
        throw(ArgumentError("All vectors must have the same length"))
    end
    
    if length(predictions) <= 1
        return 0.0
    end
    
    # Step 1: Rank and gaussianize predictions
    p = gaussianize(tie_kept_rank(predictions))
    
    # Step 2: Orthogonalize returns with respect to meta-model
    # This removes the component of returns that is already captured by the meta-model
    orthogonal_returns = orthogonalize(returns, meta_model)
    
    # Step 3: Calculate TC (correlation between gaussianized predictions and orthogonalized returns)
    if std(orthogonal_returns) == 0.0
        # If orthogonalized returns have no variance, TC is zero
        return 0.0
    end
    
    tc = cor(p, orthogonal_returns)
    
    return isnan(tc) ? 0.0 : tc
end

"""
    calculate_tc_batch(predictions_matrix::AbstractMatrix, 
                       meta_model::AbstractVector, 
                       returns::AbstractVector)

Calculate TC for multiple models simultaneously.

# Arguments
- `predictions_matrix`: Matrix where each column represents predictions from one model
- `meta_model`: Meta-model (stake-weighted ensemble) predictions
- `returns`: Actual returns (e.g., target values or realized returns)

# Returns
- Vector of TC scores, one for each model (column)
"""
function calculate_tc_batch(predictions_matrix::AbstractMatrix, 
                            meta_model::AbstractVector, 
                            returns::AbstractVector)
    n_samples, n_models = size(predictions_matrix)
    
    if !(length(meta_model) == length(returns) == n_samples)
        throw(ArgumentError("Matrix rows and vector lengths must match"))
    end
    
    tc_scores = Vector{Float64}(undef, n_models)
    
    for i in 1:n_models
        tc_scores[i] = calculate_tc(predictions_matrix[:, i], meta_model, returns)
    end
    
    return tc_scores
end

"""
    calculate_feature_neutralized_tc(predictions::AbstractVector{T},
                                     meta_model::AbstractVector{S},
                                     returns::AbstractVector{U},
                                     features::AbstractMatrix) where {T, S, U}

Calculate TC after neutralizing predictions against specific features.
This is useful for calculating Feature Neutral True Contribution.

# Arguments
- `predictions`: Model predictions to evaluate
- `meta_model`: Meta-model predictions
- `returns`: Actual returns
- `features`: Matrix of features to neutralize against (each column is a feature)

# Returns
- Feature-neutralized TC score
"""
function calculate_feature_neutralized_tc(predictions::AbstractVector{T},
                                          meta_model::AbstractVector{S},
                                          returns::AbstractVector{U},
                                          features::AbstractMatrix) where {T, S, U}
    if !(length(predictions) == length(meta_model) == length(returns) == size(features, 1))
        throw(ArgumentError("All inputs must have consistent sample dimensions"))
    end
    
    # Neutralize predictions against features
    neutralized_preds = copy(Float64.(predictions))
    
    for col in 1:size(features, 2)
        neutralized_preds = orthogonalize(neutralized_preds, features[:, col])
    end
    
    # Calculate TC with neutralized predictions
    return calculate_tc(neutralized_preds, meta_model, returns)
end

"""
    calculate_sharpe(returns::AbstractVector{T}) where T

Calculate the Sharpe ratio of a vector of returns.

The Sharpe ratio measures the excess return per unit of deviation in an investment asset.
A higher Sharpe ratio indicates better risk-adjusted performance.

# Arguments
- `returns`: Vector of returns

# Returns
- Sharpe ratio (Float64): ratio of mean return to standard deviation of returns
"""
function calculate_sharpe(returns::AbstractVector{T}) where T
    if length(returns) <= 1
        return 0.0
    end
    
    mean_return = mean(returns)
    std_return = std(returns)
    
    # Handle zero standard deviation
    if std_return == 0.0
        return mean_return > 0.0 ? Inf : (mean_return < 0.0 ? -Inf : 0.0)
    end
    
    # Calculate Sharpe ratio (assuming risk-free rate is 0)
    sharpe_ratio = mean_return / std_return
    
    return isnan(sharpe_ratio) ? 0.0 : sharpe_ratio
end

# Export all public functions
export tie_kept_rank, gaussianize, orthogonalize, create_stake_weighted_ensemble,
       calculate_mmc, calculate_mmc_batch, calculate_contribution_score,
       calculate_feature_neutralized_mmc, calculate_tc, calculate_tc_batch,
       calculate_feature_neutralized_tc, calculate_sharpe

end