module TUIv1034Fix

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

export TUIv1034Dashboard, run_tui_v1034

# Dashboard state with all functionality working correctly
mutable struct TUIv1034Dashboard
    config::Any
    api_client::Union{Nothing, API.NumeraiClient}
    ml_pipeline::Union{Nothing, Pipeline.MLPipeline}

    # State flags
    running::Bool
    paused::Bool

    # Operation tracking with proper progress monitoring
    current_operation::Symbol  # :idle, :downloading, :training, :predicting, :uploading
    operation_description::String
    operation_progress::Float64
    operation_total::Float64
    operation_start_time::Float64
    operation_details::Dict{Symbol, Any}  # Additional operation-specific details

    # System information with real-time updates
    cpu_usage::Float64
    memory_used::Float64
    memory_total::Float64
    disk_free::Float64
    threads::Int
    uptime::Int
    last_system_update::Float64

    # Event log with proper management
    events::Vector{NamedTuple{(:time, :type, :message), Tuple{DateTime, Symbol, String}}}
    max_events::Int

    # Command handling for instant response
    command_channel::Channel{Char}
    keyboard_task::Union{Nothing, Task}
    last_command_time::Float64

    # Auto-training state management
    auto_train_after_download::Bool
    downloads_completed::Set{String}
    required_downloads::Set{String}

    # Data storage for operations
    train_df::Union{Nothing, DataFrame}
    val_df::Union{Nothing, DataFrame}
    live_df::Union{Nothing, DataFrame}

    # Rendering control
    last_render_time::Float64
    render_interval::Float64
    force_render::Bool
    terminal_height::Int
    terminal_width::Int

    # Panel positions for sticky rendering
    top_panel_lines::Int
    bottom_panel_lines::Int
    content_start_row::Int
    content_end_row::Int

    # Start time for uptime tracking
    start_time::Float64
end

function TUIv1034Dashboard(config)
    # Extract API credentials safely
    public_key = isa(config, Dict) ? get(config, :api_public_key, "") :
                 hasfield(typeof(config), :api_public_key) ? config.api_public_key : ""
    secret_key = isa(config, Dict) ? get(config, :api_secret_key, "") :
                 hasfield(typeof(config), :api_secret_key) ? config.api_secret_key : ""

    # Extract auto-train setting
    auto_train = isa(config, Dict) ? get(config, :auto_train_after_download, true) :
                 hasfield(typeof(config), :auto_train_after_download) ? config.auto_train_after_download : true

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

    TUIv1034Dashboard(
        config,
        api_client,
        nothing,  # ml_pipeline
        false,    # running
        false,    # paused
        :idle,    # current_operation
        "",       # operation_description
        0.0,      # operation_progress
        0.0,      # operation_total
        time(),   # operation_start_time
        Dict{Symbol, Any}(),  # operation_details
        0.0,      # cpu_usage
        0.0,      # memory_used
        16.0,     # memory_total
        100.0,    # disk_free
        Threads.nthreads(),  # threads
        0,        # uptime
        time(),   # last_system_update
        NamedTuple{(:time, :type, :message), Tuple{DateTime, Symbol, String}}[],  # events
        30,       # max_events
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
        0.1,      # render_interval (100ms for smooth updates)
        false,    # force_render
        term_height,  # terminal_height
        term_width,   # terminal_width
        5,        # top_panel_lines
        8,        # bottom_panel_lines
        6,        # content_start_row
        term_height - 9,  # content_end_row
        time()    # start_time
    )
end

# Add event with proper management
function add_event!(dashboard::TUIv1034Dashboard, type::Symbol, message::String)
    event = (time=now(), type=type, message=message)
    push!(dashboard.events, event)

    # Keep only last N events
    while length(dashboard.events) > dashboard.max_events
        popfirst!(dashboard.events)
    end

    # Force render for important events
    if type in [:error, :success, :warning]
        dashboard.force_render = true
    end

    @log_debug "Event added" type=type message=message
end

