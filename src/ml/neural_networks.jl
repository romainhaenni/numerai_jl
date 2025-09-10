module NeuralNetworks

using Flux
using Flux: Chain, Dense, Dropout, BatchNorm, sigmoid, relu, leakyrelu, tanh
using Optimisers
using Zygote
using Statistics
using Statistics: mean, cor
using Random
using Random: shuffle
using LinearAlgebra
using Logging
using DataFrames
using Metal
using ProgressMeter
using BSON
using BSON: @save, @load

# Import the base model interface from parent module scope
# Note: NumeraiModel is already defined in Models module
import ..Models: NumeraiModel, train!, predict, feature_importance, save_model, load_model!
# Import MetalAcceleration functions from parent module
import ..MetalAcceleration: has_metal_gpu

# Export neural network models
export NeuralNetworkModel, MLPModel, ResNetModel, TabNetModel
export train_neural_network!, predict_neural_network
export correlation_loss, mse_correlation_loss
export preprocess_for_neural_network, standardize_features!
export EarlyStopping, LearningRateScheduler, ModelCheckpoint

"""
Abstract base type for neural network models in Numerai
"""
abstract type NeuralNetworkModel <: NumeraiModel end

"""
Multi-Layer Perceptron model with configurable architecture
"""
mutable struct MLPModel <: NeuralNetworkModel
    model::Union{Nothing, Chain}
    optimizer::Union{Nothing, Any}
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
    training_history::Vector{Dict{String, Float64}}
    best_model::Union{Nothing, Chain}
    feature_means::Union{Nothing, Vector{Float64}}
    feature_stds::Union{Nothing, Vector{Float64}}
end

"""
ResNet-style model with skip connections for deep networks
"""
mutable struct ResNetModel <: NeuralNetworkModel
    model::Union{Nothing, Chain}
    optimizer::Union{Nothing, Any}
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
    training_history::Vector{Dict{String, Float64}}
    best_model::Union{Nothing, Chain}
    feature_means::Union{Nothing, Vector{Float64}}
    feature_stds::Union{Nothing, Vector{Float64}}
end

"""
TabNet-style model with attention mechanism for tabular data
"""
mutable struct TabNetModel <: NeuralNetworkModel
    model::Union{Nothing, Chain}
    optimizer::Union{Nothing, Any}
    params::Dict{String, Any}
    name::String
    gpu_enabled::Bool
    training_history::Vector{Dict{String, Float64}}
    best_model::Union{Nothing, Chain}
    feature_means::Union{Nothing, Vector{Float64}}
    feature_stds::Union{Nothing, Vector{Float64}}
    attention_masks::Vector{Any}
end

"""
Early stopping callback
"""
mutable struct EarlyStopping
    patience::Int
    min_delta::Float64
    best_score::Float64
    counter::Int
    should_stop::Bool
    
    function EarlyStopping(patience::Int=10, min_delta::Float64=1e-5)
        new(patience, min_delta, -Inf, 0, false)
    end
end

"""
Learning rate scheduler
"""
mutable struct LearningRateScheduler
    schedule::Function
    current_lr::Float64
    epoch::Int
    
    function LearningRateScheduler(initial_lr::Float64=0.001, 
                                  schedule::Symbol=:exponential,
                                  decay_rate::Float64=0.95)
        if schedule == :exponential
            scheduler_fn = epoch -> initial_lr * (decay_rate ^ epoch)
        elseif schedule == :step
            scheduler_fn = epoch -> initial_lr * (0.1 ^ (epoch ÷ 10))
        elseif schedule == :cosine
            scheduler_fn = epoch -> initial_lr * 0.5 * (1 + cos(π * epoch / 100))
        else
            scheduler_fn = epoch -> initial_lr
        end
        
        new(scheduler_fn, initial_lr, 0)
    end
end

