module Dashboard

using Term
using Term: Panel
using Dates
using TimeZones
using ThreadsX
using Statistics
using JSON3
using HTTP
using Printf
using ..API
using ..Pipeline
using ..DataLoader
using ..Panels
using ..Panels: format_uptime

# Import the new grid layout system
include("grid.jl")
using .GridLayout
using ..Logger: @log_info, @log_warn, @log_error
using ..Utils  # Import Utils for use in dashboard
using ..EnhancedDashboard  # Use the module already loaded by NumeraiTournament.jl
# TUIFixes will be loaded after this module

# Import UTC utility function (already part of parent module)
# Import callbacks (already part of parent module)
using ..Models.Callbacks: CallbackInfo, CallbackResult, DashboardCallback, CONTINUE

# Define the UTC time function locally
using TimeZones
function utc_now()
    return now(tz"UTC")
end
function utc_now_datetime()
    return DateTime(utc_now())
end

# Error categorization types
@enum ErrorCategory begin
    API_ERROR
    NETWORK_ERROR
    AUTH_ERROR
    DATA_ERROR
    SYSTEM_ERROR
    TIMEOUT_ERROR
    VALIDATION_ERROR
end

@enum ErrorSeverity begin
    LOW
    MEDIUM
    HIGH
    CRITICAL
end

struct CategorizedError
    category::ErrorCategory
    severity::ErrorSeverity
    message::String
    technical_details::String
    timestamp::DateTime
    retry_count::Int
end

mutable struct ModelWizardState
    step::Int  # Current wizard step (1-6)
    total_steps::Int  # Total number of steps
    # Step 1: Model name
    model_name::String
    # Step 2: Model type
    model_type::String
    model_type_options::Vector{String}
    selected_type_index::Int
    # Step 3: Basic parameters
    learning_rate::Float64
    max_depth::Int
    feature_fraction::Float64
    num_rounds::Int
    epochs::Int
    # Step 4: Feature settings
    neutralize::Bool
    neutralize_proportion::Float64
    feature_set::String
    feature_set_options::Vector{String}
    selected_feature_index::Int
    # Step 5: Training settings
    validation_split::Float64
    early_stopping::Bool
    gpu_enabled::Bool
    # Step 6: Confirmation
    confirmed::Bool
    # Navigation helpers
    current_field::Int  # For parameter editing
    max_fields::Int     # Max fields in current step
end

mutable struct TournamentDashboard
    config::Any
    api_client::API.NumeraiClient
    model::Dict{Symbol, Any}  # Single model instead of vector
    models::Vector{Dict{Symbol, Any}}  # Support for multiple models (for compatibility)
    events::Vector{Dict{Symbol, Any}}
    system_info::Dict{Symbol, Any}
    training_info::Dict{Symbol, Any}
    predictions_history::Vector{Float64}
    performance_history::Vector{Dict{Symbol, Any}}  # Historical performance tracking for single model
    running::Bool
    paused::Bool
    show_help::Bool
    refresh_rate::Float64  # Changed to Float64 for more precise timing
    command_buffer::String  # For slash commands
    command_mode::Bool  # Track if we're in command mode
    show_model_details::Bool  # Track if model details panel should be shown
    # Model wizard and selection
    selected_model_details::Union{Nothing, Dict{Symbol, Any}}  # Details of selected model
    selected_model_stats::Union{Nothing, Dict{Symbol, Any}}  # Stats of selected model
    wizard_state::Union{Nothing, Any}  # Model wizard state
    wizard_active::Bool  # Whether wizard is active
    # Error tracking and network status
    error_counts::Dict{ErrorCategory, Int}  # Track error counts by category
    network_status::Dict{Symbol, Any}  # Network connectivity status
    last_api_errors::Vector{CategorizedError}  # Recent API errors for debugging
    # Progress tracking for operations
    progress_tracker::EnhancedDashboard.ProgressTracker
    # Real-time tracking and active operations
    realtime_tracker::Any  # Will be initialized as RealTimeTracker
    active_operations::Dict{Symbol, Bool}  # Track active operations
end

function TournamentDashboard(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key, config.tournament_id)
    
    # Use single model - get first model or default
    model_name = isempty(config.models) ? "default_model" : config.models[1]
    
    model = Dict(:name => model_name, :is_active => false, :corr => 0.0, 
                 :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0, :tc => 0.0)
    
    system_info = Dict(
        :cpu_usage => 0,
        :memory_used => 0.0,
        :memory_total => round(Sys.total_memory() / (1024^3), digits=1),  # Get actual system memory in GB
        :model_active => false,
        :threads => Threads.nthreads(),
        :uptime => 0,
        :julia_version => string(VERSION),
        :load_avg => Sys.loadavg(),
        :process_memory => 0.0
    )
    
    training_info = Dict(
        :is_training => false,
        :model_name => model_name,
        :progress => 0,
        :current_epoch => 0,
        :total_epochs => 0,
        :loss => 0.0,
        :val_score => 0.0,
        :eta => "N/A"
    )
    
    # Initialize performance history for single model
    performance_history = Vector{Dict{Symbol, Any}}()
    
    # Initialize error tracking
    error_counts = Dict{ErrorCategory, Int}(
        API_ERROR => 0,
        NETWORK_ERROR => 0,
        AUTH_ERROR => 0,
        DATA_ERROR => 0,
        SYSTEM_ERROR => 0,
        TIMEOUT_ERROR => 0,
        VALIDATION_ERROR => 0
    )
    
    # Initialize network status
    network_status = Dict{Symbol, Any}(
        :is_connected => true,
        :last_check => utc_now_datetime(),
        :api_latency => 0.0,
        :consecutive_failures => 0
    )
    
    # Get refresh rate from config
    refresh_rate = get(config.tui_config, "refresh_rate", 1.0)
    
    # Initialize models vector with single model
    models = [model]

    # Initialize active operations
    active_operations = Dict{Symbol, Bool}(
        :download => false,
        :upload => false,
        :training => false,
        :prediction => false
    )

    return TournamentDashboard(
        config, api_client, model, models,  # model and models
        Vector{Dict{Symbol, Any}}(),  # events
        system_info, training_info, Float64[], performance_history,
        false, false, false, refresh_rate,  # running, paused, show_help, refresh_rate
        "", false,  # command_buffer and command_mode
        false,  # show_model_details
        nothing, nothing, nothing, false,  # selected_model_details, selected_model_stats, wizard_state, wizard_active
        error_counts, network_status, Vector{CategorizedError}(),  # error tracking fields
        EnhancedDashboard.ProgressTracker(),  # Initialize progress tracker
        nothing,  # realtime_tracker - will be initialized by integration
        active_operations  # active operations tracking
    )
end

"""
Create a dashboard callback that updates training info in real-time
"""
function create_dashboard_training_callback(dashboard::TournamentDashboard)
    update_fn = function(info::CallbackInfo)
        # Update training info in dashboard
        dashboard.training_info[:is_training] = true
        dashboard.training_info[:model_name] = info.model_name
        dashboard.training_info[:current_epoch] = info.epoch
        dashboard.training_info[:total_epochs] = info.total_epochs
        dashboard.training_info[:progress] = info.total_epochs > 0 ?
            round(Int, (info.epoch / info.total_epochs) * 100) :
            (info.total_iterations !== nothing && info.total_iterations > 0 ?
             round(Int, (info.iteration / info.total_iterations) * 100) : 0)

        # Update progress tracker
        dashboard.progress_tracker.is_training = true
        dashboard.progress_tracker.training_model = info.model_name
        dashboard.progress_tracker.training_epoch = info.epoch
        dashboard.progress_tracker.training_total_epochs = info.total_epochs
        dashboard.progress_tracker.training_progress = dashboard.training_info[:progress]
        
        # Update metrics if available
        if info.loss !== nothing
            dashboard.training_info[:loss] = info.loss
        end
        if info.val_score !== nothing
            dashboard.training_info[:val_score] = info.val_score
        end
        if info.eta !== nothing
            eta_str = if info.eta < 60
                "$(round(Int, info.eta))s"
            elseif info.eta < 3600
                "$(round(info.eta/60, digits=1))m"
            else
                "$(round(info.eta/3600, digits=1))h"
            end
            dashboard.training_info[:eta] = eta_str
        end
        
        # Add event for significant progress milestones
        if info.epoch > 0 && info.epoch % max(1, info.total_epochs ÷ 5) == 0
            add_event!(dashboard, :info, 
                "Training $(info.model_name): $(info.epoch)/$(info.total_epochs) epochs ($(dashboard.training_info[:progress])%)")
        end
        
        return CONTINUE
    end
    
    return create_dashboard_callback(update_fn, frequency=1, name="training_progress")
end

# Include dashboard commands after TournamentDashboard is defined
include("dashboard_commands.jl")

"""
Mark training as completed in dashboard
"""
function complete_training!(dashboard::TournamentDashboard, model_name::String)
    dashboard.training_info[:is_training] = false
    dashboard.training_info[:progress] = 100
    dashboard.training_info[:eta] = "Completed"
    add_event!(dashboard, :success, "Training completed for $(model_name)")
end

function run_dashboard(dashboard::TournamentDashboard)
    dashboard.running = true
    start_time = time()
    
    # Clear screen using ANSI escape sequence
    print("\033[2J\033[H")
    # Hide cursor using ANSI escape sequence  
    print("\033[?25l")
    
    try
        add_event!(dashboard, :info, "Dashboard started")

        # Apply unified TUI fix for all features
        NumeraiTournament.UnifiedTUIFix.apply_unified_tui_fix!(dashboard)

        # Check if auto_submit is enabled and start automatic pipeline
        if dashboard.config.auto_submit
            add_event!(dashboard, :info, "Auto-submit enabled, starting automatic pipeline...")
            # Start the full tournament pipeline automatically
            @async begin
                sleep(2)  # Give dashboard time to initialize
                add_event!(dashboard, :info, "Starting full tournament pipeline...")
                # Run the complete pipeline: download → train → predict → submit
                run_full_pipeline(dashboard)
            end
        else
            add_event!(dashboard, :info, "Manual mode - press 's' to start training")
        end
        
        # Initial render to show something immediately
        try
            render(dashboard)
        catch e
            println("\n⚠️ Error during initial render: ", e)
            println("\nStack trace:")
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
                println()
            end
            println("\nPress Ctrl+C to exit...")
        end
        
        @async update_loop(dashboard, start_time)
        
        input_loop(dashboard)
        
    finally
        dashboard.running = false
        # Show cursor using ANSI escape sequence
        print("\033[?25h")
        # Clear screen using ANSI escape sequence
        print("\033[2J\033[H")
    end
end

function update_loop(dashboard::TournamentDashboard, start_time::Float64)
    last_model_update = time()
    last_render = time()
    last_network_check = time()
    frame_counter = 0

    # Get intervals from configuration
    model_update_interval = get(dashboard.config.tui_config, "model_update_interval", 30.0)
    network_check_interval = get(dashboard.config.tui_config, "network_check_interval", 60.0)
    render_interval = dashboard.refresh_rate  # Render at user-specified rate (default 1.0s)

    # Use faster render interval when progress operations are active for real-time updates
    fast_render_interval = 0.2  # 200ms for progress updates

    while dashboard.running
        current_time = time()
        frame_counter += 1

        if !dashboard.paused
            # Always update uptime for real-time display
            dashboard.system_info[:uptime] = Int(current_time - start_time)

            # Update system info every frame for real-time monitoring
            if frame_counter % 5 == 0  # Update every 0.5 seconds
                update_system_info!(dashboard)
            end

            # Periodic network connectivity check
            if current_time - last_network_check >= network_check_interval
                was_connected = dashboard.network_status[:is_connected]
                is_connected = check_network_connectivity(dashboard)

                # Log connectivity state changes
                if was_connected && !is_connected
                    add_event!(dashboard, :error, "Network connection lost",
                              Base.IOError("Network connectivity check failed"))
                elseif !was_connected && is_connected
                    add_event!(dashboard, :success, "Network connection restored")
                end

                last_network_check = current_time
            end

            # Update model performances less frequently to avoid API rate limits
            # Only attempt if network is connected
            if current_time - last_model_update >= model_update_interval
                if dashboard.network_status[:is_connected]
                    @async begin  # Run model update async to not block rendering
                        try
                            update_model_performances!(dashboard)
                        catch e
                            add_event!(dashboard, :error, "Failed to update model: $(sprint(showerror, e))")
                        end
                    end
                else
                    add_event!(dashboard, :warning, "Skipping model update - no network connection")
                end
                last_model_update = current_time
            end
        end

        # Always render at consistent intervals, even when paused (to show status changes)
        # Use faster rendering when progress operations are active
        is_progress_active = dashboard.progress_tracker.is_downloading ||
                           dashboard.progress_tracker.is_uploading ||
                           dashboard.progress_tracker.is_training ||
                           dashboard.progress_tracker.is_predicting

        current_render_interval = is_progress_active ? fast_render_interval : render_interval

        if current_time - last_render >= current_render_interval
            try
                render(dashboard)
            catch e
                # Log render errors but don't crash
                @debug "Render error: $(sprint(showerror, e))"
            end
            last_render = current_time
        end

        # Adaptive sleep to prevent busy waiting - shorter during active progress
        sleep_duration = is_progress_active ? 0.05 : 0.1
        sleep(sleep_duration)
    end
end

function read_key()
    # Robust key reading with proper error handling and recovery
    local key_pressed = ""
    local raw_mode_set = false

    try
        # Only set raw mode if stdin is a TTY
        if isa(stdin, Base.TTY)
            # Set stdin to raw mode to capture individual key presses
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)
            raw_mode_set = true

            # Read with minimal timeout for instant response
            if bytesavailable(stdin) > 0
                first_char = String(read(stdin, 1))

                # Handle escape sequences for special keys
                if first_char == "\e"  # ESC character
                    # Give a very small timeout for multi-character sequences
                    if bytesavailable(stdin) > 0
                        second_char = String(read(stdin, 1))
                        if second_char == "["
                            if bytesavailable(stdin) > 0
                                third_char = String(read(stdin, 1))
                                key_pressed = "\e[$third_char"  # Return full escape sequence
                            else
                                key_pressed = "\e["  # Partial escape sequence
                            end
                        else
                            key_pressed = first_char  # Just ESC key
                        end
                    else
                        key_pressed = first_char  # Just ESC key
                    end
                else
                    key_pressed = first_char
                end
            end
        else
            # Non-TTY mode (e.g., when running in CI or non-interactive)
            if bytesavailable(stdin) > 0
                key_pressed = String(read(stdin, 1))
            end
        end
    catch e
        # Log error but don't crash
        @debug "Error reading key: $e"
        key_pressed = ""
    finally
        # Always restore normal stdin mode if we set raw mode
        if raw_mode_set && isa(stdin, Base.TTY)
            try
                ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)
            catch
                # Even if restoration fails, continue
            end
        end
    end

    return key_pressed
