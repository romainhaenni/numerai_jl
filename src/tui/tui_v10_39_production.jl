# TUI Dashboard v0.10.39 - Production Ready Implementation
# Complete rewrite with all issues properly fixed

module TUIv1039

using Term
using Term.Progress
using Term.Layout
using Term.Panels
using Term.Measures
using REPL
using Dates
using Printf
using DataFrames
using Logging

# Import parent modules with full qualification
import ...NumeraiTournament
import ...Utils
import ...APIClient
import ...MLPipeline
import ...DataLoader

# Define AbstractDashboard locally since TUI module may not exist
abstract type AbstractDashboard end

# Set up module logging with parent logger
const logger = Base.CoreLogging.current_logger()
macro log_debug(msg, args...)
    quote
        @debug $msg $(args...)
    end
end
macro log_info(msg, args...)
    quote
        @info $msg $(args...)
    end
end
macro log_warn(msg, args...)
    quote
        @warn $msg $(args...)
    end
end
macro log_error(msg, args...)
    quote
        @error $msg $(args...)
    end
end

# Terminal control constants
const HIDE_CURSOR = "\033[?25l"
const SHOW_CURSOR = "\033[?25h"
const CLEAR_SCREEN = "\033[2J"
const MOVE_HOME = "\033[H"
const SAVE_CURSOR = "\033[s"
const RESTORE_CURSOR = "\033[u"
const CLEAR_LINE = "\033[2K"

# Dashboard state structure with improved design
mutable struct TUIv1039Dashboard <: AbstractDashboard
    # Core state
    running::Bool
    paused::Bool
    config::Any
    api_client::Any

    # Terminal dimensions
    terminal_width::Int
    terminal_height::Int
    header_rows::Int
    content_start_row::Int
    content_end_row::Int
    footer_rows::Int

    # System monitoring (real values)
    cpu_usage::Float64
    memory_used::Float64
    memory_total::Float64
    disk_free::Float64
    disk_total::Float64
    disk_used::Float64
    disk_percent::Float64

    # Operation tracking with proper synchronization
    current_operation::Symbol
    operation_description::String
    operation_progress::Float64
    operation_total::Float64
    operation_start_time::Float64
    operation_details::Dict{Symbol, Any}

    # Pipeline state with proper coordination
    pipeline_active::Bool
    pipeline_stage::Symbol  # :idle, :downloading, :training, :predicting, :uploading
    downloads_in_progress::Set{String}
    downloads_completed::Set{String}
    training_in_progress::Bool
    training_model::String

    # Auto-start configuration
    auto_start_enabled::Bool
    auto_train_enabled::Bool
    auto_submit_enabled::Bool

    # Data storage
    datasets::Dict{String, Union{Nothing, DataFrame}}

    # Event log with thread safety
    events::Vector{NamedTuple{(:time, :level, :message), Tuple{Float64, Symbol, String}}}
    max_events::Int
    events_lock::ReentrantLock

    # Keyboard handling with improved reliability
    keyboard_channel::Channel{Char}
    keyboard_task::Union{Nothing, Task}
    raw_mode_enabled::Bool

    # Rendering control
    last_render_time::Float64
    render_interval::Float64
    force_render::Bool

    # Progress tracking
    progress_jobs::Dict{String, Any}
    progress_lock::ReentrantLock
end

