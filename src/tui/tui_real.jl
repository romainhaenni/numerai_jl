module TUIReal

using Term
using Term: Panel, RenderableText
using Dates
using TimeZones
using Printf
using Statistics
using DataFrames
using ..API
using ..Pipeline
using ..Models
using ..Models.Callbacks
using ..Logger: @log_info, @log_warn, @log_error
using ..Utils
using ..DataLoader

export RealDashboard, run_real_dashboard, update_progress!, instant_command_handler

# Progress tracking state
mutable struct ProgressState
    operation::Symbol  # :download, :upload, :training, :prediction, :idle
    description::String
    current::Float64
    total::Float64
    start_time::Float64
    last_update::Float64
end

# Dashboard state with proper progress tracking
mutable struct RealDashboard
    config::Any
    api_client::API.NumeraiClient
    ml_pipeline::Union{Nothing, Pipeline.MLPipeline}
    running::Bool
    paused::Bool

    # Progress tracking
    progress::ProgressState

    # System info
    system_info::Dict{Symbol, Any}

    # Events log (last 30)
    events::Vector{Dict{Symbol, Any}}
    max_events::Int

    # Command handling
    command_mode::Bool
    command_buffer::String
    instant_commands_enabled::Bool

    # Auto-training
    auto_train_enabled::Bool
    downloads_completed::Set{String}
    required_downloads::Set{String}

    # Update tracking
    last_render_time::Float64
    last_system_update::Float64
    render_interval::Float64
    system_update_interval::Float64

    # Data storage
    train_df::Union{Nothing, DataFrame}
    val_df::Union{Nothing, DataFrame}
    live_df::Union{Nothing, DataFrame}
end

function RealDashboard(config, api_client=nothing)
    # Create API client if not provided
    if isnothing(api_client)
        # Handle both struct and dict configs
        if isa(config, Dict)
            public_key = get(config, :api_public_key, "")
            secret_key = get(config, :api_secret_key, "")
        else
            public_key = config.api_public_key
            secret_key = config.api_secret_key
        end
        api_client = API.NumeraiClient(public_key, secret_key)
    end

    # Extract auto_train setting properly
    auto_train = if isa(config, Dict)
        get(config, :auto_train_after_download, true)
    else
        try
            config.auto_train_after_download
        catch
            true
        end
    end

    RealDashboard(
        config,
        api_client,
        nothing,  # ml_pipeline (created on demand)
        false,  # running
        false,  # paused
        ProgressState(:idle, "", 0.0, 100.0, time(), time()),
        Dict{Symbol, Any}(  # system_info
            :cpu_usage => 0,
            :memory_used => 0.0,
            :memory_total => 16.0,
            :disk_free => 100.0,
            :threads => Threads.nthreads(),
            :julia_version => string(VERSION),
            :uptime => 0
        ),
        Vector{Dict{Symbol, Any}}(),  # events
        30,  # max_events
        false,  # command_mode
        "",  # command_buffer
        true,  # instant_commands_enabled
        auto_train,  # auto_train_enabled (use extracted value)
        Set{String}(),  # downloads_completed
        Set(["train", "validation", "live"]),  # required_downloads
        time(),  # last_render_time
        time(),  # last_system_update
        0.1,  # render_interval (100ms for responsive updates)
        1.0,   # system_update_interval
        nothing,  # train_df
        nothing,  # val_df
        nothing   # live_df
    )
end

# Progress update function that actually updates the dashboard state
function update_progress!(dashboard::RealDashboard, operation::Symbol, current::Float64, total::Float64, description::String="")
    dashboard.progress.operation = operation
    dashboard.progress.current = current
    dashboard.progress.total = total
    dashboard.progress.description = description
    dashboard.progress.last_update = time()

    # Force immediate render for progress updates
    dashboard.last_render_time = 0.0
end

# Add event with proper timestamp and overflow handling
function add_event!(dashboard::RealDashboard, type::Symbol, message::String)
    event = Dict{Symbol, Any}(
        :type => type,
        :message => message,
        :time => now()
    )

    push!(dashboard.events, event)

    # Keep only last N events
    if length(dashboard.events) > dashboard.max_events
        deleteat!(dashboard.events, 1:(length(dashboard.events) - dashboard.max_events))
    end
end

