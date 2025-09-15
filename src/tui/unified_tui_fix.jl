module UnifiedTUIFix

using ..Dashboard: TournamentDashboard, add_event!
using ..Dashboard: download_data_internal, train_models_internal, submit_predictions_internal
using ..Dashboard: execute_command
using ..EnhancedDashboard: render_enhanced_dashboard
using Dates
using Printf
using Term

export apply_unified_fix!, monitor_operations, setup_sticky_panels!
export read_key_improved, handle_instant_command, unified_input_loop
export download_with_progress, train_with_progress, submit_with_progress
export render_with_sticky_panels

struct UnifiedFix
    instant_commands::Bool
    auto_training::Bool
    real_progress::Bool
    sticky_panels::Bool
    monitor_thread::Ref{Union{Task, Nothing}}
end

const UNIFIED_FIX = Ref{Union{UnifiedFix, Nothing}}(nothing)

"""
Apply unified TUI fixes to enable all enhanced features
"""
function apply_unified_fix!(dashboard::TournamentDashboard)
    if !isnothing(UNIFIED_FIX[])
        @info "Unified TUI fix already applied"
        return true
    end

    try
        # Initialize unified fix
        fix = UnifiedFix(
            true,  # instant_commands
            true,  # auto_training
            true,  # real_progress
            true,  # sticky_panels
            Ref{Union{Task, Nothing}}(nothing)
        )

        UNIFIED_FIX[] = fix

        # Start monitoring task for real-time updates
        fix.monitor_thread[] = @async monitor_operations(dashboard)

        # Setup sticky panels configuration
        setup_sticky_panels!(dashboard)

        # Mark unified fix as active in dashboard
        dashboard.active_operations[:unified_fix] = true

        add_event!(dashboard, :success, "✅ Unified TUI fix applied - All features enabled")
        @info "Unified TUI fix successfully applied"

        return true
    catch e
        @error "Failed to apply unified fix" exception=e
        add_event!(dashboard, :error, "❌ Failed to apply unified fix: $(e)")
        return false
    end
end

"""
Read single key input without requiring Enter (improved version)
"""
function read_key_improved()
    local key_pressed = ""
    local raw_mode_set = false

    try
        if isa(stdin, Base.TTY)
            # Set stdin to raw mode for immediate key capture
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)
            raw_mode_set = true

            if bytesavailable(stdin) > 0
                first_char = String(read(stdin, 1))

                # Handle escape sequences
                if first_char == "\e"
                    # Check for multi-character sequences with minimal delay
                    sleep(0.001)  # Very short delay to catch sequences
                    if bytesavailable(stdin) > 0
                        second_char = String(read(stdin, 1))
                        if second_char == "["
                            if bytesavailable(stdin) > 0
                                third_char = String(read(stdin, 1))
                                key_pressed = "\e[$third_char"
                            else
                                key_pressed = "\e["
                            end
                        else
                            # Put back the second char and return just ESC
                            key_pressed = first_char
                        end
                    else
                        key_pressed = first_char  # Just ESC
                    end
                else
                    key_pressed = first_char
                end
            end
        end
    finally
        if raw_mode_set && isa(stdin, Base.TTY)
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)
        end
    end

    return key_pressed
end

"""
Handle instant command execution without Enter key
"""
function handle_instant_command(dashboard::TournamentDashboard, key::String)
    if isempty(key)
        return false
    end

    # Convert single key to command
    command = if key == "q"
        "/quit"
    elseif key == "d"
        "/download"
    elseif key == "u"
        "/upload"
    elseif key == "s"
        "/submit"
    elseif key == "t"
        "/train"
    elseif key == "p"
        "/predict"
    elseif key == "r"
        "/refresh"
    elseif key == "n"
        "/new"
    elseif key == "h"
        "/help"
    else
        return false  # Not a recognized instant command
    end

    # Execute command using real implementation
    add_event!(dashboard, :info, "🎯 Executing: $command")

    # Use the real command handler from DashboardCommands
    result = execute_command(dashboard, command)

    if result
        add_event!(dashboard, :success, "✅ Command completed: $command")
    end

    return result
end

"""
Unified input loop with instant commands
"""
function unified_input_loop(dashboard::TournamentDashboard)
    while dashboard.running
        key = read_key_improved()

        if !isempty(key)
            # Handle instant command
            if key == "q"
                dashboard.running = false
                break
            else
                @async handle_instant_command(dashboard, key)
            end
        end

        # Small delay to prevent CPU spinning
        sleep(0.05)
    end
