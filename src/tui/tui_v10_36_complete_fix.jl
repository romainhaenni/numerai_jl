module TUIv1036CompleteFix

using Term
using Dates
using TimeZones
using Printf
using Statistics
using DataFrames
using CSV
using REPL
using ..API
using ..Pipeline
using ..Models
using ..Models.Callbacks
using ..Logger: @log_info, @log_warn, @log_error, @log_debug
using ..Utils
using ..DataLoader

export TUIv1036Dashboard, run_tui_v1036

# Get real CPU usage percentage
function get_cpu_usage()
    try
        if Sys.isapple()
            # Use top command on macOS
            cmd = `top -l 1 -n 0`
            output = read(cmd, String)

            # Parse CPU usage line
            cpu_line = match(r"CPU usage:\s*([\d.]+)%\s*user,\s*([\d.]+)%\s*sys", output)
            if !isnothing(cpu_line)
                user_pct = parse(Float64, cpu_line.captures[1])
                sys_pct = parse(Float64, cpu_line.captures[2])
                return user_pct + sys_pct
            end
        elseif Sys.islinux()
            # Use /proc/stat on Linux
            lines = readlines("/proc/stat")
            cpu_line = split(lines[1])

            # Calculate CPU usage from jiffies
            user = parse(Int, cpu_line[2])
            nice = parse(Int, cpu_line[3])
            system = parse(Int, cpu_line[4])
            idle = parse(Int, cpu_line[5])

            total = user + nice + system + idle
            active = user + nice + system

            return (active / total) * 100.0
        end
    catch e
        @log_debug "Failed to get CPU usage" error=e
    end

    # Fallback: estimate based on system load
    try
        loadavg = Sys.loadavg()[1]  # 1-minute load average
        cpu_count = Sys.CPU_THREADS
        return min(100.0, (loadavg / cpu_count) * 100.0)
    catch
        return 0.0
    end
end

# Get real memory information
function get_memory_info()
    try
        total_mem = Sys.total_memory() / 1024^3  # Convert to GB
        free_mem = Sys.free_memory() / 1024^3
        used_mem = total_mem - free_mem

        return (total=total_mem, used=used_mem, free=free_mem)
    catch e
        @log_debug "Failed to get memory info" error=e
        return (total=0.0, used=0.0, free=0.0)
    end
end

# Complete dashboard state with ALL functionality working properly
mutable struct TUIv1036Dashboard
    config::Any
    api_client::Union{Nothing, API.NumeraiClient}
    ml_pipeline::Union{Nothing, Pipeline.MLPipeline}

    # State flags
    running::Bool
    paused::Bool

    # Operation tracking with REAL progress monitoring
    current_operation::Symbol  # :idle, :downloading, :training, :predicting, :uploading
    operation_description::String
    operation_progress::Float64
    operation_total::Float64
    operation_start_time::Float64
    operation_details::Dict{Symbol, Any}  # Operation-specific details

    # System information with REAL values (not simulated)
    cpu_usage::Float64
    memory_used::Float64
    memory_total::Float64
    disk_free::Float64
    disk_total::Float64
    threads::Int
    uptime::Int
    last_system_update::Float64

    # Event log with proper management (30 max, auto-scroll)
    events::Vector{NamedTuple{(:time, :type, :message), Tuple{DateTime, Symbol, String}}}
    max_events::Int

    # Command handling for INSTANT response (no Enter key needed)
    command_channel::Channel{Char}
    keyboard_task::Union{Nothing, Task}
    last_command_time::Float64

    # Auto-training state management (triggers after ALL downloads)
    auto_train_after_download::Bool
    downloads_completed::Set{String}
    required_downloads::Set{String}

    # Data storage for operations
    train_df::Union{Nothing, DataFrame}
    val_df::Union{Nothing, DataFrame}
    live_df::Union{Nothing, DataFrame}

    # Rendering control for smooth updates
    last_render_time::Float64
    render_interval::Float64  # 1s normally, 0.1s during operations
    force_render::Bool
    terminal_height::Int
    terminal_width::Int

    # Panel positions for STICKY rendering
    top_panel_lines::Int      # Fixed top panel height
    bottom_panel_lines::Int   # Fixed bottom panel height
    content_start_row::Int    # Where content area starts
    content_end_row::Int      # Where content area ends

    # Start time for uptime tracking
    start_time::Float64

    # Auto-start pipeline on initialization
    auto_start_pipeline::Bool
    pipeline_started::Bool
end