# Update system information (real implementation)
function update_system_info!(dashboard::RealDashboard)
    try
        # Get CPU usage (macOS specific)
        cpu_cmd = `top -l 1 -n 0`
        cpu_output = read(cpu_cmd, String)
        cpu_match = match(r"CPU usage: ([\d.]+)% user", cpu_output)
        if !isnothing(cpu_match)
            dashboard.system_info[:cpu_usage] = round(parse(Float64, cpu_match.captures[1]), digits=1)
        end

        # Get memory usage (macOS specific)
        mem_cmd = `vm_stat`
        mem_output = read(mem_cmd, String)

        # Parse vm_stat output
        page_size = 4096  # Default page size
        pages_free = 0
        pages_active = 0
        pages_inactive = 0
        pages_wired = 0

        for line in split(mem_output, '\n')
            if occursin("page size", line)
                m = match(r"page size of (\d+) bytes", line)
                if !isnothing(m)
                    page_size = parse(Int, m.captures[1])
                end
            elseif occursin("Pages free", line)
                m = match(r"Pages free:\s+(\d+)", line)
                if !isnothing(m)
                    pages_free = parse(Int, m.captures[1])
                end
            elseif occursin("Pages active", line)
                m = match(r"Pages active:\s+(\d+)", line)
                if !isnothing(m)
                    pages_active = parse(Int, m.captures[1])
                end
            elseif occursin("Pages inactive", line)
                m = match(r"Pages inactive:\s+(\d+)", line)
                if !isnothing(m)
                    pages_inactive = parse(Int, m.captures[1])
                end
            elseif occursin("Pages wired", line)
                m = match(r"Pages wired down:\s+(\d+)", line)
                if !isnothing(m)
                    pages_wired = parse(Int, m.captures[1])
                end
            end
        end

        # Calculate memory in GB
        total_pages = pages_free + pages_active + pages_inactive + pages_wired
        if total_pages > 0
            memory_used_gb = (pages_active + pages_wired) * page_size / (1024^3)
            memory_total_gb = total_pages * page_size / (1024^3)
            dashboard.system_info[:memory_used] = round(memory_used_gb, digits=1)
            dashboard.system_info[:memory_total] = round(memory_total_gb, digits=1)
        end

        # Get disk usage
        disk_cmd = `df -h /`
        disk_output = read(disk_cmd, String)
        disk_lines = split(disk_output, '\n')
        if length(disk_lines) >= 2
            disk_parts = split(disk_lines[2])
            if length(disk_parts) >= 4
                available = disk_parts[4]
                # Parse available space (remove unit suffix)
                if endswith(available, "G")
                    dashboard.system_info[:disk_free] = parse(Float64, available[1:end-1])
                elseif endswith(available, "T")
                    dashboard.system_info[:disk_free] = parse(Float64, available[1:end-1]) * 1024
                end
            end
        end

    catch e
        @log_warn "Failed to update system info" error=e
    end

    dashboard.last_system_update = time()
end

# Create progress bar string
function create_progress_bar(current::Float64, total::Float64; width::Int=40)
    if total <= 0
        return "["* "?" ^ width * "]"
    end

    percentage = min(100.0, (current / total) * 100.0)
    filled = Int(round((percentage / 100.0) * width))
    empty = width - filled

    bar = "[" * "█" ^ filled * "░" ^ empty * "]"
    return "$bar $(round(percentage, digits=1))%"
end

# Render sticky top panel with system info
function render_top_panel(dashboard::RealDashboard)
    term_width = displaysize(stdout)[2]

    # Clear line and move to top
    print("\033[H\033[K")

    # System status line
    status = dashboard.paused ? "⏸ PAUSED" : "▶ RUNNING"
    cpu = dashboard.system_info[:cpu_usage]
    mem_used = dashboard.system_info[:memory_used]
    mem_total = dashboard.system_info[:memory_total]
    mem_pct = mem_total > 0 ? round(100 * mem_used / mem_total, digits=0) : 0

    status_line = "System: $status │ CPU: $(cpu)% │ Memory: $(mem_used)/$(mem_total) GB ($(Int(mem_pct))%) │ Uptime: $(dashboard.system_info[:uptime])s"
    println(status_line)
    println("─" ^ term_width)
end

