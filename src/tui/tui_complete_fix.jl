"""
Complete TUI Fix Module

This module provides a comprehensive solution for all TUI issues:
1. Progress bars not showing - Fixed with proper render timing and progress tracking
2. Instant commands requiring Enter - Fixed with persistent raw TTY mode
3. No auto-training after downloads - Fixed with proper callback integration
4. Real-time updates not working - Fixed with adaptive render intervals
5. Missing sticky panels - Fixed with proper panel layout

This replaces all other TUI fix modules with a single, working implementation.
"""
module TUICompleteFix

using Term
using Printf
using Dates
using Statistics
using ..Dashboard: TournamentDashboard, add_event!, update_model_performances!,
                   execute_command, download_data_internal, train_models_internal,
                   submit_predictions_internal, run_full_pipeline, render
using ..EnhancedDashboard

export apply_complete_tui_fix!, run_fixed_dashboard, render_with_sticky_panels,
       setup_persistent_raw_mode!, cleanup_raw_mode!, fixed_input_loop,
       enable_auto_training_callbacks!, fast_render_loop

# Global state for TTY management
mutable struct TTYState
    original_mode::Int32
    raw_mode_active::Bool
    cleanup_registered::Bool
end

const TTY_STATE = Ref{Union{TTYState, Nothing}}(nothing)

"""
Apply the complete TUI fix to the dashboard.
This enables all the missing features and fixes all issues.
"""
function apply_complete_tui_fix!(dashboard::TournamentDashboard)
    @info "🔧 Applying complete TUI fix..."

    try
        # 1. Setup persistent raw TTY mode for instant commands
        setup_persistent_raw_mode!()

        # 2. Enable auto-training callbacks
        enable_auto_training_callbacks!(dashboard)

        # 3. Setup faster progress tracking
        setup_fast_progress_tracking!(dashboard)

        # 4. Enable sticky panels
        dashboard.extra_properties[:sticky_panels] = true

        add_event!(dashboard, :success, "✅ Complete TUI fix applied - all features enabled")
        return true

    catch e
        add_event!(dashboard, :error, "❌ Failed to apply TUI fix: $(sprint(showerror, e))")
        return false
    end
end

"""
Setup persistent raw TTY mode so commands execute instantly without Enter.
"""
function setup_persistent_raw_mode!()
    if !isa(stdin, Base.TTY)
        @warn "Not running in TTY, instant commands will be limited"
        return false
    end

    try
        # Get current terminal mode
        original_mode = ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)

        # Set to raw mode (characters available immediately)
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)

        # Store state
        TTY_STATE[] = TTYState(original_mode, true, false)

        # Register cleanup only once
        if !TTY_STATE[].cleanup_registered
            atexit(cleanup_raw_mode!)
            TTY_STATE[].cleanup_registered = true
        end

        @info "✅ Persistent raw mode enabled - press keys without Enter"
        return true

    catch e
        @warn "Failed to setup raw mode: $e"
        return false
    end
end

"""
Cleanup raw TTY mode on exit.
"""
function cleanup_raw_mode!()
    if !isnothing(TTY_STATE[]) && TTY_STATE[].raw_mode_active
        try
            if isa(stdin, Base.TTY)
                ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32),
                      stdin.handle, TTY_STATE[].original_mode)
            end
            TTY_STATE[].raw_mode_active = false
            @info "✅ Raw mode cleanup completed"
        catch e
            @warn "Raw mode cleanup failed: $e"
        end
    end
end

"""
Enhanced key reading that works with persistent raw mode.
"""
function read_key_instant()
    if !isa(stdin, Base.TTY)
        # Fallback for non-TTY
        return bytesavailable(stdin) > 0 ? String(read(stdin, 1)) : ""
    end

    try
        if bytesavailable(stdin) > 0
            first_char = String(read(stdin, 1))

            # Handle escape sequences for arrow keys, etc.
            if first_char == "\e"
                if bytesavailable(stdin) > 0
                    second_char = String(read(stdin, 1))
                    if second_char == "["
                        if bytesavailable(stdin) > 0
                            third_char = String(read(stdin, 1))
                            return "\e[$third_char"
                        end
                    end
                end
                return first_char
            else
                return first_char
            end
        end
    catch e
        @debug "Error reading key: $e"
    end

    return ""
end

