module TUIOperational

using Term
using Dates
using TimeZones
using Printf
using Statistics
using DataFrames
using CSV
using ..API
using ..Pipeline
using ..Models
using ..Models.Callbacks
using ..Logger: @log_info, @log_warn, @log_error
using ..Utils
using ..DataLoader

export OperationalDashboard, run_operational_dashboard

# Dashboard state with all required functionality
mutable struct OperationalDashboard
    config::Any
    api_client::API.NumeraiClient
    ml_pipeline::Union{Nothing, Pipeline.MLPipeline}

    # State flags
    running::Bool
    paused::Bool

    # Operation tracking
    current_operation::Symbol  # :idle, :downloading, :training, :predicting, :uploading
    operation_description::String
    operation_progress::Float64
    operation_total::Float64
    operation_start_time::Float64

    # System information
    cpu_usage::Float64
    memory_used::Float64
    memory_total::Float64
    disk_free::Float64
    threads::Int
    uptime::Int

    # Event log (keep last 30 events)
    events::Vector{NamedTuple{(:time, :type, :message), Tuple{DateTime, Symbol, String}}}

    # Command handling
    command_buffer::String
    last_key_time::Float64

    # Auto-training state
    auto_train_after_download::Bool
    downloads_completed::Set{String}
    required_downloads::Set{String}

    # Data storage
    train_df::Union{Nothing, DataFrame}
    val_df::Union{Nothing, DataFrame}
    live_df::Union{Nothing, DataFrame}

    # Timing
    last_render_time::Float64
    last_system_update::Float64
    start_time::Float64
end

function OperationalDashboard(config)
    # Extract API credentials
    public_key = isa(config, Dict) ? get(config, :api_public_key, "") : config.api_public_key
    secret_key = isa(config, Dict) ? get(config, :api_secret_key, "") : config.api_secret_key

    # Extract auto-train setting
    auto_train = isa(config, Dict) ? get(config, :auto_train_after_download, true) :
                 try config.auto_train_after_download catch; true end

    api_client = API.NumeraiClient(public_key, secret_key)

    OperationalDashboard(
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
        0.0,      # cpu_usage
        0.0,      # memory_used
        16.0,     # memory_total
        100.0,    # disk_free
        Threads.nthreads(),  # threads
        0,        # uptime
        NamedTuple{(:time, :type, :message), Tuple{DateTime, Symbol, String}}[],  # events
        "",       # command_buffer
        time(),   # last_key_time
        auto_train,  # auto_train_after_download
        Set{String}(),  # downloads_completed
        Set(["train", "validation", "live"]),  # required_downloads
        nothing,  # train_df
        nothing,  # val_df
        nothing,  # live_df
        time(),   # last_render_time
        time(),   # last_system_update
        time()    # start_time
    )
end

# Add event to log
function add_event!(dashboard::OperationalDashboard, type::Symbol, message::String)
    event = (time=now(), type=type, message=message)
    push!(dashboard.events, event)

    # Keep only last 30 events
    if length(dashboard.events) > 30
        popfirst!(dashboard.events)
    end

    # Force immediate render for important events
    if type in [:error, :success, :warning]
        dashboard.last_render_time = 0.0
    end
end

# Update system information
function update_system_info!(dashboard::OperationalDashboard)
    try
        # Get CPU usage (macOS)
        cpu_output = read(`top -l 1 -n 0`, String)
        cpu_match = match(r"CPU usage: ([\d.]+)% user", cpu_output)
        if !isnothing(cpu_match)
            dashboard.cpu_usage = parse(Float64, cpu_match.captures[1])
        end

        # Get memory usage (macOS)
        mem_output = read(`vm_stat`, String)
        page_size = 4096
        pages_free = pages_active = pages_inactive = pages_wired = 0

        for line in split(mem_output, '\n')
            if occursin("page size of", line)
                m = match(r"(\d+) bytes", line)
                !isnothing(m) && (page_size = parse(Int, m.captures[1]))
            elseif occursin("Pages free", line)
                m = match(r"(\d+)", line)
                !isnothing(m) && (pages_free = parse(Int, m.captures[1]))
            elseif occursin("Pages active", line)
                m = match(r"(\d+)", line)
                !isnothing(m) && (pages_active = parse(Int, m.captures[1]))
            elseif occursin("Pages inactive", line)
                m = match(r"(\d+)", line)
                !isnothing(m) && (pages_inactive = parse(Int, m.captures[1]))
            elseif occursin("Pages wired", line)
                m = match(r"(\d+)", line)
                !isnothing(m) && (pages_wired = parse(Int, m.captures[1]))
            end
        end

        total_pages = pages_free + pages_active + pages_inactive + pages_wired
        if total_pages > 0
            dashboard.memory_used = (pages_active + pages_wired) * page_size / (1024^3)
            dashboard.memory_total = total_pages * page_size / (1024^3)
        end

        # Get disk usage
        disk_output = read(`df -h /`, String)
        disk_lines = split(disk_output, '\n')
        if length(disk_lines) >= 2
            disk_parts = split(disk_lines[2])
            if length(disk_parts) >= 4
                available = disk_parts[4]
                if endswith(available, "G")
                    dashboard.disk_free = parse(Float64, available[1:end-1])
                elseif endswith(available, "T")
                    dashboard.disk_free = parse(Float64, available[1:end-1]) * 1024
                end
            end
        end

        # Update uptime
        dashboard.uptime = Int(round(time() - dashboard.start_time))

    catch e
        @log_warn "Failed to update system info" error=e
    end

    dashboard.last_system_update = time()
