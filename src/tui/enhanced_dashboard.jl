module EnhancedDashboard

using Dates
using Printf
using ..API

export render_enhanced_dashboard, render_unified_status_panel, render_events_panel,
       create_progress_bar, create_spinner,
       format_duration, center_text, create_metric_bar, ProgressTracker,
       update_progress_tracker!

# Progress indicators for ongoing operations
mutable struct ProgressTracker
    download_progress::Float64
    download_file::String
    download_total_mb::Float64
    download_current_mb::Float64
    upload_progress::Float64
    upload_file::String
    upload_total_mb::Float64
    upload_current_mb::Float64
    training_progress::Float64
    training_model::String
    training_epoch::Int
    training_total_epochs::Int
    training_loss::Float64
    training_val_score::Float64
    prediction_progress::Float64
    prediction_model::String
    prediction_rows_processed::Int
    prediction_total_rows::Int
    is_downloading::Bool
    is_uploading::Bool
    is_training::Bool
    is_predicting::Bool
    last_update::DateTime
end

ProgressTracker() = ProgressTracker(
    0.0, "", 0.0, 0.0, 0.0, "", 0.0, 0.0, 0.0, "", 0, 0, 0.0, 0.0,
    0.0, "", 0, 0, false, false, false, false, now()
)

"""
Create a visual progress bar with percentage
"""
function create_progress_bar(current::Number, total::Number; width::Int=40, show_percent::Bool=true)::String
    if total == 0
        return "─" ^ width
    end

    percentage = clamp(current / total, 0.0, 1.0)
    filled = Int(round(percentage * width))

    # Use block characters for smooth progress visualization
    blocks = ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
    remainder = (percentage * width - filled) * 8
    remainder_block = remainder > 0 ? blocks[Int(ceil(remainder))] : ""

    bar = "█" ^ filled * remainder_block * "░" ^ max(0, width - filled - (remainder > 0 ? 1 : 0))

    if show_percent
        percent_str = @sprintf("%.1f%%", percentage * 100)
        return "$bar $percent_str"
    else
        return bar
    end
end

"""
Create an animated spinner for indeterminate progress
"""
function create_spinner(frame::Int)::String
    spinners = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    return spinners[(frame % length(spinners)) + 1]
end

"""
Update progress tracker with new information
"""
function update_progress_tracker!(tracker::ProgressTracker, operation::Symbol; kwargs...)
    tracker.last_update = now()

    if operation == :download
        for (key, value) in kwargs
            if key == :progress
                tracker.download_progress = value
            elseif key == :file
                tracker.download_file = value
            elseif key == :total_mb
                tracker.download_total_mb = value
            elseif key == :current_mb
                tracker.download_current_mb = value
            elseif key == :active
                tracker.is_downloading = value
            end
        end
    elseif operation == :upload
        for (key, value) in kwargs
            if key == :progress
                tracker.upload_progress = value
            elseif key == :file
                tracker.upload_file = value
            elseif key == :total_mb
                tracker.upload_total_mb = value
            elseif key == :current_mb
                tracker.upload_current_mb = value
            elseif key == :active
                tracker.is_uploading = value
            end
        end
    elseif operation == :training
        for (key, value) in kwargs
            if key == :progress
                tracker.training_progress = value
            elseif key == :model
                tracker.training_model = value
            elseif key == :epoch
                tracker.training_epoch = value
            elseif key == :total_epochs
                tracker.training_total_epochs = value
            elseif key == :loss
                tracker.training_loss = value
            elseif key == :val_score
                tracker.training_val_score = value
            elseif key == :active
                tracker.is_training = value
            end
        end
    elseif operation == :prediction
        for (key, value) in kwargs
            if key == :progress
                tracker.prediction_progress = value
            elseif key == :model
                tracker.prediction_model = value
            elseif key == :rows_processed
                tracker.prediction_rows_processed = value
            elseif key == :total_rows
                tracker.prediction_total_rows = value
            elseif key == :active
                tracker.is_predicting = value
            end
        end
    end
