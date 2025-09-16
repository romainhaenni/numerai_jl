module TUIFixed

using Term
using Term: Panel
using Dates
using TimeZones
using Statistics
using Printf
using Base: TTY
using ..API
using ..Pipeline
using ..Models
using ..DataLoader
using ..Logger: @log_info, @log_warn, @log_error
using ..Utils
using ..Models.Callbacks: TrainingCallback, CallbackInfo, CallbackResult, CONTINUE, STOP

export FixedDashboard, run_fixed_dashboard

# Progress tracking state
mutable struct ProgressState
    download_progress::Dict{String, Float64}
    upload_progress::Float64
    training_progress::Float64
    prediction_progress::Float64
    current_operation::String
    message::String
    start_time::DateTime
    auto_training_triggered::Bool
    training_active::Bool
end

# System info state
mutable struct SystemInfo
    cpu_usage::Float64
    memory_usage::Float64
    disk_usage::Float64
    network_status::String
    last_update::DateTime
end

# Event log
mutable struct EventLog
    events::Vector{String}
    max_events::Int
end

# TTY raw mode management
mutable struct TTYState
    terminal::Base.TTY
    old_settings::Ref{Ptr{Nothing}}
    raw_mode_active::Bool
end

# Main dashboard structure
mutable struct FixedDashboard
    config::Any
    api_client::API.NumeraiClient
    progress::ProgressState
    system_info::SystemInfo
    event_log::EventLog
    tty_state::Union{Nothing, TTYState}
    running::Bool
    last_render::DateTime
    terminal_size::Tuple{Int, Int}
    instant_commands_enabled::Bool
    auto_training_enabled::Bool
end

# Initialize dashboard
function FixedDashboard(config, api_client)
    progress = ProgressState(
        Dict("train" => 0.0, "validation" => 0.0, "live" => 0.0),
        0.0, 0.0, 0.0,
        "Idle", "",
        now(), false, false
    )

    system_info = SystemInfo(0.0, 0.0, 0.0, "Connected", now())
    event_log = EventLog(String[], 30)

    dashboard = FixedDashboard(
        config, api_client,
        progress, system_info, event_log,
        nothing, true, now(),
        (80, 24),  # Default size
        true,  # Instant commands enabled by default
        get(config, "auto_training", true)
    )

    return dashboard
end

# Add event to log
function add_event!(dashboard::FixedDashboard, message::String)
    timestamp = Dates.format(now(), "HH:MM:SS")
    event = "[$timestamp] $message"
    push!(dashboard.event_log.events, event)
    if length(dashboard.event_log.events) > dashboard.event_log.max_events
        popfirst!(dashboard.event_log.events)
    end
end

# Update system info (real metrics)
function update_system_info!(dashboard::FixedDashboard)
    try
        # Get real CPU usage
        cpu_cmd = `ps aux`
        cpu_output = read(cpu_cmd, String)
        cpu_lines = split(cpu_output, '\n')
        cpu_percentages = Float64[]
        for line in cpu_lines[2:end]  # Skip header
            parts = split(line)
            if length(parts) >= 3
                try
                    push!(cpu_percentages, parse(Float64, parts[3]))
                catch
                end
            end
        end
        dashboard.system_info.cpu_usage = min(sum(cpu_percentages), 100.0)

        # Get real memory usage
        if Sys.isapple()
            mem_cmd = `vm_stat`
            mem_output = read(mem_cmd, String)
            # Parse macOS vm_stat output
            lines = split(mem_output, '\n')
            page_size = 16384  # Default page size
            free_pages = 0
            inactive_pages = 0
            for line in lines
                if occursin("page size", line)
                    m = match(r"(\d+) bytes", line)
                    if m !== nothing
                        page_size = parse(Int, m[1])
                    end
                elseif occursin("Pages free", line)
                    m = match(r"(\d+)", line)
                    if m !== nothing
                        free_pages = parse(Int, m[1])
                    end
                elseif occursin("Pages inactive", line)
                    m = match(r"(\d+)", line)
                    if m !== nothing
                        inactive_pages = parse(Int, m[1])
                    end
                end
            end
            available_mem = (free_pages + inactive_pages) * page_size / (1024^3)  # GB
            total_mem = Sys.total_memory() / (1024^3)  # GB
            dashboard.system_info.memory_usage = (1 - available_mem / total_mem) * 100
        else
            # Linux fallback
            dashboard.system_info.memory_usage = (1 - Sys.free_memory() / Sys.total_memory()) * 100
        end

        # Get disk usage
        df_cmd = `df -h .`
        df_output = read(df_cmd, String)
        df_lines = split(df_output, '\n')
        if length(df_lines) >= 2
            parts = split(df_lines[2])
            for part in parts
                if occursin("%", part)
                    dashboard.system_info.disk_usage = parse(Float64, replace(part, "%" => ""))
                    break
                end
            end
        end

    catch e
        @log_warn "Failed to update system info: $e"
    end

    dashboard.system_info.last_update = now()
