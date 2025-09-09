module MacOSNotifications

using Dates

function send_notification(title::String, message::String, type::Symbol=:info)
    if !Sys.isapple()
        @warn "macOS notifications only supported on macOS"
        return
    end
    
    sound = if type == :error
        "Basso"
    elseif type == :success
        "Glass"
    elseif type == :warning
        "Tink"
    else
        "Pop"
    end
    
    escaped_title = replace(title, "\"" => "\\\"", "\'" => "\\\'")
    escaped_message = replace(message, "\"" => "\\\"", "\'" => "\\\'")
    
    script = """
    osascript -e 'display notification "$escaped_message" with title "$escaped_title" sound name "$sound"'
    """
    
    try
        run(`sh -c $script`, wait=false)
    catch e
        @warn "Failed to send notification: $e"
    end
end

function send_alert(title::String, message::String, buttons::Vector{String}=["OK"])
    if !Sys.isapple()
        @warn "macOS alerts only supported on macOS"
        return nothing
    end
    
    escaped_title = replace(title, "\"" => "\\\"")
    escaped_message = replace(message, "\"" => "\\\"")
    button_list = join(["\"$btn\"" for btn in buttons], ", ")
    
    script = """
    osascript -e 'display dialog "$escaped_message" with title "$escaped_title" buttons {$button_list} default button 1'
    """
    
    try
        result = read(`sh -c $script`, String)
        return strip(result)
    catch e
        @warn "Alert cancelled or failed: $e"
        return nothing
    end
end

function schedule_notification(title::String, message::String, delay_seconds::Int)
    @async begin
        sleep(delay_seconds)
        send_notification(title, message)
    end
end

function send_progress_notification(title::String, current::Int, total::Int)
    percentage = round(100 * current / total, digits=1)
    message = "Progress: $current/$total ($percentage%)"
    send_notification(title, message, :info)
end

function send_tournament_update(round_number::Int, model_performances::Dict{String, Float64})
    title = "Numerai Round #$round_number Update"
    
    performance_lines = String[]
    for (model, corr) in model_performances
        emoji = corr > 0.02 ? "✅" : corr < -0.02 ? "❌" : "➖"
        push!(performance_lines, "$emoji $model: $(round(corr, digits=4))")
    end
    
    message = join(performance_lines, "\n")
    
    overall_positive = all(v -> v > 0, values(model_performances))
    type = overall_positive ? :success : :warning
    
    send_notification(title, message, type)
end

function send_submission_confirmation(model_name::String, round_number::Int)
    title = "Submission Successful"
    message = "Model '$model_name' submitted for round #$round_number"
    send_notification(title, message, :success)
end

function send_error_alert(error_type::String, details::String)
    title = "Numerai Tournament Error"
    message = "$error_type: $details"
    send_notification(title, message, :error)
    
    response = send_alert(
        title,
        "$message\n\nWould you like to retry?",
        ["Retry", "Cancel"]
    )
    
    return response == "button returned:Retry"
end

function send_training_complete(model_name::String, metrics::Dict{Symbol, Float64})
    title = "Training Complete: $model_name"
    
    metric_lines = String[]
    for (key, value) in metrics
        push!(metric_lines, "$(string(key)): $(round(value, digits=4))")
    end
    
    message = join(metric_lines, ", ")
    send_notification(title, message, :success)
end

function send_stake_update(total_stake::Float64, at_risk::Float64, expected_payout::Float64)
    title = "Numerai Stake Update"
    message = """
    Total Stake: $(round(total_stake, digits=2)) NMR
    At Risk: $(round(at_risk, digits=2)) NMR
    Expected Payout: $(round(expected_payout, digits=4)) NMR
    """
    
    type = expected_payout > 0 ? :success : :warning
    send_notification(title, message, type)
end

function setup_notification_center()
    if !Sys.isapple()
        @warn "Notification center only available on macOS"
        return
    end
    
    script = """
    osascript -e '
    on run
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
            if frontApp is not "Terminal" then
                display notification "Numerai Tournament Monitor Active" with title "Numerai" sound name "Pop"
            end if
        end tell
    end run
    '
    """
    
    try
        run(`sh -c $script`, wait=false)
    catch e
        @warn "Failed to setup notification center: $e"
    end
end

export send_notification, send_alert, schedule_notification, send_progress_notification,
       send_tournament_update, send_submission_confirmation, send_error_alert,
       send_training_complete, send_stake_update, setup_notification_center

end