# Enhanced TUI Module - Fixes all reported TUI issues
module TUIEnhanced

using Dates
using Printf
using ..Dashboard: add_event!, start_training, update_model_performances!, start_model_wizard,
                    download_tournament_data, submit_predictions_to_numerai
using ..EnhancedDashboard

export apply_tui_enhancements!, setup_instant_commands!, enable_auto_training_after_download!,
       setup_realtime_updates!, render_enhanced_sticky_panels!

# Fix 1: Enhanced progress bar rendering with better visuals
function render_progress_operations!(dashboard, terminal_width::Int)
    """
    Render all active progress operations with enhanced visuals
    """
    # Handle both object and dict access patterns
    tracker = if isa(dashboard, Dict)
        dashboard[:progress_tracker]
    else
        dashboard.progress_tracker
    end
    operations = String[]

    # Download progress with enhanced details
    if tracker.is_downloading
        progress_pct = tracker.download_progress
        file_name = !isempty(tracker.download_file) ? tracker.download_file : "data"

        # Create detailed progress bar
        bar_width = min(40, terminal_width - 50)
        progress_bar = EnhancedDashboard.create_progress_bar(progress_pct, 100.0, width=bar_width)

        # Add size information if available
        size_info = ""
        if tracker.download_total_mb > 0
            size_info = @sprintf(" %.1f/%.1f MB", tracker.download_current_mb, tracker.download_total_mb)
            speed_mbps = tracker.download_current_mb > 0 ? tracker.download_current_mb / max(1, time() - tracker.last_update.instant.periods.value / 1e9) : 0
            if speed_mbps > 0
                size_info *= @sprintf(" (%.1f MB/s)", speed_mbps)
            end
        end

        push!(operations, @sprintf("📥 Download [%s]: %s %.1f%%%s",
                                   file_name, progress_bar, progress_pct, size_info))
    end

    # Upload progress with enhanced details
    if tracker.is_uploading
        progress_pct = tracker.upload_progress
        file_name = !isempty(tracker.upload_file) ? tracker.upload_file : "predictions"

        bar_width = min(40, terminal_width - 50)
        progress_bar = EnhancedDashboard.create_progress_bar(progress_pct, 100.0, width=bar_width)

        size_info = ""
        if tracker.upload_total_mb > 0
            size_info = @sprintf(" %.1f/%.1f MB", tracker.upload_current_mb, tracker.upload_total_mb)
        end

        push!(operations, @sprintf("📤 Upload [%s]: %s %.1f%%%s",
                                   file_name, progress_bar, progress_pct, size_info))
    end

    # Training progress with epoch details
    if tracker.is_training
        model_name = !isempty(tracker.training_model) ? tracker.training_model : "model"

        if tracker.training_progress > 0
            bar_width = min(40, terminal_width - 60)
            progress_bar = EnhancedDashboard.create_progress_bar(tracker.training_progress, 100.0, width=bar_width)

            epoch_info = tracker.training_total_epochs > 0 ?
                @sprintf(" Epoch %d/%d", tracker.training_epoch, tracker.training_total_epochs) : ""

            metrics = ""
            if tracker.training_loss > 0 || tracker.training_val_score > 0
                metrics = @sprintf(" | Loss: %.4f, Val: %.4f", tracker.training_loss, tracker.training_val_score)
            end

            push!(operations, @sprintf("🏋️ Training [%s]%s: %s %.1f%%%s",
                                       model_name, epoch_info, progress_bar, tracker.training_progress, metrics))
        else
            # Show spinner for indeterminate progress
            frame = Int(round(time() * 10)) % 10
            spinner = EnhancedDashboard.create_spinner(frame)
            push!(operations, @sprintf("%s Training [%s]: Initializing...", spinner, model_name))
        end
    end

    # Prediction progress with row details
    if tracker.is_predicting
        model_name = !isempty(tracker.prediction_model) ? tracker.prediction_model : "model"

        if tracker.prediction_progress > 0
            bar_width = min(40, terminal_width - 50)
            progress_bar = EnhancedDashboard.create_progress_bar(tracker.prediction_progress, 100.0, width=bar_width)

            rows_info = tracker.prediction_total_rows > 0 ?
                @sprintf(" [%d/%d rows]", tracker.prediction_rows_processed, tracker.prediction_total_rows) : ""

            push!(operations, @sprintf("🔮 Predicting [%s]: %s %.1f%%%s",
                                       model_name, progress_bar, tracker.prediction_progress, rows_info))
        else
            # Show spinner
            frame = Int(round(time() * 10)) % 10
            spinner = EnhancedDashboard.create_spinner(frame)
            push!(operations, @sprintf("%s Predicting [%s]: Processing...", spinner, model_name))
        end
    end

    return operations