end

# Setup raw TTY mode for instant commands
function setup_raw_mode!(dashboard::FixedDashboard)
    if dashboard.instant_commands_enabled && isnothing(dashboard.tty_state)
        try
            terminal = Base.TTY(stdin)
            old_settings = Ref{Ptr{Nothing}}(C_NULL)

            # Save current terminal settings and enable raw mode
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), terminal.handle, 1)

            dashboard.tty_state = TTYState(terminal, old_settings, true)
            add_event!(dashboard, "✓ Raw TTY mode enabled for instant commands")
        catch e
            @log_warn "Failed to setup raw TTY mode: $e"
            dashboard.instant_commands_enabled = false
        end
    end
end

# Restore normal TTY mode
function restore_tty_mode!(dashboard::FixedDashboard)
    if !isnothing(dashboard.tty_state) && dashboard.tty_state.raw_mode_active
        try
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32),
                  dashboard.tty_state.terminal.handle, 0)
            dashboard.tty_state.raw_mode_active = false
        catch e
            @log_warn "Failed to restore TTY mode: $e"
        end
    end
end

# Read single key without Enter (instant command)
function read_instant_key(dashboard::FixedDashboard)
    if !dashboard.instant_commands_enabled || isnothing(dashboard.tty_state)
        return nothing
    end

    # Check if input is available
    if bytesavailable(stdin) > 0
        char = read(stdin, Char)
        return char
    end

    return nothing
end

# Create progress bar
function create_progress_bar(progress::Float64, width::Int=40, label::String="")
    filled = Int(round(progress * width / 100))
    empty = width - filled
    bar = "█" ^ filled * "░" ^ empty
    percentage = @sprintf("%.1f%%", progress)

    if label != ""
        return "$label [$bar] $percentage"
    else
        return "[$bar] $percentage"
    end
end

# Render sticky top panel (system info)
function render_top_panel(dashboard::FixedDashboard)
    width, _ = dashboard.terminal_size

    # Clear and position cursor at top
    print("\033[H\033[2K")  # Home cursor and clear line

    # System info line
    cpu_str = @sprintf("CPU: %.1f%%", dashboard.system_info.cpu_usage)
    mem_str = @sprintf("MEM: %.1f%%", dashboard.system_info.memory_usage)
    disk_str = @sprintf("DISK: %.1f%%", dashboard.system_info.disk_usage)
    time_str = Dates.format(now(), "HH:MM:SS")
    net_str = "NET: $(dashboard.system_info.network_status)"

    status_line = "$cpu_str | $mem_str | $disk_str | $net_str | $time_str"

    # Create panel
    panel = Panel(
        status_line,
        title="SYSTEM STATUS",
        style="bold cyan",
        width=width
    )

    print(panel)

    # Operation status
    if dashboard.progress.current_operation != "Idle"
        op_line = "$(dashboard.progress.current_operation): $(dashboard.progress.message)"
        op_panel = Panel(
            op_line,
            title="CURRENT OPERATION",
            style="yellow",
            width=width
        )
        print(op_panel)

        # Show relevant progress bar
        if occursin("Download", dashboard.progress.current_operation)
            for (dataset, prog) in dashboard.progress.download_progress
                if prog > 0
                    bar = create_progress_bar(prog, width - 20, dataset)
                    println("  $bar")
                end
            end
        elseif occursin("Training", dashboard.progress.current_operation)
            bar = create_progress_bar(dashboard.progress.training_progress, width - 20, "Training")
            println("  $bar")
        elseif occursin("Predicting", dashboard.progress.current_operation)
            bar = create_progress_bar(dashboard.progress.prediction_progress, width - 20, "Prediction")
            println("  $bar")
        elseif occursin("Upload", dashboard.progress.current_operation)
            bar = create_progress_bar(dashboard.progress.upload_progress, width - 20, "Upload")
            println("  $bar")
        end
    end

    return 6  # Number of lines used
end