end

function input_loop(dashboard::TournamentDashboard)
    # Check if unified fix has been applied
    if haskey(dashboard.active_operations, :unified_fix) && dashboard.active_operations[:unified_fix]
        # Use the unified input loop with instant commands
        NumeraiTournament.UnifiedTUIFix.unified_input_loop(dashboard)
    else
        # Fallback to basic input loop
        basic_input_loop(dashboard)
    end
end

function basic_input_loop(dashboard::TournamentDashboard)
    while dashboard.running
        key = read_key()

        if isempty(key)
            sleep(0.01)
            continue
        end

        # Handle basic commands
        if key == "q" || key == "Q"
            dashboard.running = false
        end

        sleep(0.01)
    end
end

function render(dashboard::TournamentDashboard)
    try
        # Create and display panels using the sticky panel system
        if dashboard.wizard_active
            # Show model creation wizard - full screen clear for this special case
            print("\033[2J\033[H")
            wizard_display = render_wizard(dashboard)
            println(wizard_display)
            status_line = create_status_line(dashboard)
            println("\n" * status_line)
        elseif dashboard.show_model_details
            # Show model details interface - full screen clear for this special case
            print("\033[2J\033[H")
            panel1 = render_model_details_panel(dashboard)
            panel2 = Panels.create_events_panel(dashboard.events, dashboard.config)
            println(panel1)
            println(panel2)
        else
            # Use sticky panel system for main dashboard
            render_sticky_dashboard(dashboard)
        end
    catch e
        # Enhanced recovery mode with comprehensive diagnostics
        render_recovery_mode(dashboard, e)
    end
end

function render_sticky_dashboard(dashboard::TournamentDashboard)
    """
    Render dashboard with sticky panels using ANSI positioning
    - Top panel: System status and progress (sticky)
    - Middle panel: Dynamic content area
    - Bottom panel: Event logs (sticky)
    """

    # If realtime tracker is available and active, use it for rendering
    if isdefined(dashboard, :realtime_tracker) && !isnothing(dashboard.realtime_tracker)
        TUIRealtime.render_realtime_dashboard!(dashboard.realtime_tracker, dashboard)
        return
    end

    # Get terminal dimensions
    terminal_height, terminal_width = try
        displaysize(stdout)
    catch
        (40, 120)  # Default dimensions
    end

    # Calculate panel heights
    top_panel_height = 10  # System info and progress (increased for better visibility)
    bottom_panel_height = 12  # Event logs - show more events
    middle_panel_height = max(5, terminal_height - top_panel_height - bottom_panel_height - 2)  # Dynamic content

    # Only clear screen on first render or if dimensions changed
    if !haskey(dashboard.system_info, :last_terminal_size) ||
       dashboard.system_info[:last_terminal_size] != (terminal_height, terminal_width)
        print("\033[2J\033[H")
        dashboard.system_info[:last_terminal_size] = (terminal_height, terminal_width)
    end

    # Save cursor position and clear only the regions we're updating
    print("\033[s")  # Save cursor position

    # Render top sticky panel (system status and active operations)
    print("\033[1;1H")  # Move cursor to top-left
    print("\033[K")  # Clear line before rendering
    render_top_sticky_panel(dashboard, terminal_width)

    # Render middle content area
    print("\033[$(top_panel_height + 1);1H")  # Position below top panel
    render_middle_content(dashboard, middle_panel_height, terminal_width)

    # Render bottom sticky panel (event logs)
    bottom_row = terminal_height - bottom_panel_height + 1
    print("\033[$(bottom_row);1H")  # Position at bottom
    print("\033[K")  # Clear line before rendering
    render_bottom_sticky_panel(dashboard, bottom_panel_height, terminal_width)

    # Restore cursor position
    print("\033[u")  # Restore cursor position
    print("\033[?25l")  # Hide cursor for cleaner display
end

function render_top_sticky_panel(dashboard::TournamentDashboard, terminal_width::Int)
    """
    Render the top sticky panel with system status and progress
    """
    lines = String[]

    # Header line
    header = "NUMERAI TOURNAMENT SYSTEM v0.10.0"
    push!(lines, EnhancedDashboard.center_text(header, terminal_width))
    push!(lines, "─" ^ terminal_width)

    # Real-time system status line with live CPU and memory updates
    system_status = dashboard.paused ? "⏸ PAUSED" : "▶ RUNNING"
    network_icon = dashboard.network_status[:is_connected] ? "●" : "○"
    network_text = dashboard.network_status[:is_connected] ? "Online" : "Offline"
    latency = dashboard.network_status[:api_latency] > 0 ?
        @sprintf(" %dms", round(dashboard.network_status[:api_latency])) : ""
    uptime = EnhancedDashboard.format_duration(dashboard.system_info[:uptime])

    # Get real-time system metrics
    cpu_usage = dashboard.system_info[:cpu_usage]
    mem_used = dashboard.system_info[:memory_used]
    mem_total = dashboard.system_info[:memory_total]
    threads = dashboard.system_info[:threads]
    load_avg = dashboard.system_info[:load_avg]

    # Format load average
    load_str = @sprintf("%.2f %.2f %.2f", load_avg[1], load_avg[2], load_avg[3])

    status_line = @sprintf("System: %s | CPU: %d%% | Memory: %.1f/%.1f GB | Load: %s | Threads: %d | Uptime: %s",
        system_status, cpu_usage, mem_used, mem_total, load_str, threads, uptime)
    push!(lines, status_line)

    # Network status on separate line
    net_line = @sprintf("Network: %s %s%s | Model: %s | Tournament: %s",
        network_icon, network_text, latency,
        dashboard.model[:name],
        dashboard.config.tournament_id == 8 ? "Classic" : "Signals")
    push!(lines, net_line)

    # Progress bars for active operations
    if dashboard.progress_tracker.is_downloading || dashboard.progress_tracker.is_uploading ||
       dashboard.progress_tracker.is_training || dashboard.progress_tracker.is_predicting

        push!(lines, "")
        push!(lines, "Active Operations:")

        if dashboard.progress_tracker.is_downloading
            spinner = EnhancedDashboard.create_spinner(Int(time() * 10))
            progress_bar = EnhancedDashboard.create_progress_bar(dashboard.progress_tracker.download_progress, 100, width=40)
            file_display = length(dashboard.progress_tracker.download_file) > 30 ?
                dashboard.progress_tracker.download_file[1:27] * "..." : dashboard.progress_tracker.download_file
            push!(lines, @sprintf("%s Download: %-30s %s", spinner, file_display, progress_bar))
        end

        if dashboard.progress_tracker.is_uploading
            spinner = EnhancedDashboard.create_spinner(Int(time() * 10))
            progress_bar = EnhancedDashboard.create_progress_bar(dashboard.progress_tracker.upload_progress, 100, width=40)
            file_display = length(dashboard.progress_tracker.upload_file) > 30 ?
                dashboard.progress_tracker.upload_file[1:27] * "..." : dashboard.progress_tracker.upload_file
            push!(lines, @sprintf("%s Upload: %-30s %s", spinner, file_display, progress_bar))
        end

        if dashboard.progress_tracker.is_training
            spinner = EnhancedDashboard.create_spinner(Int(time() * 10))
            epoch_info = @sprintf("Epoch %d/%d", dashboard.progress_tracker.training_epoch, dashboard.progress_tracker.training_total_epochs)
            model_display = length(dashboard.progress_tracker.training_model) > 20 ?
                dashboard.progress_tracker.training_model[1:17] * "..." : dashboard.progress_tracker.training_model
            progress_bar = EnhancedDashboard.create_progress_bar(dashboard.progress_tracker.training_progress, 100, width=40)
            push!(lines, @sprintf("%s Training: %-20s %s %s", spinner, model_display, epoch_info, progress_bar))
        end

        if dashboard.progress_tracker.is_predicting
            spinner = EnhancedDashboard.create_spinner(Int(time() * 10))
            model_display = length(dashboard.progress_tracker.prediction_model) > 30 ?
                dashboard.progress_tracker.prediction_model[1:27] * "..." : dashboard.progress_tracker.prediction_model
            progress_bar = EnhancedDashboard.create_progress_bar(dashboard.progress_tracker.prediction_progress, 100, width=40)
            push!(lines, @sprintf("%s Predicting: %-28s %s", spinner, model_display, progress_bar))
        end
    end

    # Pad to ensure consistent height (now 10 lines)
    while length(lines) < 10
        push!(lines, "")
    end

    # Print the lines
    for line in lines
        println(line)
    end
end

function render_middle_content(dashboard::TournamentDashboard, height::Int, width::Int)
    """
    Render the middle content area with model performance and other dynamic content
    """
    # Clear this section
    for i in 1:height
        print(" " ^ width * "\n")
    end

    # Move back to start of middle section
    print("\033[$(height)A")

    # Render main dashboard content using enhanced dashboard
    enhanced_content = EnhancedDashboard.render_enhanced_dashboard(dashboard, dashboard.progress_tracker)

    # Split content into lines and limit to available height
    content_lines = split(enhanced_content, '\n')
    displayed_lines = content_lines[1:min(length(content_lines), height - 2)]

    for line in displayed_lines
        println(line)
    end
end

function render_bottom_sticky_panel(dashboard::TournamentDashboard, height::Int, width::Int)
    """
    Render the bottom sticky panel with event logs - showing the latest 30 events
    """
    # Separator line
    println("─" ^ width)

    # Event logs header with better command hints
    if dashboard.command_mode
        command_hint = "Command Mode: /$(dashboard.command_buffer)_ (Enter to execute, ESC to cancel)"
    else
        command_hint = "Keys: [q]uit [s]tart [d]ownload [r]efresh [n]ew [h]elp [/]command"
    end

    # Show event count
    total_events = length(dashboard.events)
    events_to_show = min(30, height - 2, total_events)  # Show up to 30 latest events
    println(@sprintf("Events (showing %d of %d) | %s", events_to_show, total_events, command_hint))
    println("─" ^ width)  # Another separator for clarity

    # Get recent events (up to 30)
    recent_events = if total_events > events_to_show
        dashboard.events[end-(events_to_show-1):end]
    else
        dashboard.events
    end

    # Render event lines with better formatting
    for (idx, event) in enumerate(recent_events)
        timestamp_str = Dates.format(get(event, :timestamp, now()), "HH:MM:SS")

        # Choose icon based on event level
        level = get(event, :level, get(event, :type, :info))
        icon = if level == :error
            "❌"  # Red X
        elseif level == :warning
            "⚠️"   # Warning triangle
        elseif level == :success
            "✅"  # Green checkmark
        elseif level == :info
            "ℹ️"   # Info symbol
        else
            "•"  # Bullet point for other
        end

        # Color code based on level (using ANSI colors)
        color_start = if level == :error
            "\033[31m"  # Red
        elseif level == :warning
            "\033[33m"  # Yellow
        elseif level == :success
            "\033[32m"  # Green
        else
            "\033[36m"  # Cyan for info
        end
        color_end = "\033[0m"  # Reset

        # Truncate message if too long
        max_msg_length = width - 15  # Account for timestamp and icon
        event_msg = get(event, :message, "")
        message = if length(event_msg) > max_msg_length
            event_msg[1:max_msg_length-3] * "..."
        else
            event_msg
        end

        # Format and print the event line with color
        event_line = @sprintf("%s[%s] %s %s%s%s",
            color_start, timestamp_str, icon, message, color_end, "")
        println(event_line)
    end

    # Fill remaining space if needed
    lines_printed = events_to_show + 3  # Header + separator + events
    while lines_printed < height
        println("")  # Empty line
        lines_printed += 1
    end

    # Pad remaining lines
    remaining_lines = (height - 2) - length(recent_events)
    for i in 1:remaining_lines
        println()
    end
end

function render_grid_dashboard(dashboard::TournamentDashboard)
    """
    Render a single comprehensive panel with all dashboard information
    """
    render_unified_dashboard(dashboard)
end