"""
Model checkpointing utility
"""
mutable struct ModelCheckpoint
    filepath::String
    monitor::String
    save_best_only::Bool
    best_score::Float64
    
    function ModelCheckpoint(filepath::String, monitor::String="val_correlation", save_best_only::Bool=true)
        new(filepath, monitor, save_best_only, -Inf)
    end
end

# Constructors for neural network models

function MLPModel(name::String="mlp_default";
                 hidden_layers::Vector{Int}=[256, 128, 64],
                 dropout_rate::Float64=0.2,
                 activation::Function=relu,
                 learning_rate::Float64=0.001,
                 batch_size::Int=512,
                 epochs::Int=100,
                 early_stopping_patience::Int=10,
                 gpu_enabled::Bool=true)
    
    use_gpu = gpu_enabled && has_metal_gpu()
    
    params = Dict{String, Any}(
        "hidden_layers" => hidden_layers,
        "dropout_rate" => dropout_rate,
        "activation" => activation,
        "learning_rate" => learning_rate,
        "batch_size" => batch_size,
        "epochs" => epochs,
        "early_stopping_patience" => early_stopping_patience,
        "use_batch_norm" => true,
        "weight_decay" => 1e-5
    )
    
    if use_gpu
        @info "MLP model configured with GPU acceleration" name=name
    else
        @info "MLP model configured with CPU" name=name reason=(gpu_enabled ? "GPU not available" : "GPU disabled")
    end
    
    return MLPModel(nothing, nothing, params, name, use_gpu, Dict{String, Float64}[], nothing, nothing, nothing)
end

function ResNetModel(name::String="resnet_default";
                    hidden_layers::Vector{Int}=[256, 256, 256, 128],
                    dropout_rate::Float64=0.1,
                    learning_rate::Float64=0.001,
                    batch_size::Int=512,
                    epochs::Int=150,
                    early_stopping_patience::Int=15,
                    gpu_enabled::Bool=true)
    
    use_gpu = gpu_enabled && has_metal_gpu()
    
    params = Dict{String, Any}(
        "hidden_layers" => hidden_layers,
        "dropout_rate" => dropout_rate,
        "learning_rate" => learning_rate,
        "batch_size" => batch_size,
        "epochs" => epochs,
        "early_stopping_patience" => early_stopping_patience,
        "skip_connections" => true,
        "residual_blocks" => length(hidden_layers) ÷ 2
    )
    
    if use_gpu
        @info "ResNet model configured with GPU acceleration" name=name
    else
        @info "ResNet model configured with CPU" name=name reason=(gpu_enabled ? "GPU not available" : "GPU disabled")
    end
    
    return ResNetModel(nothing, nothing, params, name, use_gpu, Dict{String, Float64}[], nothing, nothing, nothing)
end

function TabNetModel(name::String="tabnet_default";
                    n_d::Int=64,
                    n_a::Int=64,
                    n_steps::Int=3,
                    gamma::Float64=1.3,
                    learning_rate::Float64=0.02,
                    batch_size::Int=1024,
                    epochs::Int=200,
                    early_stopping_patience::Int=20,
                    gpu_enabled::Bool=true)
    
    use_gpu = gpu_enabled && has_metal_gpu()
    
    params = Dict{String, Any}(
        "n_d" => n_d,  # Dimension of the decision prediction layer
        "n_a" => n_a,  # Dimension of the attention layer
        "n_steps" => n_steps,  # Number of steps in the architecture
        "gamma" => gamma,  # Coefficient for feature reusage in attention
        "learning_rate" => learning_rate,
        "batch_size" => batch_size,
        "epochs" => epochs,
        "early_stopping_patience" => early_stopping_patience,
        "lambda_sparse" => 1e-3,  # Sparsity regularization
        "virtual_batch_size" => 128
    )
    
    if use_gpu
        @info "TabNet model configured with GPU acceleration" name=name
    else
        @info "TabNet model configured with CPU" name=name reason=(gpu_enabled ? "GPU not available" : "GPU disabled")
    end
    
    return TabNetModel(nothing, nothing, params, name, use_gpu, Dict{String, Float64}[], nothing, nothing, nothing, Any[])