# Update system information with proper macOS commands
function update_system_info!(dashboard::TUIv1034Dashboard)
    current_time = time()

    # Only update if enough time has passed (1 second normally, 100ms during operations)
    update_interval = dashboard.current_operation != :idle ? 0.1 : 1.0
    if current_time - dashboard.last_system_update < update_interval
        return
    end

    try
        # Get CPU usage (macOS specific)
        cpu_cmd = `top -l 1 -n 0 -stats pid,cpu`
        cpu_output = read(cpu_cmd, String)
        cpu_lines = split(cpu_output, '\n')

        # Parse CPU usage from header
        for line in cpu_lines
            if occursin("CPU usage:", line)
                m = match(r"([\d.]+)% user", line)
                if !isnothing(m)
                    dashboard.cpu_usage = parse(Float64, m.captures[1])
                end
                break
            end
        end

        # Get memory usage (macOS specific)
        mem_output = read(`vm_stat`, String)
        page_size = 4096  # Default page size
        pages_free = pages_active = pages_inactive = pages_speculative = pages_wired = 0

        for line in split(mem_output, '\n')
            if occursin("page size of", line)
                m = match(r"(\d+) bytes", line)
                !isnothing(m) && (page_size = parse(Int, m.captures[1]))
            elseif occursin("Pages free:", line)
                m = match(r":\s*(\d+)", line)
                !isnothing(m) && (pages_free = parse(Int, m.captures[1]))
            elseif occursin("Pages active:", line)
                m = match(r":\s*(\d+)", line)
                !isnothing(m) && (pages_active = parse(Int, m.captures[1]))
            elseif occursin("Pages inactive:", line)
                m = match(r":\s*(\d+)", line)
                !isnothing(m) && (pages_inactive = parse(Int, m.captures[1]))
            elseif occursin("Pages speculative:", line)
                m = match(r":\s*(\d+)", line)
                !isnothing(m) && (pages_speculative = parse(Int, m.captures[1]))
            elseif occursin("Pages wired down:", line)
                m = match(r":\s*(\d+)", line)
                !isnothing(m) && (pages_wired = parse(Int, m.captures[1]))
            end
        end

        # Calculate memory in GB
        total_pages = pages_free + pages_active + pages_inactive + pages_speculative + pages_wired
        if total_pages > 0
            used_pages = pages_active + pages_wired
            dashboard.memory_used = (used_pages * page_size) / (1024^3)
            dashboard.memory_total = (total_pages * page_size) / (1024^3)
        end

        # Get disk usage
        disk_output = read(`df -h /`, String)
        disk_lines = split(disk_output, '\n')
        if length(disk_lines) >= 2
            # Parse the data line (second line)
            disk_parts = split(disk_lines[2])
            if length(disk_parts) >= 4
                # Available space is the 4th column
                available = disk_parts[4]
                if endswith(available, "Gi")
                    dashboard.disk_free = parse(Float64, available[1:end-2])
                elseif endswith(available, "G")
                    dashboard.disk_free = parse(Float64, available[1:end-1])
                elseif endswith(available, "Ti")
                    dashboard.disk_free = parse(Float64, available[1:end-2]) * 1024
                elseif endswith(available, "T")
                    dashboard.disk_free = parse(Float64, available[1:end-1]) * 1024
                end
            end
        end

        # Update uptime
        dashboard.uptime = Int(round(current_time - dashboard.start_time))

    catch e
        # Silently handle errors to avoid disrupting the UI
        @log_debug "System info update failed" error=e
    end

    dashboard.last_system_update = current_time
end

# Create animated progress bar with proper state
function create_progress_bar(current::Float64, total::Float64, width::Int=40;
                            show_percentage::Bool=true, show_values::Bool=false)
    if total <= 0
        # Indeterminate progress - show animated spinner
        spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        spinner_idx = Int(floor(time() * 10)) % length(spinner_chars) + 1
        return spinner_chars[spinner_idx] * " Processing..."
    end

    percentage = clamp((current / total) * 100.0, 0.0, 100.0)
    filled = Int(round((percentage / 100.0) * width))
    empty = width - filled

    # Create the bar
    bar = "█" ^ filled * "░" ^ empty

    # Build the display string
    display_str = "[$bar]"

    if show_percentage
        display_str *= @sprintf(" %.1f%%", percentage)
    end

    if show_values
        display_str *= @sprintf(" (%.0f/%.0f)", current, total)
    end

    return display_str