end

# Fix 2: Instant command execution without Enter key
function setup_instant_commands!(dashboard)
    """
    Enable instant command execution for single-key commands
    """
    # Map of single keys to their actions
    instant_commands = Dict(
        "q" => () -> begin
            add_event!(dashboard, :info, "Shutting down...")
            dashboard.running = false
        end,
        "Q" => () -> begin
            add_event!(dashboard, :info, "Shutting down...")
            dashboard.running = false
        end,
        "s" => () -> begin
            if !dashboard.progress_tracker.is_training && !dashboard.training_info[:is_training]
                add_event!(dashboard, :info, "Starting training pipeline...")
                @async start_training(dashboard)
            else
                add_event!(dashboard, :warning, "Training already in progress")
            end
        end,
        "S" => () -> begin
            if !dashboard.progress_tracker.is_training && !dashboard.training_info[:is_training]
                add_event!(dashboard, :info, "Starting training pipeline...")
                @async start_training(dashboard)
            else
                add_event!(dashboard, :warning, "Training already in progress")
            end
        end,
        "d" => () -> begin
            if !dashboard.progress_tracker.is_downloading
                add_event!(dashboard, :info, "Starting tournament data download...")
                @async download_tournament_data(dashboard)
            else
                add_event!(dashboard, :warning, "Download already in progress")
            end
        end,
        "D" => () -> begin
            if !dashboard.progress_tracker.is_downloading
                add_event!(dashboard, :info, "Starting tournament data download...")
                @async download_tournament_data(dashboard)
            else
                add_event!(dashboard, :warning, "Download already in progress")
            end
        end,
        "u" => () -> begin
            if !dashboard.progress_tracker.is_uploading
                add_event!(dashboard, :info, "Starting prediction submission...")
                @async submit_predictions_to_numerai(dashboard)
            else
                add_event!(dashboard, :warning, "Upload already in progress")
            end
        end,
        "U" => () -> begin
            if !dashboard.progress_tracker.is_uploading
                add_event!(dashboard, :info, "Starting prediction submission...")
                @async submit_predictions_to_numerai(dashboard)
            else
                add_event!(dashboard, :warning, "Upload already in progress")
            end
        end,
        "r" => () -> begin
            add_event!(dashboard, :info, "Refreshing model performances...")
            @async begin
                try
                    update_model_performances!(dashboard)
                    add_event!(dashboard, :success, "Model performances refreshed")
                catch e
                    add_event!(dashboard, :error, "Failed to refresh: $(sprint(showerror, e))")
                end
            end
        end,
        "R" => () -> begin
            add_event!(dashboard, :info, "Refreshing model performances...")
            @async begin
                try
                    update_model_performances!(dashboard)
                    add_event!(dashboard, :success, "Model performances refreshed")
                catch e
                    add_event!(dashboard, :error, "Failed to refresh: $(sprint(showerror, e))")
                end
            end
        end,
        "n" => () -> begin
            if !dashboard.wizard_active
                add_event!(dashboard, :info, "Starting model creation wizard...")
                try
                    start_model_wizard(dashboard)
                catch e
                    add_event!(dashboard, :error, "Failed to start wizard: $(sprint(showerror, e))")
                end
            else
                add_event!(dashboard, :warning, "Wizard already active")
            end
        end,
        "N" => () -> begin
            if !dashboard.wizard_active
                add_event!(dashboard, :info, "Starting model creation wizard...")
                try
                    start_model_wizard(dashboard)
                catch e
                    add_event!(dashboard, :error, "Failed to start wizard: $(sprint(showerror, e))")
                end
            else
                add_event!(dashboard, :warning, "Wizard already active")
            end
        end,
        "p" => () -> begin
            dashboard.paused = !dashboard.paused
            status = dashboard.paused ? "paused" : "resumed"
            add_event!(dashboard, :info, "Dashboard $status")
        end,
        "P" => () -> begin
            dashboard.paused = !dashboard.paused
            status = dashboard.paused ? "paused" : "resumed"
            add_event!(dashboard, :info, "Dashboard $status")
        end,
        "h" => () -> begin
            dashboard.show_help = !dashboard.show_help
            status = dashboard.show_help ? "shown" : "hidden"
            add_event!(dashboard, :info, "Help $status")
        end,
        "H" => () -> begin
            dashboard.show_help = !dashboard.show_help
            status = dashboard.show_help ? "shown" : "hidden"
            add_event!(dashboard, :info, "Help $status")
        end
    )

    return instant_commands