end

"""
Download data with real progress tracking
"""
function download_with_progress(dashboard::TournamentDashboard)
    add_event!(dashboard, :info, "📥 Starting data download with progress tracking...")

    # Set progress state
    dashboard.progress_tracker.is_downloading = true
    dashboard.progress_tracker.download_progress = 0.0
    dashboard.progress_tracker.download_status = "Initializing download..."

    try
        # Use real download implementation with progress callbacks
        success = download_data_internal(dashboard)

        if success
            dashboard.progress_tracker.download_progress = 1.0
            dashboard.progress_tracker.download_status = "Download complete!"
            add_event!(dashboard, :success, "✅ Data download completed successfully")

            # Auto-training after successful download if configured
            if dashboard.config.auto_submit ||
               get(dashboard.config, :auto_train_after_download, false) ||
               get(ENV, "AUTO_TRAIN", "false") == "true"
                add_event!(dashboard, :info, "🚀 Starting automatic training after download...")
                # Small delay to show completion
                sleep(1.0)
                train_with_progress(dashboard)
            end
        else
            add_event!(dashboard, :error, "❌ Data download failed")
        end
    catch e
        @error "Download error" exception=e
        add_event!(dashboard, :error, "❌ Download error: $(e)")
    finally
        dashboard.progress_tracker.is_downloading = false
    end
end

"""
Train models with real progress tracking
"""
function train_with_progress(dashboard::TournamentDashboard)
    add_event!(dashboard, :info, "🏋️ Starting model training with progress tracking...")

    # Set progress state
    dashboard.progress_tracker.is_training = true
    dashboard.progress_tracker.train_progress = 0.0
    dashboard.progress_tracker.train_status = "Initializing training..."

    try
        # Use real training implementation
        success = train_models_internal(dashboard)

        if success
            dashboard.progress_tracker.train_progress = 1.0
            dashboard.progress_tracker.train_status = "Training complete!"
            add_event!(dashboard, :success, "✅ Model training completed successfully")
        else
            add_event!(dashboard, :error, "❌ Model training failed")
        end
    catch e
        @error "Training error" exception=e
        add_event!(dashboard, :error, "❌ Training error: $(e)")
    finally
        dashboard.progress_tracker.is_training = false
    end
end

"""
Submit predictions with real progress tracking
"""
function submit_with_progress(dashboard::TournamentDashboard)
    add_event!(dashboard, :info, "📤 Starting prediction submission with progress tracking...")

    # Set progress state
    dashboard.progress_tracker.is_uploading = true
    dashboard.progress_tracker.upload_progress = 0.0
    dashboard.progress_tracker.upload_status = "Initializing submission..."

    try
        # First run predictions if needed
        dashboard.progress_tracker.is_predicting = true
        dashboard.progress_tracker.predict_progress = 0.0
        dashboard.progress_tracker.predict_status = "Generating predictions..."

        # Use real submission implementation
        success = submit_predictions_internal(dashboard)

        if success
            dashboard.progress_tracker.upload_progress = 1.0
            dashboard.progress_tracker.upload_status = "Submission complete!"
            dashboard.progress_tracker.predict_progress = 1.0
            dashboard.progress_tracker.predict_status = "Predictions complete!"
            add_event!(dashboard, :success, "✅ Predictions submitted successfully")
        else
            add_event!(dashboard, :error, "❌ Prediction submission failed")
        end
    catch e
        @error "Submission error" exception=e
        add_event!(dashboard, :error, "❌ Submission error: $(e)")
    finally
        dashboard.progress_tracker.is_uploading = false
        dashboard.progress_tracker.is_predicting = false
    end
end

"""
Monitor operations and update progress tracker in real-time
"""
function monitor_operations(dashboard::TournamentDashboard)
    @info "Starting operation monitoring for real-time updates"

    while dashboard.running
        try
            # Check if any operations are active
            is_active = dashboard.progress_tracker.is_downloading ||
                       dashboard.progress_tracker.is_uploading ||
                       dashboard.progress_tracker.is_training ||
                       dashboard.progress_tracker.is_predicting

            if is_active
                # Update system info to show activity
                dashboard.system_info[:model_active] = true

                # Force dashboard refresh for real-time updates
                dashboard.refresh_rate = 0.2  # Fast refresh during operations
            else
                # Update system info to idle when no operations
                dashboard.system_info[:model_active] = false
                dashboard.refresh_rate = 1.0  # Normal refresh when idle
            end

            # Adaptive sleep based on activity
            sleep(is_active ? 0.2 : 1.0)

        catch e
            @error "Error in operation monitoring" exception=e
            sleep(1.0)
        end
    end

    @info "Operation monitoring stopped"