# Render progress section
function render_progress(dashboard::RealDashboard)
    if dashboard.progress.operation == :idle
        return
    end

    term_width = displaysize(stdout)[2]

    # Operation header
    op_name = uppercase(string(dashboard.progress.operation))
    println("\n🔄 $op_name IN PROGRESS")

    # Progress bar
    if dashboard.progress.total > 0
        progress_bar = create_progress_bar(dashboard.progress.current, dashboard.progress.total)
        println(progress_bar)
    else
        # Indeterminate progress (spinner)
        spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        spinner_idx = Int(floor(time() * 10)) % length(spinner_chars) + 1
        println("$(spinner_chars[spinner_idx]) Working...")
    end

    # Description if available
    if !isempty(dashboard.progress.description)
        println(dashboard.progress.description)
    end

    # Time elapsed
    elapsed = time() - dashboard.progress.start_time
    elapsed_str = @sprintf("%.1f", elapsed)
    println("Elapsed: $(elapsed_str)s")

    println("─" ^ term_width)
end

# Render sticky bottom panel with event log
function render_bottom_panel(dashboard::RealDashboard)
    term_height = displaysize(stdout)[1]
    term_width = displaysize(stdout)[2]

    # Move to bottom section (leave 8 lines for events)
    print("\033[$(term_height - 8);1H")

    println("─" ^ term_width)
    println("📋 RECENT EVENTS")

    if isempty(dashboard.events)
        println("  No recent events")
    else
        # Show last 5 events
        start_idx = max(1, length(dashboard.events) - 4)
        for event in dashboard.events[start_idx:end]
            timestamp = Dates.format(event[:time], "HH:MM:SS")
            icon = event[:type] == :error ? "❌" :
                   event[:type] == :warning ? "⚠️" :
                   event[:type] == :success ? "✅" : "ℹ️"
            msg = event[:message]
            if length(msg) > term_width - 15
                msg = msg[1:term_width-18] * "..."
            end
            println("  [$timestamp] $icon $msg")
        end
    end

    # Command line at very bottom
    print("\033[$(term_height);1H\033[K")
    if dashboard.command_mode
        print("Command: /$(dashboard.command_buffer)_")
    else
        print("Commands: [d]ownload [t]rain [p]redict [s]ubmit [r]efresh [q]uit (instant, no Enter needed)")
    end
end

# Main rendering function
function render_dashboard(dashboard::RealDashboard)
    # Clear screen and reset cursor
    print("\033[2J\033[H")

    # Render sticky top panel
    render_top_panel(dashboard)

    # Render main content area
    if dashboard.progress.operation != :idle
        render_progress(dashboard)
    end

    # Render sticky bottom panel
    render_bottom_panel(dashboard)
end

# Check if auto-training should trigger
function check_auto_train(dashboard::RealDashboard)
    if !dashboard.auto_train_enabled
        return false
    end

    # Check if all required downloads are complete
    if dashboard.downloads_completed == dashboard.required_downloads
        add_event!(dashboard, :info, "All data downloaded, starting auto-training...")
        return true
    end

    return false
end

# Reset downloads after auto-train trigger
function reset_downloads!(dashboard::RealDashboard)
    empty!(dashboard.downloads_completed)
end

# Handle download completion
function on_download_complete(dashboard::RealDashboard, dataset_type::String)
    push!(dashboard.downloads_completed, dataset_type)
    add_event!(dashboard, :success, "Downloaded $dataset_type dataset")

    if check_auto_train(dashboard)
        # Reset for next cycle
        reset_downloads!(dashboard)
        # Trigger training
        @async begin
            sleep(1.0)  # Brief pause before starting training
            start_training(dashboard)
        end
    end
end