function render_unified_dashboard(dashboard::TournamentDashboard)
    """
    Render a single unified panel with all essential information in a clean, organized format
    """

    # Get terminal dimensions
    terminal_width = try
        displaysize(stdout)[2]
    catch
        120  # Default width
    end

    # Build content sections
    content_lines = String[]

    # Header section with box drawing
    header_text = "🚀 NUMERAI TOURNAMENT SYSTEM"
    header_len = 28  # Approximate length of header text with emoji
    padding = max(0, (terminal_width - header_len - 2) ÷ 2)
    header_line = "║" * " "^padding * header_text * " "^(terminal_width - padding - header_len - 2) * "║"

    push!(content_lines, "╔" * "═"^(terminal_width-2) * "╗")
    push!(content_lines, header_line)
    push!(content_lines, "╚" * "═"^(terminal_width-2) * "╝")
    push!(content_lines, "")

    # System & Network Status (single line)
    system_status = dashboard.paused ? "⏸ PAUSED" : "▶ RUNNING"
    network_icon = dashboard.network_status[:is_connected] ? "🟢" : "🔴"
    network_text = dashboard.network_status[:is_connected] ? "Connected" : "Disconnected"
    latency = dashboard.network_status[:api_latency] > 0 ? " ($(round(dashboard.network_status[:api_latency], digits=0))ms)" : ""

    push!(content_lines, "System: $system_status │ Network: $network_icon $network_text$latency │ Uptime: $(format_uptime(dashboard.system_info[:uptime]))")
    push!(content_lines, "─"^terminal_width)

    # Model Performance & Tournament Info
    push!(content_lines, "")
    push!(content_lines, "📊 MODEL PERFORMANCE")
    model_status = dashboard.model[:is_active] ? "🟢 Active" : "🔴 Inactive"

    # Try to get staking info
    round_info = ""
    submission_info = ""
    try
        stake_info = get_staking_info(dashboard)
        round_info = " │ Round: #$(stake_info[:current_round])"
        submission_info = " │ $(stake_info[:submission_status])"
    catch
        # Keep defaults
    end

    push!(content_lines, "Model: $(dashboard.model[:name]) ($model_status)$round_info$submission_info")

    # Performance metrics in a compact format
    corr = round(dashboard.model[:corr], digits=4)
    mmc = round(dashboard.model[:mmc], digits=4)
    fnc = round(dashboard.model[:fnc], digits=4)
    corr_sign = corr > 0 ? "↑" : "↓"
    mmc_sign = mmc > 0 ? "↑" : "↓"
    fnc_sign = fnc > 0 ? "↑" : "↓"

    push!(content_lines, "Metrics: CORR: $corr_sign$corr │ MMC: $mmc_sign$mmc │ FNC: $fnc_sign$fnc")

    if haskey(dashboard.model, :stake) && dashboard.model[:stake] > 0
        push!(content_lines, "Stake: 💰 $(dashboard.model[:stake]) NMR")
    end
    push!(content_lines, "─"^terminal_width)

    # Training Status
    if dashboard.training_info[:is_training]
        push!(content_lines, "")
        push!(content_lines, "🔥 TRAINING IN PROGRESS")
        progress = dashboard.training_info[:progress]
        progress_bar = create_simple_progress_bar(progress, 100, width=40)
        push!(content_lines, "Model: $(dashboard.training_info[:model_name]) │ Epoch: $(dashboard.training_info[:current_epoch])/$(dashboard.training_info[:total_epochs])")
        push!(content_lines, "Progress: $progress_bar $(progress)% │ ETA: $(dashboard.training_info[:eta])")

        if dashboard.training_info[:val_score] > 0
            val_score = round(dashboard.training_info[:val_score], digits=4)
            push!(content_lines, "Validation Score: $val_score")
        end
        push!(content_lines, "─"^terminal_width)
    end

    # System Resources (compact)
    push!(content_lines, "")
    push!(content_lines, "⚙️  SYSTEM RESOURCES")
    cpu_usage = dashboard.system_info[:cpu_usage]
    mem_used = round(dashboard.system_info[:memory_used], digits=1)
    mem_total = dashboard.system_info[:memory_total]
    mem_pct = round(100 * mem_used / mem_total, digits=0)
    cpu_bar = create_simple_progress_bar(cpu_usage, 100, width=20)
    mem_bar = create_simple_progress_bar(mem_pct, 100, width=20)

    push!(content_lines, "CPU:    $cpu_bar $(cpu_usage)%")
    push!(content_lines, "Memory: $mem_bar $mem_used/$mem_total GB ($(Int(mem_pct))%)")
    push!(content_lines, "Threads: $(dashboard.system_info[:threads]) │ Julia $(dashboard.system_info[:julia_version])")
    push!(content_lines, "─"^terminal_width)

    # Recent Events (last 8)
    push!(content_lines, "")
    push!(content_lines, "📋 RECENT EVENTS")
    if isempty(dashboard.events)
        push!(content_lines, "  No recent events")
    else
        max_events = min(8, length(dashboard.events))
        recent_events = dashboard.events[max(1, end-max_events+1):end]
        for event in reverse(recent_events)
            timestamp = Dates.format(event[:time], "HH:MM:SS")
            icon = get_event_icon(event[:type])
            message = truncate_message(event[:message], terminal_width - 20)
            push!(content_lines, "  [$timestamp] $icon $message")
        end
    end
    push!(content_lines, "─"^terminal_width)

    # Command help at bottom
    push!(content_lines, "")
    if dashboard.command_mode
        push!(content_lines, "💬 Command: /$(dashboard.command_buffer)_")
    else
        push!(content_lines, "📌 Commands: [n] New Model │ [/] Command Mode │ [h] Help │ [r] Refresh │ [s] Start Training │ [q] Quit")
    end

    # Print all lines
    for line in content_lines
        println(line)
    end
end

function render_simple_dashboard(dashboard::TournamentDashboard)
    """
    Render a simplified dashboard with essential information in a clean list format
    """
    # Header
    println("╔══════════════════════════════════════════════════════════════════════════════╗")
    println("║                        🚀 Numerai Tournament Dashboard                        ║")
    println("╚══════════════════════════════════════════════════════════════════════════════╝")
    println()
    
    # System Status
    system_status = dashboard.paused ? "PAUSED" : "RUNNING"
    system_color = dashboard.paused ? "🟡" : "🟢"
    println("📊 SYSTEM STATUS")
    println("   Status: $system_color $system_status")
    
    # Network Status
    network_icon = dashboard.network_status[:is_connected] ? "🟢" : "🔴"
    network_status_text = dashboard.network_status[:is_connected] ? "Connected" : "Disconnected"
    latency_info = dashboard.network_status[:is_connected] && dashboard.network_status[:api_latency] > 0 ? 
        " ($(round(dashboard.network_status[:api_latency], digits=0))ms)" : ""
    println("   Network: $network_icon $network_status_text$latency_info")
    
    # API Connection
    api_failures = dashboard.network_status[:consecutive_failures]
    if api_failures > 0
        println("   API Status: ⚠️ $(api_failures) consecutive failures")
    else
        println("   API Status: ✅ Connected")
    end
    println()
    
    # Current Round Information
    println("🏆 TOURNAMENT INFO")
    try
        stake_info = get_staking_info(dashboard)
        println("   Current Round: #$(stake_info[:current_round])")
        println("   Submission: $(stake_info[:submission_status])")
        println("   Time Remaining: $(stake_info[:time_remaining])")
    catch e
        println("   Current Round: ❌ Failed to fetch round info")
        println("   Submission: Unknown")
        println("   Time Remaining: Unknown")
    end
    println()
    
    # Model Performance
    println("📈 MODEL PERFORMANCE")
    model_status = dashboard.model[:is_active] ? "🟢 Active" : "🔴 Inactive"
    println("   Model: $(dashboard.model[:name]) ($model_status)")
    println("   CORR: $(round(dashboard.model[:corr], digits=4))")
    println("   MMC: $(round(dashboard.model[:mmc], digits=4))")
    println("   FNC: $(round(dashboard.model[:fnc], digits=4))")
    if haskey(dashboard.model, :stake) && dashboard.model[:stake] > 0
        println("   Stake: $(dashboard.model[:stake]) NMR")
    end
    println()
    
    # Training Status
    println("🚀 TRAINING STATUS")
    if dashboard.training_info[:is_training]
        progress = dashboard.training_info[:progress]
        progress_bar = create_simple_progress_bar(progress, 100, width=30)
        println("   Status: 🔥 Training in progress")
        println("   Model: $(dashboard.training_info[:model_name])")
        println("   Progress: $progress_bar $(progress)%")
        println("   Epoch: $(dashboard.training_info[:current_epoch])/$(dashboard.training_info[:total_epochs])")
        println("   ETA: $(dashboard.training_info[:eta])")
        if dashboard.training_info[:val_score] > 0
            println("   Validation Score: $(round(dashboard.training_info[:val_score], digits=4))")
        end
    else
        println("   Status: ⏸️ No training in progress")
    end
    println()
    
    # System Resources
    println("⚙️ SYSTEM RESOURCES")
    cpu_bar = create_simple_progress_bar(dashboard.system_info[:cpu_usage], 100, width=20)
    println("   CPU: $cpu_bar $(dashboard.system_info[:cpu_usage])%")
    memory_bar = create_simple_progress_bar(dashboard.system_info[:memory_used], dashboard.system_info[:memory_total], width=20)
    println("   Memory: $memory_bar $(round(dashboard.system_info[:memory_used], digits=1))/$(dashboard.system_info[:memory_total]) GB")
    println("   Threads: $(dashboard.system_info[:threads])")
    println("   Uptime: $(format_uptime(dashboard.system_info[:uptime]))")
    println()
    
    # Recent Events (last 5)
    println("📋 RECENT EVENTS")
    if isempty(dashboard.events)
        println("   No recent events")
    else
        recent_events = dashboard.events[max(1, end-4):end]
        for event in reverse(recent_events)
            timestamp = Dates.format(event[:time], "HH:MM:SS")
            icon = get_event_icon(event[:type])
            message = truncate_message(event[:message], 60)
            println("   [$timestamp] $icon $message")
        end
    end
    println()
    
    # Error Summary (if any)
    error_count = count(e -> e[:type] == :error, dashboard.events)
    warning_count = count(e -> e[:type] == :warning, dashboard.events)
    if error_count > 0 || warning_count > 0
        println("⚠️ ISSUES SUMMARY")
        if error_count > 0
            println("   Errors: ❌ $error_count")
        end
        if warning_count > 0
            println("   Warnings: ⚠️ $warning_count")
        end
        println()
    end
    
    # Help information if requested
    if dashboard.show_help
        println("❓ KEYBOARD SHORTCUTS (instant - no Enter required)")
        println("   q - Quit dashboard")
        println("   p - Pause/Resume updates")
        println("   s - Start training pipeline")
        println("   r - Refresh model performances")
        println("   n - Create new model (wizard)")
        println("   d - Download tournament data")
        println("   u - Upload/submit predictions")
        println("   h - Toggle this help")
        println("   ESC - Cancel current operation")
        println("   / - Command mode (requires Enter)")
        println()
        println("📝 SLASH COMMANDS (type command + Enter)")
        println("   /train    - Start training")
        println("   /submit   - Submit predictions")
        println("   /download - Download data")
        println("   /stake    - Set stake amount")
        println("   /refresh  - Refresh all data")
        println("   /diag     - Run diagnostics")
        println("   /help     - Show help")
        println()
    end
end

function create_simple_progress_bar(current::Number, total::Number; width::Int=20)::String
    """
    Create a simple text-based progress bar
    """
    if total == 0
        return "─" ^ width
    end
    
    percentage = current / total
    filled = Int(round(percentage * width))
    
    bar = "█" ^ filled * "░" ^ (width - filled)
    return bar
end

function get_event_icon(event_type::Symbol)::String
    """
    Get icon for event type
    """
    if event_type == :error
        return "❌"
    elseif event_type == :warning
        return "⚠️"
    elseif event_type == :success
        return "✅"
    else
        return "ℹ️"
    end
end

function truncate_message(message::String, max_length::Int)::String
    """
    Truncate message to fit display width
    """
    if length(message) <= max_length
        return message
    else
        return message[1:max_length-3] * "..."
    end
end

function create_status_line(dashboard::TournamentDashboard)::String
    if dashboard.command_mode
        # Show command input line
        return "Command: /$(dashboard.command_buffer)_"
    elseif dashboard.wizard_active
        # Show wizard mode status
        return "🧙 Model Creation Wizard Active | ESC to cancel | Tab/Shift+Tab to navigate | Enter to proceed"
    else
        status = dashboard.paused ? "PAUSED" : "RUNNING"
        model_name = dashboard.model[:name]
        
        return "Status: $status | Model: $model_name | Press 'n' for new model | '/' for commands | 'h' for help | 'q' to quit"
    end
end

function update_system_info!(dashboard::TournamentDashboard)
    # Get actual CPU usage (average across all cores)
    loadavg = Sys.loadavg()
    cpu_count = Sys.CPU_THREADS
    dashboard.system_info[:cpu_usage] = min(100, round(Int, (loadavg[1] / cpu_count) * 100))
    dashboard.system_info[:load_avg] = loadavg

    # Get actual memory usage in GB
    total_memory = Sys.total_memory() / (1024^3)  # Convert to GB
    free_memory = Sys.free_memory() / (1024^3)    # Convert to GB
    dashboard.system_info[:memory_used] = round(total_memory - free_memory, digits=1)
    dashboard.system_info[:memory_total] = round(total_memory, digits=1)

    # Try to get process memory (this is an approximation)
    dashboard.system_info[:process_memory] = 0.0  # Would need platform-specific code

    dashboard.system_info[:model_active] = dashboard.model[:is_active]

    # Update uptime
    if !haskey(dashboard.system_info, :start_time)
        dashboard.system_info[:start_time] = time()
    end
    dashboard.system_info[:uptime] = round(Int, time() - dashboard.system_info[:start_time])
end

function update_model_performances!(dashboard::TournamentDashboard)
    # Check network connectivity first
    if !check_network_connectivity(dashboard)
        add_event!(dashboard, :error, "Network connectivity check failed - unable to update model performance", 
                  Base.IOError("Network unreachable"))
        return
    end
    
    model_name = dashboard.model[:name]
    try
        start_time = time()
        perf = API.get_model_performance(dashboard.api_client, model_name;
                                         enable_dynamic_sharpe=dashboard.config.enable_dynamic_sharpe,
                                         sharpe_history_rounds=dashboard.config.sharpe_history_rounds,
                                         sharpe_min_data_points=dashboard.config.sharpe_min_data_points)
        api_duration = time() - start_time
        
        dashboard.model[:corr] = perf.corr
        dashboard.model[:mmc] = perf.mmc
        dashboard.model[:fnc] = perf.fnc
        dashboard.model[:sharpe] = perf.sharpe
        dashboard.model[:is_active] = true
        
        # Update API latency tracking
        dashboard.network_status[:api_latency] = api_duration * 1000  # Convert to ms
        
        # Add to history with timestamp
        push!(dashboard.performance_history, Dict(
            :timestamp => utc_now_datetime(),
            :corr => perf.corr,
            :mmc => perf.mmc,
            :fnc => perf.fnc,
            :sharpe => perf.sharpe,
            :stake => get(dashboard.model, :stake, 0.0)
        ))
        
        # Keep only configured number of entries to manage memory
        max_history = get(get(dashboard.config.tui_config, "limits", Dict()), "performance_history_max", 100)
        if length(dashboard.performance_history) > max_history
            popfirst!(dashboard.performance_history)
        end
        
        add_event!(dashboard, :success, "Updated performance for model '$model_name'")
            
    catch e
        dashboard.model[:is_active] = false
        
        # Categorize and log the specific error for this model
        add_event!(dashboard, :error, "Failed to update performance for model '$model_name'", e)
        
        # Log additional context for debugging
        @error "Model performance update failed" model=model_name exception=e
    end
end

# Function for test compatibility - updates the model's performance directly
function update_model_performance!(dashboard::TournamentDashboard, model_name::String, 
                                   corr::Float64, mmc::Float64, fnc::Float64, stake::Float64)
    if dashboard.model[:name] == model_name
        dashboard.model[:corr] = corr
        dashboard.model[:mmc] = mmc
        dashboard.model[:fnc] = fnc
        dashboard.model[:stake] = stake
        dashboard.model[:is_active] = true
    end
end