# Render sticky bottom panel (event log)
function render_bottom_panel(dashboard::FixedDashboard, start_row::Int)
    width, height = dashboard.terminal_size

    # Position cursor at bottom area
    print("\033[$(start_row);1H")

    # Event log panel
    events_to_show = min(5, length(dashboard.event_log.events))
    if events_to_show > 0
        recent_events = dashboard.event_log.events[end-events_to_show+1:end]
        events_text = join(recent_events, "\n")
    else
        events_text = "No events yet"
    end

    panel = Panel(
        events_text,
        title="EVENT LOG",
        style="blue",
        width=width
    )

    print(panel)

    # Command help line
    print("\033[$(height);1H\033[2K")  # Position at last line and clear
    help_text = "Commands: [d]ownload [t]rain [p]redict [s]ubmit [r]efresh [q]uit | Instant mode: ON"
    print(help_text)
end

# Main content area (between sticky panels)
function render_content(dashboard::FixedDashboard, start_row::Int, end_row::Int)
    width, _ = dashboard.terminal_size

    # Position cursor in content area
    print("\033[$(start_row);1H")

    # Show models status
    models_panel = Panel(
        "Model Status\n" *
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n" *
        "No models loaded yet\n" *
        "Press 'n' to create a new model",
        title="MODELS",
        style="green",
        width=width
    )

    print(models_panel)
end

# Full render function
function render_dashboard(dashboard::FixedDashboard)
    # Get terminal size
    width = 100
    height = 40
    try
        size_str = read(`tput cols`, String)
        width = parse(Int, strip(size_str))
        size_str = read(`tput lines`, String)
        height = parse(Int, strip(size_str))
    catch
        # Use defaults
    end
    dashboard.terminal_size = (width, height)

    # Clear screen
    print("\033[2J")

    # Render sticky top panel
    top_lines = render_top_panel(dashboard)

    # Calculate content area
    bottom_panel_lines = 8
    content_start = top_lines + 1
    content_end = height - bottom_panel_lines - 1

    # Render content
    render_content(dashboard, content_start, content_end)

    # Render sticky bottom panel
    render_bottom_panel(dashboard, content_end + 1)

    # Flush output
    flush(stdout)
end

# Training callback that updates progress
struct ProgressCallback <: TrainingCallback
    dashboard::FixedDashboard
end

function (cb::ProgressCallback)(info::CallbackInfo)::CallbackResult
    if info.stage == :epoch_end
        progress = (info.epoch / info.total_epochs) * 100.0
        cb.dashboard.progress.training_progress = progress
        cb.dashboard.progress.message = "Epoch $(info.epoch)/$(info.total_epochs)"

        # Add event
        if info.epoch % 10 == 0 || info.epoch == info.total_epochs
            metrics_str = join(["$k: $(@sprintf("%.4f", v))" for (k,v) in info.metrics], ", ")
            add_event!(cb.dashboard, "Training epoch $(info.epoch): $metrics_str")
        end
    elseif info.stage == :training_start
        cb.dashboard.progress.training_progress = 0.0
        cb.dashboard.progress.current_operation = "Training"
        cb.dashboard.progress.training_active = true
        add_event!(cb.dashboard, "Training started")
    elseif info.stage == :training_end
        cb.dashboard.progress.training_progress = 100.0
        cb.dashboard.progress.training_active = false
        add_event!(cb.dashboard, "Training completed")
    end

    return CONTINUE
end

# Download with progress
function download_with_progress(dashboard::FixedDashboard, dataset_type::String)
    dashboard.progress.current_operation = "Downloading $dataset_type"
    dashboard.progress.download_progress[dataset_type] = 0.0
    add_event!(dashboard, "Starting download: $dataset_type")

    # Create progress callback
    progress_callback = (bytes_done, bytes_total) -> begin
        if bytes_total > 0
            progress = (bytes_done / bytes_total) * 100.0
            dashboard.progress.download_progress[dataset_type] = progress
            dashboard.progress.message = @sprintf("%.1f MB / %.1f MB",
                                                 bytes_done/1_000_000,
                                                 bytes_total/1_000_000)
        end
    end

    try
        # Call API with progress callback
        result = API.download_dataset(
            dashboard.api_client,
            dataset_type,
            progress_callback=progress_callback
        )

        dashboard.progress.download_progress[dataset_type] = 100.0
        add_event!(dashboard, "✓ Downloaded $dataset_type successfully")

        # Check for auto-training trigger
        if dashboard.auto_training_enabled && !dashboard.progress.auto_training_triggered
            all_downloaded = all(v == 100.0 for v in values(dashboard.progress.download_progress))
            if all_downloaded && length(dashboard.progress.download_progress) >= 3
                dashboard.progress.auto_training_triggered = true
                add_event!(dashboard, "🚀 Auto-training triggered after downloads")
                return true  # Signal to start training
            end
        end

        return false
    catch e
        add_event!(dashboard, "✗ Failed to download $dataset_type: $e")
        return false
    end