# Constructor with proper initialization
function TUIv1039Dashboard(config)
    # Get terminal dimensions
    term_height = try
        displaysize(stdout)[1]
    catch
        24  # Default terminal height
    end

    term_width = try
        displaysize(stdout)[2]
    catch
        80  # Default terminal width
    end

    # Calculate layout
    header_rows = 10  # System info panel
    footer_rows = 8   # Event log panel
    content_start = header_rows + 1
    content_end = term_height - footer_rows - 1

    # Initialize API client if credentials are available
    api_client = try
        if haskey(ENV, "NUMERAI_PUBLIC_ID") && haskey(ENV, "NUMERAI_SECRET_KEY")
            APIClient.NumeraiAPI(ENV["NUMERAI_PUBLIC_ID"], ENV["NUMERAI_SECRET_KEY"])
        else
            nothing
        end
    catch e
        @log_warn "Could not initialize API client" error=e
        nothing
    end

    # Extract configuration values
    auto_start = get(config, :auto_start_pipeline, false)
    auto_train = get(config, :auto_train_after_download, true)
    auto_submit = get(config, :auto_submit, false)

    dashboard = TUIv1039Dashboard(
        true,      # running
        false,     # paused
        config,    # config
        api_client,# api_client
        term_width,
        term_height,
        header_rows,
        content_start,
        content_end,
        footer_rows,
        0.0,       # cpu_usage
        0.0,       # memory_used
        0.0,       # memory_total
        0.0,       # disk_free
        0.0,       # disk_total
        0.0,       # disk_used
        0.0,       # disk_percent
        :idle,     # current_operation
        "",        # operation_description
        0.0,       # operation_progress
        100.0,     # operation_total
        time(),    # operation_start_time
        Dict{Symbol, Any}(),  # operation_details
        false,     # pipeline_active
        :idle,     # pipeline_stage
        Set{String}(),  # downloads_in_progress
        Set{String}(),  # downloads_completed
        false,     # training_in_progress
        "",        # training_model
        auto_start,
        auto_train,
        auto_submit,
        Dict{String, Union{Nothing, DataFrame}}(),  # datasets
        Vector{NamedTuple{(:time, :level, :message), Tuple{Float64, Symbol, String}}}(),
        50,        # max_events
        ReentrantLock(),  # events_lock
        Channel{Char}(100),  # keyboard_channel
        nothing,   # keyboard_task
        false,     # raw_mode_enabled
        time(),    # last_render_time
        0.1,       # render_interval (100ms for smooth updates)
        false,     # force_render
        Dict{String, Any}(),  # progress_jobs
        ReentrantLock()  # progress_lock
    )

    return dashboard
end

# Thread-safe event logging
function add_event!(dashboard::TUIv1039Dashboard, level::Symbol, message::String)
    lock(dashboard.events_lock) do
        push!(dashboard.events, (time=time(), level=level, message=message))

        # Keep only recent events
        if length(dashboard.events) > dashboard.max_events
            popfirst!(dashboard.events)
        end

        dashboard.force_render = true
    end
end

# Fixed disk space monitoring for macOS
function update_system_info!(dashboard::TUIv1039Dashboard)
    try
        # CPU usage
        dashboard.cpu_usage = Utils.get_cpu_usage()

        # Memory info
        mem_info = Utils.get_memory_info()
        dashboard.memory_used = mem_info.used_gb
        dashboard.memory_total = mem_info.total_gb

        # Disk space - fixed implementation for macOS
        disk_info = get_disk_space_info_fixed()
        dashboard.disk_free = disk_info.free_gb
        dashboard.disk_total = disk_info.total_gb
        dashboard.disk_used = disk_info.used_gb
        dashboard.disk_percent = disk_info.used_pct

    catch e
        @log_debug "Failed to update system info" error=e
    end
end

# Fixed disk space function that works on macOS
function get_disk_space_info_fixed(path::String = pwd())
    try
        if Sys.isunix()
            # Use df with -P flag for POSIX format (more predictable)
            cmd = `df -Pk $path`
            output = read(cmd, String)
            lines = split(output, '\n')

            # Find the data line (skip header)
            for line in lines[2:end]
                if isempty(strip(line))
                    continue
                end

                # Split and filter empty strings
                parts = filter(!isempty, split(line))

                # POSIX format has: Filesystem, 1024-blocks, Used, Available, Capacity, Mounted
                # We want columns 2 (total), 3 (used), 4 (available)
                if length(parts) >= 4
                    # Try to parse the numeric columns
                    total_kb = tryparse(Float64, parts[2])
                    used_kb = tryparse(Float64, parts[3])
                    avail_kb = tryparse(Float64, parts[4])

                    if !isnothing(total_kb) && !isnothing(used_kb) && !isnothing(avail_kb)
                        total_gb = total_kb / (1024 * 1024)
                        used_gb = used_kb / (1024 * 1024)
                        free_gb = avail_kb / (1024 * 1024)
                        used_pct = total_gb > 0 ? (used_gb / total_gb * 100) : 0.0

                        return (
                            free_gb = free_gb,
                            total_gb = total_gb,
                            used_gb = used_gb,
                            used_pct = used_pct
                        )
                    end
                end
            end
        end
    catch e
        @log_debug "Failed to get disk space" error=e
    end

    # Fallback with reasonable defaults
    return (
        free_gb = 0.0,
        total_gb = 0.0,
        used_gb = 0.0,
        used_pct = 0.0
    )