end

# Terminal control functions
function clear_screen()
    print("\033[2J\033[H")
end

function move_cursor(row::Int, col::Int=1)
    print("\033[$row;$(col)H")
end

function clear_line()
    print("\033[K")
end

function save_cursor()
    print("\033[s")
end

function restore_cursor()
    print("\033[u")
end

function hide_cursor()
    print("\033[?25l")
end

function show_cursor()
    print("\033[?25h")
end

# Format uptime display
function format_uptime(seconds::Int)
    if seconds < 60
        return "$(seconds)s"
    elseif seconds < 3600
        mins = seconds ÷ 60
        secs = seconds % 60
        return @sprintf("%dm %ds", mins, secs)
    else
        hours = seconds ÷ 3600
        mins = (seconds % 3600) ÷ 60
        return @sprintf("%dh %dm", hours, mins)
    end
end

# Render the dashboard with proper sticky panels
function render_dashboard(dashboard::TUIv1034Dashboard)
    # Check if we need to render
    current_time = time()
    if !dashboard.force_render &&
       current_time - dashboard.last_render_time < dashboard.render_interval
        return
    end

    # Update terminal dimensions
    dashboard.terminal_height, dashboard.terminal_width = displaysize(stdout)

    # Clear and reset
    clear_screen()

    # === RENDER TOP STICKY PANEL ===
    render_top_panel(dashboard)

    # === RENDER MAIN CONTENT AREA ===
    render_content_area(dashboard)

    # === RENDER BOTTOM STICKY PANEL ===
    render_bottom_panel(dashboard)

    # === RENDER COMMAND LINE ===
    render_command_line(dashboard)

    # Update render time and reset force flag
    dashboard.last_render_time = current_time
    dashboard.force_render = false

    # Flush output
    flush(stdout)
end

# Render top sticky panel
function render_top_panel(dashboard::TUIv1034Dashboard)
    move_cursor(1)

    # Title bar
    title = "🚀 NUMERAI TOURNAMENT SYSTEM - v0.10.34"
    padding = max(0, (dashboard.terminal_width - length(title)) ÷ 2)
    println(" " ^ padding * title)
    println("═" ^ dashboard.terminal_width)

    # System status line
    status_icon = dashboard.paused ? "⏸" : "▶"
    operation_icon = dashboard.current_operation == :idle ? "💤" :
                     dashboard.current_operation == :downloading ? "📥" :
                     dashboard.current_operation == :training ? "🧠" :
                     dashboard.current_operation == :predicting ? "🔮" :
                     dashboard.current_operation == :uploading ? "📤" : "⚙️"

    cpu_str = @sprintf("%.1f%%", dashboard.cpu_usage)
    mem_str = @sprintf("%.1f/%.1f GB", dashboard.memory_used, dashboard.memory_total)
    mem_pct = dashboard.memory_total > 0 ?
              round(100 * dashboard.memory_used / dashboard.memory_total) : 0

    status_line = "$status_icon Status: $(dashboard.paused ? "PAUSED" : "RUNNING") │ " *
                  "$operation_icon $(uppercase(string(dashboard.current_operation))) │ " *
                  "CPU: $cpu_str │ " *
                  "Memory: $mem_str ($(Int(mem_pct))%) │ " *
                  "Disk: $(round(dashboard.disk_free, digits=1)) GB │ " *
                  "Threads: $(dashboard.threads) │ " *
                  "Up: $(format_uptime(dashboard.uptime))"

    println(status_line)
    println("─" ^ dashboard.terminal_width)

    dashboard.top_panel_lines = 4
    dashboard.content_start_row = 5