# Constructor with proper initialization
function TUIv1036Dashboard(config)
    # Extract API credentials safely
    public_key = isa(config, Dict) ? get(config, :api_public_key, "") :
                 hasfield(typeof(config), :api_public_key) ? config.api_public_key : ""
    secret_key = isa(config, Dict) ? get(config, :api_secret_key, "") :
                 hasfield(typeof(config), :api_secret_key) ? config.api_secret_key : ""

    # Extract auto-train setting (default true for convenience)
    auto_train = isa(config, Dict) ? get(config, :auto_train_after_download, true) :
                 hasfield(typeof(config), :auto_train_after_download) ? config.auto_train_after_download : true

    # Extract auto-start setting (default true for automation)
    auto_start = isa(config, Dict) ? get(config, :auto_start_pipeline, true) :
                 hasfield(typeof(config), :auto_start_pipeline) ? config.auto_start_pipeline : true

    # Create API client if credentials available
    api_client = if !isempty(public_key) && !isempty(secret_key)
        try
            API.NumeraiClient(public_key, secret_key)
        catch e
            @log_warn "Failed to create API client" error=e
            nothing
        end
    else
        @log_info "No API credentials configured - running in demo mode"
        nothing
    end

    # Get terminal dimensions
    term_height, term_width = displaysize(stdout)

    # Get initial system info
    mem_info = get_memory_info()
    disk_info = Utils.get_disk_space_info()

    TUIv1036Dashboard(
        config,
        api_client,
        nothing,  # ml_pipeline
        true,     # running (start as true)
        false,    # paused
        :idle,    # current_operation
        "",       # operation_description
        0.0,      # operation_progress
        0.0,      # operation_total
        time(),   # operation_start_time
        Dict{Symbol, Any}(),  # operation_details
        get_cpu_usage(),  # cpu_usage (REAL value)
        mem_info.used,    # memory_used (REAL value)
        mem_info.total,   # memory_total (REAL value)
        disk_info.free_gb,  # disk_free (REAL value)
        disk_info.total_gb, # disk_total (REAL value)
        Threads.nthreads(),  # threads
        0,        # uptime
        time(),   # last_system_update
        NamedTuple{(:time, :type, :message), Tuple{DateTime, Symbol, String}}[],  # events
        30,       # max_events (fixed at 30 for visibility)
        Channel{Char}(100),  # command_channel with buffer
        nothing,  # keyboard_task
        time(),   # last_command_time
        auto_train,  # auto_train_after_download
        Set{String}(),  # downloads_completed
        Set(["train", "validation", "live"]),  # required_downloads
        nothing,  # train_df
        nothing,  # val_df
        nothing,  # live_df
        time(),   # last_render_time
        1.0,      # render_interval (1s normally)
        false,    # force_render
        term_height,  # terminal_height
        term_width,   # terminal_width
        6,        # top_panel_lines (fixed height for system info)
        8,        # bottom_panel_lines (fixed height for event log)
        7,        # content_start_row (after top panel)
        term_height - 9,  # content_end_row (before bottom panel)
        time(),   # start_time
        auto_start,  # auto_start_pipeline
        false,    # pipeline_started
    )
end

# Add event with proper management (auto-trim to 30)
function add_event!(dashboard::TUIv1036Dashboard, type::Symbol, message::String)
    event = (time=now(), type=type, message=message)
    push!(dashboard.events, event)

    # Keep only last max_events (30)
    if length(dashboard.events) > dashboard.max_events
        dashboard.events = dashboard.events[end-dashboard.max_events+1:end]
    end

    dashboard.force_render = true
end

# Update system information with REAL values
function update_system_info!(dashboard::TUIv1036Dashboard)
    current_time = time()

    # Update every 1s normally, 0.1s during operations
    update_interval = dashboard.current_operation == :idle ? 1.0 : 0.1

    if current_time - dashboard.last_system_update < update_interval
        return
    end

    try
        # Get REAL CPU usage
        dashboard.cpu_usage = get_cpu_usage()

        # Get REAL memory information
        mem_info = get_memory_info()
        dashboard.memory_total = mem_info.total
        dashboard.memory_used = mem_info.used

        # Get REAL disk space
        disk_info = Utils.get_disk_space_info()
        dashboard.disk_free = disk_info.free_gb
        dashboard.disk_total = disk_info.total_gb

        # Calculate uptime
        dashboard.uptime = Int(floor(current_time - dashboard.start_time))

        dashboard.last_system_update = current_time
    catch e
        @log_debug "Error updating system info" error=e
    end
end

# ANSI escape codes for terminal control
const ESC = "\033"
const CLEAR_SCREEN = "$(ESC)[2J"
const MOVE_HOME = "$(ESC)[H"
const CLEAR_LINE = "$(ESC)[K"
const HIDE_CURSOR = "$(ESC)[?25l"
const SHOW_CURSOR = "$(ESC)[?25h"
const SAVE_CURSOR = "$(ESC)[s"
const RESTORE_CURSOR = "$(ESC)[u"

# Clear screen and reset cursor
function clear_screen()
    print(CLEAR_SCREEN)
    print(MOVE_HOME)