end

"""
Format duration in human-readable format
"""
function format_duration(seconds::Number)::String
    if seconds < 60
        return @sprintf("%ds", Int(seconds))
    elseif seconds < 3600
        mins = Int(seconds ÷ 60)
        secs = Int(seconds % 60)
        return @sprintf("%dm %ds", mins, secs)
    else
        hours = Int(seconds ÷ 3600)
        mins = Int((seconds % 3600) ÷ 60)
        return @sprintf("%dh %dm", hours, mins)
    end
end

"""
Center text within a given width
"""
function center_text(text::String, width::Int; pad_char::String=" ")::String
    text_len = length(text)
    if text_len >= width
        return text[1:width]
    end

    left_pad = (width - text_len) ÷ 2
    right_pad = width - text_len - left_pad

    return pad_char^left_pad * text * pad_char^right_pad
end

"""
Create a mini bar chart for a metric value
"""
function create_metric_bar(value::Float64, min_val::Float64, max_val::Float64, width::Int=15)::String
    # Normalize value to 0-1 range
    normalized = clamp((value - min_val) / (max_val - min_val), 0.0, 1.0)

    # Create bar with center marker
    center = width ÷ 2
    value_pos = Int(round(normalized * (width - 1)))

    bar = Char[]
    for i in 0:(width-1)
        if i == center
            push!(bar, '│')  # Center line
        elseif i == value_pos
            push!(bar, value >= 0 ? '▲' : '▼')  # Value marker
        elseif (value >= 0 && i > center && i < value_pos) || (value < 0 && i < center && i > value_pos)
            push!(bar, '═')  # Fill between center and value
        else
            push!(bar, '─')  # Empty space
        end
    end

    return "[" * join(bar) * "]"
end

