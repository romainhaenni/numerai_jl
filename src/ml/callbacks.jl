module Callbacks

using Dates
using Statistics

export TrainingCallback, ProgressCallback, LoggingCallback, DashboardCallback
export CallbackResult, CONTINUE, EARLY_STOP
export call_callback!, create_progress_callback, create_logging_callback, create_dashboard_callback

"""
Callback result enum to control training flow
"""
@enum CallbackResult begin
    CONTINUE      # Continue training
    EARLY_STOP    # Stop training early
end

"""
Abstract base type for training callbacks
"""
abstract type TrainingCallback end

"""
Callback information structure passed to callbacks
"""
struct CallbackInfo
    model_name::String
    epoch::Int
    total_epochs::Int
    iteration::Int
    total_iterations::Union{Nothing, Int}
    loss::Union{Nothing, Float64}
    val_loss::Union{Nothing, Float64}
    val_score::Union{Nothing, Float64}  # Validation correlation or other metric
    learning_rate::Union{Nothing, Float64}
    elapsed_time::Float64
    eta::Union{Nothing, Float64}  # Estimated time remaining
    extra_metrics::Dict{String, Any}  # For additional model-specific metrics
end

"""
Generic callback function type
Callback functions should accept (info::CallbackInfo) and return CallbackResult
"""
const CallbackFunction = Function

"""
Progress reporting callback that calls a user-provided function
"""
mutable struct ProgressCallback <: TrainingCallback
    callback_fn::CallbackFunction
    frequency::Int  # Call every N iterations/epochs
    last_called::Int
    name::String
    
    function ProgressCallback(callback_fn::CallbackFunction, frequency::Int=1, name::String="progress")
        new(callback_fn, frequency, 0, name)
    end
end

"""
Logging callback that prints training progress
"""
mutable struct LoggingCallback <: TrainingCallback
    frequency::Int
    verbose::Bool
    name::String
    start_time::Float64
    
    function LoggingCallback(frequency::Int=10, verbose::Bool=true, name::String="logging")
        new(frequency, verbose, name, 0.0)
    end
end

"""
Dashboard callback for real-time TUI updates
"""
mutable struct DashboardCallback <: TrainingCallback
    update_fn::CallbackFunction  # Function to update dashboard state
    frequency::Int
    last_called::Int
    name::String
    
    function DashboardCallback(update_fn::CallbackFunction, frequency::Int=1, name::String="dashboard")
        new(update_fn, frequency, 0, name)
    end
end

"""
Call a callback with training information
"""
function call_callback!(callback::TrainingCallback, info::CallbackInfo)::CallbackResult
    try
        if callback isa ProgressCallback
            if info.iteration - callback.last_called >= callback.frequency || 
               info.epoch != 0 && (info.epoch - callback.last_called >= callback.frequency)
                
                callback.last_called = max(info.iteration, info.epoch)
                return callback.callback_fn(info)
            end
            return CONTINUE
            
        elseif callback isa LoggingCallback
            if callback.start_time == 0.0
                callback.start_time = time()
            end
            
            if info.iteration % callback.frequency == 0 || info.epoch % callback.frequency == 0
                if callback.verbose
                    progress_str = ""
                    if info.total_epochs > 0
                        progress_str = "Epoch $(info.epoch)/$(info.total_epochs)"
                    elseif info.total_iterations !== nothing
                        progress_str = "Iter $(info.iteration)/$(info.total_iterations)"
                    else
                        progress_str = "Iter $(info.iteration)"
                    end
                    
                    metrics_str = ""
                    if info.loss !== nothing
                        metrics_str *= ", Loss: $(round(info.loss, digits=6))"
                    end
                    if info.val_loss !== nothing
                        metrics_str *= ", Val Loss: $(round(info.val_loss, digits=6))"
                    end
                    if info.val_score !== nothing
                        metrics_str *= ", Val Score: $(round(info.val_score, digits=6))"
                    end
                    if info.learning_rate !== nothing
                        metrics_str *= ", LR: $(round(info.learning_rate, digits=8))"
                    end
                    if info.eta !== nothing
                        eta_str = info.eta < 60 ? "$(round(info.eta))s" : "$(round(info.eta/60, digits=1))m"
                        metrics_str *= ", ETA: $eta_str"
                    end
                    
                    println("  [$(info.model_name)] $progress_str$metrics_str")
                end
            end
            return CONTINUE
            
        elseif callback isa DashboardCallback
            if info.iteration - callback.last_called >= callback.frequency || 
               info.epoch != 0 && (info.epoch - callback.last_called >= callback.frequency)
                
                callback.last_called = max(info.iteration, info.epoch)
                return callback.update_fn(info)
            end
            return CONTINUE
        end
        
    catch e
        @warn "Callback error in $(callback.name)" error=e
        return CONTINUE  # Don't stop training due to callback errors
    end
    
    return CONTINUE
end

"""
Create a simple progress callback that calls the provided function
"""
function create_progress_callback(callback_fn::CallbackFunction; frequency::Int=1, name::String="progress")
    return ProgressCallback(callback_fn, frequency, name)
end

"""
Create a logging callback for console output
"""
function create_logging_callback(; frequency::Int=10, verbose::Bool=true, name::String="logging")
    return LoggingCallback(frequency, verbose, name)
end

"""
Create a dashboard callback for TUI updates
"""
function create_dashboard_callback(update_fn::CallbackFunction; frequency::Int=1, name::String="dashboard")
    return DashboardCallback(update_fn, frequency, name)
end

"""
Helper function to calculate ETA based on elapsed time and progress
"""
function calculate_eta(elapsed_time::Float64, current_step::Int, total_steps::Int)::Union{Nothing, Float64}
    if current_step <= 0 || total_steps <= 0 || current_step >= total_steps
        return nothing
    end
    
    time_per_step = elapsed_time / current_step
    remaining_steps = total_steps - current_step
    return time_per_step * remaining_steps
end

"""
Helper function to create callback info with common calculations
"""
function create_callback_info(model_name::String, epoch::Int, total_epochs::Int, 
                             iteration::Int, total_iterations::Union{Nothing, Int},
                             start_time::Float64;
                             loss::Union{Nothing, Float64}=nothing,
                             val_loss::Union{Nothing, Float64}=nothing,
                             val_score::Union{Nothing, Float64}=nothing,
                             learning_rate::Union{Nothing, Float64}=nothing,
                             extra_metrics::Dict{String, Any}=Dict{String, Any}())
    
    elapsed_time = time() - start_time
    
    # Calculate ETA based on the most relevant progress metric
    eta = if total_epochs > 0 && epoch > 0
        calculate_eta(elapsed_time, epoch, total_epochs)
    elseif total_iterations !== nothing && iteration > 0
        calculate_eta(elapsed_time, iteration, total_iterations)
    else
        nothing
    end
    
    return CallbackInfo(
        model_name, epoch, total_epochs, iteration, total_iterations,
        loss, val_loss, val_score, learning_rate, elapsed_time, eta, extra_metrics
    )
end

end # module