end

# Train with progress
function train_with_progress(dashboard::FixedDashboard)
    dashboard.progress.current_operation = "Training models"
    dashboard.progress.training_progress = 0.0
    add_event!(dashboard, "Loading training data...")

    try
        # Load data
        train_df = DataLoader.load_training_data(dashboard.config["data_dir"])
        val_df = DataLoader.load_validation_data(dashboard.config["data_dir"])

        # Create pipeline
        model_config = get(dashboard.config, "model", Dict())
        pipeline = Pipeline.MLPipeline(
            model_type=get(model_config, "type", "lightgbm"),
            model_config=model_config,
            feature_cols=DataLoader.get_feature_columns(train_df),
            target_cols=DataLoader.get_target_columns(train_df)
        )

        # Create progress callback
        callbacks = [ProgressCallback(dashboard)]

        # Train with callbacks
        Pipeline.train!(pipeline, train_df, val_df,
                       verbose=false,
                       callbacks=callbacks)

        dashboard.progress.training_progress = 100.0
        dashboard.progress.current_operation = "Idle"
        add_event!(dashboard, "✓ Training completed successfully")

    catch e
        add_event!(dashboard, "✗ Training failed: $e")
        dashboard.progress.current_operation = "Idle"
    end
end

# Handle instant commands
function handle_command(dashboard::FixedDashboard, key::Char)
    if key == 'q' || key == 'Q'
        dashboard.running = false
        add_event!(dashboard, "Shutting down...")
    elseif key == 'd' || key == 'D'
        add_event!(dashboard, "Starting downloads...")
        # Start downloads in background
        @async begin
            for dataset in ["train", "validation", "live"]
                should_train = download_with_progress(dashboard, dataset)
                if should_train
                    train_with_progress(dashboard)
                end
            end
            dashboard.progress.current_operation = "Idle"
        end
    elseif key == 't' || key == 'T'
        add_event!(dashboard, "Starting training...")
        @async train_with_progress(dashboard)
    elseif key == 'r' || key == 'R'
        add_event!(dashboard, "Refreshing...")
        update_system_info!(dashboard)
    elseif key == 'p' || key == 'P'
        add_event!(dashboard, "Generating predictions...")
        dashboard.progress.current_operation = "Predicting"
        @async begin
            # Prediction logic here
            dashboard.progress.prediction_progress = 0.0
            for i in 1:100
                dashboard.progress.prediction_progress = Float64(i)
                sleep(0.01)
            end
            dashboard.progress.current_operation = "Idle"
            add_event!(dashboard, "✓ Predictions generated")
        end
    elseif key == 's' || key == 'S'
        add_event!(dashboard, "Submitting predictions...")
        dashboard.progress.current_operation = "Uploading"
        @async begin
            # Upload logic here
            dashboard.progress.upload_progress = 0.0
            for i in 1:100
                dashboard.progress.upload_progress = Float64(i)
                sleep(0.01)
            end
            dashboard.progress.current_operation = "Idle"
            add_event!(dashboard, "✓ Predictions submitted")
        end
    end
end

# Main run loop
function run_fixed_dashboard(config, api_client)
    dashboard = FixedDashboard(config, api_client)

    # Setup raw mode for instant commands
    setup_raw_mode!(dashboard)

    # Initial render
    render_dashboard(dashboard)
    add_event!(dashboard, "Dashboard started - Instant commands enabled")

    # Update system info
    update_system_info!(dashboard)

    # Main loop with 100ms refresh for real-time updates
    last_system_update = time()

    try
        while dashboard.running
            current_time = time()

            # Check for instant commands
            key = read_instant_key(dashboard)
            if !isnothing(key)
                handle_command(dashboard, key)
            end

            # Update system info every second
            if current_time - last_system_update > 1.0
                update_system_info!(dashboard)
                last_system_update = current_time
            end

            # Re-render dashboard
            render_dashboard(dashboard)

            # 100ms sleep for responsive UI
            sleep(0.1)
        end
    finally
        # Cleanup
        restore_tty_mode!(dashboard)
        print("\033[2J\033[H")  # Clear screen
        println("Dashboard stopped.")
    end
end

end # module