function get_staking_info(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    # Get round information with proper error handling
    round_info = nothing
    try
        round_info = API.get_current_round(dashboard.api_client)
    catch e
        add_event!(dashboard, :error, "Failed to fetch current round information", e)
        # Return fallback data
        model_stake = get(dashboard.model, :stake, 0.0)
        return Dict(
            :total_stake => round(model_stake, digits=2),
            :at_risk => round(model_stake * 0.25, digits=2),
            :expected_payout => round(model_stake * dashboard.model[:corr] * 0.5, digits=2),
            :current_round => 0,
            :submission_status => "Error - Check API connection",
            :time_remaining => "N/A"
        )
    end
    
    time_remaining = round_info.close_time - utc_now_datetime()
    
    # Get actual staking data from API for the model
    model_name = dashboard.model[:name]
    total_stake = 0.0
    total_at_risk = 0.0
    total_expected_payout = 0.0
    
    if dashboard.model[:is_active]
        try
            # Get actual staking information from API
            stake_info = API.get_model_stakes(dashboard.api_client, model_name)
            model_stake = stake_info.total_stake
            
            total_stake = model_stake
            
            # Calculate at-risk amount based on actual burn rate from API
            burn_rate = get(stake_info, :burn_rate, 0.25)  # Default to 25% if not available
            total_at_risk = model_stake * burn_rate
            
            # Calculate expected payout using real performance metrics
            corr_multiplier = get(stake_info, :corr_multiplier, 0.5)
            mmc_multiplier = get(stake_info, :mmc_multiplier, 2.0)
            expected_payout = model_stake * (
                corr_multiplier * dashboard.model[:corr] + 
                mmc_multiplier * dashboard.model[:mmc]
            )
            total_expected_payout = expected_payout
            
            # Update model with actual stake
            dashboard.model[:stake] = model_stake
            
        catch e
            # Log specific error for this model
            add_event!(dashboard, :error, "Failed to fetch stake info for model '$model_name'", e)
            
            # Fallback to model's stored stake if API call fails
            model_stake = get(dashboard.model, :stake, 0.0)
            total_stake = model_stake
            total_at_risk = model_stake * 0.25
            total_expected_payout = model_stake * dashboard.model[:corr] * 0.5
        end
    end
    
    # Determine submission status by checking latest submissions
    submission_status = try
        latest_submission = API.get_latest_submission(dashboard.api_client)
        if latest_submission.round == round_info.number
            "Submitted"
        else
            "Pending"
        end
    catch e
        add_event!(dashboard, :error, "Failed to check submission status", e)
        "Error - Check API connection"
    end
    
    return Dict(
        :total_stake => round(total_stake, digits=2),
        :at_risk => round(total_at_risk, digits=2),
        :expected_payout => round(total_expected_payout, digits=2),
        :current_round => round_info.number,
        :submission_status => submission_status,
        :time_remaining => format_time_remaining(time_remaining)
    )
end

function format_time_remaining(time_remaining::Dates.Period)::String
    # Convert to total seconds safely to avoid precision issues
    try
        # Convert to milliseconds first, then to seconds
        total_milliseconds = Dates.value(Dates.Millisecond(time_remaining))
        total_seconds = div(total_milliseconds, 1000)  # Integer division
        
        # Handle negative or very small values
        if total_seconds <= 0
            return "0m"
        end
    catch e
        # If any conversion fails, return safe default
        if isa(e, InexactError)
            return "0m"
        end
        rethrow(e)
    end
    
    hours = div(total_seconds, 3600)
    minutes = div(total_seconds % 3600, 60)
    
    if hours > 24
        days = div(hours, 24)
        hours_remainder = hours % 24
        return "$(days)d $(hours_remainder)h"
    elseif hours > 0
        return "$(hours)h $(minutes)m"
    else
        return "$(minutes)m"
    end
end

# Error categorization helper functions
function categorize_error(exception::Exception)::Tuple{ErrorCategory, ErrorSeverity}
    error_msg = string(exception)
    
    # Network-related errors
    if isa(exception, HTTP.ConnectError) || isa(exception, HTTP.TimeoutError)
        return (NETWORK_ERROR, HIGH)
    elseif isa(exception, Base.IOError) && occursin("network", lowercase(error_msg))
        return (NETWORK_ERROR, HIGH)
    
    # Authentication errors
    elseif occursin("unauthorized", lowercase(error_msg)) || 
           occursin("forbidden", lowercase(error_msg)) ||
           occursin("authentication", lowercase(error_msg))
        return (AUTH_ERROR, CRITICAL)
    
    # API-specific errors
    elseif occursin("graphql", lowercase(error_msg)) ||
           occursin("api", lowercase(error_msg))
        return (API_ERROR, MEDIUM)
    
    # Timeout errors
    elseif isa(exception, TaskFailedException) || 
           occursin("timeout", lowercase(error_msg))
        return (TIMEOUT_ERROR, MEDIUM)
    
    # Data validation errors
    elseif isa(exception, ArgumentError) || 
           occursin("validation", lowercase(error_msg))
        return (VALIDATION_ERROR, LOW)
    
    # System errors
    else
        return (SYSTEM_ERROR, MEDIUM)
    end
end

function get_user_friendly_message(category::ErrorCategory, technical_msg::String)::String
    base_msg = if category == API_ERROR
        "API communication issue"
    elseif category == NETWORK_ERROR
        "Network connectivity problem"
    elseif category == AUTH_ERROR
        "Authentication failed - check API credentials"
    elseif category == DATA_ERROR
        "Data processing error"
    elseif category == SYSTEM_ERROR
        "System error occurred"
    elseif category == TIMEOUT_ERROR
        "Request timed out - server may be busy"
    elseif category == VALIDATION_ERROR
        "Input validation failed"
    else
        "Unknown error"
    end
    
    # Add specific context if available
    if occursin("model not found", lowercase(technical_msg))
        return "$base_msg: Model not found in your account"
    elseif occursin("rate limit", lowercase(technical_msg))
        return "$base_msg: Rate limit exceeded, will retry shortly"
    elseif occursin("invalid credentials", lowercase(technical_msg))
        return "$base_msg: Please verify your API keys in configuration"
    else
        return base_msg
    end
end

function get_severity_icon(severity::ErrorSeverity)::String
    if severity == LOW
        "ℹ️"
    elseif severity == MEDIUM
        "⚠️"
    elseif severity == HIGH
        "❌"
    elseif severity == CRITICAL
        "🚨"
    else
        "❓"
    end
end

function check_network_connectivity(dashboard::TournamentDashboard)::Bool
    try
        start_time = time()
        # Simple HTTP check to Google DNS
        network_timeout = get(dashboard.config.tui_config, "network_timeout", 5)
        response = HTTP.get("https://8.8.8.8", timeout=network_timeout)
        latency = time() - start_time
        
        dashboard.network_status[:is_connected] = true
        dashboard.network_status[:last_check] = utc_now_datetime()
        dashboard.network_status[:api_latency] = latency * 1000  # Convert to ms
        dashboard.network_status[:consecutive_failures] = 0
        
        return true
    catch e
        dashboard.network_status[:is_connected] = false
        dashboard.network_status[:last_check] = utc_now_datetime()
        dashboard.network_status[:consecutive_failures] += 1
        
        return false
    end
end

# Enhanced add_event! function with error categorization
# Single function with optional exception parameter handles both cases
function add_event!(dashboard::TournamentDashboard, type::Symbol, message::String, 
                   exception::Union{Nothing, Exception}=nothing)
    # If there's an exception, categorize it and create enhanced error info
    if exception !== nothing && type == :error
        category, severity = categorize_error(exception)
        user_message = get_user_friendly_message(category, string(exception))
        severity_icon = get_severity_icon(severity)
        
        # Update error counts
        dashboard.error_counts[category] += 1
        
        # Store detailed error for debugging
        categorized_error = CategorizedError(
            category,
            severity,
            user_message,
            string(exception),
            utc_now_datetime(),
            get(dashboard.error_counts, category, 0)
        )
        
        push!(dashboard.last_api_errors, categorized_error)
        # Keep only configured number of errors
        max_errors = get(get(dashboard.config.tui_config, "limits", Dict()), "api_error_history_max", 50)
        if length(dashboard.last_api_errors) > max_errors
            popfirst!(dashboard.last_api_errors)
        end
        
        # Create enhanced event with categorization
        event = Dict(
            :type => type,
            :message => "$severity_icon $user_message",
            :time => utc_now_datetime(),
            :category => category,
            :severity => severity,
            :technical_details => string(exception)
        )
    else
        # Standard event without error categorization
        event = Dict(
            :type => type,
            :message => message,
            :time => utc_now_datetime()
        )
    end
    
    push!(dashboard.events, event)
    
    # Keep only configured number of events
    max_events = get(get(dashboard.config.tui_config, "limits", Dict()), "events_history_max", 100)
    if length(dashboard.events) > max_events
        popfirst!(dashboard.events)
    end
    
    if type == :error
        @log_error "Dashboard event" message=message
    elseif type == :success
        @log_info "Dashboard success" message=message
    end
end

function start_training(dashboard::TournamentDashboard)
    if dashboard.training_info[:is_training] || dashboard.progress_tracker.is_training
        add_event!(dashboard, :warning, "Training already in progress")
        return
    end

    # Update both old and new tracking systems
    dashboard.training_info[:is_training] = true
    dashboard.training_info[:model_name] = dashboard.model[:name]
    dashboard.training_info[:progress] = 0

    # Update progress tracker for visual display
    dashboard.progress_tracker.is_training = true
    dashboard.progress_tracker.training_model = dashboard.model[:name]
    dashboard.progress_tracker.training_progress = 0.0
    dashboard.progress_tracker.training_epoch = 0
    dashboard.progress_tracker.training_total_epochs = 100

    # Update progress tracker
    dashboard.progress_tracker.is_training = true
    dashboard.progress_tracker.training_model = dashboard.model[:name]
    dashboard.progress_tracker.training_progress = 0.0

    # Get default epochs from config
    default_epochs = get(get(dashboard.config.tui_config, "training", Dict()), "default_epochs", 100)
    dashboard.training_info[:total_epochs] = default_epochs
    dashboard.progress_tracker.training_total_epochs = default_epochs
    dashboard.progress_tracker.training_epoch = 0

    add_event!(dashboard, :info, "Starting training for $(dashboard.training_info[:model_name])")

    @async run_real_training(dashboard)
end

function run_real_training(dashboard::TournamentDashboard)
    try
        # Load configuration
        config = dashboard.config
        data_dir = config.data_dir
        
        # Initialize progress tracking
        dashboard.training_info[:current_epoch] = 0
        dashboard.training_info[:progress] = 10
        dashboard.training_info[:eta] = "Loading data..."
        
        # Load training data
        add_event!(dashboard, :info, "Loading training data...")
        train_data = DataLoader.load_training_data(
            joinpath(data_dir, "train.parquet"),
            sample_pct=config.sample_pct
        )
        
        dashboard.training_info[:progress] = 25
        
        # Get feature columns
        features_path = joinpath(data_dir, "features.json")
        feature_set = config.feature_set
        feature_cols = if isfile(features_path)
            features, _ = DataLoader.load_features_json(features_path; feature_set=feature_set)
            features
        else
            DataLoader.get_feature_columns(train_data)
        end
        
        dashboard.training_info[:progress] = 30
        dashboard.training_info[:eta] = "Initializing pipeline..."
        
        # Create ML pipeline
        # Use XGBoost as the default model for training
        model_config = Pipeline.ModelConfig(
            "xgboost",
            Dict(
                :n_estimators => 100,
                :max_depth => 5,
                :learning_rate => 0.01,
                :subsample => 0.8
            )
        )
        pipeline = Pipeline.MLPipeline(
            feature_cols=feature_cols,
            target_col=config.target_col,
            model_config=model_config,
            neutralize=config.enable_neutralization
        )
        
        dashboard.training_info[:progress] = 40
        dashboard.training_info[:eta] = "Training models..."
        
        # Train the pipeline with progress updates
        add_event!(dashboard, :info, "Training ensemble models...")
        
        # Create a progress callback for real training updates
        function training_progress_callback(epoch::Int, total_epochs::Int, loss::Float64, val_score::Float64)
            if !dashboard.training_info[:is_training]
                return false  # Signal to stop training
            end
            
            dashboard.training_info[:current_epoch] = epoch
            dashboard.training_info[:total_epochs] = total_epochs
            dashboard.training_info[:progress] = 40 + (epoch / total_epochs) * 40
            dashboard.training_info[:eta] = "Training epoch $epoch/$total_epochs..."
            dashboard.training_info[:loss] = loss
            dashboard.training_info[:val_score] = val_score
            
            return true  # Continue training
        end
        
        # Load validation data for training
        val_data = DataLoader.load_training_data(
            joinpath(data_dir, "validation.parquet"),
            feature_cols=feature_cols,
            target_col=config.target_col
        )
        
        # Create dashboard callback for training progress
        dashboard_callback = create_dashboard_training_callback(dashboard)
        callbacks = [dashboard_callback]
        
        # Train the pipeline with callbacks for real-time progress updates
        Pipeline.train!(pipeline, train_data, val_data, verbose=false, callbacks=callbacks)
        
        
        dashboard.training_info[:progress] = 90
        dashboard.training_info[:eta] = "Evaluating performance..."
        
        # Generate validation predictions (val_data already loaded)
        predictions = Pipeline.predict(pipeline, val_data)
        
        # Calculate performance metrics
        if haskey(val_data, Symbol(pipeline.target_cols[1]))
            target = val_data[!, Symbol(pipeline.target_cols[1])]
            correlation = cor(predictions, target)
            
            # Update model with real performance
            dashboard.model[:corr] = round(correlation, digits=4)
            # MMC and FNC require meta-model data from Numerai, not available locally
            dashboard.model[:mmc] = 0.0  # Requires meta-model from Numerai API
            dashboard.model[:fnc] = 0.0  # Requires feature-neutralized meta-model
            
            dashboard.training_info[:val_score] = correlation
            
            add_event!(dashboard, :success, 
                "Training completed! Validation correlation: $(round(correlation, digits=4))")
        else
            add_event!(dashboard, :success, "Training completed successfully")
        end
        
        # Store validation score in history
        if dashboard.training_info[:val_score] > 0
            push!(dashboard.predictions_history, dashboard.training_info[:val_score])
        end
        
        dashboard.training_info[:progress] = 100
        dashboard.training_info[:is_training] = false

        # Clear progress tracker immediately
        dashboard.progress_tracker.training_progress = 100.0
        dashboard.progress_tracker.is_training = false
        dashboard.progress_tracker.training_model = ""
        dashboard.progress_tracker.training_epoch = 0

    catch e
        dashboard.training_info[:is_training] = false
        dashboard.training_info[:progress] = 0
        dashboard.progress_tracker.is_training = false
        dashboard.progress_tracker.training_progress = 0.0
        add_event!(dashboard, :error, "Training failed: $(sprint(showerror, e))")
        @error "Training error" exception=e
    end
end


function render_model_details_panel(dashboard::TournamentDashboard)
    if isnothing(dashboard.selected_model_details)
        return nothing
    end
    
    model = dashboard.selected_model_details
    stats = dashboard.selected_model_stats
    
    content = """
    $(Term.highlight("📊 Model Details"))
    
    $(Term.bold("Basic Information"))
    • Name: $(model[:name])
    • Type: $(get(model, :type, "Unknown"))
    • Status: $(model[:is_active] ? "🟢 Active" : "🔴 Inactive")
    • Current Stake: $(get(model, :stake, 0.0)) NMR
    
    $(Term.bold("Current Performance"))
    • Correlation: $(round(model[:corr], digits=4))
    • MMC: $(round(model[:mmc], digits=4))
    • FNC: $(round(model[:fnc], digits=4))
    • Sharpe: $(round(model[:sharpe], digits=3))
    """
    
    if !isnothing(stats)
        content *= """
        
        $(Term.bold("Historical Statistics"))
        • CORR: μ=$(stats[:corr_mean]), σ=$(stats[:corr_std])
        • MMC:  μ=$(stats[:mmc_mean]), σ=$(stats[:mmc_std])
        • Sharpe: $(stats[:sharpe])
        • Samples: $(stats[:samples])
        """
    end
    
    content *= """
    
    $(Term.dim("Press ESC to close"))
    """
    
    return Panel(
        content,
        title="📊 Model Details - $(model[:name])",
        title_style="bold cyan",
        width=60,
        height=25
    )
end

function render_wizard_panel(dashboard::TournamentDashboard)
    if isnothing(dashboard.wizard_state)
        return Panel("Error: Wizard state not initialized", title="Error")
    end
    
    ws = dashboard.wizard_state
    
    content = if ws.step == 1
        """
        $(Term.highlight("Step 1: Model Name"))
        
        Enter model name: $(ws.model_name)_
        
        Press Enter to continue
        Press Backspace to edit
        Press Esc to cancel
        """
    elseif ws.step == 2
        """
        $(Term.highlight("Step 2: Model Type"))
        
        Select model type:
        $(ws.model_type == "XGBoost" ? "▶" : " ") [1] XGBoost (Gradient Boosting)
        $(ws.model_type == "LightGBM" ? "▶" : " ") [2] LightGBM (Light Gradient Boosting)  
        $(ws.model_type == "EvoTrees" ? "▶" : " ") [3] EvoTrees (Pure Julia Boosting)
        $(ws.model_type == "Ensemble" ? "▶" : " ") [4] Ensemble (Multiple Models)
        
        Press 1-4 to select
        Press Enter to continue
        """
    elseif ws.step == 3
        """
        $(Term.highlight("Step 3: Training Parameters"))
        
        Learning Rate: $(ws.learning_rate)
        Max Depth: $(ws.max_depth)
        Feature Fraction: $(ws.feature_fraction)
        Number of Rounds: $(ws.num_rounds)
        
        Press ↑/↓ to navigate, ←/→ to adjust
        Press Enter to continue
        """
    elseif ws.step == 4
        """
        $(Term.highlight("Step 4: Neutralization Settings"))
        
        Feature Neutralization: $(ws.neutralize ? "✅ Enabled" : "❌ Disabled")
        Neutralization Proportion: $(ws.neutralize_proportion)
        
        Press Space to toggle neutralization
        Press ←/→ to adjust proportion
        Press Enter to continue
        """
    elseif ws.step == 5
        """
        $(Term.highlight("Step 5: Review & Confirm"))
        
        Model Configuration:
        • Name: $(ws.model_name)
        • Type: $(ws.model_type)
        • Learning Rate: $(ws.learning_rate)
        • Max Depth: $(ws.max_depth)
        • Feature Fraction: $(ws.feature_fraction)
        • Rounds: $(ws.num_rounds)
        • Neutralization: $(ws.neutralize ? "Yes ($(ws.neutralize_proportion))" : "No")
        
        Press Enter to create model
        Press Esc to cancel
        """
    else
        "Unknown wizard step"
    end
    
    Panel(
        content,
        title="📦 New Model Wizard - Step $(ws.step)/5",
        title_style="bold cyan",
        width=60,
        height=20
    )
end




function show_model_details(dashboard::TournamentDashboard)
    model_name = dashboard.model[:name]
    
    # Set the model details to be shown
    dashboard.show_model_details = true
    dashboard.selected_model_details = dashboard.model
    
    # Display historical performance if available
    if !isempty(dashboard.performance_history)
        history = dashboard.performance_history
        
        # Calculate statistics
        corr_values = [h[:corr] for h in history]
        mmc_values = [h[:mmc] for h in history]
        fnc_values = [h[:fnc] for h in history]
        sharpe_values = [h[:sharpe] for h in history]
        
        # Store stats in dashboard for display
        dashboard.selected_model_stats = Dict(
            :corr_mean => round(mean(corr_values), digits=4),
            :corr_std => round(std(corr_values), digits=4),
            :mmc_mean => round(mean(mmc_values), digits=4),
            :mmc_std => round(std(mmc_values), digits=4),
            :sharpe => round(mean(sharpe_values), digits=3),
            :samples => length(history)
        )
        
        add_event!(dashboard, :info, "Showing details for $(model_name)")
    else
        dashboard.selected_model_stats = nothing
        add_event!(dashboard, :warning, "No historical data for $(model_name)")
    end
end

function save_performance_history(dashboard::TournamentDashboard, filepath::String="performance_history.json")
    try
        # Convert history to a format suitable for JSON serialization
        history_data = Dict{String, Any}()
        model_name = dashboard.model[:name]
        history_data[model_name] = [Dict(
            "timestamp" => string(h[:timestamp]),
            "corr" => h[:corr],
            "mmc" => h[:mmc],
            "fnc" => h[:fnc],
            "sharpe" => h[:sharpe],
            "stake" => h[:stake]
        ) for h in dashboard.performance_history]
        
        open(filepath, "w") do io
            JSON3.write(io, history_data)
        end
        
        add_event!(dashboard, :success, "Performance history saved to $filepath")
    catch e
        add_event!(dashboard, :error, "Failed to save history: $e")
    end
end

function load_performance_history!(dashboard::TournamentDashboard, filepath::String="performance_history.json")
    if !isfile(filepath)
        return
    end
    
    try
        history_data = JSON3.read(read(filepath, String))
        model_name = dashboard.model[:name]
        
        # Load history for the current model if it exists in the file
        if haskey(history_data, model_name)
            history = history_data[model_name]
            dashboard.performance_history = [Dict{Symbol, Any}(
                :timestamp => DateTime(h["timestamp"]),
                :corr => Float64(h["corr"]),
                :mmc => Float64(h["mmc"]),
                :fnc => Float64(h["fnc"]),
                :sharpe => Float64(h["sharpe"]),
                :stake => Float64(h["stake"])
            ) for h in history]
        end
        
        add_event!(dashboard, :success, "Performance history loaded from $filepath")
    catch e
        add_event!(dashboard, :error, "Failed to load history: $e")
    end
end

function get_performance_summary(dashboard::TournamentDashboard, model_name::String)
    if dashboard.model[:name] != model_name || isempty(dashboard.performance_history)
        return nothing
    end
    
    history = dashboard.performance_history
    corr_values = [h[:corr] for h in history]
    mmc_values = [h[:mmc] for h in history]
    fnc_values = [h[:fnc] for h in history]
    sharpe_values = [h[:sharpe] for h in history]
    
    return Dict(
        :count => length(history),
        :corr_mean => mean(corr_values),
        :corr_std => std(corr_values),
        :corr_max => maximum(corr_values),
        :corr_min => minimum(corr_values),
        :mmc_mean => mean(mmc_values),
        :mmc_std => std(mmc_values),
        :fnc_mean => mean(fnc_values),
        :sharpe_mean => mean(sharpe_values),
        :last_update => history[end][:timestamp]
    )
end

# Enhanced Recovery Mode Functions
function render_recovery_mode(dashboard::TournamentDashboard, error::Exception)
    """
    Comprehensive recovery mode display with system diagnostics, configuration status,
    and troubleshooting suggestions.
    """
    println("╔═══════════════════════════════════════════════════════════════════════════════╗")
    println("║                  🚀 Numerai Tournament Dashboard - Recovery Mode              ║")
    println("╚═══════════════════════════════════════════════════════════════════════════════╝")
    println()
    
    # 1. Error Information
    println("⚠️  RENDERING ERROR DETAILS:")
    println("   Error Type: $(typeof(error))")
    println("   Message: $(error)")
    category, severity = categorize_error(error)
    severity_icon = get_severity_icon(severity)
    user_msg = get_user_friendly_message(category, string(error))
    println("   Category: $severity_icon $category ($severity)")
    println("   User Message: $user_msg")
    println()
    
    # 2. System Diagnostics
    diagnostics = get_system_diagnostics(dashboard)
    println("🔧 SYSTEM DIAGNOSTICS:")
    println("   CPU Usage: $(diagnostics[:cpu_usage])% (Load: $(diagnostics[:load_avg]))")
    println("   Memory: $(diagnostics[:memory_used]) GB / $(diagnostics[:memory_total]) GB ($(diagnostics[:memory_percent])%)")
    println("   Disk Space: $(diagnostics[:disk_free]) GB free / $(diagnostics[:disk_total]) GB total")
    println("   Process Memory: $(diagnostics[:process_memory]) MB")
    println("   Threads: $(diagnostics[:threads]) (Julia: $(diagnostics[:julia_threads]))")
    println("   Uptime: $(diagnostics[:uptime])")
    println()
    
    # 3. Configuration Status
    config_status = get_configuration_status(dashboard)
    println("⚙️  CONFIGURATION STATUS:")
    println("   API Keys: $(config_status[:api_keys_status])")
    println("   Tournament ID: $(config_status[:tournament_id])")
    println("   Data Directory: $(config_status[:data_dir])")
    println("   Models Directory: $(config_status[:model_dir])")
    println("   Feature Set: $(config_status[:feature_set])")
    env_vars_str = length(config_status[:env_vars]) > 0 ? join(config_status[:env_vars], ", ") : "None"
    println("   Environment Variables: $(env_vars_str)")
    println()
    
    # 4. Local Data Files
    data_files = discover_local_data_files(dashboard)
    println("📁 LOCAL DATA FILES:")
    if isempty(data_files)
        println("   ❌ No data files found")
    else
        for (category, files) in data_files
            println("   $(category):")
            for file_info in files
                println("     • $(file_info[:name]) ($(file_info[:size]), $(file_info[:modified]))")
            end
        end
    end
    println()
    
    # 5. Last Known Good State
    last_good_state = get_last_known_good_state(dashboard)
    println("💾 LAST KNOWN GOOD STATE:")
    if isnothing(last_good_state)
        println("   ❌ No previous good state recorded")
    else
        println("   Last Successful Render: $(last_good_state[:timestamp])")
        println("   Model Performance: CORR=$(last_good_state[:corr]), MMC=$(last_good_state[:mmc])")
        println("   Network Status: $(last_good_state[:network_connected] ? "Connected" : "Disconnected")")
        println("   API Latency: $(last_good_state[:api_latency])ms")
    end
    println()
    
    # 6. Network Status
    println("🌐 NETWORK STATUS:")
    network_info = get_detailed_network_status(dashboard)
    println("   Connection: $(network_info[:status])")
    println("   Last Check: $(network_info[:last_check])")
    println("   API Latency: $(network_info[:latency])ms")
    println("   Consecutive Failures: $(network_info[:failures])")
    if !isempty(network_info[:recent_errors])
        println("   Recent Network Errors:")
        for err in network_info[:recent_errors][1:min(3, end)]
            println("     • $(err)")
        end
    end
    println()
    
    # 7. Troubleshooting Suggestions
    suggestions = get_troubleshooting_suggestions(error, category, dashboard)
    println("🔍 TROUBLESHOOTING SUGGESTIONS:")
    for (i, suggestion) in enumerate(suggestions)
        println("   $(i). $(suggestion)")
    end
    println()
    
    # 8. Manual Operation Shortcuts
    println("⌨️  RECOVERY COMMANDS:")
    println("   r  - Retry dashboard initialization")
    println("   n  - Test network connectivity")
    println("   c  - Check configuration files")
    println("   d  - Download fresh tournament data")
    println("   l  - View detailed error logs")
    println("   s  - Start training (original functionality)")
    println("   /save - Save current diagnostic report")
    println("   /diag - Run full system diagnostics")
    println("   /reset - Reset all error counters")
    println("   /backup - Create configuration backup")
    println("   q  - Quit dashboard")
    println("   h  - Show help")
    println()
    
    # 9. Recent Events (if available)
    println("📝 RECENT EVENTS:")
    recent_events = Iterators.take(Iterators.reverse(dashboard.events), 5)
    if isempty(dashboard.events)
        println("   ❌ No events recorded")
    else
        for event in recent_events
            timestamp = haskey(event, :time) ? event[:time] : "N/A"
            type_icon = event[:type] == :error ? "❌" : event[:type] == :success ? "✅" : "ℹ️"
            println("   $type_icon [$timestamp] $(event[:message])")
        end
    end
    println()
    
    # 10. Current Model Status
    println("📊 CURRENT MODEL STATUS:")
    println("   Model: $(dashboard.model[:name])")
    println("   Active: $(dashboard.model[:is_active] ? "Yes" : "No")")
    if dashboard.model[:is_active]
        println("   Performance: CORR=$(round(dashboard.model[:corr], digits=4)) MMC=$(round(dashboard.model[:mmc], digits=4))")
        println("   Stake: $(get(dashboard.model, :stake, 0.0)) NMR")
    end
    
    println("")
    println("═══════════════════════════════════════════════════════════════════════════════")
end

function get_system_diagnostics(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Comprehensive system diagnostics including CPU, memory, disk usage.
    """
    try
        # CPU diagnostics
        loadavg = Sys.loadavg()
        cpu_count = Sys.CPU_THREADS
        cpu_usage = min(100, round(Int, (loadavg[1] / cpu_count) * 100))
        
        # Memory diagnostics
        total_memory_bytes = Sys.total_memory()
        free_memory_bytes = Sys.free_memory()
        total_memory_gb = round(total_memory_bytes / (1024^3), digits=1)
        free_memory_gb = round(free_memory_bytes / (1024^3), digits=1)
        used_memory_gb = round((total_memory_bytes - free_memory_bytes) / (1024^3), digits=1)
        memory_percent = round(Int, ((total_memory_bytes - free_memory_bytes) / total_memory_bytes) * 100)
        
        # Process memory
        process_memory_mb = round(Base.summarysize(dashboard) / (1024^2), digits=1)
        
        # Disk diagnostics (current directory)
        disk_info = try
            stat_result = stat(".")
            # On macOS/Linux, try to get disk usage via df command
            df_output = read(`df -h .`, String)
            lines = split(df_output, '\n')
            if length(lines) >= 2
                parts = split(lines[2])
                if length(parts) >= 4
                    disk_total = replace(parts[2], "G" => "", "T" => "000") |> x -> (try parse(Float64, x) catch _ 0.0 end)
                    disk_free = replace(parts[4], "G" => "", "T" => "000") |> x -> (try parse(Float64, x) catch _ 0.0 end)
                    (total=disk_total, free=disk_free)
                else
                    (total=0.0, free=0.0)
                end
            else
                (total=0.0, free=0.0)
            end
        catch
            (total=0.0, free=0.0)
        end
        
        # Uptime calculation
        uptime_seconds = Int(dashboard.system_info[:uptime])
        uptime_str = if uptime_seconds < 60
            "$(uptime_seconds)s"
        elseif uptime_seconds < 3600
            "$(div(uptime_seconds, 60))m $(uptime_seconds % 60)s"
        else
            hours = div(uptime_seconds, 3600)
            minutes = div(uptime_seconds % 3600, 60)
            "$(hours)h $(minutes)m"
        end
        
        return Dict{Symbol, Any}(
            :cpu_usage => cpu_usage,
            :load_avg => "$(round(loadavg[1], digits=2)), $(round(loadavg[2], digits=2)), $(round(loadavg[3], digits=2))",
            :memory_used => used_memory_gb,
            :memory_total => total_memory_gb,
            :memory_free => free_memory_gb,
            :memory_percent => memory_percent,
            :disk_total => isa(disk_info, NamedTuple) ? disk_info.total : disk_info[1],
            :disk_free => isa(disk_info, NamedTuple) ? disk_info.free : disk_info[2],
            :process_memory => process_memory_mb,
            :threads => dashboard.system_info[:threads],
            :julia_threads => Threads.nthreads(),
            :uptime => uptime_str
        )
    catch e
        # Fallback diagnostics if system calls fail
        return Dict{Symbol, Any}(
            :cpu_usage => 0,
            :load_avg => "N/A",
            :memory_used => 0.0,
            :memory_total => get(dashboard.system_info, :memory_total, 0.0),
            :memory_free => 0.0,
            :memory_percent => 0,
            :disk_total => 0.0,
            :disk_free => 0.0,
            :process_memory => 0.0,
            :threads => get(dashboard.system_info, :threads, 0),
            :julia_threads => Threads.nthreads(),
            :uptime => "N/A"
        )
    end
end

function get_configuration_status(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Check configuration status including environment variables and file paths.
    """
    config = dashboard.config
    
    # Check API keys (masked for security)
    api_keys_status = if haskey(ENV, "NUMERAI_PUBLIC_ID") && haskey(ENV, "NUMERAI_SECRET_KEY")
        pub_key = ENV["NUMERAI_PUBLIC_ID"]
        secret_key = ENV["NUMERAI_SECRET_KEY"]
        pub_masked = length(pub_key) > 8 ? pub_key[1:4] * "..." * pub_key[end-3:end] : "***"
        secret_masked = length(secret_key) > 8 ? secret_key[1:4] * "..." * secret_key[end-3:end] : "***"
        "✅ Set via ENV ($pub_masked, $secret_masked)"
    elseif hasfield(typeof(config), :api_public_key) && hasfield(typeof(config), :api_secret_key)
        "✅ Set in config file"
    else
        "❌ Not configured"
    end
    
    # Check directories
    data_dir_status = isdir(config.data_dir) ? "✅ $(config.data_dir)" : "❌ $(config.data_dir) (missing)"
    model_dir_status = isdir(config.model_dir) ? "✅ $(config.model_dir)" : "❌ $(config.model_dir) (missing)"
    
    # Environment variables check
    env_vars = String[]
    for var in ["NUMERAI_PUBLIC_ID", "NUMERAI_SECRET_KEY", "JULIA_NUM_THREADS", "PATH"]
        if haskey(ENV, var)
            value = var in ["NUMERAI_PUBLIC_ID", "NUMERAI_SECRET_KEY"] ? "***" : ENV[var][1:min(20, end)] * "..."
            push!(env_vars, "$var=$value")
        end
    end
    
    return Dict{Symbol, Any}(
        :api_keys_status => api_keys_status,
        :tournament_id => config.tournament_id,
        :data_dir => data_dir_status,
        :model_dir => model_dir_status,
        :feature_set => config.feature_set,
        :env_vars => env_vars
    )
end

function discover_local_data_files(dashboard::TournamentDashboard)::Dict{String, Vector{Dict{Symbol, Any}}}
    """
    Discover and categorize local data files.
    """
    result = Dict{String, Vector{Dict{Symbol, Any}}}()
    config = dashboard.config
    
    # Check data directory
    data_files = Vector{Dict{Symbol, Any}}()
    if isdir(config.data_dir)
        try
            for file in readdir(config.data_dir, join=true)
                if isfile(file)
                    stat_info = stat(file)
                    file_info = Dict{Symbol, Any}(
                        :name => basename(file),
                        :path => file,
                        :size => format_file_size(stat_info.size),
                        :modified => format_file_time(stat_info.mtime)
                    )
                    push!(data_files, file_info)
                end
            end
        catch e
            push!(data_files, Dict{Symbol, Any}(:name => "Error reading directory: $e", :size => "", :modified => "", :path => ""))
        end
    end
    result["Data Files"] = data_files
    
    # Check model directory
    model_files = Vector{Dict{Symbol, Any}}()
    if isdir(config.model_dir)
        try
            for file in readdir(config.model_dir, join=true)
                if isfile(file)
                    stat_info = stat(file)
                    file_info = Dict{Symbol, Any}(
                        :name => basename(file),
                        :path => file,
                        :size => format_file_size(stat_info.size),
                        :modified => format_file_time(stat_info.mtime)
                    )
                    push!(model_files, file_info)
                end
            end
        catch e
            push!(model_files, Dict{Symbol, Any}(:name => "Error reading directory: $e", :size => "", :modified => "", :path => ""))
        end
    end
    result["Model Files"] = model_files
    
    # Check for config files
    config_files = Vector{Dict{Symbol, Any}}()
    for config_file in ["config.toml", "features.json", "models.json"]
        if isfile(config_file)
            stat_info = stat(config_file)
            file_info = Dict{Symbol, Any}(
                :name => config_file,
                :path => abspath(config_file),
                :size => format_file_size(stat_info.size),
                :modified => format_file_time(stat_info.mtime)
            )
            push!(config_files, file_info)
        end
    end
    result["Config Files"] = config_files
    
    return result
end

function format_file_size(size_bytes::Int64)::String
    """
    Format file size in human-readable format.
    """
    if size_bytes < 1024
        "$(size_bytes) B"
    elseif size_bytes < 1024^2
        "$(round(size_bytes / 1024, digits=1)) KB"
    elseif size_bytes < 1024^3
        "$(round(size_bytes / 1024^2, digits=1)) MB"
    else
        "$(round(size_bytes / 1024^3, digits=1)) GB"
    end
end

function format_file_time(mtime::Float64)::String
    """
    Format file modification time.
    """
    try
        dt = unix2datetime(mtime)
        return Dates.format(dt, "yyyy-mm-dd HH:MM")
    catch
        return "Unknown"
    end
end

function get_last_known_good_state(dashboard::TournamentDashboard)::Union{Nothing, Dict{Symbol, Any}}
    """
    Retrieve last known good state from persistent storage.
    """
    state_file = ".dashboard_state.json"
    if !isfile(state_file)
        return nothing
    end
    
    try
        state_data = JSON3.read(read(state_file, String))
        return Dict{Symbol, Any}(
            :timestamp => get(state_data, "timestamp", "Unknown"),
            :corr => get(state_data, "corr", 0.0),
            :mmc => get(state_data, "mmc", 0.0),
            :fnc => get(state_data, "fnc", 0.0),
            :sharpe => get(state_data, "sharpe", 0.0),
            :network_connected => get(state_data, "network_connected", false),
            :api_latency => get(state_data, "api_latency", 0.0),
            :model_name => get(state_data, "model_name", "Unknown")
        )
    catch
        return nothing
    end
end

function save_last_known_good_state(dashboard::TournamentDashboard)
    """
    Save current good state to persistent storage.
    """
    state_file = ".dashboard_state.json"
    try
        state_data = Dict(
            "timestamp" => string(utc_now_datetime()),
            "corr" => dashboard.model[:corr],
            "mmc" => dashboard.model[:mmc],
            "fnc" => dashboard.model[:fnc],
            "sharpe" => get(dashboard.model, :sharpe, 0.0),
            "network_connected" => dashboard.network_status[:is_connected],
            "api_latency" => dashboard.network_status[:api_latency],
            "model_name" => dashboard.model[:name]
        )
        
        open(state_file, "w") do io
            JSON3.write(io, state_data)
        end
    catch e
        @warn "Failed to save dashboard state" exception=e
    end
end

function get_detailed_network_status(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Get detailed network status including recent errors.
    """
    network_status = dashboard.network_status
    
    status_text = if network_status[:is_connected]
        "✅ Connected"
    else
        "❌ Disconnected ($(network_status[:consecutive_failures]) consecutive failures)"
    end
    
    # Get recent network errors from events
    recent_network_errors = String[]
    for event in Iterators.take(Iterators.reverse(dashboard.events), 10)
        if event[:type] == :error && haskey(event, :category) && 
           event[:category] in [NETWORK_ERROR, TIMEOUT_ERROR]
            push!(recent_network_errors, "$(event[:time]): $(event[:message])")
        end
    end
    
    return Dict{Symbol, Any}(
        :status => status_text,
        :last_check => network_status[:last_check],
        :latency => round(network_status[:api_latency], digits=1),
        :failures => network_status[:consecutive_failures],
        :recent_errors => recent_network_errors
    )
end

function get_troubleshooting_suggestions(error::Exception, category::ErrorCategory, dashboard::TournamentDashboard)::Vector{String}
    """
    Generate context-specific troubleshooting suggestions based on error type and dashboard state.
    """
    suggestions = String[]
    
    # Error-specific suggestions
    if category == NETWORK_ERROR
        push!(suggestions, "Check your internet connection and try again")
        push!(suggestions, "Verify that Numerai API (https://api-tournament.numer.ai) is accessible")
        push!(suggestions, "Check firewall settings and proxy configuration")
        push!(suggestions, "Try running: /reset to clear network error counters")
    elseif category == AUTH_ERROR
        push!(suggestions, "Verify your NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY environment variables")
        push!(suggestions, "Regenerate API credentials from your Numerai account settings")
        push!(suggestions, "Check that your API keys have the required permissions")
    elseif category == API_ERROR
        push!(suggestions, "Check Numerai API status at https://status.numer.ai")
        push!(suggestions, "Reduce API request frequency by increasing refresh_rate in config.toml")
        push!(suggestions, "Try running: r to retry dashboard initialization")
    elseif category == DATA_ERROR
        push!(suggestions, "Verify that data files exist in the $(dashboard.config.data_dir) directory")
        push!(suggestions, "Try running: d to download fresh tournament data")
        push!(suggestions, "Check file permissions in data directory")
    elseif category == SYSTEM_ERROR
        push!(suggestions, "Check available memory and disk space")
        push!(suggestions, "Try restarting the dashboard application")
        push!(suggestions, "Review Julia installation and package versions")
    end
    
    # State-specific suggestions
    if !dashboard.network_status[:is_connected]
        push!(suggestions, "Network is disconnected - try running: n to test connectivity")
    end
    
    if dashboard.network_status[:consecutive_failures] > 3
        push!(suggestions, "Multiple network failures detected - check your connection stability")
    end
    
    # Dashboard state suggestions
    if isempty(dashboard.events)
        push!(suggestions, "No events recorded - dashboard may have initialization issues")
    end
    
    # Configuration suggestions
    config_status = get_configuration_status(dashboard)
    if occursin("❌", config_status[:api_keys_status])
        push!(suggestions, "API keys not configured - set NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY")
    end
    
    if occursin("missing", config_status[:data_dir])
        push!(suggestions, "Data directory missing - create $(dashboard.config.data_dir) directory")
    end
    
    # General suggestions if no specific ones
    if isempty(suggestions)
        push!(suggestions, "Try restarting the dashboard with: q (quit) then restart")
        push!(suggestions, "Check the log files for more detailed error information")
        push!(suggestions, "Run: /diag for comprehensive system diagnostics")
    end
    
    return suggestions
end

# Recovery mode command functions
function test_network_connectivity(dashboard::TournamentDashboard)
    """
    Test network connectivity and update dashboard state.
    """
    add_event!(dashboard, :info, "Testing network connectivity...")
    
    try
        # Test basic connectivity
        start_time = time()
        response = HTTP.get("https://8.8.8.8", timeout=5)
        basic_latency = (time() - start_time) * 1000
        
        # Test Numerai API connectivity
        start_time = time()
        api_response = HTTP.get("https://api-tournament.numer.ai/healthz", timeout=10)
        api_latency = (time() - start_time) * 1000
        
        # Update network status
        dashboard.network_status[:is_connected] = true
        dashboard.network_status[:api_latency] = api_latency
        dashboard.network_status[:consecutive_failures] = 0
        dashboard.network_status[:last_check] = utc_now_datetime()
        
        add_event!(dashboard, :success, "✅ Network test successful - Basic: $(round(basic_latency, digits=1))ms, API: $(round(api_latency, digits=1))ms")
        
    catch e
        dashboard.network_status[:is_connected] = false
        dashboard.network_status[:consecutive_failures] += 1
        dashboard.network_status[:last_check] = utc_now_datetime()
        
        add_event!(dashboard, :error, "❌ Network test failed", e)
    end
end

function check_configuration_files(dashboard::TournamentDashboard)
    """
    Check configuration files and display status.
    """
    add_event!(dashboard, :info, "Checking configuration files...")
    
    config_status = get_configuration_status(dashboard)
    data_files = discover_local_data_files(dashboard)
    
    # Report configuration status
    add_event!(dashboard, :info, "API Keys: $(config_status[:api_keys_status])")
    add_event!(dashboard, :info, "Data Directory: $(config_status[:data_dir])")
    add_event!(dashboard, :info, "Model Directory: $(config_status[:model_dir])")
    
    # Report data files status
    total_files = sum(length(files) for files in values(data_files))
    add_event!(dashboard, :info, "Found $total_files local data files")
    
    # Check for missing critical files
    critical_files = ["config.toml"]
    missing_files = [f for f in critical_files if !isfile(f)]
    
    if !isempty(missing_files)
        missing_str = join(missing_files, ", ")
        add_event!(dashboard, :error, "❌ Missing critical files: $(missing_str)")
    else
        add_event!(dashboard, :success, "✅ All critical configuration files present")
    end
end

function download_tournament_data_and_train(dashboard::TournamentDashboard)
    """
    Download tournament data and automatically trigger training after completion.
    """
    add_event!(dashboard, :info, "Starting tournament data download...")

    # Use the existing download function
    download_tournament_data(dashboard)
end

function submit_predictions_to_numerai(dashboard::TournamentDashboard)
    """
    Submit predictions to Numerai with progress tracking.
    """
    # Delegate to the command implementation
    submit_predictions_command(dashboard)
end

function download_tournament_data(dashboard::TournamentDashboard)
    """
    Download fresh tournament data with real progress tracking.
    """

    # Set progress tracker for download
    dashboard.progress_tracker.is_downloading = true
    dashboard.progress_tracker.download_progress = 0.0

    try
        # Check if data directory exists
        if !isdir(dashboard.config.data_dir)
            mkpath(dashboard.config.data_dir)
            add_event!(dashboard, :info, "Created data directory: $(dashboard.config.data_dir)")
        end

        # Download each dataset with real progress updates
        datasets = [
            ("train", "train.parquet"),
            ("validation", "validation.parquet"),
            ("live", "live.parquet"),
            ("features", "features.json")
        ]

        total_datasets = length(datasets)
        for (idx, (dataset_type, filename)) in enumerate(datasets)
            dashboard.progress_tracker.download_file = filename
            base_progress = (idx - 1) * (100.0 / total_datasets)
            dashboard.progress_tracker.download_progress = base_progress

            add_event!(dashboard, :info, "Downloading $dataset_type data...")

            # Create a progress callback for the actual download
            progress_callback = (phase; kwargs...) -> begin
                if phase == :start
                    file_name = get(kwargs, :name, filename)
                    dashboard.progress_tracker.download_file = file_name
                    dashboard.progress_tracker.is_downloading = true
                    segment_progress = base_progress + (0.1 * 100.0 / total_datasets)
                    dashboard.progress_tracker.download_progress = segment_progress
                elseif phase == :progress
                    # Real-time progress update
                    progress = get(kwargs, :progress, 0.0)
                    current_mb = get(kwargs, :current_mb, 0.0)
                    total_mb = get(kwargs, :total_mb, 0.0)
                    segment_progress = base_progress + (progress * 100.0 / (total_datasets * 100.0))
                    dashboard.progress_tracker.download_progress = segment_progress
                    dashboard.progress_tracker.download_current_mb = current_mb
                    dashboard.progress_tracker.download_total_mb = total_mb
                elseif phase == :complete
                    size_mb = get(kwargs, :size_mb, 0.0)
                    segment_progress = base_progress + (100.0 / total_datasets)
                    dashboard.progress_tracker.download_progress = segment_progress
                    dashboard.progress_tracker.download_total_mb = size_mb
                    dashboard.progress_tracker.download_current_mb = size_mb
                    add_event!(dashboard, :success, "Downloaded $dataset_type ($(round(size_mb, digits=1)) MB)")
                end
            end

            # Try to download with the actual API
            try
                file_path = joinpath(dashboard.config.data_dir, filename)

                # Use the actual API download function
                API.download_dataset(dashboard.api_client, dataset_type, file_path;
                                   progress_callback=progress_callback)

            catch e
                add_event!(dashboard, :error, "Error downloading $dataset_type: $(sprint(showerror, e))")
                # Don't continue if download fails
                throw(e)
            end
        end

        dashboard.progress_tracker.download_progress = 100.0
        sleep(0.5)  # Show completion briefly

        add_event!(dashboard, :success, "✅ All tournament data downloaded successfully")

        # Trigger automatic training if configured
        if dashboard.config.auto_submit || dashboard.config.auto_train_after_download
            add_event!(dashboard, :info, "🚀 Starting automatic training after download...")
            @async begin
                sleep(1)  # Brief pause before starting training
                NumeraiTournament.UnifiedTUIFix.train_with_progress(dashboard)
            end
        end

    catch e
        add_event!(dashboard, :error, "❌ Failed to download tournament data: $(sprint(showerror, e))")
    finally
        # Clear progress immediately - no need for delay
        dashboard.progress_tracker.is_downloading = false
        dashboard.progress_tracker.download_progress = 0.0
        dashboard.progress_tracker.download_file = ""
    end
end

# Function run_full_pipeline is defined in dashboard_commands.jl

function view_detailed_error_logs(dashboard::TournamentDashboard)
    """
    Display detailed error logs and statistics.
    """
    add_event!(dashboard, :info, "Displaying detailed error logs...")
    
    error_summary = get_error_summary(dashboard)
    
    # Display error statistics
    add_event!(dashboard, :info, "Total errors: $(error_summary[:total_errors])")
    add_event!(dashboard, :info, "Recent errors: $(error_summary[:recent_errors])")
    
    # Display error counts by category
    for (category, count) in error_summary[:error_counts_by_category]
        if count > 0
            add_event!(dashboard, :info, "$category: $count errors")
        end
    end
    
    # Display recent API errors
    if !isempty(dashboard.last_api_errors)
        add_event!(dashboard, :info, "Recent API errors:")
        for (i, error) in enumerate(dashboard.last_api_errors[max(1, end-2):end])
            severity_icon = get_severity_icon(error.severity)
            add_event!(dashboard, :info, "$severity_icon $(error.timestamp): $(error.message)")
        end
    end
    
    # Display error trends
    trends = get_error_trends(dashboard, 60)  # Last hour
    if !isempty(trends)
        add_event!(dashboard, :info, "Error trends (last hour):")
        for (category, count) in trends
            add_event!(dashboard, :info, "  $category: $count")
        end
    end
end

function save_diagnostic_report(dashboard::TournamentDashboard)
    """
    Save comprehensive diagnostic report to file.
    """
    report_file = "dashboard_diagnostics_$(Dates.format(utc_now_datetime(), "yyyy-mm-dd_HH-MM-SS")).txt"
    
    try
        open(report_file, "w") do io
            println(io, "═══════════════════════════════════════════════════════════════")
            println(io, "Numerai Dashboard Diagnostic Report")
            println(io, "Generated: $(utc_now_datetime())")
            println(io, "═══════════════════════════════════════════════════════════════")
            println(io)
            
            # System diagnostics
            diagnostics = get_system_diagnostics(dashboard)
            println(io, "SYSTEM DIAGNOSTICS:")
            for (key, value) in diagnostics
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Configuration status
            config_status = get_configuration_status(dashboard)
            println(io, "CONFIGURATION STATUS:")
            for (key, value) in config_status
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Network status
            network_info = get_detailed_network_status(dashboard)
            println(io, "NETWORK STATUS:")
            for (key, value) in network_info
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Error summary
            error_summary = get_error_summary(dashboard)
            println(io, "ERROR SUMMARY:")
            for (key, value) in error_summary
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Recent events
            println(io, "RECENT EVENTS:")
            for event in Iterators.take(Iterators.reverse(dashboard.events), 10)
                timestamp = haskey(event, :time) ? event[:time] : "N/A"
                println(io, "  [$timestamp] $(event[:type]): $(event[:message])")
            end
        end
        
        add_event!(dashboard, :success, "✅ Diagnostic report saved to: $report_file")
        
    catch e
        add_event!(dashboard, :error, "❌ Failed to save diagnostic report", e)
    end
end

# Error statistics and debugging functions
function get_error_summary(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Get a comprehensive summary of errors and their categories for debugging.
    """
    total_errors = sum(values(dashboard.error_counts))
    recent_errors = count(e -> e[:type] == :error, dashboard.events)
    
    return Dict(
        :total_errors => total_errors,
        :recent_errors => recent_errors,
        :error_counts_by_category => copy(dashboard.error_counts),
        :network_status => copy(dashboard.network_status),
        :last_api_errors => length(dashboard.last_api_errors) > 5 ? 
            dashboard.last_api_errors[end-4:end] : dashboard.last_api_errors
    )
end

function reset_error_tracking!(dashboard::TournamentDashboard)
    """
    Reset error tracking counters (useful for testing or after resolving issues).
    """
    for category in keys(dashboard.error_counts)
        dashboard.error_counts[category] = 0
    end
    empty!(dashboard.last_api_errors)
    dashboard.network_status[:consecutive_failures] = 0
    add_event!(dashboard, :info, "Error tracking counters reset")
end

function get_error_trends(dashboard::TournamentDashboard, minutes_back::Int=60)::Dict{Symbol, Int}
    """
    Analyze error trends over the specified time period.
    """
    cutoff_time = utc_now_datetime() - Dates.Minute(minutes_back)
    recent_events = filter(e -> e[:time] > cutoff_time && e[:type] == :error, dashboard.events)
    
    trends = Dict{Symbol, Int}()
    for event in recent_events
        category = get(event, :category, :UNKNOWN)
        trends[category] = get(trends, category, 0) + 1
    end
    
    return trends
end

# Model Wizard Functions
function start_model_wizard(dashboard::TournamentDashboard)
    """Start the model creation wizard"""
    model_types = ["XGBoost", "LightGBM", "CatBoost", "EvoTrees", "MLP", "ResNet", "Ridge", "Lasso", "ElasticNet"]
    feature_sets = ["small", "medium", "all"]
    
    dashboard.wizard_state = ModelWizardState(
        1,  # step
        6,  # total_steps
        "",  # model_name
        "XGBoost",  # model_type
        model_types,  # model_type_options
        1,  # selected_type_index
        0.1,  # learning_rate
        6,    # max_depth
        0.8,  # feature_fraction
        100,  # num_rounds
        100,  # epochs
        false,  # neutralize
        0.5,   # neutralize_proportion
        "medium",  # feature_set
        feature_sets,  # feature_set_options
        2,     # selected_feature_index (medium)
        0.2,   # validation_split
        true,  # early_stopping
        false, # gpu_enabled
        false, # confirmed
        1,     # current_field
        1      # max_fields (varies per step)
    )
    
    dashboard.wizard_active = true
    add_event!(dashboard, :info, "Model creation wizard started - Press Tab/Shift+Tab to navigate, Enter to proceed")
end

function handle_wizard_input(dashboard::TournamentDashboard, key::Union{Char, String})
    if isnothing(dashboard.wizard_state)
        return
    end
    
    ws = dashboard.wizard_state
    
    if key == "\e"  # ESC - cancel wizard
        dashboard.wizard_active = false
        dashboard.wizard_state = nothing
        add_event!(dashboard, :info, "Model wizard cancelled")
        return
    end
    
    if key == "\t"  # Tab - next field/option
        navigate_wizard_field(ws, :next)
    elseif key == "\e[Z"  # Shift+Tab - previous field/option
        navigate_wizard_field(ws, :prev)
    elseif key == "\r" || key == "\n"  # Enter - next step or confirm
        if ws.step < ws.total_steps
            advance_wizard_step(dashboard, ws)
        else
            # Final step - confirm and create model
            if ws.confirmed
                create_model_from_wizard(dashboard, ws)
            else
                ws.confirmed = true
                add_event!(dashboard, :info, "Press Enter again to create the model")
            end
        end
    elseif key == "\x08" || key == "\x7f"  # Backspace - go back
        if ws.step > 1
            ws.step -= 1
            update_wizard_fields_for_step(ws)
            add_event!(dashboard, :info, "Wizard step $(ws.step)/$(ws.total_steps)")
        end
    elseif ws.step == 1 && length(key) == 1 && (isalnum(key[1]) || key[1] == '_' || key[1] == '-')
        # Model name input
        ws.model_name *= key
    elseif ws.step == 1 && (key == "\x08" || key == "\x7f")  # Backspace in name field
        if length(ws.model_name) > 0
            ws.model_name = ws.model_name[1:end-1]
        end
    elseif ws.step == 2  # Model type selection
        handle_wizard_arrow_key(ws, key)
    elseif ws.step == 3  # Parameters
        handle_parameter_input(ws, key)
    elseif ws.step == 4  # Feature settings
        handle_feature_input(ws, key)
    elseif ws.step == 5  # Training settings  
        handle_training_input(ws, key)
    end
end

function navigate_wizard_field(ws::ModelWizardState, direction::Symbol)
    if direction == :next
        ws.current_field = min(ws.current_field + 1, ws.max_fields)
    elseif direction == :prev
        ws.current_field = max(ws.current_field - 1, 1)
    end
end

function advance_wizard_step(dashboard::TournamentDashboard, ws::ModelWizardState)
    # Validate current step
    if ws.step == 1 && isempty(strip(ws.model_name))
        add_event!(dashboard, :warning, "Please enter a model name")
        return
    end
    
    ws.step += 1
    update_wizard_fields_for_step(ws)
    add_event!(dashboard, :info, "Wizard step $(ws.step)/$(ws.total_steps)")
end

function update_wizard_fields_for_step(ws::ModelWizardState)
    if ws.step == 1
        ws.max_fields = 1  # Just the name field
    elseif ws.step == 2
        ws.max_fields = length(ws.model_type_options)
    elseif ws.step == 3
        # Different parameters based on model type
        if ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]
            ws.max_fields = 4  # learning_rate, max_depth, feature_fraction, num_rounds
        elseif ws.model_type in ["MLP", "ResNet"]
            ws.max_fields = 2  # learning_rate, epochs
        else  # Linear models
            ws.max_fields = 1  # just learning_rate (alpha)
        end
    elseif ws.step == 4
        ws.max_fields = 3  # neutralize, neutralize_proportion, feature_set
    elseif ws.step == 5
        ws.max_fields = 3  # validation_split, early_stopping, gpu_enabled
    else
        ws.max_fields = 1  # confirmation
    end
    ws.current_field = 1
end

function handle_wizard_arrow_key(ws::ModelWizardState, key::String)
    if ws.step == 2  # Model type selection
        if key == "\e[A"  # Up arrow
            ws.selected_type_index = max(1, ws.selected_type_index - 1)
            ws.model_type = ws.model_type_options[ws.selected_type_index]
        elseif key == "\e[B"  # Down arrow
            ws.selected_type_index = min(length(ws.model_type_options), ws.selected_type_index + 1)
            ws.model_type = ws.model_type_options[ws.selected_type_index]
        end
    elseif ws.step == 4 && ws.current_field == 3  # Feature set selection
        if key == "\e[A"  # Up arrow
            ws.selected_feature_index = max(1, ws.selected_feature_index - 1)
            ws.feature_set = ws.feature_set_options[ws.selected_feature_index]
        elseif key == "\e[B"  # Down arrow
            ws.selected_feature_index = min(length(ws.feature_set_options), ws.selected_feature_index + 1)
            ws.feature_set = ws.feature_set_options[ws.selected_feature_index]
        end
    end
end

function handle_parameter_input(ws::ModelWizardState, key::String)
    # Handle numeric parameter inputs with arrow keys
    if key == "↑" || key == "\e[A"  # Up arrow - increase value
        if ws.current_field == 1  # learning_rate
            ws.learning_rate = min(1.0, ws.learning_rate * 1.5)
        elseif ws.current_field == 2 && ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]  # max_depth
            ws.max_depth = min(20, ws.max_depth + 1)
        elseif ws.current_field == 3 && ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]  # feature_fraction
            ws.feature_fraction = min(1.0, round(ws.feature_fraction + 0.1, digits=1))
        elseif ws.current_field == 4 && ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]  # num_rounds
            ws.num_rounds = min(5000, ws.num_rounds + 50)
        elseif ws.current_field == 2 && ws.model_type in ["MLP", "ResNet"]  # epochs
            ws.epochs = min(1000, ws.epochs + 10)
        end
    elseif key == "↓" || key == "\e[B"  # Down arrow - decrease value
        if ws.current_field == 1  # learning_rate
            ws.learning_rate = max(0.001, ws.learning_rate / 1.5)
        elseif ws.current_field == 2 && ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]  # max_depth
            ws.max_depth = max(1, ws.max_depth - 1)
        elseif ws.current_field == 3 && ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]  # feature_fraction
            ws.feature_fraction = max(0.1, round(ws.feature_fraction - 0.1, digits=1))
        elseif ws.current_field == 4 && ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]  # num_rounds
            ws.num_rounds = max(10, ws.num_rounds - 50)
        elseif ws.current_field == 2 && ws.model_type in ["MLP", "ResNet"]  # epochs
            ws.epochs = max(10, ws.epochs - 10)
        end
    end