end

# Create progress bar
function create_progress_bar(current::Float64, total::Float64; width::Int=40)
    if total <= 0
        # Indeterminate progress - show spinner
        spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        spinner_idx = Int(floor(time() * 10)) % length(spinner_chars) + 1
        return spinner_chars[spinner_idx] * " Working..."
    end

    percentage = min(100.0, (current / total) * 100.0)
    filled = Int(round((percentage / 100.0) * width))
    empty = width - filled

    bar = "[" * "█" ^ filled * "░" ^ empty * "]"
    return "$bar $(round(percentage, digits=1))%"
end

# Clear screen and move cursor to home
function clear_screen()
    print("\033[2J\033[H")
end

# Move cursor to specific position
function move_cursor(row::Int, col::Int=1)
    print("\033[$row;$(col)H")
end

# Clear current line
function clear_line()
    print("\033[K")
end

# Get terminal dimensions
function terminal_size()
    return displaysize(stdout)
end

# Render the complete dashboard
function render_dashboard(dashboard::OperationalDashboard)
    term_height, term_width = terminal_size()

    # Clear screen
    clear_screen()

    # === TOP STICKY PANEL (System Info) ===
    move_cursor(1)

    # Title bar
    title = "🚀 NUMERAI TOURNAMENT SYSTEM - v0.10.32"
    padding = max(0, (term_width - length(title)) ÷ 2)
    println(" " ^ padding * title)
    println("═" ^ term_width)

    # System status line
    status_icon = dashboard.paused ? "⏸" : "▶"
    cpu_str = @sprintf("%.1f%%", dashboard.cpu_usage)
    mem_str = @sprintf("%.1f/%.1f GB", dashboard.memory_used, dashboard.memory_total)
    mem_pct = dashboard.memory_total > 0 ? round(100 * dashboard.memory_used / dashboard.memory_total) : 0

    status_line = "$status_icon Status: $(dashboard.paused ? "PAUSED" : "RUNNING") │ " *
                  "CPU: $cpu_str │ " *
                  "Memory: $mem_str ($(Int(mem_pct))%) │ " *
                  "Disk: $(dashboard.disk_free) GB free │ " *
                  "Threads: $(dashboard.threads) │ " *
                  "Uptime: $(format_uptime(dashboard.uptime))"

    println(status_line)
    println("─" ^ term_width)

    # === MAIN CONTENT AREA ===
    current_row = 6

    # Operation progress
    if dashboard.current_operation != :idle
        move_cursor(current_row)

        op_name = uppercase(string(dashboard.current_operation))
        op_icon = dashboard.current_operation == :downloading ? "📥" :
                  dashboard.current_operation == :training ? "🧠" :
                  dashboard.current_operation == :predicting ? "🔮" :
                  dashboard.current_operation == :uploading ? "📤" : "⚙️"

        println("\n$op_icon $op_name")

        # Progress bar
        progress_bar = create_progress_bar(dashboard.operation_progress, dashboard.operation_total)
        println(progress_bar)

        # Description
        if !isempty(dashboard.operation_description)
            println(dashboard.operation_description)
        end

        # Time elapsed
        elapsed = time() - dashboard.operation_start_time
        println(@sprintf("Elapsed: %.1f seconds", elapsed))
        println()

        current_row += 6
    else
        # Show idle message
        move_cursor(current_row)
        println("\n💤 System idle - Press command key to start an operation")
        println()
        current_row += 3
    end

    # === BOTTOM STICKY PANEL (Event Log) ===
    # Calculate position for bottom panel (last 10 rows)
    event_start_row = max(current_row + 2, term_height - 9)

    move_cursor(event_start_row)
    println("─" ^ term_width)
    println("📋 RECENT EVENTS (Last 30)")

    # Show last 5 events
    if isempty(dashboard.events)
        println("  No events yet")
    else
        num_to_show = min(5, length(dashboard.events))
        start_idx = length(dashboard.events) - num_to_show + 1

        for event in dashboard.events[start_idx:end]
            timestamp = Dates.format(event.time, "HH:MM:SS")
            icon = event.type == :error ? "❌" :
                   event.type == :warning ? "⚠️ " :
                   event.type == :success ? "✅" : "ℹ️ "

            msg = event.message
            max_msg_len = term_width - 15
            if length(msg) > max_msg_len
                msg = msg[1:max_msg_len-3] * "..."
            end

            println("  [$timestamp] $icon $msg")
        end
    end

    # Command prompt at very bottom
    move_cursor(term_height)
    clear_line()

    if !isempty(dashboard.command_buffer)
        print("Command: $(dashboard.command_buffer)_")
    else
        print("Commands: [d]ownload [t]rain [p]redict [s]ubmit [r]efresh [q]uit │ Press key (no Enter needed)")
    end

    # Flush output
    flush(stdout)