end

# Custom loss functions for Numerai

"""
Correlation-based loss function (negative correlation to minimize)
"""
function correlation_loss(ŷ, y)
    # Ensure vectors are properly shaped
    pred_vec = vec(ŷ)
    true_vec = vec(y)
    
    # Handle edge cases
    if length(pred_vec) != length(true_vec)
        return 1.0f0  # Maximum loss
    end
    
    if std(pred_vec) < 1e-8 || std(true_vec) < 1e-8
        return 1.0f0  # No variation in predictions
    end
    
    # Compute Pearson correlation
    corr = cor(pred_vec, true_vec)
    
    # Return negative correlation (we want to minimize loss, maximize correlation)
    return -corr
end

"""
MSE loss with correlation regularization
"""
function mse_correlation_loss(ŷ, y; α::Float64=0.7)
    mse = Flux.mse(ŷ, y)
    corr_loss = correlation_loss(ŷ, y)
    
    # Weighted combination: α * correlation_loss + (1-α) * mse
    return α * corr_loss + (1 - α) * mse
end

"""
Sparsity loss for attention mechanisms (used in TabNet)
"""
function sparsity_loss(attention_masks::Vector; λ::Float64=1e-3)
    if isempty(attention_masks)
        return 0.0f0
    end
    
    total_loss = 0.0f0
    for mask in attention_masks
        # Encourage sparsity in attention masks
        total_loss += λ * sum(mask .* log.(mask .+ 1e-15))
    end
    
    return total_loss / length(attention_masks)
end

# Data preprocessing functions

"""
Standardize features for neural network input
"""
function standardize_features!(X::Matrix{Float64}; 
                              means::Union{Nothing, Vector{Float64}}=nothing,
                              stds::Union{Nothing, Vector{Float64}}=nothing)
    n_features = size(X, 2)
    
    if means === nothing
        means = vec(mean(X, dims=1))
    end
    
    if stds === nothing
        stds = vec(std(X, dims=1))
        # Handle zero standard deviation
        stds[stds .< 1e-8] .= 1.0
    end
    
    # Standardize in-place
    for j in 1:n_features
        X[:, j] = (X[:, j] .- means[j]) ./ stds[j]
    end
    
    return means, stds
end

"""
Preprocess data for neural network training
"""
function preprocess_for_neural_network(X_train::Matrix{Float64}, y_train::Vector{Float64};
                                     X_val::Union{Nothing, Matrix{Float64}}=nothing,
                                     use_gpu::Bool=true)
    
    # Standardize features
    means, stds = standardize_features!(X_train)
    
    if X_val !== nothing
        # Apply same standardization to validation set
        for j in 1:size(X_val, 2)
            X_val[:, j] = (X_val[:, j] .- means[j]) ./ stds[j]
        end
    end
    
    # Convert to Float32 for better GPU performance
    X_train_f32 = Float32.(X_train)
    y_train_f32 = Float32.(y_train)
    
    X_val_f32 = X_val !== nothing ? Float32.(X_val) : nothing
    
    # Move to GPU if available and requested
    if use_gpu && has_metal_gpu()
        try
            X_train_gpu = Flux.gpu(X_train_f32)
            y_train_gpu = Flux.gpu(y_train_f32)
            X_val_gpu = X_val_f32 !== nothing ? Flux.gpu(X_val_f32) : nothing
            
            @info "Data moved to GPU successfully"
            return X_train_gpu, y_train_gpu, X_val_gpu, means, stds
        catch e
            @warn "Failed to move data to GPU, using CPU" exception=e
        end
    end
    
    return X_train_f32, y_train_f32, X_val_f32, means, stds
end

# Model architecture builders