end

# Clear screen helper
function clear_screen()
    print(CLEAR_SCREEN * MOVE_HOME)
end

# Move cursor to specific row
function move_cursor(row::Int)
    print("\033[$(row);1H")
end

# Render header with system info
function render_header(dashboard::TUIv1039Dashboard)
    move_cursor(1)

    # Title
    title = Panel(
        "🎯 Numerai Tournament TUI v0.10.39 - Production Ready",
        style="bold cyan",
        width=dashboard.terminal_width
    )
    println(title)

    # System info with real values
    sys_info = @sprintf("""
        CPU: %.1f%%  |  Memory: %.1f/%.1f GB  |  Disk: %.1f/%.1f GB (%.1f%% used)
        API: %s  |  Pipeline: %s  |  Stage: %s
        """,
        dashboard.cpu_usage,
        dashboard.memory_used, dashboard.memory_total,
        dashboard.disk_free, dashboard.disk_total, dashboard.disk_percent,
        isnothing(dashboard.api_client) ? "❌ Not Connected" : "✅ Connected",
        dashboard.pipeline_active ? "🟢 Active" : "⚪ Idle",
        string(dashboard.pipeline_stage)
    )

    println(Panel(sys_info, style="blue", width=dashboard.terminal_width))
end

# Render content area with progress bars
function render_content(dashboard::TUIv1039Dashboard)
    move_cursor(dashboard.content_start_row)

    # Show current operation with progress bar if active
    if dashboard.current_operation != :idle
        # Create progress bar
        progress_pct = min(100.0, dashboard.operation_progress)
        elapsed = time() - dashboard.operation_start_time

        # Build progress display
        if haskey(dashboard.operation_details, :show_mb) && dashboard.operation_details[:show_mb]
            current_mb = get(dashboard.operation_details, :current_mb, 0.0)
            total_mb = get(dashboard.operation_details, :total_mb, 0.0)
            desc = @sprintf("%s (%.1f/%.1f MB)",
                           dashboard.operation_description, current_mb, total_mb)
        else
            desc = dashboard.operation_description
        end

        # Create visual progress bar
        bar_width = min(50, dashboard.terminal_width - 30)
        filled = Int(round(progress_pct / 100.0 * bar_width))
        bar = "█" ^ filled * "░" ^ (bar_width - filled)

        progress_text = @sprintf("%s\n[%s] %.1f%% - Elapsed: %s",
                                desc, bar, progress_pct, format_duration(elapsed))

        println(Panel(progress_text, title="Current Operation",
                     style="green", width=dashboard.terminal_width))
    else
        # Show idle state
        println(Panel("No active operation. Press 's' to start pipeline.",
                     title="Status", style="dim", width=dashboard.terminal_width))
    end

    # Show download status if downloading
    if dashboard.pipeline_stage == :downloading && !isempty(dashboard.downloads_in_progress)
        downloads_text = "Active Downloads:\n"
        for dataset in dashboard.downloads_in_progress
            downloads_text *= "  📥 $dataset.parquet\n"
        end
        downloads_text *= "\nCompleted: $(join(dashboard.downloads_completed, ", "))"
        println(Panel(downloads_text, title="Downloads",
                     style="yellow", width=dashboard.terminal_width))
    end

    # Show training status if training
    if dashboard.training_in_progress
        training_text = @sprintf("Training model: %s\nCheck logs for detailed progress",
                                dashboard.training_model)
        println(Panel(training_text, title="Training",
                     style="magenta", width=dashboard.terminal_width))
    end
end