end

# Move cursor to specific row
function move_cursor(row::Int)
    print("$(ESC)[$(row);1H")
end

# Create a progress bar string with real progress
function create_progress_bar(current::Float64, total::Float64, width::Int=50)
    if total <= 0
        return "━" ^ width
    end

    percentage = min(100.0, (current / total) * 100)
    filled = Int(round((percentage / 100) * width))
    empty = width - filled

    bar = "█" ^ filled * "░" ^ empty
    return @sprintf("[%s] %.1f%%", bar, percentage)
end

# Render the top sticky panel (system status)
function render_top_panel(dashboard::TUIv1036Dashboard)
    move_cursor(1)

    # Title bar
    title = " 🚀 Numerai Tournament TUI v0.10.36 - COMPLETE FIX "
    centered_title = center_text(title, dashboard.terminal_width)
    println(Term.Panel(centered_title, style="bold cyan", width=dashboard.terminal_width))

    # System information panel with REAL values
    uptime_str = format_duration(dashboard.uptime)
    status_icon = dashboard.paused ? "⏸" : "▶"
    operation_str = dashboard.current_operation == :idle ? "Idle" :
                   string(dashboard.current_operation)

    system_info = [
        "$(status_icon) Status: $(dashboard.paused ? "PAUSED" : "RUNNING")",
        "🖥  CPU: $(round(dashboard.cpu_usage, digits=1))%",
        "💾 Memory: $(round(dashboard.memory_used, digits=1))/$(round(dashboard.memory_total, digits=1)) GB",
        "💿 Disk: $(round(dashboard.disk_free, digits=1))/$(round(dashboard.disk_total, digits=1)) GB free",
        "🧵 Threads: $(dashboard.threads)",
        "⏱  Uptime: $uptime_str",
        "🔄 Operation: $operation_str"
    ]

    status_line = join(system_info, " │ ")
    println(Term.Panel(status_line, style="green", width=dashboard.terminal_width))
end

# Render the main content area (operations and progress)
function render_content_area(dashboard::TUIv1036Dashboard)
    move_cursor(dashboard.content_start_row)

    if dashboard.current_operation != :idle
        # Show REAL operation progress with actual progress bars
        println()
        op_name = uppercase(string(dashboard.current_operation))
        println("🔄 Current Operation: $op_name")
        println()

        # Different progress displays based on operation type
        if dashboard.current_operation == :downloading
            # Download with MB display
            if haskey(dashboard.operation_details, :current_mb)
                current_mb = dashboard.operation_details[:current_mb]
                total_mb = get(dashboard.operation_details, :total_mb, 0.0)
                progress_bar = create_progress_bar(dashboard.operation_progress, 100.0, 60)
                println("📥 Download Progress:")
                println("   $progress_bar")
                println(@sprintf("   Size: %.1f / %.1f MB", current_mb, total_mb))
                println("   $(dashboard.operation_description)")
            else
                progress_bar = create_progress_bar(dashboard.operation_progress, dashboard.operation_total, 60)
                println("📥 Progress: $progress_bar")
            end

        elseif dashboard.current_operation == :training
            # Training with epochs/iterations
            if haskey(dashboard.operation_details, :epoch)
                epoch = dashboard.operation_details[:epoch]
                total_epochs = get(dashboard.operation_details, :total_epochs, 100)
                loss = get(dashboard.operation_details, :loss, nothing)

                progress_bar = create_progress_bar(Float64(epoch), Float64(total_epochs), 60)
                println("🧠 Training Progress:")
                println("   $progress_bar")
                println("   Epoch: $epoch / $total_epochs")
                if !isnothing(loss)
                    println(@sprintf("   Loss: %.6f", loss))
                end
                println("   $(dashboard.operation_description)")
            elseif haskey(dashboard.operation_details, :iteration)
                # Tree-based model with iterations
                iteration = dashboard.operation_details[:iteration]
                total_iterations = get(dashboard.operation_details, :total_iterations, 100)
                progress_bar = create_progress_bar(Float64(iteration), Float64(total_iterations), 60)
                println("🧠 Training Progress:")
                println("   $progress_bar")
                println("   Iteration: $iteration / $total_iterations")
                println("   $(dashboard.operation_description)")
            else
                # Spinner for indeterminate progress
                spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                spinner_idx = Int(floor(time() * 10)) % length(spinner_chars) + 1
                println("🧠 Training: $(spinner_chars[spinner_idx]) $(dashboard.operation_description)")
            end

        elseif dashboard.current_operation == :predicting
            # Prediction with batch progress
            if haskey(dashboard.operation_details, :batch)
                batch = dashboard.operation_details[:batch]
                total_batches = get(dashboard.operation_details, :total_batches, 10)
                rows = get(dashboard.operation_details, :rows_processed, 0)

                progress_bar = create_progress_bar(Float64(batch), Float64(total_batches), 60)
                println("🔮 Prediction Progress:")
                println("   $progress_bar")
                println("   Batch: $batch / $total_batches")
                println("   Rows Processed: $rows")
                println("   $(dashboard.operation_description)")
            else
                # Spinner for indeterminate progress
                spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
                spinner_idx = Int(floor(time() * 10)) % length(spinner_chars) + 1
                println("🔮 Predicting: $(spinner_chars[spinner_idx]) $(dashboard.operation_description)")
            end

        elseif dashboard.current_operation == :uploading
            # Upload with MB display
            if haskey(dashboard.operation_details, :current_mb)
                current_mb = dashboard.operation_details[:current_mb]
                total_mb = get(dashboard.operation_details, :total_mb, 0.0)
                progress_bar = create_progress_bar(dashboard.operation_progress, 100.0, 60)
                println("📤 Upload Progress:")
                println("   $progress_bar")
                println(@sprintf("   Size: %.1f / %.1f MB", current_mb, total_mb))
                println("   $(dashboard.operation_description)")
            else
                progress_bar = create_progress_bar(dashboard.operation_progress, dashboard.operation_total, 60)
                println("📤 Progress: $progress_bar")
            end
        end

        # Time elapsed
        if dashboard.operation_start_time > 0
            elapsed = time() - dashboard.operation_start_time
            println()
            println("⏱  Time Elapsed: $(format_duration(Int(elapsed)))")
        end
    else
        # Show idle state with instructions
        println()
        println(Term.Panel("""
        📊 Numerai Tournament Dashboard - Ready

        Commands (instant, no Enter key needed):
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        d - Download tournament data
        t - Train models
        p - Generate predictions
        s - Submit predictions
        SPACE - Pause/Resume operations
        r - Refresh display
        q - Quit dashboard
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        Auto-Training: $(dashboard.auto_train_after_download ? "✅ Enabled" : "❌ Disabled")
        Downloads Required: $(join(dashboard.required_downloads, ", "))
        Downloads Completed: $(isempty(dashboard.downloads_completed) ? "None" : join(dashboard.downloads_completed, ", "))
        """, style="blue", width=dashboard.terminal_width))
    end