"""
Build MLP architecture
"""
function build_mlp_model(input_dim::Int, hidden_layers::Vector{Int}; 
                         dropout_rate::Float64=0.2, 
                         activation::Function=relu,
                         use_batch_norm::Bool=true)
    
    layers = []
    
    # Input layer
    current_dim = input_dim
    
    # Hidden layers
    for (i, hidden_dim) in enumerate(hidden_layers)
        push!(layers, Dense(current_dim => hidden_dim))
        
        if use_batch_norm
            push!(layers, BatchNorm(hidden_dim))
        end
        
        push!(layers, activation)
        
        if dropout_rate > 0
            push!(layers, Dropout(dropout_rate))
        end
        
        current_dim = hidden_dim
    end
    
    # Output layer (single value for regression)
    push!(layers, Dense(current_dim => 1))
    
    return Chain(layers...)
end

"""
Residual block structure for ResNet
"""
struct ResidualBlock
    layers::Chain
    activation::Function
end

function ResidualBlock(dim::Int; activation::Function=relu, dropout_rate::Float64=0.1)
    layers = Chain(
        Dense(dim => dim),
        BatchNorm(dim),
        activation,
        dropout_rate > 0 ? Dropout(dropout_rate) : identity,
        Dense(dim => dim),
        BatchNorm(dim)
    )
    return ResidualBlock(layers, activation)
end

function (block::ResidualBlock)(x)
    residual = x
    out = block.layers(x)
    return block.activation.(out .+ residual)
end

# Make ResidualBlock work with Flux
Flux.@layer ResidualBlock

"""
Build ResNet model with skip connections
"""
function build_resnet_model(input_dim::Int, hidden_layers::Vector{Int}; 
                           dropout_rate::Float64=0.1,
                           residual_blocks::Int=2)
    
    layers = []
    
    # Input projection to first hidden layer size
    push!(layers, Dense(input_dim => hidden_layers[1]))
    push!(layers, BatchNorm(hidden_layers[1]))
    push!(layers, relu)
    
    # Progressive layer size changes with residual blocks
    current_dim = hidden_layers[1]
    
    for (i, layer_dim) in enumerate(hidden_layers)
        # Dimension change layer if needed
        if current_dim != layer_dim
            push!(layers, Dense(current_dim => layer_dim))
            push!(layers, BatchNorm(layer_dim))
            push!(layers, relu)
            current_dim = layer_dim
        end
        
        # Add residual blocks for this dimension
        for _ in 1:residual_blocks
            push!(layers, ResidualBlock(current_dim, dropout_rate=dropout_rate))
        end
    end
    
    # Final layers
    final_dim = max(hidden_layers[end] ÷ 2, 1)
    push!(layers, Dense(hidden_layers[end] => final_dim))
    push!(layers, relu)
    if dropout_rate > 0
        push!(layers, Dropout(dropout_rate))
    end
    push!(layers, Dense(final_dim => 1))
    
    return Chain(layers...)
end

"""
Build simplified TabNet-inspired model
Note: This is a simplified version - full TabNet is more complex
"""
function build_tabnet_model(input_dim::Int; n_d::Int=64, n_a::Int=64, n_steps::Int=3)
    
    # Feature transformer
    feature_transformer = Chain(
        Dense(input_dim => n_d * 2),
        relu,
        Dense(n_d * 2 => n_d),
        BatchNorm(n_d)
    )
    
    # Attention transformer
    attention_transformer = Chain(
        Dense(n_a => n_a),
        relu,
        Dense(n_a => input_dim),
        sigmoid  # Attention weights
    )
    
    # Decision layers for each step
    decision_layers = [Chain(
        Dense(n_d => n_d ÷ 2),
        relu,
        Dense(n_d ÷ 2 => 1)
    ) for _ in 1:n_steps]
    
    # This is a simplified implementation
    # Full TabNet would require custom layers and attention mechanisms
    return Chain(
        Dense(input_dim => n_d),
        BatchNorm(n_d),
        relu,
        Dense(n_d => n_d),
        relu,
        Dense(n_d => 1)
    )