end

function handle_feature_input(ws::ModelWizardState, key::String)
    if ws.current_field == 1  # neutralize toggle
        if key == " "  # Space to toggle
            ws.neutralize = !ws.neutralize
        end
    elseif ws.current_field == 3  # feature set
        handle_wizard_arrow_key(ws, key)
    end
end

function handle_training_input(ws::ModelWizardState, key::String)
    if ws.current_field == 1  # validation_split
        if key == "↑" || key == "\e[A"  # Up arrow
            ws.validation_split = min(0.5, round(ws.validation_split + 0.05, digits=2))
        elseif key == "↓" || key == "\e[B"  # Down arrow
            ws.validation_split = max(0.1, round(ws.validation_split - 0.05, digits=2))
        end
    elseif ws.current_field == 2  # early_stopping toggle
        if key == " "  # Space to toggle
            ws.early_stopping = !ws.early_stopping
        end
    elseif ws.current_field == 3  # gpu_enabled toggle
        if key == " "  # Space to toggle
            ws.gpu_enabled = !ws.gpu_enabled
        end
    end
end

function create_model_from_wizard(dashboard::TournamentDashboard, ws::ModelWizardState)
    """Create and save model configuration from wizard state"""
    try
        # Create model configuration dictionary
        model_config = Dict{String, Any}(
            "name" => ws.model_name,
            "type" => ws.model_type,
            "parameters" => create_model_parameters(ws),
            "feature_settings" => Dict{String, Any}(
                "feature_set" => ws.feature_set,
                "neutralize" => ws.neutralize,
                "neutralize_proportion" => ws.neutralize_proportion
            ),
            "training_settings" => Dict{String, Any}(
                "validation_split" => ws.validation_split,
                "early_stopping" => ws.early_stopping,
                "gpu_enabled" => ws.gpu_enabled
            )
        )
        
        # Save to models.json or similar configuration file
        save_model_configuration(model_config)
        
        # Add the new model to dashboard
        new_model = Dict(
            :name => ws.model_name,
            :type => ws.model_type,
            :is_active => false,
            :corr => 0.0,
            :mmc => 0.0,
            :fnc => 0.0,
            :sharpe => 0.0,
            :tc => 0.0
        )
        push!(dashboard.models, new_model)
        
        dashboard.wizard_active = false
        dashboard.wizard_state = nothing
        
        add_event!(dashboard, :success, "✅ Model '$(ws.model_name)' created successfully!")
        add_event!(dashboard, :info, "Use /train command to start training the new model")
        
    catch e
        add_event!(dashboard, :error, "Failed to create model: $e")
    end