"""
Enable auto-training callbacks that trigger after downloads complete.
"""
function enable_auto_training_callbacks!(dashboard::TournamentDashboard)
    # Use dashboard's extra_properties field
    dashboard.extra_properties[:auto_train_enabled] = true
    dashboard.extra_properties[:original_download_callback] = get(dashboard.extra_properties, :download_completion_callback, nothing)

    # Create new callback that includes auto-training
    dashboard.extra_properties[:download_completion_callback] = function()
        add_event!(dashboard, :info, "📥 Download completed - starting auto-training...")

        # Call original callback if it exists
        original_callback = get(dashboard.extra_properties, :original_download_callback, nothing)
        if !isnothing(original_callback)
            try
                original_callback()
            catch e
                @warn "Original download callback failed: $e"
            end
        end

        # Start training automatically
        @async begin
            sleep(1)  # Give download time to finish cleanup
            add_event!(dashboard, :info, "🤖 Auto-training initiated...")
            try
                # Use the internal training function with progress tracking
                train_models_internal(dashboard)
            catch e
                add_event!(dashboard, :error, "Auto-training failed: $(sprint(showerror, e))")
            end
        end
    end

    @info "✅ Auto-training callbacks enabled"
end

"""
Setup faster progress tracking for real-time updates.
"""
function setup_fast_progress_tracking!(dashboard::TournamentDashboard)
    # Use dashboard's extra_properties field
    # Reduce refresh rates for real-time progress
    dashboard.extra_properties[:fast_refresh_rate] = 0.1  # 100ms for ultra-responsive progress
    dashboard.extra_properties[:progress_refresh_rate] = 0.05  # 50ms during active operations

    # Enable real-time progress mode
    dashboard.extra_properties[:realtime_progress] = true

    @info "✅ Fast progress tracking enabled"
end

"""
Fixed input loop with instant commands and proper error handling.
"""
function fixed_input_loop(dashboard::TournamentDashboard)
    @info "🎮 Starting fixed input loop with instant commands..."

    while dashboard.running
        try
            key = read_key_instant()

            if !isempty(key)
                # Handle instant commands
                handled = handle_instant_command(dashboard, key)

                if !handled
                    # Check for slash commands or other special handling
                    if key == "/"
                        dashboard.command_mode = true
                        dashboard.command_buffer = "/"
                        add_event!(dashboard, :info, "Command mode: type command and press Enter")
                    elseif hasfield(typeof(dashboard), :command_mode) && dashboard.command_mode
                        if key == "\r" || key == "\n"  # Enter key
                            # Execute command
                            if !isempty(dashboard.command_buffer)
                                execute_command(dashboard, dashboard.command_buffer)
                            end
                            dashboard.command_mode = false
                            dashboard.command_buffer = ""
                        elseif key == "\b" || key == "\x7f"  # Backspace
                            if length(dashboard.command_buffer) > 1
                                dashboard.command_buffer = dashboard.command_buffer[1:end-1]
                            else
                                dashboard.command_mode = false
                                dashboard.command_buffer = ""
                            end
                        elseif isascii(key) && isprintable(key[1])
                            dashboard.command_buffer *= key
                        end
                    end
                end
            end

            # Very short sleep to prevent busy waiting but maintain responsiveness
            sleep(0.01)

        catch e
            # Don't let input errors crash the dashboard
            @debug "Input error: $e"
            sleep(0.1)
        end
    end

    @info "🎮 Input loop terminated"
end

"""
Handle instant commands without Enter key.
"""
function handle_instant_command(dashboard::TournamentDashboard, key::String)
    # Convert to lowercase for case-insensitive commands
    cmd = lowercase(key)

    if cmd == "q"
        add_event!(dashboard, :info, "👋 Shutting down dashboard...")
        dashboard.running = false
        return true

    elseif cmd == "d"
        add_event!(dashboard, :info, "📥 Starting download with progress tracking...")
        @async begin
            try
                dashboard.active_operations[:download] = true
                download_data_internal(dashboard)

                # Trigger auto-training if enabled
                if get(dashboard.extra_properties, :auto_train_enabled, false)
                    add_event!(dashboard, :info, "🔄 Auto-training triggered after download")
                    callback = get(dashboard.extra_properties, :download_completion_callback, nothing)
                    if !isnothing(callback)
                        callback()
                    end
                end
            finally
                dashboard.active_operations[:download] = false
            end
        end
        return true

    elseif cmd == "t"
        add_event!(dashboard, :info, "🤖 Starting training with progress tracking...")
        @async begin
            try
                dashboard.active_operations[:training] = true
                train_models_internal(dashboard)
            finally
                dashboard.active_operations[:training] = false
            end
        end
        return true

    elseif cmd == "s"
        add_event!(dashboard, :info, "🚀 Starting submission with progress tracking...")
        @async begin
            try
                dashboard.active_operations[:upload] = true
                # Get the most recent predictions file
                predictions_path = "predictions/$(dashboard.model[:name])_predictions.csv"
                if isfile(predictions_path)
                    submit_predictions_internal(dashboard, predictions_path)
                else
                    add_event!(dashboard, :error, "No predictions file found. Run training first.")
                end
            finally
                dashboard.active_operations[:upload] = false
            end
        end
        return true

    elseif cmd == "p"
        dashboard.paused = !dashboard.paused
        status = dashboard.paused ? "⏸ PAUSED" : "▶ RESUMED"
        add_event!(dashboard, :info, status)
        return true

    elseif cmd == "h"
        dashboard.show_help = !dashboard.show_help
        return true

    elseif cmd == "r"
        add_event!(dashboard, :info, "🔄 Refreshing dashboard data...")
        @async begin
            try
                update_model_performances!(dashboard)
                add_event!(dashboard, :success, "✅ Dashboard data refreshed")
            catch e
                add_event!(dashboard, :error, "❌ Refresh failed: $(sprint(showerror, e))")
            end
        end
        return true

    elseif cmd == "n"
        add_event!(dashboard, :info, "🆕 Model creation wizard would start here...")
        # TODO: Implement model wizard
        return true

    elseif cmd == "f"
        add_event!(dashboard, :info, "🏃‍♂️ Starting full pipeline (download → train → submit)...")
        @async begin
            run_full_pipeline(dashboard)
        end
        return true
    end

    return false  # Command not handled