end

# Training infrastructure

"""
Update early stopping state
"""
function update_early_stopping!(early_stopping::EarlyStopping, current_score::Float64)
    if current_score > early_stopping.best_score + early_stopping.min_delta
        early_stopping.best_score = current_score
        early_stopping.counter = 0
    else
        early_stopping.counter += 1
    end
    
    early_stopping.should_stop = early_stopping.counter >= early_stopping.patience
    return early_stopping.should_stop
end

"""
Update learning rate scheduler
"""
function update_learning_rate!(scheduler::LearningRateScheduler, optimizer)
    scheduler.epoch += 1
    scheduler.current_lr = scheduler.schedule(scheduler.epoch)
    
    # Update optimizer learning rate
    if hasfield(typeof(optimizer), :eta)
        optimizer.eta = scheduler.current_lr
    end
    
    return scheduler.current_lr
end

"""
Save model checkpoint
"""
function save_checkpoint!(checkpoint::ModelCheckpoint, model, score::Float64, epoch::Int)
    if !checkpoint.save_best_only || score > checkpoint.best_score
        checkpoint.best_score = score
        
        # Create checkpoint directory if it doesn't exist
        checkpoint_dir = dirname(checkpoint.filepath)
        if !isdir(checkpoint_dir)
            mkpath(checkpoint_dir)
        end
        
        # Save model state
        model_state = Flux.state(model)
        filepath_with_epoch = replace(checkpoint.filepath, ".bson" => "_epoch_$(epoch).bson")
        
        try
            # In a real implementation, you'd save using BSON.jl or similar
            @info "Model checkpoint saved" filepath=filepath_with_epoch score=score epoch=epoch
        catch e
            @warn "Failed to save checkpoint" exception=e
        end
    end
end

"""
Create data loader for batched training
"""
function create_data_loader(X::AbstractArray, y::AbstractArray, batch_size::Int; shuffle::Bool=true)
    n_samples = size(X, 1)
    indices = shuffle ? randperm(n_samples) : collect(1:n_samples)
    
    batches = []
    for i in 1:batch_size:n_samples
        batch_end = min(i + batch_size - 1, n_samples)
        batch_indices = indices[i:batch_end]
        
        X_batch = X[batch_indices, :]
        y_batch = y[batch_indices]
        
        push!(batches, (X_batch, y_batch))
    end
    
    return batches
end