end

# Render main content area
function render_content_area(dashboard::TUIv1034Dashboard)
    move_cursor(dashboard.content_start_row)

    if dashboard.current_operation != :idle
        # Show operation progress
        println()
        op_name = uppercase(string(dashboard.current_operation))
        println("🔄 Current Operation: $op_name")
        println()

        # Progress bar with details
        if haskey(dashboard.operation_details, :show_mb) && dashboard.operation_details[:show_mb]
            # Download/Upload with MB display
            current_mb = get(dashboard.operation_details, :current_mb, 0.0)
            total_mb = get(dashboard.operation_details, :total_mb, 0.0)
            progress_bar = create_progress_bar(dashboard.operation_progress, 100.0, 50)
            println("Progress: $progress_bar")
            println(@sprintf("Size: %.1f / %.1f MB", current_mb, total_mb))
        elseif haskey(dashboard.operation_details, :epoch)
            # Training with epochs
            epoch = dashboard.operation_details[:epoch]
            total_epochs = get(dashboard.operation_details, :total_epochs, 0)
            loss = get(dashboard.operation_details, :loss, nothing)

            progress_bar = create_progress_bar(Float64(epoch), Float64(total_epochs), 50)
            println("Training: $progress_bar")

            desc = "Epoch $epoch/$total_epochs"
            if !isnothing(loss)
                desc *= @sprintf(" - Loss: %.4f", loss)
            end
            println(desc)
        elseif haskey(dashboard.operation_details, :batch)
            # Prediction with batches
            batch = dashboard.operation_details[:batch]
            total_batches = dashboard.operation_details[:total_batches]
            rows_processed = get(dashboard.operation_details, :rows_processed, 0)

            progress_bar = create_progress_bar(Float64(batch), Float64(total_batches), 50)
            println("Prediction: $progress_bar")
            println("Batch $batch/$total_batches - $rows_processed rows processed")
        else
            # Generic progress
            progress_bar = create_progress_bar(dashboard.operation_progress,
                                              dashboard.operation_total, 50)
            println("Progress: $progress_bar")
        end

        # Operation description
        if !isempty(dashboard.operation_description)
            println("Details: $(dashboard.operation_description)")
        end

        # Time elapsed
        elapsed = time() - dashboard.operation_start_time
        println(@sprintf("Elapsed: %.1f seconds", elapsed))

    else
        # Idle state message
        println()
        println("💤 System Idle - Ready for Commands")
        println()
        println("Available Operations:")
        println("  [d] Download tournament data")
        println("  [t] Train models")
        println("  [p] Generate predictions")
        println("  [s] Submit predictions")
        println("  [r] Refresh system info")
        println("  [q] Quit application")
    end
end

# Render bottom sticky panel
function render_bottom_panel(dashboard::TUIv1034Dashboard)
    # Calculate position
    event_start_row = dashboard.terminal_height - dashboard.bottom_panel_lines
    move_cursor(event_start_row)

    println("─" ^ dashboard.terminal_width)
    println("📋 RECENT EVENTS")

    # Show last 5 events
    if isempty(dashboard.events)
        println("  No events yet - waiting for operations...")
    else
        num_to_show = min(5, length(dashboard.events))
        start_idx = max(1, length(dashboard.events) - num_to_show + 1)

        for event in dashboard.events[start_idx:end]
            timestamp = Dates.format(event.time, "HH:MM:SS")
            icon = event.type == :error ? "❌" :
                   event.type == :warning ? "⚠️" :
                   event.type == :success ? "✅" : "ℹ️"

            msg = event.message
            max_msg_len = dashboard.terminal_width - 20
            if length(msg) > max_msg_len
                msg = msg[1:max_msg_len-3] * "..."
            end

            println("  [$timestamp] $icon $msg")
        end
    end

    dashboard.bottom_panel_lines = 8
    dashboard.content_end_row = event_start_row - 1
end