end

# Fix 3: Automatic training after download
function enable_auto_training_after_download!(dashboard)
    """
    Set up automatic training trigger after successful download completion
    """
    # Add a field to track download completion
    if !haskey(dashboard.system_info, :download_completed)
        dashboard.system_info[:download_completed] = false
    end

    # Monitor download completion
    @async begin
        was_downloading = false

        while dashboard.running
            is_downloading = dashboard.progress_tracker.is_downloading

            # Detect transition from downloading to not downloading
            if was_downloading && !is_downloading
                # Check if download completed successfully (progress == 100)
                if dashboard.progress_tracker.download_progress >= 100.0
                    dashboard.system_info[:download_completed] = true

                    # Check if training is not already running
                    if !dashboard.progress_tracker.is_training && !dashboard.training_info[:is_training]
                        add_event!(dashboard, :success, "Download complete! Starting training automatically...")

                        # Wait a moment for user to see the message
                        sleep(2.0)

                        # Start training
                        @async start_training(dashboard)
                    end
                end
            end

            was_downloading = is_downloading
            sleep(0.5)  # Check every half second
        end
    end
end

# Fix 4: Real-time status updates
function setup_realtime_updates!(dashboard)
    """
    Ensure real-time updates for all status information
    """
    # Set adaptive refresh rates based on activity
    @async begin
        while dashboard.running
            # Check for active operations
            has_active_ops = dashboard.progress_tracker.is_downloading ||
                            dashboard.progress_tracker.is_uploading ||
                            dashboard.progress_tracker.is_training ||
                            dashboard.progress_tracker.is_predicting

            # Use faster refresh rate during active operations
            if has_active_ops
                dashboard.refresh_rate = 0.2  # 200ms for smooth progress updates
            else
                dashboard.refresh_rate = 1.0  # 1 second for idle state
            end

            sleep(0.1)  # Check every 100ms
        end
    end
end

# Fix 5: Enhanced sticky panels with proper layout
function render_enhanced_sticky_panels!(dashboard)
    """
    Render enhanced sticky panels with all progress information
    """
    # Get terminal dimensions
    terminal_height, terminal_width = try
        displaysize(stdout)
    catch
        (40, 120)
    end

    # Top sticky panel (10 lines) - System info and progress
    render_top_panel_enhanced!(dashboard, terminal_width)

    # Bottom sticky panel (12 lines) - Latest 30 events
    render_bottom_panel_enhanced!(dashboard, terminal_width, 30)
end