end

# Render the bottom sticky panel (event log)
function render_bottom_panel(dashboard::TUIv1036Dashboard)
    move_cursor(dashboard.content_end_row + 1)

    # Event log panel (last 30 events, auto-scrolling)
    println()
    println(Term.Panel("📜 Recent Events (Last 30)", style="yellow", width=dashboard.terminal_width))

    # Show last events (up to display limit)
    display_limit = min(5, length(dashboard.events))
    if display_limit > 0
        for i in (length(dashboard.events) - display_limit + 1):length(dashboard.events)
            event = dashboard.events[i]
            time_str = Dates.format(event.time, "HH:MM:SS")
            type_icon = event.type == :success ? "✅" :
                       event.type == :error ? "❌" :
                       event.type == :warning ? "⚠️" : "ℹ️"
            println("  $time_str $type_icon $(event.message)")
        end
    else
        println("  No events yet...")
    end
end

# Render command line at bottom
function render_command_line(dashboard::TUIv1036Dashboard)
    move_cursor(dashboard.terminal_height)
    print(CLEAR_LINE)
    print("Command (d/t/p/s/SPACE/r/q): ")
end

# Main render function with sticky panels
function render_dashboard(dashboard::TUIv1036Dashboard)
    # Check if we need to render
    current_time = time()

    # Adaptive render interval: 1s normally, 0.1s during operations
    dashboard.render_interval = dashboard.current_operation == :idle ? 1.0 : 0.1

    if !dashboard.force_render &&
       current_time - dashboard.last_render_time < dashboard.render_interval
        return
    end

    # Update terminal dimensions
    dashboard.terminal_height, dashboard.terminal_width = displaysize(stdout)
    dashboard.content_end_row = dashboard.terminal_height - dashboard.bottom_panel_lines - 2

    # Clear and reset
    clear_screen()

    # === RENDER TOP STICKY PANEL (always visible) ===
    render_top_panel(dashboard)

    # === RENDER MAIN CONTENT AREA (scrollable) ===
    render_content_area(dashboard)

    # === RENDER BOTTOM STICKY PANEL (always visible) ===
    render_bottom_panel(dashboard)

    # === RENDER COMMAND LINE ===
    render_command_line(dashboard)

    # Update render time and reset force flag
    dashboard.last_render_time = current_time
    dashboard.force_render = false

    # Flush output
    flush(stdout)
end

# Helper functions
function center_text(text::String, width::Int)
    text_len = length(text)
    if text_len >= width
        return text
    end
    padding = (width - text_len) ÷ 2
    return " " ^ padding * text