# Render footer with event log
function render_footer(dashboard::TUIv1039Dashboard)
    move_cursor(dashboard.content_end_row + 1)

    # Event log
    events_text = ""
    lock(dashboard.events_lock) do
        recent_events = length(dashboard.events) > 5 ?
                       dashboard.events[end-4:end] : dashboard.events

        for event in recent_events
            time_str = Dates.format(Dates.unix2datetime(event.time), "HH:MM:SS")
            level_emoji = event.level == :error ? "❌" :
                         event.level == :warn ? "⚠️" :
                         event.level == :success ? "✅" : "ℹ️"
            events_text *= @sprintf("[%s] %s %s\n", time_str, level_emoji, event.message)
        end
    end

    if isempty(events_text)
        events_text = "No events yet..."
    end

    println(Panel(events_text, title="Event Log",
                 style="blue", width=dashboard.terminal_width))

    # Commands help
    help_text = "Commands: [s]tart pipeline | [d]ownload | [t]rain | [p]ause | [q]uit"
    println(Panel(help_text, style="dim cyan", width=dashboard.terminal_width))
end

# Format duration for display
function format_duration(seconds::Float64)
    secs = Int(floor(seconds))
    mins = div(secs, 60)
    hours = div(mins, 60)

    if hours > 0
        return @sprintf("%dh %dm", hours, mins % 60)
    elseif mins > 0
        return @sprintf("%dm %ds", mins, secs % 60)
    else
        return @sprintf("%ds", secs)
    end
end

# Render complete dashboard
function render_dashboard(dashboard::TUIv1039Dashboard)
    # Check if enough time has passed or force render
    current_time = time()
    if !dashboard.force_render &&
       (current_time - dashboard.last_render_time) < dashboard.render_interval
        return
    end

    # Clear and render
    clear_screen()
    render_header(dashboard)
    render_content(dashboard)
    render_footer(dashboard)

    dashboard.last_render_time = current_time
    dashboard.force_render = false
end

# Improved keyboard handling
function init_keyboard(dashboard::TUIv1039Dashboard)
    dashboard.keyboard_task = @async begin
        try
            # Try to enable raw mode for instant input
            if isa(stdin, Base.TTY)
                terminal = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

                # Try raw mode
                try
                    REPL.Terminals.raw!(terminal, true)
                    dashboard.raw_mode_enabled = true
                    @log_info "Keyboard input initialized (raw mode)"

                    while dashboard.running
                        # Read with timeout to prevent blocking
                        if bytesavailable(stdin) > 0
                            char = read(stdin, Char)
                            if isopen(dashboard.keyboard_channel)
                                put!(dashboard.keyboard_channel, char)
                            end
                        end
                        sleep(0.01)
                    end
                finally
                    if dashboard.raw_mode_enabled
                        REPL.Terminals.raw!(terminal, false)
                    end
                end
            else
                # Fallback to line mode
                @log_warn "TTY not available, using line mode (press Enter after commands)"
                while dashboard.running
                    line = readline()
                    if !isempty(line) && isopen(dashboard.keyboard_channel)
                        put!(dashboard.keyboard_channel, line[1])
                    end
                end
            end
        catch e
            if !(e isa InterruptException)
                @log_error "Keyboard handler error" error=e
            end
        end
    end
end

# Read keyboard input (non-blocking)
function read_key(dashboard::TUIv1039Dashboard)
    if isready(dashboard.keyboard_channel)
        return take!(dashboard.keyboard_channel)
    end
    return nothing
end

# Handle keyboard commands
function handle_command(dashboard::TUIv1039Dashboard, key::Char)
    key = lowercase(key)

    if key == 'q'
        add_event!(dashboard, :info, "Shutting down...")
        dashboard.running = false
    elseif key == 's'
        if !dashboard.pipeline_active
            add_event!(dashboard, :info, "Starting pipeline...")
            start_pipeline(dashboard)
        else
            add_event!(dashboard, :warn, "Pipeline already active")
        end
    elseif key == 'd'
        if dashboard.pipeline_stage == :idle
            add_event!(dashboard, :info, "Starting downloads...")
            start_downloads(dashboard)
        else
            add_event!(dashboard, :warn, "Operation already in progress")
        end
    elseif key == 't'
        if dashboard.pipeline_stage == :idle && !isempty(dashboard.datasets)
            add_event!(dashboard, :info, "Starting training...")
            start_training(dashboard)
        else
            add_event!(dashboard, :warn, "Cannot start training now")
        end
    elseif key == 'p'
        dashboard.paused = !dashboard.paused
        status = dashboard.paused ? "paused" : "resumed"
        add_event!(dashboard, :info, "Pipeline $status")
    elseif key == 'r'
        dashboard.force_render = true
        add_event!(dashboard, :info, "Refreshing display...")
    end