"""
Render the enhanced single-panel dashboard
"""
function render_enhanced_dashboard(dashboard, progress_tracker::ProgressTracker)
    # Get terminal dimensions
    terminal_width = try
        displaysize(stdout)[2]
    catch
        120  # Default width
    end

    terminal_height = try
        displaysize(stdout)[1]
    catch
        40  # Default height
    end

    # Build dashboard content
    lines = String[]

    # Clean header without full-width borders
    push!(lines, "")
    header = "NUMERAI TOURNAMENT SYSTEM v0.10.0"
    push!(lines, center_text(header, terminal_width))
    push!(lines, "─" ^ terminal_width)

    # System status bar with real-time updates
    system_status = dashboard.paused ? "⏸ PAUSED" : "▶ RUNNING"
    network_icon = dashboard.network_status[:is_connected] ? "●" : "○"
    network_text = dashboard.network_status[:is_connected] ? "Online" : "Offline"
    latency = dashboard.network_status[:api_latency] > 0 ?
        @sprintf(" %dms", round(dashboard.network_status[:api_latency])) : ""
    uptime = format_duration(dashboard.system_info[:uptime])

    # Add memory and CPU info
    mem_used = dashboard.system_info[:memory_used]
    mem_total = dashboard.system_info[:memory_total]
    mem_usage = mem_total > 0 ? (mem_used / mem_total * 100) : 0.0
    threads = dashboard.system_info[:threads]

    status_line = @sprintf("System: %s | Network: %s %s%s | Memory: %.1f GB/%.1f GB | Threads: %d | Uptime: %s",
        system_status, network_icon, network_text, latency, mem_used, mem_total, threads, uptime)
    push!(lines, status_line)
    push!(lines, "")

    # Active Operations Section with improved visibility
    if progress_tracker.is_downloading || progress_tracker.is_uploading ||
       progress_tracker.is_training || progress_tracker.is_predicting

        push!(lines, "┌─ ACTIVE OPERATIONS ─────────────────────────────────────────┐")

        if progress_tracker.is_downloading
            spinner = create_spinner(Int(time() * 10))
            progress_bar = create_progress_bar(progress_tracker.download_progress, 100, width=40)
            file_display = length(progress_tracker.download_file) > 30 ?
                progress_tracker.download_file[1:27] * "..." : progress_tracker.download_file
            push!(lines, @sprintf("│ %s Download: %-30s │", spinner, file_display))
            push!(lines, @sprintf("│   %s │", progress_bar))
        end

        if progress_tracker.is_uploading
            spinner = create_spinner(Int(time() * 10))
            progress_bar = create_progress_bar(progress_tracker.upload_progress, 100, width=40)
            file_display = length(progress_tracker.upload_file) > 30 ?
                progress_tracker.upload_file[1:27] * "..." : progress_tracker.upload_file
            push!(lines, @sprintf("│ %s Upload: %-32s │", spinner, file_display))
            push!(lines, @sprintf("│   %s │", progress_bar))
        end

        if progress_tracker.is_training
            spinner = create_spinner(Int(time() * 10))
            epoch_info = @sprintf("Epoch %d/%d",
                progress_tracker.training_epoch, progress_tracker.training_total_epochs)
            model_display = length(progress_tracker.training_model) > 20 ?
                progress_tracker.training_model[1:17] * "..." : progress_tracker.training_model
            progress_bar = create_progress_bar(progress_tracker.training_progress, 100, width=40)
            push!(lines, @sprintf("│ %s Training: %-20s %s │", spinner, model_display, epoch_info))
            push!(lines, @sprintf("│   %s │", progress_bar))
        end

        if progress_tracker.is_predicting
            spinner = create_spinner(Int(time() * 10))
            model_display = length(progress_tracker.prediction_model) > 30 ?
                progress_tracker.prediction_model[1:27] * "..." : progress_tracker.prediction_model
            progress_bar = create_progress_bar(progress_tracker.prediction_progress, 100, width=40)
            push!(lines, @sprintf("│ %s Predicting: %-28s │", spinner, model_display))
            push!(lines, @sprintf("│   %s │", progress_bar))
        end

        push!(lines, "└──────────────────────────────────────────────────────────────┘")
        push!(lines, "")
    end

    # Model Performance Section
    push!(lines, "")
    push!(lines, "📊 MODEL PERFORMANCE")

    model_status = dashboard.model[:is_active] ? "🟢 Active" : "🔴 Inactive"
    push!(lines, "Model: $(dashboard.model[:name]) ($model_status)")

    # Tournament info - simplified without API call for now
    round_str = "Round #000"  # Will be updated when API is called
    submission_str = "Pending"
    time_left = "00:00:00"

    # Try to get actual tournament info if available
    try
        # Get current round info from API if available
        if isdefined(dashboard, :api_client) && dashboard.api_client !== nothing
            # This would need proper API integration
            # For now, use placeholder values
        end
    catch
        # Keep defaults on any error
    end

    push!(lines, "Tournament: $round_str │ Submission: $submission_str │ Time Left: $time_left")

    push!(lines, "")

    # Performance metrics with visual bars
    corr = dashboard.model[:corr]
    mmc = dashboard.model[:mmc]
    fnc = dashboard.model[:fnc]
    tc = get(dashboard.model, :tc, 0.0)
    sharpe = get(dashboard.model, :sharpe, 0.0)

    corr_bar = create_metric_bar(corr, -0.1, 0.1, 20)
    mmc_bar = create_metric_bar(mmc, -0.05, 0.05, 20)
    fnc_bar = create_metric_bar(fnc, -0.05, 0.05, 20)

    push!(lines, "CORR:   $corr_bar " * @sprintf("%+.4f", corr))
    push!(lines, "MMC:    $mmc_bar " * @sprintf("%+.4f", mmc))
    push!(lines, "FNC:    $fnc_bar " * @sprintf("%+.4f", fnc))
    push!(lines, "TC:     " * @sprintf("%+.4f", tc) * " │ Sharpe: " * @sprintf("%+.3f", sharpe))

    # Staking info if available
    if haskey(dashboard.model, :stake) && dashboard.model[:stake] > 0
        stake = dashboard.model[:stake]
        at_risk = stake * 0.25
        expected = stake * corr * 0.5
        push!(lines, "")
        stake_str = @sprintf("%.2f", stake)
        risk_str = @sprintf("%.2f", at_risk)
        expected_str = @sprintf("%+.2f", expected)
        push!(lines, "💰 Stake: $stake_str NMR │ At Risk: $risk_str NMR │ Expected: $expected_str NMR")
    end

    push!(lines, "─" ^ terminal_width)

    # System Resources Section
    push!(lines, "")
    push!(lines, "⚙️  SYSTEM RESOURCES")

    cpu_usage = dashboard.system_info[:cpu_usage]
    mem_used = dashboard.system_info[:memory_used]
    mem_total = dashboard.system_info[:memory_total]
    mem_pct = round(100 * mem_used / max(mem_total, 1), digits=0)

    cpu_bar = create_progress_bar(cpu_usage, 100, width=25, show_percent=false)
    mem_bar = create_progress_bar(mem_pct, 100, width=25, show_percent=false)

    cpu_str = @sprintf("%3d%%", cpu_usage)
    push!(lines, "CPU:    $cpu_bar $cpu_str")

    mem_str = @sprintf("%3d%%", Int(mem_pct))
    mem_detail = @sprintf("(%.1f/%.1f GB)", mem_used, mem_total)
    push!(lines, "Memory: $mem_bar $mem_str $mem_detail")

    threads = dashboard.system_info[:threads]
    julia_ver = get(dashboard.system_info, :julia_version, VERSION)
    push!(lines, "Threads: $threads │ Julia $julia_ver")

    push!(lines, "─" ^ terminal_width)

    # Recent Events Section
    push!(lines, "")
    push!(lines, "📋 RECENT EVENTS")

    if isempty(dashboard.events)
        push!(lines, "  No recent events")
    else
        # Calculate how many events we can show based on remaining space
        used_lines = length(lines) + 4  # Account for command help and spacing
        available_lines = terminal_height - used_lines
        max_events = min(max(5, available_lines - 2), length(dashboard.events))

        recent_events = dashboard.events[max(1, end-max_events+1):end]
        for event in reverse(recent_events)
            timestamp = Dates.format(event[:time], "HH:MM:SS")
            icon = event[:type] == :error ? "❌" :
                   event[:type] == :warning ? "⚠️ " :
                   event[:type] == :success ? "✅" : "ℹ️ "

            # Truncate message to fit terminal width
            max_msg_len = terminal_width - 15  # Account for timestamp and icon
            message = length(event[:message]) > max_msg_len ?
                     event[:message][1:max_msg_len-3] * "..." : event[:message]

            push!(lines, "  [$timestamp] $icon $message")
        end
    end

    push!(lines, "─" ^ terminal_width)

    # Help/Commands Section
    push!(lines, "")
    if dashboard.command_mode
        push!(lines, "💬 Command: /$(dashboard.command_buffer)_")
    elseif dashboard.show_help
        push!(lines, "❓ HELP")
        push!(lines, "  [n] New Model     [/] Command Mode  [h] Toggle Help")
        push!(lines, "  [s] Start Train   [r] Refresh Data   [q] Quit")
        push!(lines, "  [p] Pause/Resume  [d] Download Data  [c] Check Config")
    else
        push!(lines, "Press 'n' for new model │ '/' for commands │ 'h' for help │ 'q' to quit")
    end

    # Print all lines
    for line in lines
        println(line)
    end