# Start training process with REAL ML pipeline
function start_training(dashboard::RealDashboard)
    add_event!(dashboard, :info, "Starting model training...")
    update_progress!(dashboard, :training, 0.0, 100.0, "Initializing training...")

    @async begin
        try
            # Check if we have data
            if isnothing(dashboard.train_df) || isnothing(dashboard.val_df)
                add_event!(dashboard, :error, "No training data available. Download data first.")
                update_progress!(dashboard, :idle, 0.0, 0.0)
                return
            end

            # Create ML pipeline if not exists
            if isnothing(dashboard.ml_pipeline)
                # Get model config
                model_config = if isa(dashboard.config, Dict)
                    get(dashboard.config, :model, Dict(:type => "XGBoost"))
                else
                    try
                        dashboard.config.model
                    catch
                        Dict(:type => "XGBoost")
                    end
                end

                # Create pipeline
                dashboard.ml_pipeline = Pipeline.MLPipeline(
                    model_config,
                    dashboard.api_client,
                    nothing  # Let pipeline determine targets
                )
            end

            # Create training callback for progress updates
            training_callback = Models.Callbacks.create_dashboard_callback(
                function(info::Models.Callbacks.CallbackInfo)
                    # Update progress based on training info
                    if info.total_epochs > 0
                        progress_pct = (info.epoch / info.total_epochs) * 100.0
                        desc = "Epoch $(info.epoch)/$(info.total_epochs)"
                        if !isnothing(info.loss)
                            desc *= " - Loss: $(round(info.loss, digits=4))"
                        end
                        if !isnothing(info.val_score)
                            desc *= " - Val: $(round(info.val_score, digits=4))"
                        end
                        update_progress!(dashboard, :training, Float64(info.epoch), Float64(info.total_epochs), desc)
                    elseif info.total_iterations !== nothing && info.total_iterations > 0
                        progress_pct = (info.iteration / info.total_iterations) * 100.0
                        desc = "Iteration $(info.iteration)/$(info.total_iterations)"
                        update_progress!(dashboard, :training, Float64(info.iteration), Float64(info.total_iterations), desc)
                    else
                        # For models without clear progress (tree-based), use time estimate
                        desc = "Training $(info.model_name)..."
                        if !isnothing(info.eta)
                            desc *= " - ETA: $(round(info.eta, digits=0))s"
                        end
                        # Estimate progress based on time (assume 60s total)
                        progress = min(info.elapsed_time / 60.0 * 100.0, 99.0)
                        update_progress!(dashboard, :training, progress, 100.0, desc)
                    end

                    return Models.Callbacks.CONTINUE  # Continue training
                end,
                frequency=1  # Update every epoch/iteration
            )

            # Train the model with real data
            @log_info "Starting real training with pipeline"
            Pipeline.train!(dashboard.ml_pipeline, dashboard.train_df, dashboard.val_df,
                     callbacks=[training_callback])

            update_progress!(dashboard, :idle, 0.0, 0.0)
            add_event!(dashboard, :success, "Training completed successfully")

        catch e
            @log_error "Training failed" error=e
            add_event!(dashboard, :error, "Training failed: $(e)")
            update_progress!(dashboard, :idle, 0.0, 0.0)
        end
    end
end

# Download data with REAL API calls and progress tracking
function download_data(dashboard::RealDashboard)
    @async begin
        try
            for dataset in ["train", "validation", "live"]
                if !dashboard.running
                    break
                end

                add_event!(dashboard, :info, "Downloading $dataset dataset...")
                update_progress!(dashboard, :download, 0.0, 100.0, "Downloading $dataset.parquet")

                # Create progress callback for real download
                progress_callback = function(phase; kwargs...)
                    if phase == :start
                        update_progress!(dashboard, :download, 0.0, 100.0,
                                      "Starting download of $(kwargs[:name])")
                    elseif phase == :progress
                        current_mb = get(kwargs, :current_mb, 0)
                        total_mb = get(kwargs, :total_mb, 100)
                        progress_pct = get(kwargs, :progress, 0)
                        update_progress!(dashboard, :download, progress_pct, 100.0,
                                      "Downloading $(kwargs[:name]) ($(round(current_mb, digits=1)) MB / $(round(total_mb, digits=1)) MB)")
                    elseif phase == :complete
                        size_mb = get(kwargs, :size_mb, 0)
                        add_event!(dashboard, :success, "Downloaded $(kwargs[:name]) ($(round(size_mb, digits=1)) MB)")
                    elseif phase == :error
                        add_event!(dashboard, :error, "Download failed: $(get(kwargs, :message, "Unknown error"))")
                    end
                end

                # Determine output path
                data_dir = if isa(dashboard.config, Dict)
                    get(dashboard.config, :data_dir, "data")
                else
                    try
                        dashboard.config.data_dir
                    catch
                        "data"
                    end
                end

                if !isdir(data_dir)
                    mkpath(data_dir)
                end

                output_path = joinpath(data_dir, "$dataset.parquet")

                # Download with real API
                @log_info "Downloading $dataset dataset to $output_path"
                API.download_dataset(dashboard.api_client, dataset, output_path,
                                   show_progress=false,  # We handle progress ourselves
                                   progress_callback=progress_callback)

                # Load the downloaded data
                if dataset == "train"
                    dashboard.train_df = DataLoader.load_training_data(output_path)
                    @log_info "Loaded train data" rows=nrow(dashboard.train_df) cols=ncol(dashboard.train_df)
                elseif dataset == "validation"
                    dashboard.val_df = DataLoader.load_training_data(output_path)
                    @log_info "Loaded validation data" rows=nrow(dashboard.val_df) cols=ncol(dashboard.val_df)
                elseif dataset == "live"
                    dashboard.live_df = DataLoader.load_live_data(output_path)
                    @log_info "Loaded live data" rows=nrow(dashboard.live_df) cols=ncol(dashboard.live_df)
                end

                on_download_complete(dashboard, dataset)
            end

            update_progress!(dashboard, :idle, 0.0, 0.0)

        catch e
            @log_error "Download failed" error=e
            add_event!(dashboard, :error, "Download failed: $(e)")
            update_progress!(dashboard, :idle, 0.0, 0.0)
        end
    end