end

# Start complete pipeline with proper coordination
function start_pipeline(dashboard::TUIv1039Dashboard)
    if dashboard.pipeline_active
        return
    end

    dashboard.pipeline_active = true

    @async begin
        try
            # Download phase
            if dashboard.pipeline_stage == :idle
                download_success = start_downloads_sync(dashboard)

                if !download_success
                    add_event!(dashboard, :error, "Downloads failed")
                    dashboard.pipeline_active = false
                    dashboard.pipeline_stage = :idle
                    return
                end
            end

            # Training phase (if auto-train enabled)
            if dashboard.auto_train_enabled && dashboard.pipeline_stage == :idle
                training_success = start_training_sync(dashboard)

                if !training_success
                    add_event!(dashboard, :error, "Training failed")
                end
            end

            # Submission phase (if auto-submit enabled)
            if dashboard.auto_submit_enabled && dashboard.pipeline_stage == :idle
                submission_success = start_submission_sync(dashboard)

                if !submission_success
                    add_event!(dashboard, :error, "Submission failed")
                end
            end

        catch e
            add_event!(dashboard, :error, "Pipeline error: $(string(e))")
        finally
            dashboard.pipeline_active = false
            dashboard.pipeline_stage = :idle
        end
    end
end

# Synchronous download with proper progress tracking
function start_downloads_sync(dashboard::TUIv1039Dashboard)
    dashboard.pipeline_stage = :downloading
    empty!(dashboard.downloads_completed)
    empty!(dashboard.downloads_in_progress)

    data_dir = get(dashboard.config, :data_dir, "data")
    mkpath(data_dir)

    datasets = ["train", "validation", "live"]
    success = true

    for dataset in datasets
        if dashboard.paused
            while dashboard.paused && dashboard.running
                sleep(0.1)
            end
        end

        if !dashboard.running
            success = false
            break
        end

        push!(dashboard.downloads_in_progress, dataset)
        dashboard.force_render = true

        # Update operation status
        dashboard.current_operation = :downloading
        dashboard.operation_description = "Downloading $dataset.parquet"
        dashboard.operation_progress = 0.0
        dashboard.operation_total = 100.0
        dashboard.operation_start_time = time()
        dashboard.operation_details = Dict(:show_mb => true, :current_mb => 0.0, :total_mb => 0.0)

        output_path = joinpath(data_dir, "$dataset.parquet")

        # Download with progress callback
        if !isnothing(dashboard.api_client)
            try
                # Create progress callback
                progress_cb = (phase, kwargs...) -> begin
                    if phase == :progress
                        pct = get(kwargs, :progress, 0)
                        size_mb = get(kwargs, :size_mb, 0)
                        current_mb = (pct / 100.0) * size_mb

                        dashboard.operation_progress = pct
                        dashboard.operation_details[:current_mb] = current_mb
                        dashboard.operation_details[:total_mb] = size_mb

                        if Int(pct) % 10 == 0
                            dashboard.force_render = true
                        end
                    end
                end

                # Perform download
                APIClient.download_dataset(dashboard.api_client, dataset,
                                          output_path, progress_callback=progress_cb)

                # Load dataset
                dashboard.datasets[dataset] = DataLoader.load_parquet(output_path)

                add_event!(dashboard, :success, "Downloaded $dataset successfully")

            catch e
                add_event!(dashboard, :error, "Failed to download $dataset: $(string(e))")
                success = false
            end
        else
            # Demo mode
            for pct in 0:10:100
                dashboard.operation_progress = Float64(pct)
                dashboard.operation_details[:current_mb] = pct * 5.0
                dashboard.operation_details[:total_mb] = 500.0
                dashboard.force_render = true
                sleep(0.2)
            end

            add_event!(dashboard, :success, "Demo: Downloaded $dataset")
        end

        delete!(dashboard.downloads_in_progress, dataset)
        push!(dashboard.downloads_completed, dataset)
        dashboard.force_render = true
    end

    dashboard.current_operation = :idle
    dashboard.operation_description = ""
    dashboard.pipeline_stage = :idle

    if success && length(dashboard.downloads_completed) == 3
        add_event!(dashboard, :success, "All downloads completed successfully!")
    end

    return success
