# Neural Networks Module for Numerai Tournament

This document describes the comprehensive neural network module implemented for the Numerai tournament machine learning pipeline.

## Overview

The neural networks module provides state-of-the-art deep learning models specifically designed for Numerai's tabular data prediction tasks. It seamlessly integrates with the existing ML pipeline and provides GPU acceleration support via Metal.jl.

## Features

### 🧠 Multiple Architectures
- **MLPModel**: Multi-layer perceptron with configurable layers
- **ResNetModel**: Skip connections for deep networks  
- **TabNetModel**: Attention mechanism optimized for tabular data

### 🚀 Advanced Training Infrastructure
- Early stopping with configurable patience
- Learning rate scheduling (exponential, step, cosine)
- Model checkpointing and best model saving
- Comprehensive training history tracking
- Batch processing with custom data loaders

### 🎯 Custom Loss Functions for Numerai
- **Correlation-based loss**: Directly optimizes Pearson correlation
- **MSE with correlation regularization**: Balanced approach
- **Sparsity loss**: For attention mechanisms (TabNet)

### ⚡ GPU Acceleration
- Full Metal.jl integration for Apple Silicon
- Automatic CPU fallback for compatibility
- GPU-accelerated data preprocessing
- Mixed precision training support

### 🔧 Production-Ready Features
- Comprehensive error handling and logging
- Ensemble compatibility with existing models
- Cross-validation support
- Feature importance analysis
- Model serialization and loading

## Quick Start

```julia
using NumeraiTournament
include("src/ml/neural_networks.jl")
using .NeuralNetworks

# Create and train an MLP model
model = MLPModel("my_mlp",
                hidden_layers=[128, 64, 32],
                dropout_rate=0.3,
                learning_rate=0.001,
                epochs=100,
                gpu_enabled=true)

# Train the model
train!(model, X_train, y_train, X_val=X_val, y_val=y_val, verbose=true)

# Make predictions
predictions = predict(model, X_test)
```

## Architecture Details

### MLPModel (Multi-Layer Perceptron)
- **Purpose**: General-purpose feedforward neural network
- **Best for**: Baseline models, quick experiments
- **Features**: Configurable layers, batch normalization, dropout
- **Parameters**:
  - `hidden_layers`: Vector of layer sizes, e.g., [256, 128, 64]
  - `dropout_rate`: Dropout probability (0.0-1.0)
  - `activation`: Activation function (relu, tanh, etc.)

```julia
model = MLPModel("numerai_mlp",
                hidden_layers=[256, 128, 64, 32],
                dropout_rate=0.3,
                learning_rate=0.001,
                epochs=150,
                batch_size=512)
```

### ResNetModel (Residual Networks)
- **Purpose**: Deep networks with skip connections
- **Best for**: Complex patterns, deep architectures
- **Features**: Residual blocks, gradient flow optimization
- **Parameters**:
  - `hidden_layers`: Layer dimensions for residual blocks
  - `residual_blocks`: Number of residual blocks per layer

```julia
model = ResNetModel("numerai_resnet",
                   hidden_layers=[256, 256, 128, 128],
                   residual_blocks=2,
                   dropout_rate=0.2,
                   learning_rate=0.001)
```

### TabNetModel (Attention for Tabular Data)
- **Purpose**: Attention-based architecture for tabular data
- **Best for**: Feature selection, interpretable predictions
- **Features**: Sequential attention, feature masking
- **Parameters**:
  - `n_d`: Decision prediction layer dimension
  - `n_a`: Attention layer dimension  
  - `n_steps`: Number of sequential attention steps

```julia
model = TabNetModel("numerai_tabnet",
                   n_d=64,
                   n_a=64,
                   n_steps=4,
                   learning_rate=0.02,
                   batch_size=1024)
```

## Custom Loss Functions

### Correlation Loss
Directly optimizes the Pearson correlation coefficient (negated for minimization):

```julia
function correlation_loss(ŷ, y)
    return -cor(vec(ŷ), vec(y))
end
```

### MSE + Correlation Loss
Balanced approach combining mean squared error with correlation:

```julia
function mse_correlation_loss(ŷ, y; α::Float64=0.7)
    mse = Flux.mse(ŷ, y)
    corr_loss = correlation_loss(ŷ, y)
    return α * corr_loss + (1 - α) * mse
end
```

## Training Infrastructure

### Early Stopping
Prevents overfitting with configurable patience:

```julia
early_stopping = EarlyStopping(patience=15, min_delta=1e-5)
```

### Learning Rate Scheduling
Multiple scheduling strategies available:

```julia
# Exponential decay
scheduler = LearningRateScheduler(0.001, :exponential, 0.95)

# Step decay  
scheduler = LearningRateScheduler(0.001, :step)

# Cosine annealing
scheduler = LearningRateScheduler(0.001, :cosine)
```

### Model Checkpointing
Automatically saves best models:

```julia
checkpoint = ModelCheckpoint("models/best_model.bson", 
                           monitor="val_correlation",
                           save_best_only=true)
```

## Data Preprocessing

The module includes specialized preprocessing for neural networks:

```julia
# Automatic standardization and GPU transfer
X_proc, y_proc, X_val_proc, means, stds = preprocess_for_neural_network(
    X_train, y_train, X_val=X_val, use_gpu=true
)
```