end

# Generate predictions with REAL ML pipeline
function generate_predictions(dashboard::RealDashboard)
    @async begin
        try
            add_event!(dashboard, :info, "Generating predictions...")
            update_progress!(dashboard, :prediction, 0.0, 100.0, "Processing live data...")

            # Check if we have live data and trained model
            if isnothing(dashboard.live_df)
                add_event!(dashboard, :error, "No live data available. Download data first.")
                update_progress!(dashboard, :idle, 0.0, 0.0)
                return
            end

            if isnothing(dashboard.ml_pipeline)
                add_event!(dashboard, :error, "No trained model available. Train model first.")
                update_progress!(dashboard, :idle, 0.0, 0.0)
                return
            end

            # Generate predictions with progress tracking
            update_progress!(dashboard, :prediction, 25.0, 100.0, "Preprocessing data...")

            # Predict using the pipeline
            update_progress!(dashboard, :prediction, 50.0, 100.0, "Running inference...")
            predictions_df = Pipeline.predict(dashboard.ml_pipeline, dashboard.live_df)

            update_progress!(dashboard, :prediction, 75.0, 100.0, "Formatting predictions...")

            # Save predictions
            data_dir = if isa(dashboard.config, Dict)
                get(dashboard.config, :data_dir, "data")
            else
                try
                    dashboard.config.data_dir
                catch
                    "data"
                end
            end

            predictions_path = joinpath(data_dir, "predictions.csv")
            Pipeline.save_predictions(dashboard.ml_pipeline, predictions_df, predictions_path)

            update_progress!(dashboard, :idle, 0.0, 0.0)
            add_event!(dashboard, :success, "Predictions generated successfully")

        catch e
            @log_error "Prediction generation failed" error=e
            add_event!(dashboard, :error, "Prediction failed: $(e)")
            update_progress!(dashboard, :idle, 0.0, 0.0)
        end
    end
end

# Submit predictions with REAL API
function submit_predictions(dashboard::RealDashboard)
    @async begin
        try
            # First generate predictions if needed
            predictions_path = joinpath(
                isa(dashboard.config, Dict) ? get(dashboard.config, :data_dir, "data") : dashboard.config.data_dir,
                "predictions.csv"
            )

            if !isfile(predictions_path)
                add_event!(dashboard, :info, "No predictions found, generating first...")
                generate_predictions(dashboard)
                # Wait for predictions to be generated
                wait_time = 0
                while !isfile(predictions_path) && wait_time < 30
                    sleep(1)
                    wait_time += 1
                end

                if !isfile(predictions_path)
                    add_event!(dashboard, :error, "Failed to generate predictions")
                    update_progress!(dashboard, :idle, 0.0, 0.0)
                    return
                end
            end

            add_event!(dashboard, :info, "Uploading predictions...")
            update_progress!(dashboard, :upload, 0.0, 100.0, "Uploading to Numerai...")

            # Create progress callback for real upload
            progress_callback = function(phase; kwargs...)
                if phase == :start
                    model = get(kwargs, :model, "model")
                    size_mb = get(kwargs, :size_mb, 0)
                    update_progress!(dashboard, :upload, 0.0, 100.0,
                                  "Preparing upload for $model ($(round(size_mb, digits=1)) MB)")
                elseif phase == :progress
                    progress_pct = get(kwargs, :progress, 0)
                    phase_desc = get(kwargs, :phase, "Uploading")
                    update_progress!(dashboard, :upload, Float64(progress_pct), 100.0, phase_desc)
                elseif phase == :complete
                    submission_id = get(kwargs, :submission_id, "")
                    add_event!(dashboard, :success, "Submission completed! ID: $submission_id")
                elseif phase == :error
                    add_event!(dashboard, :error, "Upload failed: $(get(kwargs, :message, "Unknown error"))")
                end
            end

            # Get model name
            model_name = if isa(dashboard.config, Dict)
                get(dashboard.config, :model_name, "numerai_model")
            else
                try
                    dashboard.config.model_name
                catch
                    "numerai_model"
                end
            end

            # Submit with real API
            @log_info "Submitting predictions for model $model_name"
            submission_id = API.submit_predictions(dashboard.api_client, model_name, predictions_path,
                                                  progress_callback=progress_callback)

            update_progress!(dashboard, :idle, 0.0, 0.0)
            add_event!(dashboard, :success, "Predictions submitted successfully! ID: $submission_id")

        catch e
            @log_error "Submission failed" error=e
            add_event!(dashboard, :error, "Submission failed: $(e)")
            update_progress!(dashboard, :idle, 0.0, 0.0)
        end
    end