end

"""
Render dashboard with sticky panels (top and bottom).
"""
function render_with_sticky_panels(dashboard::TournamentDashboard)
    # Get terminal dimensions
    terminal_height, terminal_width = displaysize(stdout)

    # Clear screen and move cursor to top
    print("\033[2J\033[H")

    # Render sticky top panel (header and system status)
    top_panel = render_top_sticky_panel(dashboard, terminal_width)
    print(top_panel)

    # Calculate available space for main content
    top_lines = count('\n', top_panel) + 1
    bottom_lines = 4  # Reserve space for bottom panel
    available_lines = terminal_height - top_lines - bottom_lines

    # Render main content area
    main_content = render_main_content_area(dashboard, terminal_width, available_lines)
    print(main_content)

    # Render sticky bottom panel (help and commands)
    bottom_panel = render_bottom_sticky_panel(dashboard, terminal_width)
    print(bottom_panel)

    # Ensure cursor positioning
    print("\033[$(terminal_height);1H")  # Move to bottom
end

"""
Render the sticky top panel with header and system status.
"""
function render_top_sticky_panel(dashboard::TournamentDashboard, width::Int)
    lines = String[]

    # Header
    header = "NUMERAI TOURNAMENT SYSTEM v0.10.0 - COMPLETE TUI FIX"
    push!(lines, EnhancedDashboard.center_text(header, width))
    push!(lines, "═" ^ width)

    # System status
    system_status = dashboard.paused ? "⏸ PAUSED" : "▶ RUNNING"
    network_icon = dashboard.network_status[:is_connected] ? "🟢" : "🔴"
    uptime = EnhancedDashboard.format_duration(dashboard.system_info[:uptime])

    status_line = @sprintf("Status: %s | Network: %s | Uptime: %s | Model: %s",
        system_status, network_icon, uptime, dashboard.model[:name])
    push!(lines, EnhancedDashboard.center_text(status_line, width))

    # Active operations status
    operations = String[]
    if dashboard.active_operations[:download]
        push!(operations, "📥 Downloading")
    end
    if dashboard.active_operations[:training]
        push!(operations, "🤖 Training")
    end
    if dashboard.active_operations[:upload]
        push!(operations, "🚀 Uploading")
    end

    if !isempty(operations)
        ops_line = "Active: " * join(operations, " | ")
        push!(lines, EnhancedDashboard.center_text(ops_line, width))
    end

    push!(lines, "─" ^ width)

    return join(lines, "\n") * "\n"
end

