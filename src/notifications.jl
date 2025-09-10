module Notifications

using Dates
using TimeZones

# Import UTC utility function
include("utils.jl")

# Detect the current platform
const PLATFORM = Sys.isapple() ? :macos : (Sys.islinux() ? :linux : (Sys.iswindows() ? :windows : :unknown))

# Rate limiting for notifications
const NOTIFICATION_CACHE = Dict{String, DateTime}()
const MIN_NOTIFICATION_INTERVAL = Dates.Second(30)  # Minimum 30 seconds between identical notifications

function should_throttle_notification(key::String)::Bool
    now_time = Dates.now()
    if haskey(NOTIFICATION_CACHE, key)
        last_time = NOTIFICATION_CACHE[key]
        if now_time - last_time < MIN_NOTIFICATION_INTERVAL
            return true
        end
    end
    NOTIFICATION_CACHE[key] = now_time
    return false
end

function send_notification(title::String, message::String, type::Symbol=:info)
    # Check rate limiting
    notification_key = "$title:$message"
    if should_throttle_notification(notification_key)
        return  # Skip this notification due to rate limiting
    end
    
    if PLATFORM == :macos
        send_notification_macos(title, message, type)
    elseif PLATFORM == :linux
        send_notification_linux(title, message, type)
    elseif PLATFORM == :windows
        send_notification_windows(title, message, type)
    else
        # Fallback to console output
        send_notification_console(title, message, type)
    end
end

# macOS notification implementation
function send_notification_macos(title::String, message::String, type::Symbol)
    sound = type == :error ? "Basso" : (type == :success ? "Glass" : "default")
    
    script = """
    display notification "$message" with title "$title" sound name "$sound"
    """
    
    try
        run(`osascript -e $script`)
    catch e
        @warn "Failed to send macOS notification, falling back to console" error=e
        send_notification_console(title, message, type)
    end
end

# Linux notification implementation
function send_notification_linux(title::String, message::String, type::Symbol)
    # Try notify-send first (most common)
    urgency = type == :error ? "critical" : (type == :success ? "normal" : "low")
    
    try
        # Check if notify-send is available
        run(pipeline(`which notify-send`, devnull))
        
        # Send notification using notify-send
        run(`notify-send -u $urgency "$title" "$message"`)
    catch
        # Try zenity as fallback
        try
            run(pipeline(`which zenity`, devnull))
            icon = type == :error ? "error" : (type == :success ? "info" : "warning")
            run(`zenity --notification --text="$title: $message"`)
        catch
            # Fallback to console output
            @warn "No Linux notification tool found (notify-send or zenity), using console output"
            send_notification_console(title, message, type)
        end
    end
end

# Windows notification implementation
function send_notification_windows(title::String, message::String, type::Symbol)
    # Use PowerShell to create Windows toast notifications
    icon = type == :error ? "Error" : (type == :success ? "Information" : "Warning")
    
    powershell_script = """
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    
    \$template = @'
    <toast>
        <visual>
            <binding template="ToastGeneric">
                <text>$title</text>
                <text>$message</text>
            </binding>
        </visual>
    </toast>
    '@
    
    \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    \$xml.LoadXml(\$template)
    
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
    \$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("NumeraiTournament")
    \$notifier.Show(\$toast)
    """
    
    try
        run(`powershell -Command $powershell_script`)
    catch e
        # Try simpler Windows MSG command as fallback
        try
            msg_text = "$title: $message"
            run(Cmd(["msg", "*", "/TIME:10", msg_text]))
        catch
            @warn "Failed to send Windows notification, falling back to console" error=e
            send_notification_console(title, message, type)
        end
    end
end

# Console fallback notification
function send_notification_console(title::String, message::String, type::Symbol)
    # Color codes for different notification types
    color_code = type == :error ? "\033[31m" : (type == :success ? "\033[32m" : "\033[33m")  # Red, Green, Yellow
    reset_code = "\033[0m"
    
    # Print formatted notification to console
    println()
    println("$(color_code)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(reset_code)")
    println("$(color_code)🔔 NOTIFICATION: $title$(reset_code)")
    println("$(color_code)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(reset_code)")
    for line in split(message, "\\n")
        println("  $line")
    end
    println("$(color_code)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(reset_code)")
    println()
end

function send_training_complete(model_name::String, score::Float64)
    title = "Training Complete"
    message = "Model: $model_name\\nValidation Score: $(round(score, digits=4))"
    send_notification(title, message, :success)
end

function send_submission_success(model_name::String, round_number::Int)
    title = "Submission Successful"
    message = "Model: $model_name\\nRound: $round_number"
    send_notification(title, message, :success)
end

function send_error_notification(error_msg::String)
    title = "Numerai Error"
    send_notification(title, error_msg, :error)
end

function send_round_open(round_number::Int, close_time::DateTime)
    title = "New Round Open"
    time_remaining = close_time - utc_now_datetime()
    hours = Dates.hour(time_remaining)
    minutes = Dates.minute(time_remaining)
    message = "Round $round_number is open\\nCloses in $(hours)h $(minutes)m"
    send_notification(title, message, :info)
end

function send_staking_update(total_stake::Float64, payout::Float64)
    title = "Staking Update"
    message = "Total Stake: $(round(total_stake, digits=2)) NMR\\nExpected Payout: $(round(payout, digits=4)) NMR"
    send_notification(title, message, :info)
end

function send_download_complete(dataset_type::String, file_size_mb::Float64)
    title = "Download Complete"
    message = "Dataset: $dataset_type\\nSize: $(round(file_size_mb, digits=1)) MB"
    send_notification(title, message, :success)
end

function send_model_ranking(model_name::String, rank::Int, percentile::Float64)
    title = "Model Ranking Update"
    message = "Model: $model_name\\nRank: #$rank\\nTop $(round(percentile, digits=1))%"
    send_notification(title, message, :info)
end

export send_notification, send_training_complete, send_submission_success,
       send_error_notification, send_round_open, send_staking_update,
       send_download_complete, send_model_ranking

end