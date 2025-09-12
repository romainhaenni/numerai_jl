# Training Callback System

This document describes the training callback system that allows real-time monitoring and progress reporting during model training.

## Overview

The callback system provides a standardized way to monitor training progress, log metrics, and update user interfaces (like the TUI dashboard) during model training. It supports all model types (XGBoost, LightGBM, EvoTrees, CatBoost) and works with both single-target and multi-target training.

## Key Components

### 1. Callback Interface

```julia
# Abstract base type for all callbacks
abstract type TrainingCallback end

# Callback information passed to callbacks
struct CallbackInfo
    model_name::String
    epoch::Int
    total_epochs::Int
    iteration::Int
    total_iterations::Union{Nothing, Int}
    loss::Union{Nothing, Float64}
    val_loss::Union{Nothing, Float64}
    val_score::Union{Nothing, Float64}
    learning_rate::Union{Nothing, Float64}
    elapsed_time::Float64
    eta::Union{Nothing, Float64}
    extra_metrics::Dict{String, Any}
end

# Return values to control training flow
@enum CallbackResult begin
    CONTINUE      # Continue training
    EARLY_STOP    # Stop training early
end
```

### 2. Built-in Callback Types

#### ProgressCallback
Executes a custom function with training progress information.

```julia
progress_callback = create_progress_callback(
    function(info::CallbackInfo)
        println("Epoch $(info.epoch)/$(info.total_epochs) - Progress: $(round(info.epoch/info.total_epochs*100))%")
        return CONTINUE
    end,
    frequency=5,  # Call every 5 epochs/iterations
    name="my_progress"
)
```

#### LoggingCallback
Provides console logging of training progress.

```julia
logging_callback = create_logging_callback(
    frequency=10,    # Log every 10 epochs/iterations
    verbose=true,    # Enable detailed output
    name="console_logger"
)
```

#### DashboardCallback
Updates dashboard/TUI state for real-time display.

```julia
dashboard_callback = create_dashboard_callback(
    function(info::CallbackInfo)
        # Update dashboard state
        dashboard.training_info[:current_epoch] = info.epoch
        dashboard.training_info[:progress] = round(Int, (info.epoch / info.total_epochs) * 100)
        return CONTINUE
    end,
    frequency=1,  # Update every iteration
    name="dashboard_updater"
)
```

## Usage Examples

### Basic Usage with Single Model

```julia
using Models, Models.Callbacks

# Create sample data
X_train, y_train = create_data()
X_val, y_val = create_data()

# Create callbacks
callbacks = [
    create_logging_callback(frequency=10),
    create_progress_callback(info -> begin
        println("Training $(info.model_name): $(info.epoch)/$(info.total_epochs)")
        return CONTINUE
    end, frequency=5)
]

# Train model with callbacks
model = XGBoostModel("my_model", num_rounds=100)
train!(model, X_train, y_train,
       X_val=X_val, y_val=y_val,
       verbose=false,  # Let callbacks handle output
       callbacks=callbacks)
```

### Pipeline Integration

```julia
using Pipeline, Models.Callbacks

# Create pipeline
pipeline = MLPipeline(
    target_col="target_cyrus_v4_20",
    model_config=ModelConfig("xgboost", Dict(:max_depth=>8, :num_rounds=>200))
)

# Create callbacks for dashboard integration
dashboard_callback = create_dashboard_training_callback(dashboard)
callbacks = [dashboard_callback]

# Train with callbacks
train!(pipeline, train_df, val_df,
       verbose=true,
       callbacks=callbacks)

# Mark training as completed
complete_training!(dashboard, pipeline.model.name)
```

### Dashboard Integration

The callback system integrates seamlessly with the TUI dashboard:

```julia
using Dashboard

# Create dashboard
dashboard = TournamentDashboard(config)

# Create dashboard callback
dashboard_callback = create_dashboard_training_callback(dashboard)

# Use in training
callbacks = [dashboard_callback]
train!(model, X_train, y_train, callbacks=callbacks)

# Dashboard automatically updates:
# - training_info[:is_training] = true/false
# - training_info[:progress] = 0-100
# - training_info[:current_epoch] = current epoch
# - training_info[:total_epochs] = total epochs
# - training_info[:eta] = estimated time remaining
# - training_info[:val_score] = validation score
```

### Multi-Target Training

Callbacks work automatically with multi-target training:

```julia
# Multi-target data
y_train_multi = [y_target1 y_target2 y_target3]  # Matrix with multiple targets

# Callbacks will be called for each target
callbacks = [create_progress_callback(info -> begin
    println("Training $(info.model_name)")  # e.g., "my_model_target_1"
    return CONTINUE
end)]

# Train multi-target model
train!(model, X_train, y_train_multi, callbacks=callbacks)
```

### Custom Callback Example

```julia
# Track best validation score
best_score = Ref(0.0)

best_score_tracker = create_progress_callback(
    function(info::CallbackInfo)
        if info.val_score !== nothing && info.val_score > best_score[]
            best_score[] = info.val_score
            println("🎯 New best score: $(round(info.val_score, digits=6))")
            
            # Could save model checkpoint here
            # save_model(model, "best_model.json")
        end
        
        return CONTINUE  # or EARLY_STOP to halt training
    end,
    frequency=1,
    name="best_score_tracker"
)
```

## Integration Points

### Model Training Methods

All `train!` methods now accept a `callbacks` parameter:

```julia
# XGBoost
train!(xgb_model, X, y; callbacks=callbacks)

# LightGBM  
train!(lgbm_model, X, y; callbacks=callbacks)

# EvoTrees
train!(evo_model, X, y; callbacks=callbacks)

# CatBoost (basic support)
train!(catboost_model, X, y; callbacks=callbacks)
```

### Pipeline Integration

The `Pipeline.train!` method passes callbacks to individual models:

```julia
train!(pipeline, train_df, val_df; callbacks=callbacks)
```

### Dashboard Integration

Dashboard provides helper functions:

```julia
# Create dashboard callback
callback = create_dashboard_training_callback(dashboard)

# Mark training completion
complete_training!(dashboard, model_name)
```

## Implementation Notes

### Frequency Control
- `frequency=1`: Called every epoch/iteration
- `frequency=5`: Called every 5 epochs/iterations  
- `frequency=0`: Never called (disabled)

### Model-Specific Behavior
- **XGBoost**: Callbacks called at start and completion of training
- **LightGBM**: Callbacks called at start and completion of training  
- **EvoTrees**: Callbacks called at start and completion of training
- **CatBoost**: Basic callback support implemented
- **Multi-target**: Separate callbacks for each target model

### Error Handling
- Callback errors don't stop training
- Failed callbacks log warnings but continue
- Training continues even if callbacks fail

### Performance Impact
- Minimal overhead for simple callbacks
- Dashboard updates are lightweight
- Callback frequency can be adjusted for performance

## Example Scripts

See `examples/callback_example.jl` for comprehensive demonstrations of:
- Basic callback usage
- Multi-target training with callbacks
- Dashboard-style progress tracking
- Custom callback implementations

## Future Enhancements

Potential improvements:
- Early stopping based on callback signals
- Model checkpointing integration
- More granular iteration-level callbacks for neural networks
- Web dashboard integration via WebSocket callbacks
- Training metrics persistence