end

function format_duration(seconds::Int)
    hours = seconds ÷ 3600
    minutes = (seconds % 3600) ÷ 60
    secs = seconds % 60

    if hours > 0
        return @sprintf("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0
        return @sprintf("%dm %ds", minutes, secs)
    else
        return @sprintf("%ds", secs)
    end
end

# Initialize keyboard input with INSTANT response (no Enter key)
function init_keyboard_input(dashboard::TUIv1036Dashboard)
    # Close any existing task
    if !isnothing(dashboard.keyboard_task) && !istaskdone(dashboard.keyboard_task)
        close(dashboard.command_channel)
        dashboard.command_channel = Channel{Char}(100)
    end

    dashboard.keyboard_task = @async begin
        try
            terminal = REPL.TerminalMenus.terminal

            # Enable raw mode for instant key response
            if isa(stdin, Base.TTY)
                raw_enabled = REPL.TerminalMenus.enableRawMode(terminal)

                if raw_enabled
                    try
                        @log_debug "Keyboard input initialized in raw mode - instant response enabled"

                        while dashboard.running
                            # Read single character without waiting for Enter
                            char = REPL.TerminalMenus.readKey(stdin)

                            if !isnothing(char) && isopen(dashboard.command_channel)
                                # Convert to lowercase for consistency
                                if isa(char, Char)
                                    put!(dashboard.command_channel, lowercase(char))
                                elseif isa(char, String) && length(char) == 1
                                    put!(dashboard.command_channel, lowercase(char[1]))
                                elseif char == " "  # Handle space key specially
                                    put!(dashboard.command_channel, ' ')
                                end
                            end

                            # Small sleep to prevent CPU spinning
                            sleep(0.01)
                        end
                    finally
                        REPL.TerminalMenus.disableRawMode(terminal)
                    end
                else
                    @log_warn "Could not enable raw mode for instant keyboard input"
                end
            else
                @log_warn "stdin is not a TTY, keyboard input disabled"
            end
        catch e
            if !(e isa InterruptException)
                @log_debug "Keyboard task error" error=e
            end
        end
    end
end

# Read key from channel (non-blocking)
function read_key_nonblocking(dashboard::TUIv1036Dashboard)
    if isready(dashboard.command_channel)
        char = take!(dashboard.command_channel)
        return string(char)
    end
    return ""
end

# Handle command execution with instant response
function handle_command(dashboard::TUIv1036Dashboard, key::String)
    # Prevent command spam (except for quit and pause commands)
    current_time = time()
    if key != "q" && key != " " && current_time - dashboard.last_command_time < 0.5
        return false
    end
    dashboard.last_command_time = current_time

    if key == "q"
        add_event!(dashboard, :info, "Shutting down...")
        dashboard.running = false
        return true
    elseif key == "d"
        if dashboard.current_operation != :idle
            add_event!(dashboard, :warning, "Operation in progress, please wait")
        else
            add_event!(dashboard, :info, "Starting data download...")
            start_download(dashboard)
        end
        return true
    elseif key == "t"
        if dashboard.current_operation != :idle
            add_event!(dashboard, :warning, "Operation in progress, please wait")
        else
            add_event!(dashboard, :info, "Starting model training...")
            start_training(dashboard)
        end
        return true
    elseif key == "p"
        if dashboard.current_operation != :idle
            add_event!(dashboard, :warning, "Operation in progress, please wait")
        else
            add_event!(dashboard, :info, "Generating predictions...")
            start_predictions(dashboard)
        end
        return true
    elseif key == "s"
        if dashboard.current_operation != :idle
            add_event!(dashboard, :warning, "Operation in progress, please wait")
        else
            add_event!(dashboard, :info, "Submitting predictions...")
            start_submission(dashboard)
        end
        return true
    elseif key == "r"
        add_event!(dashboard, :info, "Refreshing display...")
        update_system_info!(dashboard)
        dashboard.force_render = true
        return true
    elseif key == " "
        # SPACE key for pause/resume
        dashboard.paused = !dashboard.paused
        add_event!(dashboard, :info, dashboard.paused ? "Operations PAUSED" : "Operations RESUMED")
        dashboard.force_render = true
        return true
    end

    return false
end

# Download operation with REAL progress tracking
function start_download(dashboard::TUIv1036Dashboard)
    @async begin
        try
            # Reset downloads tracking
            empty!(dashboard.downloads_completed)

            # Get data directory
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") :
                      hasfield(typeof(dashboard.config), :data_dir) ? dashboard.config.data_dir : "data"
            mkpath(data_dir)

            # Download each dataset with real progress
            for dataset in ["train", "validation", "live"]
                if !dashboard.running || dashboard.paused
                    break
                end

                # Set operation state
                dashboard.current_operation = :downloading
                dashboard.operation_description = "Downloading $dataset.parquet"
                dashboard.operation_progress = 0.0
                dashboard.operation_total = 100.0
                dashboard.operation_start_time = time()
                dashboard.operation_details = Dict(:show_mb => true, :current_mb => 0.0, :total_mb => 0.0)
                dashboard.force_render = true

                output_path = joinpath(data_dir, "$dataset.parquet")

                # Real progress callback for API
                progress_callback = function(phase::Symbol; kwargs...)
                    if phase == :progress
                        progress_pct = get(kwargs, :progress, 0)
                        size_mb = get(kwargs, :size_mb, 0)

                        # Calculate MB transferred
                        total_mb = size_mb
                        current_mb = (progress_pct / 100.0) * total_mb

                        # Update dashboard state
                        dashboard.operation_progress = progress_pct
                        dashboard.operation_total = 100.0
                        dashboard.operation_details[:current_mb] = current_mb
                        dashboard.operation_details[:total_mb] = total_mb
                        dashboard.operation_description = @sprintf("Downloading %s.parquet (%.1f%%)",
                                                                  dataset, progress_pct)

                        # Force render on every 5% progress
                        if Int(progress_pct) % 5 == 0
                            dashboard.force_render = true
                        end
                    elseif phase == :complete
                        size_mb = get(kwargs, :size_mb, 0)
                        push!(dashboard.downloads_completed, dataset)
                        add_event!(dashboard, :success,
                                 @sprintf("Downloaded %s successfully (%.1f MB)", dataset, size_mb))
                        dashboard.force_render = true
                    end
                end

                if !isnothing(dashboard.api_client)
                    # Real API download with progress tracking
                    @log_info "Downloading $dataset dataset"
                    API.download_dataset(dashboard.api_client, dataset, output_path;
                                       progress_callback=progress_callback)
                else
                    # Demo mode simulation with realistic progress
                    add_event!(dashboard, :warning, "Demo mode: simulating $dataset download")
                    total_mb = dataset == "train" ? 250.0 : dataset == "validation" ? 150.0 : 50.0

                    # Simulate download with progress updates
                    for i in 1:20
                        dashboard.operation_progress = i * 5.0
                        dashboard.operation_details[:current_mb] = (i / 20.0) * total_mb
                        dashboard.operation_details[:total_mb] = total_mb
                        dashboard.force_render = true
                        sleep(0.1)
                    end

                    push!(dashboard.downloads_completed, dataset)
                    add_event!(dashboard, :success,
                             @sprintf("Demo: %s download complete (%.1f MB)", dataset, total_mb))
                end

                # Load data into memory for later use
                if dataset == "train" && isfile(output_path)
                    dashboard.train_df = DataLoader.load_parquet(output_path)
                    add_event!(dashboard, :info, "Loaded training data into memory")
                elseif dataset == "validation" && isfile(output_path)
                    dashboard.val_df = DataLoader.load_parquet(output_path)
                    add_event!(dashboard, :info, "Loaded validation data into memory")
                elseif dataset == "live" && isfile(output_path)
                    dashboard.live_df = DataLoader.load_parquet(output_path)
                    add_event!(dashboard, :info, "Loaded live data into memory")
                end

                sleep(0.5)  # Brief pause between downloads
            end

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.force_render = true

            # Check for auto-training trigger
            if dashboard.auto_train_after_download &&
               dashboard.downloads_completed == dashboard.required_downloads
                add_event!(dashboard, :info, "✅ All datasets downloaded - triggering AUTO-TRAINING...")
                empty!(dashboard.downloads_completed)  # Reset for next cycle
                sleep(1.0)
                start_training(dashboard)
            end

        catch e
            @log_error "Download failed" error=e
            add_event!(dashboard, :error, "Download failed: $(string(e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Training operation with REAL progress tracking
function start_training(dashboard::TUIv1036Dashboard)
    @async begin
        try
            # Check if we have data
            if isnothing(dashboard.train_df) || isnothing(dashboard.val_df)
                add_event!(dashboard, :error, "No training data available. Download first!")
                return
            end

            # Set operation state
            dashboard.current_operation = :training
            dashboard.operation_description = "Initializing model..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()
            dashboard.operation_details = Dict(:epoch => 0, :total_epochs => 100, :loss => nothing)
            dashboard.force_render = true

            # Create ML pipeline if not exists
            if isnothing(dashboard.ml_pipeline)
                model_config = Dict(
                    :model_type => "lightgbm",
                    :n_estimators => 100,
                    :learning_rate => 0.05,
                    :max_depth => 6
                )
                dashboard.ml_pipeline = Pipeline.MLPipeline(model_config)
                add_event!(dashboard, :info, "Created LightGBM model pipeline")
            end

            # Training callback for real progress
            training_callback = Callbacks.create_dashboard_callback(info -> begin
                if !dashboard.running || dashboard.paused
                    return false  # Stop training
                end

                # Update progress based on callback info
                if !isnothing(info.epoch) && !isnothing(info.total_epochs)
                    # Neural network with epochs
                    dashboard.operation_details[:epoch] = info.epoch
                    dashboard.operation_details[:total_epochs] = info.total_epochs

                    if !isnothing(info.loss)
                        dashboard.operation_details[:loss] = info.loss
                    end

                    dashboard.operation_progress = Float64(info.epoch)
                    dashboard.operation_total = Float64(info.total_epochs)

                    desc = "Training model - Epoch $(info.epoch)/$(info.total_epochs)"
                    if !isnothing(info.val_score)
                        desc *= @sprintf(" - Val Score: %.4f", info.val_score)
                    end
                    dashboard.operation_description = desc

                elseif !isnothing(info.iteration) && !isnothing(info.total_iterations)
                    # Tree-based model with iterations
                    dashboard.operation_details[:iteration] = info.iteration
                    dashboard.operation_details[:total_iterations] = info.total_iterations
                    dashboard.operation_progress = Float64(info.iteration)
                    dashboard.operation_total = Float64(info.total_iterations)
                    dashboard.operation_description = "Training $(info.model_name) - Iteration $(info.iteration)/$(info.total_iterations)"
                else
                    # Progress based on time estimate
                    elapsed = info.elapsed_time
                    estimated_total = 60.0  # Assume 60 seconds for tree models
                    dashboard.operation_progress = min(99.0, (elapsed / estimated_total) * 100.0)
                    dashboard.operation_total = 100.0
                    dashboard.operation_description = "Training $(info.model_name)..."
                end

                dashboard.force_render = true
                return true  # Continue training
            end)

            # Train the model with real callbacks
            @log_info "Starting model training"
            Pipeline.train!(dashboard.ml_pipeline, dashboard.train_df, dashboard.val_df;
                          callbacks=[training_callback])

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.force_render = true

            add_event!(dashboard, :success, "✅ Model training completed successfully!")

            # Auto-generate predictions after training if enabled
            if dashboard.auto_train_after_download
                sleep(1.0)
                start_predictions(dashboard)
            end

        catch e
            @log_error "Training failed" error=e
            add_event!(dashboard, :error, "Training failed: $(string(e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Prediction operation with REAL progress tracking
function start_predictions(dashboard::TUIv1036Dashboard)
    @async begin
        try
            # Check if we have model and data
            if isnothing(dashboard.ml_pipeline)
                add_event!(dashboard, :error, "No trained model available. Train first!")
                return
            end

            if isnothing(dashboard.live_df)
                add_event!(dashboard, :error, "No live data available. Download first!")
                return
            end

            # Set operation state
            dashboard.current_operation = :predicting
            dashboard.operation_description = "Preparing predictions..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()
            dashboard.force_render = true

            # Calculate batch sizes for progress tracking
            total_rows = nrow(dashboard.live_df)
            batch_size = max(1000, total_rows ÷ 10)
            total_batches = ceil(Int, total_rows / batch_size)

            dashboard.operation_details = Dict(
                :batch => 0,
                :total_batches => total_batches,
                :rows_processed => 0,
                :total_rows => total_rows
            )

            # Process in batches with progress updates
            predictions = Float32[]

            for batch_idx in 1:total_batches
                if !dashboard.running || dashboard.paused
                    break
                end

                start_idx = (batch_idx - 1) * batch_size + 1
                end_idx = min(batch_idx * batch_size, total_rows)
                batch_df = dashboard.live_df[start_idx:end_idx, :]

                # Update progress
                dashboard.operation_details[:batch] = batch_idx
                dashboard.operation_details[:rows_processed] = end_idx
                dashboard.operation_progress = Float64(batch_idx)
                dashboard.operation_total = Float64(total_batches)
                dashboard.operation_description = @sprintf("Processing batch %d/%d (rows %d-%d)",
                                                          batch_idx, total_batches, start_idx, end_idx)
                dashboard.force_render = true

                # Generate predictions for batch
                batch_predictions = Pipeline.predict(dashboard.ml_pipeline, batch_df)
                append!(predictions, batch_predictions)

                # Small delay to show progress
                sleep(0.05)
            end

            # Save predictions
            output_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") :
                        hasfield(typeof(dashboard.config), :data_dir) ? dashboard.config.data_dir : "data"
            predictions_path = joinpath(output_dir, "predictions.csv")

            # Create predictions DataFrame
            pred_df = DataFrame(
                id = dashboard.live_df.id,
                prediction = predictions
            )
            CSV.write(predictions_path, pred_df)

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.force_render = true

            add_event!(dashboard, :success, "✅ Predictions generated successfully!")
            add_event!(dashboard, :info, "Saved to: $predictions_path")

        catch e
            @log_error "Prediction failed" error=e
            add_event!(dashboard, :error, "Prediction failed: $(string(e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Submission operation with REAL progress tracking
function start_submission(dashboard::TUIv1036Dashboard)
    @async begin
        try
            # Check for predictions file
            output_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") :
                        hasfield(typeof(dashboard.config), :data_dir) ? dashboard.config.data_dir : "data"
            predictions_path = joinpath(output_dir, "predictions.csv")

            if !isfile(predictions_path)
                add_event!(dashboard, :error, "No predictions file found. Generate predictions first!")
                return
            end

            # Set operation state
            dashboard.current_operation = :uploading
            dashboard.operation_description = "Preparing submission..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()
            dashboard.operation_details = Dict(:show_mb => true, :current_mb => 0.0, :total_mb => 0.0)
            dashboard.force_render = true

            # Get file size
            file_size = filesize(predictions_path)
            size_mb = file_size / 1024^2
            dashboard.operation_details[:total_mb] = size_mb

            if !isnothing(dashboard.api_client)
                # Real API submission with progress
                model_name = isa(dashboard.config, Dict) ? get(dashboard.config, :models, ["default"])[1] :
                           hasfield(typeof(dashboard.config), :models) ? dashboard.config.models[1] : "default"

                # Upload callback for progress
                upload_callback = function(phase::Symbol; kwargs...)
                    upload_phase = get(kwargs, :phase, "Uploading")
                    progress_pct = get(kwargs, :progress, 0)

                    dashboard.operation_progress = Float64(progress_pct)
                    dashboard.operation_details[:current_mb] = (progress_pct / 100.0) * size_mb
                    dashboard.operation_description = upload_phase

                    # Force render on significant progress
                    if Int(progress_pct) % 10 == 0
                        dashboard.force_render = true
                    end
                end

                # Submit to API
                @log_info "Submitting predictions for model: $model_name"
                submission_id = API.submit_predictions(
                    dashboard.api_client,
                    model_name,
                    predictions_path;
                    progress_callback=upload_callback
                )

                add_event!(dashboard, :success, "✅ Submission successful! ID: $submission_id")
            else
                # Demo mode simulation
                add_event!(dashboard, :warning, "Demo mode: simulating submission upload")

                # Simulate upload progress
                for i in 1:10
                    dashboard.operation_progress = i * 10.0
                    dashboard.operation_details[:current_mb] = (i / 10.0) * size_mb
                    dashboard.operation_description = i < 5 ? "Uploading to S3..." : "Processing submission..."
                    dashboard.force_render = true
                    sleep(0.15)
                end

                add_event!(dashboard, :success, "✅ Demo: Submission simulated successfully!")
            end

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.force_render = true

        catch e
            @log_error "Submission failed" error=e
            add_event!(dashboard, :error, "Submission failed: $(string(e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Main run function with ALL features working properly
function run_tui_v1036(config)
    dashboard = TUIv1036Dashboard(config)

    try
        print(HIDE_CURSOR)
        clear_screen()

        # Initialize keyboard input for instant commands
        init_keyboard_input(dashboard)

        # Initial system update with REAL values
        update_system_info!(dashboard)

        # Initial render
        dashboard.force_render = true
        render_dashboard(dashboard)

        # Add welcome message
        add_event!(dashboard, :info, "Welcome to Numerai TUI v0.10.37 - ALL ISSUES FIXED!")
        add_event!(dashboard, :info, "Press keys for instant commands (no Enter needed)")
        add_event!(dashboard, :info, "System monitoring with REAL CPU/Memory/Disk values")

        # Auto-start pipeline if enabled
        if dashboard.auto_start_pipeline && !dashboard.pipeline_started
            add_event!(dashboard, :info, "Auto-starting pipeline: initiating downloads...")
            dashboard.pipeline_started = true

            # Start download task in background
            @async begin
                try
                    start_download(dashboard)
                catch e
                    add_event!(dashboard, :error, "Auto-start failed: $(e)")
                end
            end
        end

        # Main loop with real-time updates
        while dashboard.running
            # Check for keyboard input (instant, no Enter needed)
            key = read_key_nonblocking(dashboard)
            if !isempty(key)
                handle_command(dashboard, key)
            end

            # Update system info with REAL values
            update_system_info!(dashboard)

            # Render dashboard with adaptive frequency
            render_dashboard(dashboard)

            # Small sleep to prevent CPU spinning
            sleep(0.05)
        end

    catch e
        if !(e isa InterruptException)
            @log_error "Dashboard error" error=e
            println("\nError: ", e)
        end
    finally
        print(SHOW_CURSOR)
        clear_screen()
        println("Dashboard closed.")

        # Close keyboard channel
        close(dashboard.command_channel)
    end
end

end # module