end

# Format uptime nicely
function format_uptime(seconds::Int)
    if seconds < 60
        return "$(seconds)s"
    elseif seconds < 3600
        mins = seconds ÷ 60
        secs = seconds % 60
        return "$(mins)m $(secs)s"
    else
        hours = seconds ÷ 3600
        mins = (seconds % 3600) ÷ 60
        return "$(hours)h $(mins)m"
    end
end

# Read a single key without Enter (non-blocking)
function read_key_nonblocking()
    key = ""

    if isa(stdin, Base.TTY)
        try
            # Set raw mode
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)

            # Check if data available
            if bytesavailable(stdin) > 0
                char = read(stdin, Char)
                key = string(char)
            end

            # Restore normal mode
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)
        catch
            # Ignore errors
        end
    end

    return lowercase(key)
end

# Handle command execution
function handle_command(dashboard::OperationalDashboard, key::String)
    if key == "q"
        add_event!(dashboard, :info, "Shutting down...")
        dashboard.running = false
        return true
    elseif key == "d"
        add_event!(dashboard, :info, "Starting download...")
        start_download(dashboard)
        return true
    elseif key == "t"
        add_event!(dashboard, :info, "Starting training...")
        start_training(dashboard)
        return true
    elseif key == "p"
        add_event!(dashboard, :info, "Generating predictions...")
        start_predictions(dashboard)
        return true
    elseif key == "s"
        add_event!(dashboard, :info, "Submitting predictions...")
        start_submission(dashboard)
        return true
    elseif key == "r"
        add_event!(dashboard, :info, "Refreshing system info...")
        update_system_info!(dashboard)
        return true
    elseif key == " "
        dashboard.paused = !dashboard.paused
        add_event!(dashboard, :info, dashboard.paused ? "Paused" : "Resumed")
        return true
    end

    return false
end