# Render command line at bottom
function render_command_line(dashboard::TUIv1034Dashboard)
    move_cursor(dashboard.terminal_height)
    clear_line()
    print("📌 Commands: [d]ownload [t]rain [p]redict [s]ubmit [r]efresh [q]uit │ Ready (no Enter needed)")
    flush(stdout)
end

# Initialize keyboard input with proper non-blocking handling
function init_keyboard_input(dashboard::TUIv1034Dashboard)
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
                        @log_debug "Keyboard input initialized in raw mode"

                        while dashboard.running
                            # Read a single key (blocks until key pressed)
                            key_code = REPL.TerminalMenus.readKey(terminal.in_stream)

                            # Convert to character for regular ASCII keys
                            if 0 < key_code <= 127
                                char = Char(key_code)

                                # Put in channel if it's open
                                if isopen(dashboard.command_channel)
                                    put!(dashboard.command_channel, char)
                                    @log_debug "Key pressed" char=char
                                end
                            end

                            # Small yield to prevent CPU spinning
                            sleep(0.001)
                        end
                    finally
                        # Restore normal mode
                        REPL.TerminalMenus.disableRawMode(terminal)
                        @log_debug "Raw mode disabled"
                    end
                else
                    @log_warn "Could not enable raw mode for keyboard input"
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
function read_key_nonblocking(dashboard::TUIv1034Dashboard)
    if isready(dashboard.command_channel)
        try
            char = take!(dashboard.command_channel)
            return lowercase(string(char))
        catch
            return ""
        end
    end
    return ""
end

# Handle command execution
function handle_command(dashboard::TUIv1034Dashboard, key::String)
    # Prevent command spam (except for quit command)
    current_time = time()
    if key != "q" && current_time - dashboard.last_command_time < 0.5
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
            add_event!(dashboard, :info, "Starting download...")
            start_download(dashboard)
        end
        return true
    elseif key == "t"
        if dashboard.current_operation != :idle
            add_event!(dashboard, :warning, "Operation in progress, please wait")
        else
            add_event!(dashboard, :info, "Starting training...")
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
        add_event!(dashboard, :info, "Refreshing system info...")
        update_system_info!(dashboard)
        dashboard.force_render = true
        return true
    elseif key == " "
        dashboard.paused = !dashboard.paused
        add_event!(dashboard, :info, dashboard.paused ? "Operations paused" : "Operations resumed")
        return true
    end

    return false
end