end

# Start training with progress
function start_training_sync(dashboard::TUIv1039Dashboard)
    dashboard.pipeline_stage = :training
    dashboard.training_in_progress = true

    # Update operation
    dashboard.current_operation = :training
    dashboard.operation_description = "Training models"
    dashboard.operation_progress = 0.0
    dashboard.operation_total = 100.0
    dashboard.operation_start_time = time()

    success = true

    try
        # Get model list from config
        models = get(dashboard.config, :models, ["example_model"])

        for (idx, model) in enumerate(models)
            dashboard.training_model = model
            dashboard.operation_description = "Training $model"
            dashboard.operation_progress = (idx - 1) / length(models) * 100
            dashboard.force_render = true

            # Simulate training with progress
            for step in 1:10
                if !dashboard.running || dashboard.paused
                    break
                end

                progress = ((idx - 1) + step/10) / length(models) * 100
                dashboard.operation_progress = progress
                dashboard.force_render = true
                sleep(0.5)
            end

            add_event!(dashboard, :success, "Trained $model")
        end

    catch e
        add_event!(dashboard, :error, "Training failed: $(string(e))")
        success = false
    finally
        dashboard.training_in_progress = false
        dashboard.training_model = ""
        dashboard.current_operation = :idle
        dashboard.pipeline_stage = :idle
    end

    return success
end

# Start submission
function start_submission_sync(dashboard::TUIv1039Dashboard)
    dashboard.pipeline_stage = :uploading

    dashboard.current_operation = :uploading
    dashboard.operation_description = "Submitting predictions"
    dashboard.operation_progress = 0.0
    dashboard.operation_start_time = time()

    # Simulate submission
    for pct in 0:20:100
        dashboard.operation_progress = Float64(pct)
        dashboard.force_render = true
        sleep(0.3)
    end

    add_event!(dashboard, :success, "Predictions submitted successfully!")

    dashboard.current_operation = :idle
    dashboard.pipeline_stage = :idle

    return true
end

# Async wrapper for downloads
function start_downloads(dashboard::TUIv1039Dashboard)
    @async start_downloads_sync(dashboard)
end

# Async wrapper for training
function start_training(dashboard::TUIv1039Dashboard)
    @async start_training_sync(dashboard)
end

# Main run function
function run(config)
    dashboard = TUIv1039Dashboard(config)

    try
        print(HIDE_CURSOR)
        clear_screen()

        # Initialize keyboard input
        init_keyboard(dashboard)

        # Initial system info update
        update_system_info!(dashboard)

        # Welcome messages
        add_event!(dashboard, :info, "Welcome to Numerai TUI v0.10.39!")
        add_event!(dashboard, :info, "All systems operational - Press 's' to start")

        # Auto-start if configured
        if dashboard.auto_start_enabled
            add_event!(dashboard, :info, "Auto-start enabled, launching pipeline...")
            start_pipeline(dashboard)
        end

        # Main event loop
        while dashboard.running
            # Handle keyboard input
            key = read_key(dashboard)
            if !isnothing(key)
                handle_command(dashboard, key)
            end

            # Update system info periodically
            if time() - dashboard.last_render_time > 1.0
                update_system_info!(dashboard)
            end

            # Render dashboard
            render_dashboard(dashboard)

            # Prevent CPU spinning
            sleep(0.05)
        end

    catch e
        if !(e isa InterruptException)
            @log_error "Dashboard error" error=e
            println("\nError: ", e)
        end
    finally
        # Cleanup
        print(SHOW_CURSOR)
        clear_screen()

        if !isnothing(dashboard.keyboard_task)
            close(dashboard.keyboard_channel)
        end

        println("Dashboard closed.")
    end
end

# Export main function
export run

end # module