end

function create_model_parameters(ws::ModelWizardState)
    """Create parameter dictionary based on model type and wizard settings"""
    if ws.model_type == "XGBoost"
        return Dict{String, Any}(
            "learning_rate" => ws.learning_rate,
            "max_depth" => ws.max_depth,
            "subsample" => ws.feature_fraction,
            "num_boost_round" => ws.num_rounds,
            "objective" => "reg:squarederror"
        )
    elseif ws.model_type == "LightGBM"
        return Dict{String, Any}(
            "learning_rate" => ws.learning_rate,
            "max_depth" => ws.max_depth,
            "feature_fraction" => ws.feature_fraction,
            "num_iterations" => ws.num_rounds,
            "objective" => "regression"
        )
    elseif ws.model_type == "CatBoost"
        return Dict{String, Any}(
            "learning_rate" => ws.learning_rate,
            "depth" => ws.max_depth,
            "rsm" => ws.feature_fraction,
            "iterations" => ws.num_rounds,
            "loss_function" => "RMSE"
        )
    elseif ws.model_type == "EvoTrees"
        return Dict{String, Any}(
            "learning_rate" => ws.learning_rate,
            "max_depth" => ws.max_depth,
            "subsample" => ws.feature_fraction,
            "nrounds" => ws.num_rounds
        )
    elseif ws.model_type in ["MLP", "ResNet"]
        return Dict{String, Any}(
            "learning_rate" => ws.learning_rate,
            "epochs" => ws.epochs,
            "batch_size" => 1024,
            "hidden_layers" => ws.model_type == "MLP" ? [256, 128, 64] : [512, 256, 128]
        )
    else  # Linear models
        return Dict{String, Any}(
            "alpha" => ws.learning_rate  # regularization parameter
        )
    end