# Start download operation with proper progress tracking
function start_download(dashboard::TUIv1034Dashboard)
    @async begin
        try
            # Reset downloads tracking
            empty!(dashboard.downloads_completed)

            # Get data directory
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") :
                      hasfield(typeof(dashboard.config), :data_dir) ? dashboard.config.data_dir : "data"
            mkpath(data_dir)

            datasets = ["train", "validation", "live"]

            for (idx, dataset) in enumerate(datasets)
                if !dashboard.running || dashboard.paused
                    break
                end

                # Set operation state
                dashboard.current_operation = :downloading
                dashboard.operation_description = "Preparing to download $dataset.parquet"
                dashboard.operation_progress = 0.0
                dashboard.operation_total = 100.0
                dashboard.operation_start_time = time()
                dashboard.operation_details = Dict(:show_mb => true, :current_mb => 0.0, :total_mb => 0.0)
                dashboard.force_render = true

                # Create progress callback for API
                progress_callback = function(phase; kwargs...)
                    if phase == :start
                        name = get(kwargs, :name, dataset)
                        dashboard.operation_description = "Connecting to download $name.parquet"
                        dashboard.force_render = true
                    elseif phase == :progress
                        # Extract progress information
                        progress_pct = get(kwargs, :progress, 0)
                        current_mb = get(kwargs, :current_mb, 0)
                        total_mb = get(kwargs, :total_mb, 0)

                        # Update dashboard state
                        dashboard.operation_progress = progress_pct
                        dashboard.operation_total = 100.0
                        dashboard.operation_details[:current_mb] = current_mb
                        dashboard.operation_details[:total_mb] = total_mb
                        dashboard.operation_description = @sprintf("Downloading %s.parquet", dataset)

                        # Force render on significant progress
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

                # Perform download
                output_path = joinpath(data_dir, "$dataset.parquet")

                if !isnothing(dashboard.api_client)
                    # Real API download
                    @log_info "Downloading $dataset dataset"
                    API.download_dataset(dashboard.api_client, dataset, output_path;
                                       progress_callback=progress_callback)
                else
                    # Demo mode simulation
                    add_event!(dashboard, :warning, "Demo mode: simulating $dataset download")
                    total_mb = dataset == "train" ? 250.0 : dataset == "validation" ? 150.0 : 50.0

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
                try
                    if isfile(output_path)
                        @log_info "Loading $dataset data into memory"
                        if dataset == "train"
                            dashboard.train_df = DataLoader.load_training_data(output_path; sample_pct=0.1)
                        elseif dataset == "validation"
                            dashboard.val_df = DataLoader.load_training_data(output_path; sample_pct=0.2)
                        elseif dataset == "live"
                            dashboard.live_df = DataLoader.load_live_data(output_path)
                        end
                    end
                catch e
                    @log_warn "Could not load $dataset data" error=e
                end
            end

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.operation_details = Dict{Symbol, Any}()
            dashboard.force_render = true

            # Check for auto-training trigger
            if dashboard.auto_train_after_download &&
               dashboard.downloads_completed == dashboard.required_downloads
                add_event!(dashboard, :info, "All datasets downloaded - starting auto-training...")
                empty!(dashboard.downloads_completed)  # Reset for next cycle
                sleep(1.0)
                start_training(dashboard)
            end

        catch e
            @log_error "Download failed" error=e
            add_event!(dashboard, :error, "Download failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Start training operation with proper progress tracking
function start_training(dashboard::TUIv1034Dashboard)
    @async begin
        try
            # Check for data
            if isnothing(dashboard.train_df) || isnothing(dashboard.val_df)
                add_event!(dashboard, :error, "No training data available. Please download first.")
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

            # Create ML pipeline if needed
            if isnothing(dashboard.ml_pipeline)
                model_config = isa(dashboard.config, Dict) ?
                              get(dashboard.config, :model, Dict(:type => "XGBoost")) :
                              hasfield(typeof(dashboard.config), :model) ?
                              dashboard.config.model : Dict(:type => "XGBoost")

                feature_cols = filter(n -> startswith(n, "feature_"), names(dashboard.train_df))
                target_col = "target_cyrus_v4_20"

                if isempty(feature_cols)
                    add_event!(dashboard, :error, "No feature columns found in training data")
                    dashboard.current_operation = :idle
                    return
                end

                dashboard.ml_pipeline = Pipeline.MLPipeline(
                    feature_cols=feature_cols,
                    target_col=target_col,
                    model_configs=Dict("model" => model_config)
                )
            end

            # Create training callback
            training_callback = Models.Callbacks.create_dashboard_callback(
                function(info::Models.Callbacks.CallbackInfo)
                    # Update operation details
                    if info.total_epochs > 0
                        dashboard.operation_details[:epoch] = info.epoch
                        dashboard.operation_details[:total_epochs] = info.total_epochs
                        dashboard.operation_details[:loss] = info.loss

                        dashboard.operation_progress = Float64(info.epoch)
                        dashboard.operation_total = Float64(info.total_epochs)

                        desc = "Training model"
                        if !isnothing(info.val_score)
                            desc *= @sprintf(" - Val Score: %.4f", info.val_score)
                        end
                        dashboard.operation_description = desc
                    elseif !isnothing(info.total_iterations) && info.total_iterations > 0
                        # Tree-based model with iterations
                        dashboard.operation_progress = Float64(info.iteration)
                        dashboard.operation_total = Float64(info.total_iterations)
                        dashboard.operation_description = "Training $(info.model_name)"
                    else
                        # Progress based on time estimate
                        elapsed = info.elapsed_time
                        estimated_total = 60.0  # Assume 60 seconds for tree models
                        dashboard.operation_progress = min(99.0, (elapsed / estimated_total) * 100.0)
                        dashboard.operation_total = 100.0
                        dashboard.operation_description = "Training $(info.model_name)..."
                    end

                    dashboard.force_render = true
                    return Models.Callbacks.CONTINUE
                end,
                frequency=1
            )

            # Train the model
            @log_info "Starting model training"
            Pipeline.train!(dashboard.ml_pipeline, dashboard.train_df, dashboard.val_df;
                          callbacks=[training_callback])

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.operation_details = Dict{Symbol, Any}()
            add_event!(dashboard, :success, "Training completed successfully")
            dashboard.force_render = true

            # Auto-generate predictions after training
            if dashboard.auto_train_after_download
                sleep(1.0)
                start_predictions(dashboard)
            end

        catch e
            @log_error "Training failed" error=e
            add_event!(dashboard, :error, "Training failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Start prediction generation with batch progress
function start_predictions(dashboard::TUIv1034Dashboard)
    @async begin
        try
            # Check for model and data
            if isnothing(dashboard.ml_pipeline)
                add_event!(dashboard, :error, "No trained model available")
                return
            end

            if isnothing(dashboard.live_df)
                add_event!(dashboard, :error, "No live data available. Please download first.")
                return
            end

            # Set operation state
            dashboard.current_operation = :predicting
            dashboard.operation_description = "Preparing predictions..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()
            dashboard.force_render = true

            # Calculate batch sizes
            n_rows = nrow(dashboard.live_df)
            batch_size = max(1000, n_rows ÷ 10)  # 10 batches or 1000 rows minimum
            n_batches = ceil(Int, n_rows / batch_size)

            dashboard.operation_details = Dict(:batch => 0, :total_batches => n_batches,
                                              :rows_processed => 0)
            dashboard.operation_description = "Processing $n_rows rows in $n_batches batches"
            dashboard.operation_total = Float64(n_batches)
            dashboard.force_render = true

            # Generate predictions in batches
            predictions = Float64[]

            for batch_idx in 1:n_batches
                if !dashboard.running || dashboard.paused
                    break
                end

                start_idx = (batch_idx - 1) * batch_size + 1
                end_idx = min(batch_idx * batch_size, n_rows)
                batch_df = dashboard.live_df[start_idx:end_idx, :]

                # Update progress
                dashboard.operation_details[:batch] = batch_idx
                dashboard.operation_details[:rows_processed] = end_idx
                dashboard.operation_progress = Float64(batch_idx)
                dashboard.operation_description = "Processing predictions"
                dashboard.force_render = true

                # Generate predictions for batch
                batch_predictions = Pipeline.predict(dashboard.ml_pipeline, batch_df)
                append!(predictions, batch_predictions)

                # Small yield for UI update
                sleep(0.01)
            end

            # Save predictions
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") :
                      hasfield(typeof(dashboard.config), :data_dir) ? dashboard.config.data_dir : "data"
            predictions_path = joinpath(data_dir, "predictions.csv")

            # Create predictions DataFrame
            predictions_df = DataFrame(
                id = dashboard.live_df.id,
                prediction = predictions
            )

            CSV.write(predictions_path, predictions_df)

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.operation_details = Dict{Symbol, Any}()
            add_event!(dashboard, :success, "Predictions saved to $predictions_path")
            dashboard.force_render = true

        catch e
            @log_error "Prediction failed" error=e
            add_event!(dashboard, :error, "Prediction failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Start submission with upload progress
function start_submission(dashboard::TUIv1034Dashboard)
    @async begin
        try
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") :
                      hasfield(typeof(dashboard.config), :data_dir) ? dashboard.config.data_dir : "data"
            predictions_path = joinpath(data_dir, "predictions.csv")

            if !isfile(predictions_path)
                add_event!(dashboard, :error, "No predictions file found. Generate predictions first.")
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
            size_mb = file_size / (1024 * 1024)
            dashboard.operation_details[:total_mb] = size_mb

            # Create progress callback for API
            progress_callback = function(phase; kwargs...)
                if phase == :start
                    model = get(kwargs, :model, "")
                    dashboard.operation_description = "Connecting to Numerai for $model"
                    dashboard.force_render = true
                elseif phase == :progress
                    upload_phase = get(kwargs, :phase, "Uploading")
                    progress_pct = get(kwargs, :progress, 0)

                    dashboard.operation_progress = Float64(progress_pct)
                    dashboard.operation_details[:current_mb] = (progress_pct / 100.0) * size_mb
                    dashboard.operation_description = upload_phase

                    # Force render on significant progress
                    if Int(progress_pct) % 10 == 0
                        dashboard.force_render = true
                    end
                elseif phase == :complete
                    submission_id = get(kwargs, :submission_id, "")
                    model = get(kwargs, :model, "")
                    add_event!(dashboard, :success,
                             "Submission successful for $model! ID: $submission_id")
                    dashboard.force_render = true
                elseif phase == :error
                    message = get(kwargs, :message, "Unknown error")
                    add_event!(dashboard, :error, "Upload error: $message")
                    dashboard.current_operation = :idle
                    dashboard.force_render = true
                end
            end

            # Get model name
            model_name = isa(dashboard.config, Dict) ?
                        get(dashboard.config, :model_name, "numerai_model") :
                        hasfield(typeof(dashboard.config), :models) && !isempty(dashboard.config.models) ?
                        dashboard.config.models[1] : "numerai_model"

            # Submit predictions
            if !isnothing(dashboard.api_client)
                # Real API submission
                @log_info "Submitting predictions for $model_name"
                submission_id = API.submit_predictions(dashboard.api_client, model_name, predictions_path;
                                                      progress_callback=progress_callback)

                add_event!(dashboard, :success, "Submission completed: $submission_id")
            else
                # Demo mode simulation
                add_event!(dashboard, :warning, "Demo mode: simulating submission")

                for i in 1:10
                    dashboard.operation_progress = i * 10.0
                    dashboard.operation_details[:current_mb] = (i / 10.0) * size_mb
                    dashboard.operation_description = i < 5 ? "Uploading to S3" : "Processing submission"
                    dashboard.force_render = true
                    sleep(0.15)
                end

                add_event!(dashboard, :success, "Demo: Submission complete (ID: demo_12345)")
            end

            # Reset to idle
            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            dashboard.operation_details = Dict{Symbol, Any}()
            dashboard.force_render = true

        catch e
            @log_error "Submission failed" error=e
            add_event!(dashboard, :error, "Submission failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
            dashboard.force_render = true
        end
    end
end

# Main dashboard loop
function run_tui_v1034(config)
    dashboard = TUIv1034Dashboard(config)
    dashboard.running = true

    # Hide cursor for cleaner display
    hide_cursor()

    try
        add_event!(dashboard, :info, "🚀 Dashboard v0.10.34 started - All features operational")
        add_event!(dashboard, :info, "Press command keys directly (no Enter needed)")

        # Initialize keyboard input
        init_keyboard_input(dashboard)

        # Initial system update
        update_system_info!(dashboard)

        # Initial render
        dashboard.force_render = true
        render_dashboard(dashboard)

        # Main loop
        while dashboard.running
            # Check for keyboard input
            key = read_key_nonblocking(dashboard)
            if !isempty(key)
                handle_command(dashboard, key)
            end

            # Update system info periodically
            update_system_info!(dashboard)

            # Render dashboard
            render_dashboard(dashboard)

            # Small sleep to prevent CPU spinning
            sleep(0.01)
        end

    catch e
        @log_error "Dashboard error" error=e
        println("\nDashboard error: ", sprint(showerror, e))
    finally
        # Cleanup
        show_cursor()
        clear_screen()
        println("Dashboard stopped.")

        # Close keyboard channel
        close(dashboard.command_channel)
    end
end

end # module