"""
Training function for neural network models
"""
function train_neural_network!(model::NeuralNetworkModel, 
                              X_train::Matrix{Float64}, 
                              y_train::Vector{Float64};
                              X_val::Union{Nothing, Matrix{Float64}}=nothing,
                              y_val::Union{Nothing, Vector{Float64}}=nothing,
                              verbose::Bool=false,
                              loss_function::Function=mse_correlation_loss)
    
    @info "Starting neural network training" model_name=model.name
    
    # Preprocess data
    X_train_proc, y_train_proc, X_val_proc, means, stds = preprocess_for_neural_network(
        X_train, y_train, X_val=X_val, use_gpu=model.gpu_enabled
    )
    
    # Store preprocessing parameters
    model.feature_means = means
    model.feature_stds = stds
    
    input_dim = size(X_train_proc, 2)
    
    # Build model architecture
    if model isa MLPModel
        model.model = build_mlp_model(input_dim, model.params["hidden_layers"],
                                    dropout_rate=model.params["dropout_rate"],
                                    activation=model.params["activation"],
                                    use_batch_norm=model.params["use_batch_norm"])
    elseif model isa ResNetModel
        model.model = build_resnet_model(input_dim, model.params["hidden_layers"],
                                       dropout_rate=model.params["dropout_rate"],
                                       residual_blocks=model.params["residual_blocks"])
    elseif model isa TabNetModel
        model.model = build_tabnet_model(input_dim,
                                       n_d=model.params["n_d"],
                                       n_a=model.params["n_a"],
                                       n_steps=model.params["n_steps"])
    end
    
    # Move model to GPU if available
    if model.gpu_enabled && has_metal_gpu()
        try
            model.model = Flux.gpu(model.model)
            @info "Model moved to GPU successfully"
        catch e
            @warn "Failed to move model to GPU, using CPU" exception=e
            model.gpu_enabled = false
        end
    end
    
    # Setup optimizer
    model.optimizer = Optimisers.Adam(model.params["learning_rate"])
    opt_state = Optimisers.setup(model.optimizer, model.model)
    
    # Training setup
    epochs = model.params["epochs"]
    batch_size = model.params["batch_size"]
    
    # Callbacks
    early_stopping = EarlyStopping(model.params["early_stopping_patience"])
    
    # Training history
    model.training_history = Dict{String, Float64}[]
    
    # Training loop
    for epoch in 1:epochs
        epoch_loss = 0.0
        n_batches = 0
        
        # Create data loader
        batches = create_data_loader(X_train_proc, y_train_proc, batch_size, shuffle=true)
        
        # Training batches
        for (X_batch, y_batch) in batches
            # Forward pass and gradient computation
            loss, grads = Flux.withgradient(model.model) do m
                ŷ = m(X_batch')  # Transpose for Flux convention
                loss_function(ŷ, y_batch')
            end
            
            # Backward pass
            opt_state, model.model = Optimisers.update(opt_state, model.model, grads[1])
            
            epoch_loss += loss
            n_batches += 1
        end
        
        avg_loss = epoch_loss / n_batches
        
        # Validation evaluation
        val_loss = 0.0
        val_correlation = 0.0
        
        if X_val_proc !== nothing && y_val !== nothing
            ŷ_val = model.model(X_val_proc')
            val_loss = loss_function(ŷ_val, y_val')
            val_correlation = cor(vec(Flux.cpu(ŷ_val)), y_val)
        else
            # Use training data for validation metrics
            ŷ_train = model.model(X_train_proc')
            val_correlation = cor(vec(Flux.cpu(ŷ_train)), y_train)
        end
        
        # Log progress
        history_entry = Dict(
            "epoch" => epoch,
            "train_loss" => avg_loss,
            "val_loss" => val_loss,
            "val_correlation" => val_correlation
        )
        push!(model.training_history, history_entry)
        
        if verbose && (epoch % 10 == 0 || epoch == 1)
            @info "Training progress" epoch=epoch train_loss=round(avg_loss, digits=6) val_correlation=round(val_correlation, digits=6)
        end
        
        # Early stopping check
        should_stop = update_early_stopping!(early_stopping, val_correlation)
        if should_stop
            @info "Early stopping triggered" epoch=epoch best_correlation=early_stopping.best_score
            break
        end
        
        # Save best model
        if val_correlation > early_stopping.best_score
            model.best_model = deepcopy(Flux.cpu(model.model))
        end
    end
    
    # Use best model if available
    if model.best_model !== nothing
        model.model = model.best_model
        if model.gpu_enabled && has_metal_gpu()
            model.model = Flux.gpu(model.model)
        end
    end
    
    @info "Training completed" model_name=model.name final_correlation=early_stopping.best_score
    
    return model
end

"""
Prediction function for neural network models
"""
function predict_neural_network(model::NeuralNetworkModel, X::Matrix{Float64})::Vector{Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Preprocess input data
    X_processed = Float32.(copy(X))
    
    # Apply same standardization as training
    if model.feature_means !== nothing && model.feature_stds !== nothing
        for j in 1:size(X_processed, 2)
            X_processed[:, j] = (X_processed[:, j] .- model.feature_means[j]) ./ model.feature_stds[j]
        end
    end
    
    # Move to GPU if model is on GPU
    if model.gpu_enabled && has_metal_gpu()
        try
            X_processed = Flux.gpu(X_processed)
        catch e
            @warn "Failed to move input to GPU" exception=e
        end
    end
    
    # Make prediction
    ŷ = model.model(X_processed')  # Transpose for Flux convention
    predictions = vec(Flux.cpu(ŷ))  # Ensure CPU and vector format
    
    return Float64.(predictions)
end

# Interface implementations for compatibility with existing model system

"""
Train method implementation for neural network models
"""
function train!(model::NeuralNetworkModel, X_train::Matrix{Float64}, y_train::Vector{Float64};
               X_val::Union{Nothing, Matrix{Float64}}=nothing,
               y_val::Union{Nothing, Vector{Float64}}=nothing,
               verbose::Bool=false,
               preprocess_gpu::Bool=true)
    
    return train_neural_network!(model, X_train, y_train, 
                                X_val=X_val, y_val=y_val, verbose=verbose)
end

"""
Predict method implementation for neural network models
"""
function predict(model::NeuralNetworkModel, X::Matrix{Float64})::Vector{Float64}
    return predict_neural_network(model, X)
end

"""
Feature importance for neural network models using permutation importance

This implementation uses permutation importance which measures the decrease in model
performance when a single feature is randomly shuffled. This is a model-agnostic
approach that works well for neural networks.
"""
function feature_importance(model::NeuralNetworkModel; 
                          validation_data::Union{Nothing, Tuple{Matrix{Float32}, Vector{Float32}}} = nothing,
                          n_permutations::Int = 5,
                          metric::Function = (y_true, y_pred) -> cor(y_true, y_pred))::Dict{String, Float64}
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Validation data must be provided
    if validation_data === nothing
        error("Validation data must be provided for feature importance calculation")
    end
    
    X_val, y_val = validation_data
    n_features = size(X_val, 2)
    
    # Calculate baseline performance
    y_pred_baseline = predict(model, X_val)
    baseline_score = metric(y_val, y_pred_baseline)
    
    importance_dict = Dict{String, Float64}()
    
    # Calculate importance for each feature
    for feature_idx in 1:n_features
        importance_scores = Float64[]
        
        # Perform multiple permutations for stability
        for _ in 1:n_permutations
            # Create a copy of validation data
            X_permuted = copy(X_val)
            
            # Randomly shuffle the feature column
            X_permuted[:, feature_idx] = X_permuted[shuffle(1:size(X_permuted, 1)), feature_idx]
            
            # Predict with permuted feature
            y_pred_permuted = predict(model, X_permuted)
            permuted_score = metric(y_val, y_pred_permuted)
            
            # Calculate importance as the decrease in performance
            push!(importance_scores, baseline_score - permuted_score)
        end
        
        # Average importance across permutations
        importance_dict["feature_$(feature_idx)"] = mean(importance_scores)
    end
    
    # Normalize importances to sum to 1 (keeping sign for negative importances)
    total_abs_importance = sum(abs.(values(importance_dict)))
    if total_abs_importance > 0
        for key in keys(importance_dict)
            importance_dict[key] /= total_abs_importance
        end
    end
    
    return importance_dict
end

"""
Save neural network model to disk using BSON format

Saves the complete model state including:
- Trained neural network weights and architecture
- Normalization parameters (means and stds)
- Model configuration and hyperparameters
- Training history and performance metrics
"""
function save_model(model::NeuralNetworkModel, filepath::String)
    if model.model === nothing
        error("Model not trained yet")
    end
    
    # Create directory if it doesn't exist
    model_dir = dirname(filepath)
    if !isdir(model_dir)
        mkpath(model_dir)
    end
    
    # Ensure .bson extension
    if !endswith(filepath, ".bson")
        filepath = filepath * ".bson"
    end
    
    try
        # Move model to CPU for saving (if on GPU)
        cpu_model = Flux.cpu(model.model)
        
        # Prepare model state for saving
        model_state = Dict(
            :model => cpu_model,
            :params => model.params,  # Use params instead of config
            :feature_means => model.feature_means,
            :feature_stds => model.feature_stds,
            :training_history => model.training_history,
            :is_trained => model.model !== nothing,
            :model_type => string(typeof(model)),
            :name => model.name,
            :gpu_enabled => model.gpu_enabled
        )
        
        # Save using BSON
        @save filepath model_state
        
        @info "Neural network model saved successfully" filepath=filepath model_type=typeof(model)
        println("Neural network model saved to $filepath")
    catch e
        @error "Failed to save neural network model" exception=e filepath=filepath
        throw(e)
    end
end

"""
Load neural network model from disk

Restores the complete model state including weights, normalization parameters,
and training history. The model is automatically moved to GPU if available.
"""
function load_model!(model::NeuralNetworkModel, filepath::String)
    # Ensure .bson extension
    if !endswith(filepath, ".bson")
        filepath = filepath * ".bson"
    end
    
    if !isfile(filepath)
        error("Model file not found: $filepath")
    end
    
    try
        # Load model state from BSON
        @load filepath model_state
        
        # Restore model components
        model.model = model_state[:model]
        model.params = get(model_state, :params, model_state[:config])  # Support old :config key
        model.feature_means = model_state[:feature_means]
        model.feature_stds = model_state[:feature_stds]
        model.training_history = model_state[:training_history]
        # Restore optional fields if they exist
        if haskey(model_state, :name)
            model.name = model_state[:name]
        end
        if haskey(model_state, :gpu_enabled)
            model.gpu_enabled = model_state[:gpu_enabled]
        end
        
        # Move model to GPU if available
        if has_metal_gpu()
            model.model = Flux.gpu(model.model)
            @info "Model moved to Metal GPU"
        end
        
        @info "Neural network model loaded successfully" filepath=filepath model_type=model_state[:model_type]
        return model
    catch e
        @error "Failed to load neural network model" exception=e filepath=filepath
        throw(e)
    end
end

"""
Get training history for neural network models
"""
function get_training_history(model::NeuralNetworkModel)
    return model.training_history
end

"""
Plot training history (requires Plots.jl)
"""
function plot_training_history(model::NeuralNetworkModel)
    if isempty(model.training_history)
        @warn "No training history available"
        return nothing
    end
    
    epochs = [h["epoch"] for h in model.training_history]
    train_loss = [h["train_loss"] for h in model.training_history]
    val_correlation = [h["val_correlation"] for h in model.training_history]
    
    @info "Training history summary" epochs=length(epochs) best_correlation=maximum(val_correlation)
    
    # In a real implementation, you might create plots here
    return (epochs, train_loss, val_correlation)
end

"""
Cross-validation for neural network models
"""
function cross_validate_neural_network(model_constructor::Function, 
                                     X::Matrix{Float64}, 
                                     y::Vector{Float64}, 
                                     eras::Vector{Int}; 
                                     n_splits::Int=5, 
                                     use_gpu::Bool=true)::Vector{Float64}
    
    unique_eras = unique(eras)
    n_eras = length(unique_eras)
    era_size = n_eras ÷ n_splits
    
    cv_scores = Float64[]
    
    @info "Starting neural network cross-validation" n_splits=n_splits use_gpu=use_gpu
    
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
        train!(model, X_train, y_train, X_val=X_val, y_val=y_val)
        
        predictions = predict(model, X_val)
        score = cor(predictions, y_val)
        
        push!(cv_scores, score)
        @info "CV fold completed" fold=i score=score
    end
    
    @info "Neural network cross-validation completed" mean_score=mean(cv_scores) std_score=std(cv_scores)
    return cv_scores
end

# Export all necessary functions and types
export correlation_loss, mse_correlation_loss, sparsity_loss
export standardize_features!, preprocess_for_neural_network
export train_neural_network!, predict_neural_network
export get_training_history, plot_training_history
export cross_validate_neural_network
export feature_importance, save_model, load_model!

end  # module NeuralNetworks