end

function save_model_configuration(model_config::Dict{String, Any})
    """Save model configuration to models.json file"""
    models_file = "models.json"
    
    # Load existing models or create new array
    existing_models = if isfile(models_file)
        try
            JSON3.read(read(models_file, String))
        catch
            []
        end
    else
        []
    end
    
    # Add new model
    push!(existing_models, model_config)
    
    # Save back to file
    open(models_file, "w") do io
        JSON3.pretty(io, existing_models)
    end
end

function render_wizard(dashboard::TournamentDashboard)
    """Render the model creation wizard interface"""
    if !dashboard.wizard_active || isnothing(dashboard.wizard_state)
        return ""
    end
    
    ws = dashboard.wizard_state
    
    # Create wizard frame
    wizard_content = []
    
    # Title
    push!(wizard_content, "")
    push!(wizard_content, "╔═══════════════════════════════════════════════════════════════════╗")
    push!(wizard_content, "║                    🧙 New Model Creation Wizard                  ║")
    push!(wizard_content, "║                         Step $(ws.step)/$(ws.total_steps)                           ║")
    push!(wizard_content, "╠═══════════════════════════════════════════════════════════════════╣")
    
    # Step-specific content
    if ws.step == 1
        push!(wizard_content, "║ Step 1: Model Name                                               ║")
        push!(wizard_content, "║ Enter a unique name for your model:                             ║")
        push!(wizard_content, "║                                                                   ║")
        name_display = isempty(ws.model_name) ? "_" : ws.model_name
        push!(wizard_content, "║ Name: $(name_display)$(repeat(" ", 50-length(name_display))) ║")
        push!(wizard_content, "║                                                                   ║")
        push!(wizard_content, "║ Press Enter when ready to continue                              ║")
        
    elseif ws.step == 2
        push!(wizard_content, "║ Step 2: Model Type Selection                                     ║")
        push!(wizard_content, "║ Use ↑/↓ arrows to select model type:                            ║")
        push!(wizard_content, "║                                                                   ║")
        
        for (i, model_type) in enumerate(ws.model_type_options)
            marker = i == ws.selected_type_index ? "►" : " "
            push!(wizard_content, "║ $(marker) $(model_type)$(repeat(" ", 60-length(model_type))) ║")
        end
        
    elseif ws.step == 3
        push!(wizard_content, "║ Step 3: Model Parameters                                         ║")
        push!(wizard_content, "║ Current model: $(ws.model_type)$(repeat(" ", 50-length(ws.model_type))) ║")
        push!(wizard_content, "║ Use ↑/↓ arrows to adjust values, Tab to navigate               ║")
        push!(wizard_content, "║                                                                   ║")
        
        if ws.model_type in ["XGBoost", "LightGBM", "CatBoost", "EvoTrees"]
            lr_marker = ws.current_field == 1 ? "►" : " "
            depth_marker = ws.current_field == 2 ? "►" : " "
            frac_marker = ws.current_field == 3 ? "►" : " "
            rounds_marker = ws.current_field == 4 ? "►" : " "
            push!(wizard_content, "║$(lr_marker) Learning Rate: $(round(ws.learning_rate, digits=4))$(repeat(" ", 38-length(string(round(ws.learning_rate, digits=4))))) ║")
            push!(wizard_content, "║$(depth_marker) Max Depth: $(ws.max_depth)$(repeat(" ", 48-length(string(ws.max_depth)))) ║")
            push!(wizard_content, "║$(frac_marker) Feature Fraction: $(ws.feature_fraction)$(repeat(" ", 41-length(string(ws.feature_fraction)))) ║")
            push!(wizard_content, "║$(rounds_marker) Num Rounds: $(ws.num_rounds)$(repeat(" ", 46-length(string(ws.num_rounds)))) ║")
        elseif ws.model_type in ["MLP", "ResNet"]
            lr_marker = ws.current_field == 1 ? "►" : " "
            epochs_marker = ws.current_field == 2 ? "►" : " "
            push!(wizard_content, "║$(lr_marker) Learning Rate: $(round(ws.learning_rate, digits=4))$(repeat(" ", 38-length(string(round(ws.learning_rate, digits=4))))) ║")
            push!(wizard_content, "║$(epochs_marker) Epochs: $(ws.epochs)$(repeat(" ", 50-length(string(ws.epochs)))) ║")
        else
            lr_marker = ws.current_field == 1 ? "►" : " "
            push!(wizard_content, "║$(lr_marker) Alpha (regularization): $(round(ws.learning_rate, digits=4))$(repeat(" ", 29-length(string(round(ws.learning_rate, digits=4))))) ║")
        end
        
    elseif ws.step == 4
        push!(wizard_content, "║ Step 4: Feature Settings                                         ║")
        push!(wizard_content, "║ Use Space to toggle, Tab to navigate, ↑/↓ for feature set        ║")
        push!(wizard_content, "║                                                                   ║")
        
        neutralize_marker = ws.current_field == 1 ? "►" : " "
        neutralize_status = ws.neutralize ? "✓ Enabled" : "✗ Disabled"
        push!(wizard_content, "║$(neutralize_marker) Neutralization: $(neutralize_status)$(repeat(" ", 44-length(neutralize_status))) ║")
        
        if ws.neutralize
            prop_marker = ws.current_field == 2 ? "►" : " "
            push!(wizard_content, "║$(prop_marker) Neutralize Proportion: $(ws.neutralize_proportion)$(repeat(" ", 36-length(string(ws.neutralize_proportion)))) ║")
        end
        
        push!(wizard_content, "║                                                                   ║")
        feature_set_marker = ws.current_field == 3 ? "►" : " "
        push!(wizard_content, "║$(feature_set_marker) Feature Set:                                                ║")
        
        for (i, feature_set) in enumerate(ws.feature_set_options)
            marker = i == ws.selected_feature_index ? "►" : " "
            feature_desc = feature_set == "small" ? "~300 features" : 
                          feature_set == "medium" ? "~1000 features" : "~5000 features"
            display_text = "$(feature_set) ($(feature_desc))"
            push!(wizard_content, "║   $(marker) $(display_text)$(repeat(" ", 58-length(display_text))) ║")
        end
        
    elseif ws.step == 5
        push!(wizard_content, "║ Step 5: Training Settings                                        ║")
        push!(wizard_content, "║ Use ↑/↓ to adjust validation split, Space to toggle options       ║")
        push!(wizard_content, "║                                                                   ║")
        
        val_marker = ws.current_field == 1 ? "►" : " "
        push!(wizard_content, "║$(val_marker) Validation Split: $(ws.validation_split)$(repeat(" ", 42-length(string(ws.validation_split)))) ║")
        
        early_marker = ws.current_field == 2 ? "►" : " "
        early_stop_status = ws.early_stopping ? "✓ Enabled" : "✗ Disabled"
        push!(wizard_content, "║$(early_marker) Early Stopping: $(early_stop_status)$(repeat(" ", 45-length(early_stop_status))) ║")
        
        gpu_marker = ws.current_field == 3 ? "►" : " "
        gpu_status = ws.gpu_enabled ? "✓ Enabled" : "✗ Disabled"
        push!(wizard_content, "║$(gpu_marker) GPU Acceleration: $(gpu_status)$(repeat(" ", 43-length(gpu_status))) ║")
        
    elseif ws.step == 6
        push!(wizard_content, "║ Step 6: Confirmation                                            ║")
        push!(wizard_content, "║                                                                   ║")
        push!(wizard_content, "║ Model Configuration Summary:                                     ║")
        push!(wizard_content, "║ • Name: $(ws.model_name)$(repeat(" ", 54-length(ws.model_name))) ║")
        push!(wizard_content, "║ • Type: $(ws.model_type)$(repeat(" ", 54-length(ws.model_type))) ║")
        push!(wizard_content, "║ • Feature Set: $(ws.feature_set)$(repeat(" ", 47-length(ws.feature_set))) ║")
        push!(wizard_content, "║ • Neutralization: $(ws.neutralize ? "Yes" : "No")$(repeat(" ", 46)) ║")
        push!(wizard_content, "║ • GPU: $(ws.gpu_enabled ? "Yes" : "No")$(repeat(" ", 53)) ║")
        push!(wizard_content, "║                                                                   ║")
        
        if ws.confirmed
            push!(wizard_content, "║ ✅ Ready to create! Press Enter to confirm                      ║")
        else
            push!(wizard_content, "║ Press Enter to create this model                                ║")
        end
    end
    
    # Footer
    push!(wizard_content, "╠═══════════════════════════════════════════════════════════════════╣")
    push!(wizard_content, "║ Controls: Tab/Shift+Tab=Navigate, ↑/↓=Select, Space=Toggle      ║")
    push!(wizard_content, "║ Enter=Next/Confirm, Backspace=Previous, ESC=Cancel              ║")
    push!(wizard_content, "╚═══════════════════════════════════════════════════════════════════╝")
    
    return join(wizard_content, "\n")