# Start download operation
function start_download(dashboard::OperationalDashboard)
    if dashboard.current_operation != :idle
        add_event!(dashboard, :warning, "Another operation is in progress")
        return
    end

    @async begin
        try
            # Get data directory
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") : dashboard.config.data_dir
            mkpath(data_dir)

            datasets = ["train", "validation", "live"]

            for (idx, dataset) in enumerate(datasets)
                if !dashboard.running || dashboard.current_operation == :idle
                    break
                end

                dashboard.current_operation = :downloading
                dashboard.operation_description = "Downloading $dataset.parquet"
                dashboard.operation_progress = 0.0
                dashboard.operation_total = 100.0
                dashboard.operation_start_time = time()

                # Create progress callback
                progress_callback = function(phase; kwargs...)
                    if phase == :start
                        size_mb = get(kwargs, :size_mb, 0)
                        dashboard.operation_description = "Downloading $dataset.parquet ($(round(size_mb, digits=1)) MB)"
                    elseif phase == :progress
                        bytes_downloaded = get(kwargs, :bytes_downloaded, 0)
                        total_bytes = get(kwargs, :total_bytes, 1)
                        dashboard.operation_progress = (bytes_downloaded / total_bytes) * 100.0
                        mb_downloaded = bytes_downloaded / (1024^2)
                        mb_total = total_bytes / (1024^2)
                        dashboard.operation_description = @sprintf("Downloading %s: %.1f / %.1f MB",
                                                                  dataset, mb_downloaded, mb_total)
                    elseif phase == :complete
                        push!(dashboard.downloads_completed, dataset)
                        add_event!(dashboard, :success, "Downloaded $dataset successfully")
                    end
                end

                # Download with API
                output_path = joinpath(data_dir, "$dataset.parquet")
                API.download_dataset(dashboard.api_client, dataset, output_path;
                                   progress_callback=progress_callback)

                # Load the data into memory for later use
                if dataset == "train"
                    dashboard.train_df = DataLoader.load_training_data(output_path; sample_pct=0.1)
                elseif dataset == "validation"
                    dashboard.val_df = DataLoader.load_training_data(output_path; sample_pct=0.2)
                elseif dataset == "live"
                    dashboard.live_df = DataLoader.load_live_data(output_path)
                end
            end

            dashboard.current_operation = :idle
            dashboard.operation_description = ""

            # Check for auto-training
            if dashboard.auto_train_after_download &&
               dashboard.downloads_completed == dashboard.required_downloads
                add_event!(dashboard, :info, "All datasets downloaded, starting auto-training...")
                empty!(dashboard.downloads_completed)  # Reset for next cycle
                sleep(1.0)
                start_training(dashboard)
            end

        catch e
            @log_error "Download failed" error=e
            add_event!(dashboard, :error, "Download failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
        end
    end
end

# Start training operation
function start_training(dashboard::OperationalDashboard)
    if dashboard.current_operation != :idle
        add_event!(dashboard, :warning, "Another operation is in progress")
        return
    end

    @async begin
        try
            # Check for data
            if isnothing(dashboard.train_df) || isnothing(dashboard.val_df)
                add_event!(dashboard, :error, "No training data available. Download first.")
                return
            end

            dashboard.current_operation = :training
            dashboard.operation_description = "Initializing model..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()

            # Create ML pipeline if needed
            if isnothing(dashboard.ml_pipeline)
                model_config = isa(dashboard.config, Dict) ?
                              get(dashboard.config, :model, Dict(:type => "XGBoost")) :
                              try dashboard.config.model catch; Dict(:type => "XGBoost") end

                feature_cols = filter(n -> startswith(n, "feature_"), names(dashboard.train_df))
                target_col = "target_cyrus_v4_20"

                dashboard.ml_pipeline = Pipeline.MLPipeline(
                    feature_cols=feature_cols,
                    target_col=target_col,
                    model_configs=Dict("model" => model_config)
                )
            end

            # Create callback for progress updates
            training_callback = Models.Callbacks.create_dashboard_callback(
                function(info::Models.Callbacks.CallbackInfo)
                    if info.total_epochs > 0
                        dashboard.operation_progress = Float64(info.epoch)
                        dashboard.operation_total = Float64(info.total_epochs)
                        desc = "Epoch $(info.epoch)/$(info.total_epochs)"
                        if !isnothing(info.loss)
                            desc *= @sprintf(" - Loss: %.4f", info.loss)
                        end
                        if !isnothing(info.val_score)
                            desc *= @sprintf(" - Val: %.4f", info.val_score)
                        end
                        dashboard.operation_description = desc
                    elseif !isnothing(info.total_iterations) && info.total_iterations > 0
                        dashboard.operation_progress = Float64(info.iteration)
                        dashboard.operation_total = Float64(info.total_iterations)
                        dashboard.operation_description = "Iteration $(info.iteration)/$(info.total_iterations)"
                    else
                        # For tree-based models without clear progress
                        elapsed = info.elapsed_time
                        estimated_total = 60.0  # Assume 60 seconds
                        dashboard.operation_progress = min(99.0, (elapsed / estimated_total) * 100.0)
                        dashboard.operation_total = 100.0
                        dashboard.operation_description = "Training $(info.model_name)..."
                    end

                    return Models.Callbacks.CONTINUE
                end,
                frequency=1
            )

            # Train the model
            Pipeline.train!(dashboard.ml_pipeline, dashboard.train_df, dashboard.val_df;
                          callbacks=[training_callback])

            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            add_event!(dashboard, :success, "Training completed successfully")

            # Auto-generate predictions after training
            if dashboard.auto_train_after_download
                sleep(1.0)
                start_predictions(dashboard)
            end

        catch e
            @log_error "Training failed" error=e
            add_event!(dashboard, :error, "Training failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
        end
    end
end

# Start prediction generation
function start_predictions(dashboard::OperationalDashboard)
    if dashboard.current_operation != :idle
        add_event!(dashboard, :warning, "Another operation is in progress")
        return
    end

    @async begin
        try
            # Check for model and data
            if isnothing(dashboard.ml_pipeline)
                add_event!(dashboard, :error, "No trained model available")
                return
            end

            if isnothing(dashboard.live_df)
                add_event!(dashboard, :error, "No live data available. Download first.")
                return
            end

            dashboard.current_operation = :predicting
            dashboard.operation_description = "Generating predictions..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()

            # Generate predictions
            predictions = Pipeline.predict(dashboard.ml_pipeline, dashboard.live_df)

            # Simulate progress (since predict doesn't have callbacks)
            for i in 1:10
                dashboard.operation_progress = i * 10.0
                dashboard.operation_description = "Processing batch $(i)/10..."
                sleep(0.1)
            end

            # Save predictions
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") : dashboard.config.data_dir
            predictions_path = joinpath(data_dir, "predictions.csv")

            # Create predictions DataFrame
            predictions_df = DataFrame(
                id = dashboard.live_df.id,
                prediction = predictions
            )

            CSV.write(predictions_path, predictions_df)

            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            add_event!(dashboard, :success, "Predictions saved to $predictions_path")

        catch e
            @log_error "Prediction failed" error=e
            add_event!(dashboard, :error, "Prediction failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
        end
    end
end

# Start submission
function start_submission(dashboard::OperationalDashboard)
    if dashboard.current_operation != :idle
        add_event!(dashboard, :warning, "Another operation is in progress")
        return
    end

    @async begin
        try
            data_dir = isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") : dashboard.config.data_dir
            predictions_path = joinpath(data_dir, "predictions.csv")

            if !isfile(predictions_path)
                add_event!(dashboard, :error, "No predictions file found")
                return
            end

            dashboard.current_operation = :uploading
            dashboard.operation_description = "Uploading predictions..."
            dashboard.operation_progress = 0.0
            dashboard.operation_total = 100.0
            dashboard.operation_start_time = time()

            # Create progress callback
            progress_callback = function(phase; kwargs...)
                if phase == :start
                    size_mb = get(kwargs, :size_mb, 0)
                    dashboard.operation_description = "Preparing upload ($(round(size_mb, digits=1)) MB)"
                elseif phase == :progress
                    progress_pct = get(kwargs, :progress, 0)
                    dashboard.operation_progress = Float64(progress_pct)
                    dashboard.operation_description = "Uploading: $(Int(progress_pct))%"
                elseif phase == :complete
                    submission_id = get(kwargs, :submission_id, "")
                    add_event!(dashboard, :success, "Submission successful! ID: $submission_id")
                end
            end

            # Get model name
            model_name = isa(dashboard.config, Dict) ?
                        get(dashboard.config, :model_name, "numerai_model") :
                        try dashboard.config.models[1] catch; "numerai_model" end

            # Submit predictions
            submission_id = API.submit_predictions(dashboard.api_client, model_name, predictions_path;
                                                  progress_callback=progress_callback)

            dashboard.current_operation = :idle
            dashboard.operation_description = ""
            add_event!(dashboard, :success, "Submission completed: $submission_id")

        catch e
            @log_error "Submission failed" error=e
            add_event!(dashboard, :error, "Submission failed: $(sprint(showerror, e))")
            dashboard.current_operation = :idle
        end
    end
end

# Main dashboard loop
function run_operational_dashboard(config)
    dashboard = OperationalDashboard(config)
    dashboard.running = true

    # Hide cursor
    print("\033[?25l")

    try
        add_event!(dashboard, :info, "🚀 Dashboard started - All operations fully functional")
        add_event!(dashboard, :info, "Press command keys directly (no Enter needed)")

        # Initial system update
        update_system_info!(dashboard)

        # Initial render
        render_dashboard(dashboard)

        # Main loop
        while dashboard.running
            # Check for keyboard input (non-blocking)
            key = read_key_nonblocking()
            if !isempty(key)
                handle_command(dashboard, key)
            end

            # Update system info every second
            if time() - dashboard.last_system_update >= 1.0
                update_system_info!(dashboard)
            end

            # Render dashboard every 100ms or when there's an active operation
            if time() - dashboard.last_render_time >= 0.1 || dashboard.current_operation != :idle
                render_dashboard(dashboard)
                dashboard.last_render_time = time()
            end

            # Small sleep to prevent CPU spinning
            sleep(0.01)
        end

    finally
        # Show cursor
        print("\033[?25h")
        # Clear screen
        clear_screen()
        println("Dashboard stopped.")
    end
end

end # module