"""
Render the main content area with progress bars and panels.
"""
function render_main_content_area(dashboard::TournamentDashboard, width::Int, available_lines::Int)
    lines = String[]

    # Progress bars for active operations
    if any(values(dashboard.active_operations))
        push!(lines, "PROGRESS TRACKING:")
        push!(lines, "")

        if dashboard.active_operations[:download] && dashboard.progress_tracker.is_downloading
            progress = dashboard.progress_tracker.download_progress
            file = dashboard.progress_tracker.download_file
            bar = create_progress_bar_line(progress, "📥 Download", file, width - 20)
            push!(lines, bar)
        end

        if dashboard.active_operations[:training] && dashboard.progress_tracker.is_training
            progress = dashboard.training_info[:progress]
            epoch = dashboard.training_info[:current_epoch]
            total = dashboard.training_info[:total_epochs]
            info = total > 0 ? "Epoch $epoch/$total" : "Training"
            bar = create_progress_bar_line(progress, "🤖 Training", info, width - 20)
            push!(lines, bar)
        end

        if dashboard.active_operations[:upload] && dashboard.progress_tracker.is_uploading
            progress = dashboard.progress_tracker.upload_progress
            file = dashboard.progress_tracker.upload_file
            bar = create_progress_bar_line(progress, "🚀 Upload", file, width - 20)
            push!(lines, bar)
        end

        push!(lines, "")
    end

    # Model performance
    push!(lines, "MODEL PERFORMANCE:")
    model = dashboard.model
    perf_line = @sprintf("Corr: %.4f | MMC: %.4f | FNC: %.4f | TC: %.4f | Sharpe: %.4f",
        model[:corr], model[:mmc], model[:fnc], model[:tc], model[:sharpe])
    push!(lines, perf_line)
    push!(lines, "")

    # Recent events (fill remaining space)
    remaining_lines = available_lines - length(lines) - 2
    if remaining_lines > 0
        push!(lines, "RECENT EVENTS:")
        event_lines = min(remaining_lines, length(dashboard.events))
        for i in 1:event_lines
            if i <= length(dashboard.events)
                event = dashboard.events[end-i+1]  # Most recent first
                timestamp = Dates.format(event[:timestamp], "HH:MM:SS")
                icon = event[:type] == :success ? "✅" :
                       event[:type] == :error ? "❌" :
                       event[:type] == :warning ? "⚠️" : "ℹ️"
                line = "$timestamp $icon $(event[:message])"
                if length(line) > width - 2
                    line = line[1:width-5] * "..."
                end
                push!(lines, line)
            end
        end
    end

    return join(lines, "\n") * "\n"
end

"""
Render the sticky bottom panel with help and commands.
"""
function render_bottom_sticky_panel(dashboard::TournamentDashboard, width::Int)
    lines = String[]

    push!(lines, "─" ^ width)

    if dashboard.show_help
        push!(lines, "COMMANDS: [d]ownload [t]rain [s]ubmit [f]ull-pipeline [p]ause [r]efresh [h]elp [q]uit")
        push!(lines, "INSTANT: Press any key immediately (no Enter needed) | /command for advanced options")
    else
        push!(lines, "Press [h] for help | Commands execute instantly without Enter")
    end

    # Command mode indicator
    if hasfield(typeof(dashboard), :command_mode) && dashboard.command_mode
        cmd_line = "Command: $(dashboard.command_buffer)_"
        push!(lines, EnhancedDashboard.center_text(cmd_line, width))
    end

    return join(lines, "\n")
end

"""
Create a progress bar line with icon, label and file info.
"""
function create_progress_bar_line(progress::Float64, icon_label::String, info::String, bar_width::Int)
    # Clamp progress between 0 and 100
    prog = clamp(progress, 0.0, 100.0)

    # Create progress bar
    filled = Int(round(prog / 100.0 * bar_width))
    bar = "█" ^ filled * "░" ^ (bar_width - filled)

    # Format info string
    info_display = length(info) > 20 ? info[1:17] * "..." : info

    return @sprintf("%s [%s] %5.1f%% %s", icon_label, bar, prog, info_display)
end

"""
Fast render loop that updates progress in real-time.
"""
function fast_render_loop(dashboard::TournamentDashboard)
    last_render = time()

    while dashboard.running
        current_time = time()

        # Determine render interval based on activity
        is_active = any(values(dashboard.active_operations))
        render_interval = is_active ? 0.1 : 1.0  # 10 FPS during operations, 1 FPS otherwise

        if current_time - last_render >= render_interval
            try
                if get(dashboard.extra_properties, :sticky_panels, false)
                    render_with_sticky_panels(dashboard)
                else
                    # Fallback to normal render
                    render(dashboard)
                end
            catch e
                @debug "Render error: $e"
            end
            last_render = current_time
        end

        # Adaptive sleep
        sleep(is_active ? 0.02 : 0.1)
    end
end

"""
Main entry point to run the dashboard with all fixes applied.
"""
function run_fixed_dashboard(dashboard::TournamentDashboard)
    @info "🚀 Starting fixed TUI dashboard with all enhancements..."

    # Apply all fixes
    if !apply_complete_tui_fix!(dashboard)
        @error "Failed to apply TUI fixes, falling back to basic mode"
        return false
    end

    dashboard.running = true

    # Hide cursor
    print("\033[?25l")

    try
        # Start background render loop
        render_task = @async fast_render_loop(dashboard)

        # Start input loop
        fixed_input_loop(dashboard)

        # Wait for render task to complete
        wait(render_task)

    finally
        dashboard.running = false
        cleanup_raw_mode!()

        # Show cursor
        print("\033[?25h")

        # Clear screen
        print("\033[2J\033[H")

        @info "🏁 Dashboard shutdown complete"
    end

    return true
end

end  # module TUICompleteFix