end

# Read single key without Enter (instant commands)
function read_key_instant()
    key_pressed = ""
    raw_mode_set = false

    try
        if isa(stdin, Base.TTY)
            # Set raw mode for instant key capture
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)
            raw_mode_set = true

            # Non-blocking read
            if bytesavailable(stdin) > 0
                char = read(stdin, Char)
                key_pressed = string(char)
            end
        end
    catch e
        # Ignore errors in key reading
    finally
        if raw_mode_set && isa(stdin, Base.TTY)
            try
                # Restore normal mode
                ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)
            catch
                # Continue even if restoration fails
            end
        end
    end

    return key_pressed
end

# Instant command handler (no Enter required)
function instant_command_handler(dashboard::RealDashboard, key::String)
    if isempty(key)
        return false
    end

    handled = true

    if key == "q" || key == "Q"
        add_event!(dashboard, :info, "Shutting down...")
        dashboard.running = false
    elseif key == "d" || key == "D"
        add_event!(dashboard, :info, "Starting download...")
        download_data(dashboard)
    elseif key == "t" || key == "T"
        add_event!(dashboard, :info, "Starting training...")
        start_training(dashboard)
    elseif key == "s" || key == "S"
        add_event!(dashboard, :info, "Submitting predictions...")
        submit_predictions(dashboard)
    elseif key == "p" || key == "P"
        # Generate predictions
        add_event!(dashboard, :info, "Generating predictions...")
        generate_predictions(dashboard)
    elseif key == "r" || key == "R"
        add_event!(dashboard, :info, "Refreshing...")
        update_system_info!(dashboard)
    else
        handled = false
    end

    return handled
end

# Main dashboard loop
function run_real_dashboard(config, api_client=nothing)
    dashboard = RealDashboard(config, api_client)
    dashboard.running = true

    # Hide cursor
    print("\033[?25l")

    try
        add_event!(dashboard, :info, "Dashboard started with REAL operations!")
        add_event!(dashboard, :info, "Commands work instantly without Enter key")

        # Initial system info update
        update_system_info!(dashboard)

        # Start time for uptime tracking
        start_time = time()

        # Main loop
        while dashboard.running
            current_time = time()

            # Update uptime
            dashboard.system_info[:uptime] = Int(current_time - start_time)

            # Check for key input (instant commands)
            key = read_key_instant()
            if !isempty(key)
                instant_command_handler(dashboard, key)
            end

            # Update system info periodically
            if current_time - dashboard.last_system_update >= dashboard.system_update_interval
                update_system_info!(dashboard)
            end

            # Render dashboard if needed
            if current_time - dashboard.last_render_time >= dashboard.render_interval ||
               dashboard.progress.operation != :idle  # Always render during operations
                render_dashboard(dashboard)
                dashboard.last_render_time = current_time
            end

            # Small sleep to prevent CPU spinning
            sleep(0.01)
        end

    finally
        # Show cursor
        print("\033[?25h")
        # Clear screen
        print("\033[2J\033[H")
        println("Dashboard stopped.")
    end
end

end # module