end

"""
Setup sticky panels with ANSI positioning
"""
function setup_sticky_panels!(dashboard::TournamentDashboard)
    # Enable sticky panels in TUI configuration dictionary
    dashboard.config.tui_config["sticky_top_panel"] = true
    dashboard.config.tui_config["sticky_bottom_panel"] = true
    dashboard.config.tui_config["event_limit"] = 30  # Show last 30 events in bottom panel

    # Store terminal dimensions for proper positioning
    terminal_height, terminal_width = displaysize(stdout)

    # Configure panel heights
    dashboard.config.tui_config["top_panel_height"] = 8    # System status panel
    dashboard.config.tui_config["bottom_panel_height"] = 10 # Event log panel
    dashboard.config.tui_config["main_panel_start"] = 9    # Main content starts after top panel
    dashboard.config.tui_config["main_panel_end"] = terminal_height - 10  # Main content ends before bottom panel

    add_event!(dashboard, :info, "📌 Sticky panels configured (top: system, bottom: events)")
end

"""
Enhanced render dashboard with sticky panels using ANSI positioning and real-time updates
"""
function render_with_sticky_panels(dashboard::TournamentDashboard)
    # Get terminal dimensions
    terminal_height, terminal_width = displaysize(stdout)

    # Clear screen once
    print("\033[2J")

    # === TOP STICKY PANEL (System Status) ===
    # Position cursor at top
    print("\033[1;1H")

    # Render system status panel
    status_icon = dashboard.system_info[:model_active] ? "🔄" : "🟢"
    status_level = dashboard.system_info[:model_active] ? "Running" : "Ready"
    status_panel = Panel(
        """
        $(status_icon) Status: $(status_level)
        📊 Active Models: $(length(dashboard.models))
        🔄 Last Update: $(Dates.format(now(), "HH:MM:SS"))

        Progress:
        $(dashboard.progress_tracker.is_downloading ? "📥 Download: $(round(dashboard.progress_tracker.download_progress * 100, digits=1))%" : "")
        $(dashboard.progress_tracker.is_training ? "🏋️ Training: $(round(dashboard.progress_tracker.train_progress * 100, digits=1))%" : "")
        $(dashboard.progress_tracker.is_uploading ? "📤 Upload: $(round(dashboard.progress_tracker.upload_progress * 100, digits=1))%" : "")
        """,
        title="System Status",
        style="green",
        width=terminal_width
    )
    println(status_panel)

    # === MAIN SCROLLABLE CONTENT ===
    # Position cursor after top panel
    print("\033[9;1H")

    # Render main dashboard content (will be scrollable)
    # This uses the existing enhanced dashboard rendering
    render_enhanced_dashboard(dashboard)

    # === BOTTOM STICKY PANEL (Event Logs) ===
    # Position cursor at bottom section
    bottom_start = terminal_height - 10
    print("\033[$(bottom_start);1H")

    # Get last 30 events (or configured limit)
    event_limit = get(dashboard.config.tui_config, "event_limit", 30)
    recent_events = length(dashboard.events) > event_limit ?
                   dashboard.events[end-(event_limit-1):end] :
                   dashboard.events

    # Format events with color coding and emojis
    event_lines = String[]
    for event in recent_events
        event_level = get(event, :level, :info)
        event_message = get(event, :message, "")
        event_timestamp = get(event, :timestamp, now())

        color = event_level == :error ? "red" :
                event_level == :warning ? "yellow" :
                event_level == :success ? "green" :
                "white"

        emoji = event_level == :error ? "❌" :
                event_level == :warning ? "⚠️" :
                event_level == :success ? "✅" :
                "ℹ️"

        time_str = Dates.format(event_timestamp, "HH:MM:SS")
        push!(event_lines, "[$time_str] $emoji $(event_message)")
    end

    events_panel = Panel(
        join(event_lines, "\n"),
        title="Recent Events (Last 30)",
        style="blue",
        width=terminal_width
    )
    println(events_panel)

    # Reset cursor position
    print("\033[$(terminal_height);1H")
end

end # module