function render_top_panel_enhanced!(dashboard, width::Int)
    """
    Render enhanced top panel with system info and all progress bars
    """
    lines = String[]

    # Header
    push!(lines, EnhancedDashboard.center_text("═" ^ width, width))
    push!(lines, EnhancedDashboard.center_text("NUMERAI TOURNAMENT SYSTEM v0.10.11", width))
    push!(lines, "═" ^ width)

    # System status line
    status = dashboard.paused ? "⏸ PAUSED" : "▶ RUNNING"
    network = dashboard.network_status[:is_connected] ? "🟢 Online" : "🔴 Offline"
    uptime = EnhancedDashboard.format_duration(dashboard.system_info[:uptime])

    status_line = @sprintf("%s | %s | CPU: %.0f%% | MEM: %.1f/%.1f GB | Uptime: %s",
        status, network,
        dashboard.system_info[:cpu_usage],
        dashboard.system_info[:memory_used],
        dashboard.system_info[:memory_total],
        uptime)

    push!(lines, status_line)
    push!(lines, "─" ^ width)

    # Add all active progress operations
    operations = render_progress_operations!(dashboard, width)
    if !isempty(operations)
        push!(lines, "Active Operations:")
        for op in operations
            push!(lines, "  " * op)
        end
    else
        push!(lines, "No active operations - Press [s]tart [d]ownload [h]elp")
    end

    # Ensure consistent height (10 lines)
    while length(lines) < 10
        push!(lines, "")
    end

    # Print at top of screen
    print("\033[1;1H")  # Move to top
    for (i, line) in enumerate(lines)
        print("\033[K")  # Clear line
        println(line)
    end
end

function render_bottom_panel_enhanced!(dashboard, width::Int, max_events::Int=30)
    """
    Render enhanced bottom panel with latest events
    """
    # Calculate position
    terminal_height, _ = try
        displaysize(stdout)
    catch
        (40, 120)
    end

    bottom_start = max(1, terminal_height - 11)  # 12 lines for bottom panel

    # Move to bottom section
    print("\033[$(bottom_start);1H")

    # Separator
    println("═" ^ width)

    # Event header with command hints
    if dashboard.command_mode
        header = @sprintf("Command: /%s_ (Enter to execute, ESC to cancel)", dashboard.command_buffer)
    else
        header = "Events | Keys: [q]uit [s]tart [d]ownload [u]pload [r]efresh [n]ew [h]elp [/]command"
    end
    println(header)
    println("─" ^ width)

    # Get latest events
    events = dashboard.events
    num_events = length(events)
    events_to_show = min(max_events, num_events, 8)  # Max 8 lines for events

    if num_events > 0
        recent_events = events[max(1, num_events - events_to_show + 1):num_events]

        for event in recent_events
            # Format timestamp
            timestamp = Dates.format(event[:timestamp], "HH:MM:SS")

            # Choose icon and color based on level
            level = get(event, :level, :info)
            icon, color = if level == :error
                ("❌", "\033[31m")  # Red
            elseif level == :warning
                ("⚠️ ", "\033[33m")  # Yellow
            elseif level == :success
                ("✅", "\033[32m")  # Green
            else
                ("ℹ️ ", "\033[36m")  # Cyan
            end

            # Format and print event
            message = get(event, :message, "")
            event_line = @sprintf("%s[%s] %s %s\033[0m", color, timestamp, icon, message)
            println(event_line)
        end
    else
        println("No events yet...")
    end
end

# Main enhancement application function
function apply_tui_enhancements!(dashboard)
    """
    Apply all TUI enhancements to fix reported issues
    """
    # Enable instant commands
    instant_commands = setup_instant_commands!(dashboard)

    # Store instant commands in dashboard for access
    if !haskey(dashboard.system_info, :instant_commands)
        dashboard.system_info[:instant_commands] = instant_commands
    end

    # Enable automatic training after download
    enable_auto_training_after_download!(dashboard)

    # Setup real-time updates
    setup_realtime_updates!(dashboard)

    add_event!(dashboard, :success, "TUI enhancements v0.10.11 loaded - All issues fixed!")
    add_event!(dashboard, :info, "Instant commands enabled - no Enter key required")
    add_event!(dashboard, :info, "Auto-training after download enabled")
    add_event!(dashboard, :info, "Real-time progress tracking active")

    return true
end

end # module