end

export TournamentDashboard, run_dashboard, add_event!, start_training, save_performance_history, load_performance_history!, get_performance_summary,
       get_error_summary, reset_error_tracking!, get_error_trends, check_network_connectivity,
       categorize_error, get_user_friendly_message, get_severity_icon, render_recovery_mode,
       get_system_diagnostics, get_configuration_status, discover_local_data_files, get_last_known_good_state,
       save_last_known_good_state, get_detailed_network_status, get_troubleshooting_suggestions,
       test_network_connectivity, check_configuration_files, download_tournament_data,
       view_detailed_error_logs, save_diagnostic_report,
       # Callback integration functions
       create_dashboard_training_callback, complete_training!,
       # Model wizard functions
       start_model_wizard, handle_wizard_input, render_wizard,
       # Full pipeline function
       run_full_pipeline,
       # Sticky panel functions
       render_sticky_dashboard, render_top_sticky_panel, render_bottom_sticky_panel,
       # System info functions
       update_system_info!,
       # Command execution functions
       execute_command, download_data_internal, train_models_internal, submit_predictions_internal,
       # Types and structs
       ModelInfo, ChartPoint, EventLevel, EventEntry, SystemStatus,
       StatusLevel, ProgressTracker, DashboardConfig, CategorizedError, ModelWizardState

end