end

"""
Render unified status panel with all system information
"""
function render_unified_status_panel(dashboard)::String
    lines = String[]

    # System Diagnostics
    push!(lines, "🔧 SYSTEM DIAGNOSTICS:")
    sys = dashboard.system
    cpu_usage = @sprintf("%.0f%%", get(sys, :cpu_usage, 0))
    load_avg = get(sys, :load_avg, (0.0, 0.0, 0.0))
    load_str = @sprintf("%.2f, %.2f, %.2f", load_avg...)
    memory_used = get(sys, :memory_used, 0.0)
    memory_total = get(sys, :memory_total, 48.0)
    memory_pct = memory_total > 0 ? (memory_used / memory_total * 100) : 0

    push!(lines, "   CPU Usage: $cpu_usage (Load: $load_str)")
    push!(lines, @sprintf("   Memory: %.1f GB / %.1f GB (%.0f%%)", memory_used, memory_total, memory_pct))

    # Disk space (placeholder - would need actual implementation)
    push!(lines, "   Disk Space: 0.0 GB free / 0.0 GB total")
    push!(lines, @sprintf("   Process Memory: %.1f MB", get(sys, :process_memory, 0.0)))
    push!(lines, @sprintf("   Threads: %d (Julia: %d)", get(sys, :threads, 1), Threads.nthreads()))

    uptime = get(sys, :uptime, 0)
    uptime_str = format_duration(uptime)
    push!(lines, "   Uptime: $uptime_str")
    push!(lines, "")

    # Configuration Status
    push!(lines, "⚙️  CONFIGURATION STATUS:")

    # API Keys - safely display partial keys
    pub_key = get(ENV, "NUMERAI_PUBLIC_ID", "NOT SET")
    sec_key = get(ENV, "NUMERAI_SECRET_KEY", "NOT SET")
    if pub_key != "NOT SET" && length(pub_key) > 8
        pub_display = pub_key[1:4] * "..." * pub_key[end-3:end]
    else
        pub_display = pub_key
    end
    if sec_key != "NOT SET" && length(sec_key) > 8
        sec_display = sec_key[1:4] * "..." * sec_key[end-3:end]
    else
        sec_display = sec_key
    end
    api_status = (pub_key != "NOT SET" && sec_key != "NOT SET") ? "✅" : "❌"
    push!(lines, "   API Keys: $api_status Set via ENV ($pub_display, $sec_display)")

    push!(lines, "   Tournament ID: $(dashboard.config.tournament_id)")
    push!(lines, "   Data Directory: ✅ $(dashboard.config.data_dir)")
    push!(lines, "   Models Directory: ✅ $(dashboard.config.model_dir)")
    push!(lines, "   Feature Set: $(dashboard.config.feature_set)")

    # Environment variables summary
    env_vars = []
    push!(env_vars, "NUMERAI_PUBLIC_ID=***")
    push!(env_vars, "NUMERAI_SECRET_KEY=***")
    push!(env_vars, "JULIA_NUM_THREADS=$(Threads.nthreads())")
    if haskey(ENV, "PATH")
        path = ENV["PATH"]
        if length(path) > 30
            path = path[1:27] * "..."
        end
        push!(env_vars, "PATH=$path")
    end
    push!(lines, "   Environment Variables: " * join(env_vars, ", "))
    push!(lines, "")

    # Current Model Status
    push!(lines, "📊 CURRENT MODEL STATUS:")
    model_name = get(dashboard.model, :name, "Unknown")
    is_active = get(dashboard.model, :is_active, false)
    push!(lines, "   Model: $model_name")
    push!(lines, "   Active: $(is_active ? "Yes" : "No")")
    push!(lines, "")

    # Local Data Files
    push!(lines, "📁 LOCAL DATA FILES:")

    # Check for model files
    push!(lines, "   Model Files:")
    model_dir = dashboard.config.model_dir
    if isdir(model_dir)
        model_files = readdir(model_dir)
        if !isempty(model_files)
            for file in model_files[1:min(3, length(model_files))]
                filepath = joinpath(model_dir, file)
                if isfile(filepath)
                    size_mb = filesize(filepath) / 1024 / 1024
                    mtime_val = mtime(filepath)
                    mtime_dt = Dates.unix2datetime(mtime_val)
                    time_str = Dates.format(mtime_dt, "yyyy-mm-dd HH:MM")
                    push!(lines, @sprintf("     • %s (%.1f MB, %s)", file, size_mb, time_str))
                end
            end
        end
    end

    # Check for data files
    push!(lines, "   Data Files:")
    data_dir = dashboard.config.data_dir
    important_files = ["features.json", "live.parquet", "train.parquet", "validation.parquet"]
    for file in important_files
        filepath = joinpath(data_dir, file)
        if isfile(filepath)
            size_bytes = filesize(filepath)
            if size_bytes > 1024 * 1024 * 1024  # GB
                size_str = @sprintf("%.1f GB", size_bytes / 1024 / 1024 / 1024)
            elseif size_bytes > 1024 * 1024  # MB
                size_str = @sprintf("%.1f MB", size_bytes / 1024 / 1024)
            else  # KB
                size_str = @sprintf("%.1f KB", size_bytes / 1024)
            end
            mtime_val = mtime(filepath)
            mtime_dt = Dates.unix2datetime(mtime_val)
            time_str = Dates.format(mtime_dt, "yyyy-mm-dd HH:MM")
            push!(lines, "     • $file ($size_str, $time_str)")
        end
    end

    # Config files
    push!(lines, "   Config Files:")
    config_files = ["config.toml"]
    for file in config_files
        if isfile(file)
            size_bytes = filesize(file)
            size_str = @sprintf("%.0f B", size_bytes)
            mtime_val = mtime(file)
            mtime_dt = Dates.unix2datetime(mtime_val)
            time_str = Dates.format(mtime_dt, "yyyy-mm-dd HH:MM")
            push!(lines, "     • $file ($size_str, $time_str)")
        end
    end
    push!(lines, "")

    # Last Known Good State
    push!(lines, "💾 LAST KNOWN GOOD STATE:")
    # This would need implementation to track successful operations
    push!(lines, "   ❌ No previous good state recorded")
    push!(lines, "")

    # Network Status
    push!(lines, "🌐 NETWORK STATUS:")
    network = dashboard.network_status
    is_connected = get(network, :is_connected, false)
    connection_str = is_connected ? "✅ Connected" : "❌ Disconnected"
    push!(lines, "   Connection: $connection_str")

    last_check = get(network, :last_check, nothing)
    if last_check !== nothing
        push!(lines, "   Last Check: $last_check")
    else
        push!(lines, "   Last Check: Never")
    end

    latency = get(network, :api_latency, 0.0)
    push!(lines, @sprintf("   API Latency: %.1fms", latency))

    failures = get(network, :consecutive_failures, 0)
    push!(lines, "   Consecutive Failures: $failures")
    push!(lines, "")

    # Add progress bars for active operations
    if dashboard.progress_tracker.is_downloading
        push!(lines, "📥 DOWNLOADING:")
        push!(lines, "   File: $(dashboard.progress_tracker.download_file)")
        progress_bar = create_progress_bar(
            dashboard.progress_tracker.download_current_mb,
            dashboard.progress_tracker.download_total_mb,
            width=40
        )
        push!(lines, "   Progress: $progress_bar")
        push!(lines, @sprintf("   %.1f MB / %.1f MB",
            dashboard.progress_tracker.download_current_mb,
            dashboard.progress_tracker.download_total_mb))
        push!(lines, "")
    end

    if dashboard.progress_tracker.is_uploading
        push!(lines, "📤 UPLOADING:")
        push!(lines, "   File: $(dashboard.progress_tracker.upload_file)")
        progress_bar = create_progress_bar(
            dashboard.progress_tracker.upload_current_mb,
            dashboard.progress_tracker.upload_total_mb,
            width=40
        )
        push!(lines, "   Progress: $progress_bar")
        push!(lines, @sprintf("   %.1f MB / %.1f MB",
            dashboard.progress_tracker.upload_current_mb,
            dashboard.progress_tracker.upload_total_mb))
        push!(lines, "")
    end

    if dashboard.progress_tracker.is_training
        push!(lines, "🏋️ TRAINING:")
        push!(lines, "   Model: $(dashboard.progress_tracker.training_model)")
        progress_bar = create_progress_bar(
            dashboard.progress_tracker.training_epoch,
            dashboard.progress_tracker.training_total_epochs,
            width=40
        )
        push!(lines, "   Progress: $progress_bar")
        push!(lines, @sprintf("   Epoch: %d / %d",
            dashboard.progress_tracker.training_epoch,
            dashboard.progress_tracker.training_total_epochs))
        push!(lines, @sprintf("   Loss: %.4f | Val Score: %.4f",
            dashboard.progress_tracker.training_loss,
            dashboard.progress_tracker.training_val_score))
        push!(lines, "")
    end

    if dashboard.progress_tracker.is_predicting
        push!(lines, "🔮 PREDICTING:")
        push!(lines, "   Model: $(dashboard.progress_tracker.prediction_model)")
        progress_bar = create_progress_bar(
            dashboard.progress_tracker.prediction_rows_processed,
            dashboard.progress_tracker.prediction_total_rows,
            width=40
        )
        push!(lines, "   Progress: $progress_bar")
        push!(lines, @sprintf("   Rows: %d / %d",
            dashboard.progress_tracker.prediction_rows_processed,
            dashboard.progress_tracker.prediction_total_rows))
        push!(lines, "")
    end

    # Troubleshooting Suggestions
    push!(lines, "🔍 TROUBLESHOOTING SUGGESTIONS:")
    if !is_connected
        push!(lines, "   1. Check your internet connection")
        push!(lines, "   2. Verify API credentials are correct")
        push!(lines, "   3. Check Numerai API status at https://status.numer.ai")
    elseif failures > 0
        push!(lines, "   1. Check Numerai API status at https://status.numer.ai")
        push!(lines, "   2. Reduce API request frequency by increasing refresh_rate in config.toml")
        push!(lines, "   3. Try running: r to retry dashboard initialization")
    else
        push!(lines, "   System is operating normally")
    end
    push!(lines, "")

    # Recovery Commands
    push!(lines, "⌨️  RECOVERY COMMANDS:")
    push!(lines, "   r  - Retry dashboard initialization")
    push!(lines, "   n  - Test network connectivity")
    push!(lines, "   c  - Check configuration files")
    push!(lines, "   d  - Download fresh tournament data")
    push!(lines, "   l  - View detailed error logs")
    push!(lines, "   s  - Start training (original functionality)")
    push!(lines, "   /save - Save current diagnostic report")
    push!(lines, "   /diag - Run full system diagnostics")
    push!(lines, "   /reset - Reset all error counters")
    push!(lines, "   /backup - Create configuration backup")
    push!(lines, "   q  - Quit dashboard")
    push!(lines, "   h  - Show help")

    return join(lines, "\n")
end

"""
Render events panel showing recent events
"""
function render_events_panel(dashboard; max_events::Int=20)::String
    lines = String[]

    push!(lines, "📋 RECENT EVENTS:")
    push!(lines, "" * "─" ^ 60)

    events = dashboard.events
    if isempty(events)
        push!(lines, "   No events recorded yet")
    else
        # Show most recent events first
        for (i, event) in enumerate(reverse(events)[1:min(max_events, length(events))])
            type_icon = if event[:type] == :error
                "❌"
            elseif event[:type] == :warning
                "⚠️"
            elseif event[:type] == :success
                "✅"
            else
                "ℹ️"
            end

            timestamp = get(event, :time, now())
            time_str = Dates.format(timestamp, "HH:MM:SS")
            message = get(event, :message, "Unknown event")

            # Truncate long messages
            if length(message) > 50
                message = message[1:47] * "..."
            end

            push!(lines, "   [$time_str] $type_icon $message")
        end
    end

    return join(lines, "\n")
end

end # module