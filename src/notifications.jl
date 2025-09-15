"""
    notifications.jl

macOS notification system for the Numerai tournament application.
Provides native alerts for important events using AppleScript via osascript.
"""

module Notifications

using Dates
using ..Logger

export send_notification, NotificationLevel, 
       notify_training_complete, notify_submission_complete, 
       notify_performance_alert, notify_error, notify_round_open

@enum NotificationLevel begin
    INFO
    WARNING
    ERROR
    CRITICAL
end

"""
    send_notification(title::String, message::String; 
                     level::NotificationLevel=INFO,
                     sound::Bool=true)

Send a macOS notification using AppleScript.

# Arguments
- `title`: The notification title
- `message`: The notification message body
- `level`: Notification level (affects icon and urgency)
- `sound`: Whether to play a notification sound

# Returns
- `true` if notification was sent successfully, `false` otherwise
"""
function send_notification(title::String, message::String;
                          level::NotificationLevel=INFO,
                          sound::Bool=true)
    # Check notification support on first use
    if !check_notification_support()
        @log_debug "Notifications not supported, skipping" title=title
        return false
    end

    # Escape quotes in title and message for AppleScript
    title_escaped = replace(title, "\"" => "\\\"")
    message_escaped = replace(message, "\"" => "\\\"")

    # Determine sound name based on level
    sound_name = if !sound
        ""
    elseif level == CRITICAL || level == ERROR
        "Basso"  # Error sound
    elseif level == WARNING
        "Ping"   # Warning sound
    else
        "Glass"  # Info sound
    end

    # Build AppleScript command
    script = if sound_name != ""
        """
        display notification "$(message_escaped)" with title "Numerai Tournament" subtitle "$(title_escaped)" sound name "$(sound_name)"
        """
    else
        """
        display notification "$(message_escaped)" with title "Numerai Tournament" subtitle "$(title_escaped)"
        """
    end

    # Execute AppleScript via osascript
    cmd = `osascript -e $script`

    try
        run(cmd)
        @log_debug "Notification sent" title=title level=level
        return true
    catch e
        @log_warn "Failed to send notification" error=string(e) title=title
        return false
    end
end

"""
    notify_training_complete(model_name::String, success::Bool; 
                           duration_minutes::Float64=0.0,
                           metrics::Dict=Dict())

Send notification when model training completes.

# Arguments
- `model_name`: Name of the model that finished training
- `success`: Whether training completed successfully
- `duration_minutes`: Training duration in minutes
- `metrics`: Optional metrics to include (e.g., validation score)
"""
function notify_training_complete(model_name::String, success::Bool; 
                                duration_minutes::Float64=0.0,
                                metrics::Dict=Dict())
    if success
        duration_str = duration_minutes > 0 ? " ($(round(duration_minutes, digits=1)) min)" : ""
        
        # Include validation score if available
        val_score_str = ""
        if haskey(metrics, "validation_score")
            val_score_str = " - Val: $(round(metrics["validation_score"], digits=4))"
        end
        
        send_notification(
            "Training Complete",
            "Model $(model_name) trained successfully$(duration_str)$(val_score_str)",
            level=INFO
        )
    else
        error_msg = get(metrics, "error", "Unknown error")
        send_notification(
            "Training Failed",
            "Model $(model_name) training failed: $(error_msg)",
            level=ERROR
        )
    end
end

"""
    notify_submission_complete(model_name::String, success::Bool;
                             submission_id::String="",
                             round_number::Int=0)

Send notification when prediction submission completes.

# Arguments
- `model_name`: Name of the model
- `success`: Whether submission was successful
- `submission_id`: Optional submission ID
- `round_number`: Optional round number
"""
function notify_submission_complete(model_name::String, success::Bool;
                                  submission_id::String="",
                                  round_number::Int=0)
    if success
        round_str = round_number > 0 ? " for round $(round_number)" : ""
        id_str = submission_id != "" ? " (ID: $(submission_id))" : ""
        
        send_notification(
            "Submission Complete",
            "Model $(model_name) submitted successfully$(round_str)$(id_str)",
            level=INFO
        )
    else
        send_notification(
            "Submission Failed",
            "Failed to submit predictions for model $(model_name)",
            level=ERROR
        )
    end
end

"""
    notify_performance_alert(model_name::String, metric::String, 
                           value::Float64, threshold::Float64)

Send alert when model performance crosses a threshold.

# Arguments
- `model_name`: Name of the model
- `metric`: Performance metric name (e.g., "correlation", "sharpe")
- `value`: Current metric value
- `threshold`: Threshold that was crossed
"""
function notify_performance_alert(model_name::String, metric::String, 
                                 value::Float64, threshold::Float64)
    if value < threshold
        send_notification(
            "Performance Alert",
            "$(model_name): $(metric) dropped to $(round(value, digits=4)) (threshold: $(threshold))",
            level=WARNING,
            sound=true
        )
    else
        send_notification(
            "Performance Improvement",
            "$(model_name): $(metric) improved to $(round(value, digits=4))",
            level=INFO,
            sound=false
        )
    end
end

"""
    notify_error(error_type::String, message::String; 
                details::String="")

Send error notification for system errors.

# Arguments
- `error_type`: Type of error (e.g., "API Error", "Database Error")
- `message`: Error message
- `details`: Optional additional details
"""
function notify_error(error_type::String, message::String; 
                     details::String="")
    full_message = details != "" ? "$(message)\n$(details)" : message
    
    # Determine severity based on error type
    level = if occursin("critical", lowercase(error_type))
        CRITICAL
    elseif occursin("network", lowercase(error_type)) || occursin("api", lowercase(error_type))
        WARNING
    else
        ERROR
    end
    
    send_notification(
        error_type,
        full_message,
        level=level,
        sound=true
    )
end

"""
    notify_round_open(round_number::Int, closes_at::DateTime;
                     is_weekend::Bool=false)

Send notification when a new tournament round opens.

# Arguments
- `round_number`: Tournament round number
- `closes_at`: When the round closes
- `is_weekend`: Whether this is a weekend round
"""
function notify_round_open(round_number::Int, closes_at::DateTime;
                          is_weekend::Bool=false)
    round_type = is_weekend ? "Weekend" : "Daily"
    
    # Calculate time remaining
    time_remaining = closes_at - now(UTC)
    hours_remaining = round(Dates.value(time_remaining) / (1000 * 60 * 60), digits=1)
    
    send_notification(
        "$(round_type) Round Open",
        "Round $(round_number) is open. Closes in $(hours_remaining) hours.",
        level=INFO,
        sound=true
    )
end

"""
    check_notification_support()

Check if macOS notifications are supported on this system.

# Returns
- `true` if notifications are supported, `false` otherwise
"""
function check_notification_support()
    try
        # Test if osascript is available
        run(`which osascript`)
        return true
    catch
        @log_warn "macOS notifications not supported on this system"
        return false
    end
end

# Module initialization
function __init__()
    # Defer notification support check to first use to speed up module loading
    @log_info "Notification system initialized"
end

end # module