Features:
- Z-score standardization with stored parameters
- Float32 conversion for GPU efficiency  
- Automatic GPU transfer when available
- Preserved statistics for inference

## GPU Acceleration

### Metal.jl Integration
Full support for Apple Silicon GPUs:

```julia
# Enable GPU acceleration
model = MLPModel("gpu_model", gpu_enabled=true)

# Automatic fallback to CPU if GPU unavailable
# GPU operations include:
# - Model training and inference
# - Data preprocessing
# - Loss computation
```

### GPU Memory Management
- Automatic memory optimization
- Error handling for GPU operations
- Memory usage monitoring
- Cache clearing utilities

## Ensemble Integration

Neural networks integrate seamlessly with existing ensemble framework:

```julia
# Combine neural networks with traditional models
models = [
    MLPModel("mlp", gpu_enabled=true),
    XGBoostModel("xgb"),
    LightGBMModel("lgbm")
]

ensemble = ModelEnsemble(models)
train_ensemble!(ensemble, X_train, y_train)
predictions = predict_ensemble(ensemble, X_test)
```

## Cross-Validation

Era-aware cross-validation for neural networks:

```julia
scores = cross_validate_neural_network(
    () -> MLPModel("cv_mlp", epochs=50),
    X, y, eras,
    n_splits=5,
    use_gpu=true
)
```

## Performance Optimization

### Batch Processing
Efficient batch processing for large datasets:

```julia
# Configurable batch sizes
model = MLPModel("batch_model", batch_size=1024)

# Automatic batch creation and shuffling
batches = create_data_loader(X, y, batch_size=512, shuffle=true)
```

### Memory Efficiency
- Float32 precision for GPU efficiency
- Gradient accumulation for large models
- Memory-mapped data loading
- Automatic garbage collection

## Model Analysis

### Training History
Comprehensive tracking of training metrics:

```julia
history = get_training_history(model)
# Returns: epochs, train_loss, val_loss, val_correlation

# Visualize training progress
epochs, train_loss, val_correlation = plot_training_history(model)
```

### Feature Importance
Simplified feature importance for neural networks:

```julia
importance = feature_importance(model)
# Note: Neural network feature importance is approximate
```

## Error Handling

Robust error handling throughout:
- GPU operation failures → CPU fallback
- Memory exhaustion → Batch size reduction
- Training instability → Early stopping
- Model loading errors → Graceful degradation

## Example Usage Patterns

### Basic Training
```julia
model = MLPModel("basic", hidden_layers=[64, 32])
train!(model, X_train, y_train, verbose=true)
predictions = predict(model, X_test)
correlation = cor(predictions, y_test)
```

### Advanced Training with Validation
```julia
model = ResNetModel("advanced",
                   hidden_layers=[128, 128, 64],
                   epochs=200,
                   early_stopping_patience=20,
                   gpu_enabled=true)

train!(model, X_train, y_train, 
       X_val=X_val, y_val=y_val,
       verbose=true)
```

### Ensemble with Neural Networks
```julia
nn_models = [
    MLPModel("mlp1", hidden_layers=[128, 64]),
    ResNetModel("resnet1", hidden_layers=[128, 128]),
    TabNetModel("tabnet1", n_steps=3)
]

# Train all models
for model in nn_models
    train!(model, X_train, y_train, X_val=X_val, y_val=y_val)
end

# Create ensemble
ensemble = ModelEnsemble(nn_models)
ensemble_pred = predict_ensemble(ensemble, X_test)
```

## File Structure

```
src/ml/neural_networks.jl          # Main neural networks module
example_neural_networks.jl         # Comprehensive usage example
docs/neural_networks.md           # This documentation
```

## Dependencies

- **Flux.jl**: Deep learning framework
- **Optimisers.jl**: Advanced optimizers
- **Zygote.jl**: Automatic differentiation
- **Metal.jl**: GPU acceleration for Apple Silicon
- **Statistics.jl**: Statistical functions
- **DataFrames.jl**: Data manipulation

## Integration with Existing Pipeline

The neural networks module fully integrates with the existing Numerai pipeline:

1. **Model Interface**: Implements the same `NumeraiModel` interface
2. **Training API**: Uses same `train!` and `predict` functions
3. **Ensemble Compatibility**: Works with existing `ModelEnsemble`
4. **GPU Integration**: Uses existing `MetalAcceleration` module
5. **Cross-Validation**: Compatible with era-based CV
6. **Logging**: Uses existing logging infrastructure

## Best Practices

### Model Selection
- **MLPModel**: Start here for baseline performance
- **ResNetModel**: Use for complex, non-linear patterns
- **TabNetModel**: Choose when interpretability is important

### Hyperparameter Tuning
- Start with small models and increase complexity
- Use early stopping to prevent overfitting
- Experiment with learning rates (0.001-0.02)
- Adjust batch sizes based on available memory

### GPU Usage
- Enable GPU for faster training on large datasets
- Monitor GPU memory usage
- Use CPU fallback for development/debugging
- Consider mixed precision for memory efficiency

### Production Deployment
- Save best models with checkpointing
- Use ensemble methods for robustness
- Monitor training metrics continuously
- Implement proper error handling

This neural networks module provides a complete, production-ready solution for deep learning in the Numerai tournament, offering state-of-the-art architectures with robust engineering practices.