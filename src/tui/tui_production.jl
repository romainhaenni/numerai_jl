# TUI Dashboard Production Implementation
# This implementation provides real API integration with actual progress tracking

module TUIProduction

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
using Statistics
using CSV

# Import parent modules
using ..Utils
using ..API
using ..DataLoader
import ..TournamentConfig

# Import ML components
using ..Models: create_model, train!, predict
using ..Pipeline: MLPipeline

# Terminal control constants
const HIDE_CURSOR = "\033[?25l"
const SHOW_CURSOR = "\033[?25h"
const CLEAR_SCREEN = "\033[2J"
const MOVE_HOME = "\033[H"

# Dashboard state structure
mutable struct ProductionDashboard
    # Core state
    running::Bool
    paused::Bool
    config::Any
    api_client::Any

    # Terminal dimensions
    terminal_width::Int
    terminal_height::Int

    # System monitoring
    cpu_usage::Float64
    memory_used::Float64
    memory_total::Float64
    disk_free::Float64
    disk_total::Float64

    # Operation tracking
    current_operation::Symbol
    operation_description::String
    operation_progress::Float64
    operation_details::Dict{Symbol, Any}

    # Pipeline state
    pipeline_active::Bool
    pipeline_stage::Symbol

    # Data state
    datasets::Dict{String, Any}
    models::Vector{Any}

    # UI state
    keyboard_channel::Channel{Char}
    force_render::Bool
    last_render_time::Float64
    events::Vector{Tuple{DateTime, Symbol, String}}

    # Auto-start configuration
    auto_start_enabled::Bool
    auto_start_initiated::Bool
    auto_start_delay::Float64
    auto_train_enabled::Bool

    # Download tracking
    downloads_in_progress::Set{String}
    downloads_completed::Set{String}
end

# Create dashboard with real system monitoring
function create_dashboard(config::Any, api_client::Any)
    # Get initial real system values
    disk_info = Utils.get_disk_space_info()
    mem_info = Utils.get_memory_info()
    cpu_usage = Utils.get_cpu_usage()

    # Handle TUI-specific configuration section
    tui_config = if isa(config, Dict)
        get(config, :tui, Dict())
    else
        hasfield(typeof(config), :tui_config) ? config.tui_config : Dict()
    end

    # Read configuration values - check both TUI section and top-level for backward compatibility
    auto_start_pipeline_val = if isa(config, Dict)
        # Check TUI section first, then top-level
        if isa(tui_config, Dict) && haskey(tui_config, "auto_start_pipeline")
            tui_config["auto_start_pipeline"]
        else
            get(config, :auto_start_pipeline, false)
        end
    else
        config.auto_start_pipeline
    end

    auto_train_after_download_val = if isa(config, Dict)
        # Check TUI section first, then top-level
        if isa(tui_config, Dict) && haskey(tui_config, "auto_train_after_download")
            tui_config["auto_train_after_download"]
        else
            get(config, :auto_train_after_download, true)
        end
    else
        config.auto_train_after_download
    end

    auto_start_delay_val = if isa(tui_config, Dict)
        get(tui_config, "auto_start_delay", 2.0)
    else
        2.0
    end

    # Log configuration values for debugging (using standard println for module isolation)
    println("Dashboard Configuration:")
    println("  - Auto-start enabled: $auto_start_pipeline_val")
    println("  - Auto-start delay: $auto_start_delay_val seconds")
    println("  - Auto-train after download: $auto_train_after_download_val")
    println("  - System Info - CPU: $cpu_usage%, Memory: $(mem_info.used_gb)/$(mem_info.total_gb) GB, Disk: $(disk_info.free_gb)/$(disk_info.total_gb) GB")

    dashboard = ProductionDashboard(
        true,  # running
        false, # paused
        config,
        api_client,
        displaysize(stdout)[2], # terminal_width
        displaysize(stdout)[1], # terminal_height
        cpu_usage,
        mem_info.used_gb,
        mem_info.total_gb,
        disk_info.free_gb,
        disk_info.total_gb,
        :idle,  # current_operation
        "",     # operation_description
        0.0,    # operation_progress
        Dict{Symbol, Any}(),
        false,  # pipeline_active
        :idle,  # pipeline_stage
        Dict{String, Any}(),
        [],
        Channel{Char}(100),
        true,   # force_render
        time(), # last_render_time
        [],     # events
        auto_start_pipeline_val,
        false,  # auto_start_initiated
        auto_start_delay_val,
        auto_train_after_download_val,
        Set{String}(),
        Set{String}()
    )

    return dashboard
end

# Add event to dashboard log
function add_event!(dashboard::ProductionDashboard, level::Symbol, message::String)
    push!(dashboard.events, (now(), level, message))
    # Keep only last 100 events
    if length(dashboard.events) > 100
        popfirst!(dashboard.events)
    end
    dashboard.force_render = true
end

# Real download with API integration and progress callback
function download_datasets(dashboard::ProductionDashboard, datasets::Vector{String})
    success = true

    for dataset in datasets
        if dataset in dashboard.downloads_completed
            add_event!(dashboard, :info, "⏭️  $dataset already downloaded")
            continue
        end

        push!(dashboard.downloads_in_progress, dataset)
        dashboard.current_operation = :downloading
        dashboard.operation_description = "Downloading $dataset dataset"
        dashboard.pipeline_stage = :downloading_data

        # Handle both Dict and struct configs
        data_dir = if isa(dashboard.config, Dict)
            get(dashboard.config, :data_dir, "data")
        else
            dashboard.config.data_dir
        end
        output_path = joinpath(data_dir, "$dataset.parquet")

        try
            add_event!(dashboard, :info, "📥 Starting download: $dataset")

            # Enhanced progress callback for real API download
            progress_callback = function(status; kwargs...)
                if status == :start
                    dashboard.operation_progress = 0.0
                    dashboard.operation_details[:dataset] = dataset
                    dashboard.operation_details[:phase] = "Starting download"
                    start_time = get(kwargs, :start_time, time())
                    dashboard.operation_details[:start_time] = start_time
                    dashboard.force_render = true
                elseif status == :progress
                    progress = get(kwargs, :progress, 0.0)
                    current_mb = get(kwargs, :current_mb, 0.0)
                    total_mb = get(kwargs, :total_mb, 0.0)
                    speed_mb_s = get(kwargs, :speed_mb_s, 0.0)
                    eta_seconds = get(kwargs, :eta_seconds, nothing)
                    elapsed_time = get(kwargs, :elapsed_time, 0.0)

                    dashboard.operation_progress = progress
                    dashboard.operation_details[:current_mb] = current_mb
                    dashboard.operation_details[:total_mb] = total_mb
                    dashboard.operation_details[:speed_mb_s] = speed_mb_s
                    dashboard.operation_details[:eta_seconds] = eta_seconds
                    dashboard.operation_details[:elapsed_time] = elapsed_time
                    dashboard.operation_details[:phase] = "Downloading"
                    dashboard.force_render = true
                elseif status == :complete
                    dashboard.operation_progress = 100.0
                    size_mb = get(kwargs, :size_mb, 0.0)
                    total_time = get(kwargs, :total_time, 0.0)
                    avg_speed = get(kwargs, :avg_speed_mb_s, 0.0)
                    dashboard.operation_details[:size_mb] = size_mb
                    dashboard.operation_details[:total_time] = total_time
                    dashboard.operation_details[:avg_speed] = avg_speed
                    dashboard.operation_details[:phase] = "Download complete"
                    dashboard.force_render = true
                elseif status == :error
                    error_msg = get(kwargs, :error, "Unknown error")
                    dashboard.operation_details[:error] = error_msg
                    dashboard.operation_details[:phase] = "Download failed"
                    dashboard.force_render = true
                end
            end

            # Use real API download with progress callback
            API.download_dataset(
                dashboard.api_client,
                dataset,
                output_path;
                show_progress=true,
                progress_callback=progress_callback
            )

            # Load the downloaded data
            dashboard.datasets[dataset] = DataLoader.load_data(output_path)

            add_event!(dashboard, :success, "✅ Downloaded $dataset")

        catch e
            add_event!(dashboard, :error, "❌ Failed to download $dataset: $(string(e))")
            success = false
        end

        delete!(dashboard.downloads_in_progress, dataset)
        push!(dashboard.downloads_completed, dataset)
        dashboard.force_render = true
    end

    dashboard.current_operation = :idle
    dashboard.pipeline_stage = :idle

    # Auto-training trigger
    if success && dashboard.auto_train_enabled
        add_event!(dashboard, :info, "🤖 Downloads complete. Starting training...")
        @async begin
            sleep(2.0)
            if dashboard.running && !dashboard.pipeline_active
                train_models(dashboard)
            end
        end
    end

    return success
end

# Real training with progress tracking
function train_models(dashboard::ProductionDashboard)
    dashboard.current_operation = :training
    dashboard.pipeline_stage = :training
    dashboard.operation_description = "Training models"

    try
        add_event!(dashboard, :info, "🏋️ Starting model training")

        # Check if we have data
        if !haskey(dashboard.datasets, "train") || !haskey(dashboard.datasets, "validation")
            add_event!(dashboard, :error, "❌ Missing training data")
            return false
        end

        train_data = dashboard.datasets["train"]
        val_data = dashboard.datasets["validation"]

        # Prepare features and targets
        feature_cols = filter(x -> startswith(x, "feature_"), names(train_data))
        X_train = Matrix(train_data[:, feature_cols])
        y_train = train_data.target
        X_val = Matrix(val_data[:, feature_cols])
        y_val = val_data.target

        # Train each configured model
        # Handle both Dict and struct configs
        models_config = if isa(dashboard.config, Dict)
            get(dashboard.config, :models, [])
        else
            dashboard.config.models
        end

        for model_config in models_config
            model_name = model_config["name"]
            model_type = model_config["type"]

            add_event!(dashboard, :info, "📊 Training $model_name ($model_type)")

            dashboard.operation_description = "Training $model_name"
            dashboard.operation_details[:model] = model_name
            dashboard.operation_details[:type] = model_type

            # Create model
            model = create_model(model_type, model_config)

            # Enhanced training progress callback
            training_progress_callback = function(status; kwargs...)
                if status == :start
                    dashboard.operation_progress = 0.0
                    dashboard.operation_details[:phase] = "Initializing training"
                    dashboard.operation_details[:model] = model_name
                    dashboard.operation_details[:start_time] = time()
                    dashboard.force_render = true
                elseif status == :progress
                    progress = get(kwargs, :progress, 0.0)
                    phase = get(kwargs, :phase, "Training")
                    epoch = get(kwargs, :epoch, 0)
                    total_epochs = get(kwargs, :total_epochs, 1)
                    elapsed_time = get(kwargs, :elapsed_time, 0.0)

                    dashboard.operation_progress = progress
                    dashboard.operation_details[:phase] = phase
                    dashboard.operation_details[:epoch] = epoch
                    dashboard.operation_details[:total_epochs] = total_epochs
                    dashboard.operation_details[:elapsed_time] = elapsed_time
                    dashboard.force_render = true
                elseif status == :complete
                    dashboard.operation_progress = 100.0
                    total_time = get(kwargs, :total_time, 0.0)
                    dashboard.operation_details[:phase] = "Training complete"
                    dashboard.operation_details[:total_time] = total_time
                    dashboard.force_render = true
                end
            end

            # Train with enhanced progress tracking
            train!(model, X_train, y_train;
                     X_val=X_val, y_val=y_val,
                     verbose=false,
                     progress_callback=training_progress_callback)

            push!(dashboard.models, model)
            add_event!(dashboard, :success, "✅ Trained $model_name")
        end

        dashboard.operation_progress = 100.0
        add_event!(dashboard, :success, "✅ All models trained successfully")

        # Auto-submit if configured
        auto_submit = if isa(dashboard.config, Dict)
            get(dashboard.config, :auto_submit, false)
        else
            dashboard.config.auto_submit
        end

        if auto_submit
            @async begin
                sleep(2.0)
                submit_predictions(dashboard)
            end
        end

        return true

    catch e
        add_event!(dashboard, :error, "❌ Training failed: $(string(e))")
        return false
    finally
        dashboard.current_operation = :idle
        dashboard.pipeline_stage = :idle
        dashboard.force_render = true
    end
end

# Submit predictions with progress
function submit_predictions(dashboard::ProductionDashboard)
    dashboard.current_operation = :submitting
    dashboard.pipeline_stage = :submitting
    dashboard.operation_description = "Submitting predictions"

    try
        add_event!(dashboard, :info, "📤 Generating predictions")

        if !haskey(dashboard.datasets, "live")
            add_event!(dashboard, :error, "❌ Missing live data")
            return false
        end

        live_data = dashboard.datasets["live"]
        feature_cols = filter(x -> startswith(x, "feature_"), names(live_data))
        X_live = Matrix(live_data[:, feature_cols])

        # Enhanced prediction progress callback
        prediction_progress_callback = function(status; kwargs...)
            if status == :start
                dashboard.operation_progress = 10.0
                dashboard.operation_details[:phase] = "Generating predictions"
                dashboard.operation_details[:total_rows] = get(kwargs, :total_rows, nrow(live_data))
                dashboard.force_render = true
            elseif status == :progress
                progress = 10.0 + (get(kwargs, :progress, 0.0) * 0.6)  # Scale to 10-70%
                phase = get(kwargs, :phase, "Generating predictions")
                rows_processed = get(kwargs, :rows_processed, 0)
                total_rows = get(kwargs, :total_rows, nrow(live_data))

                dashboard.operation_progress = progress
                dashboard.operation_details[:phase] = phase
                dashboard.operation_details[:rows_processed] = rows_processed
                dashboard.operation_details[:total_rows] = total_rows
                dashboard.force_render = true
            elseif status == :complete
                dashboard.operation_progress = 70.0
                dashboard.operation_details[:phase] = "Predictions generated"
                dashboard.force_render = true
            end
        end

        # Generate predictions from each model with progress tracking
        predictions = []
        n_models = length(dashboard.models)

        for (i, model) in enumerate(dashboard.models)
            dashboard.operation_details[:phase] = "Predicting with model $i/$n_models"
            dashboard.operation_progress = 10.0 + (i / n_models) * 50.0
            dashboard.force_render = true

            # For now, predict without individual model progress (could be enhanced further)
            pred = predict(model, X_live)
            push!(predictions, pred)
        end

        # Ensemble predictions
        dashboard.operation_details[:phase] = "Ensembling predictions"
        dashboard.operation_progress = 70.0
        dashboard.force_render = true

        final_predictions = mean(predictions)

        # Create submission DataFrame
        dashboard.operation_details[:phase] = "Creating submission file"
        dashboard.operation_progress = 75.0
        dashboard.force_render = true

        submission = DataFrame(
            id = live_data.id,
            prediction = final_predictions
        )

        # Submit to API
        add_event!(dashboard, :info, "📤 Uploading predictions")
        dashboard.operation_progress = 50.0

        # Handle both Dict and struct configs
        models_config = if isa(dashboard.config, Dict)
            get(dashboard.config, :models, [])
        else
            dashboard.config.models
        end

        model_name = if !isempty(models_config)
            first(models_config)["name"]
        else
            "default_model"
        end

        # Enhanced upload progress callback
        upload_progress_callback = function(status; kwargs...)
            if status == :start
                dashboard.operation_progress = 80.0
                dashboard.operation_details[:phase] = "Starting upload"
                dashboard.force_render = true
            elseif status == :progress
                progress = 80.0 + (get(kwargs, :progress, 0.0) * 0.18)  # Scale to 80-98%
                phase = get(kwargs, :phase, "Uploading")
                bytes_uploaded = get(kwargs, :bytes_uploaded, 0)
                total_bytes = get(kwargs, :total_bytes, 0)

                dashboard.operation_progress = progress
                dashboard.operation_details[:phase] = phase
                dashboard.operation_details[:bytes_uploaded] = bytes_uploaded
                dashboard.operation_details[:total_bytes] = total_bytes
                dashboard.force_render = true
            elseif status == :complete
                dashboard.operation_progress = 98.0
                dashboard.operation_details[:phase] = "Upload complete"
                dashboard.force_render = true
            elseif status == :error
                error_msg = get(kwargs, :message, "Upload failed")
                dashboard.operation_details[:error] = error_msg
                dashboard.operation_details[:phase] = "Upload failed"
                dashboard.force_render = true
            end
        end

        # Save submission temporarily for upload
        temp_path = tempname() * ".csv"
        CSV.write(temp_path, submission)

        try
            submission_id = API.submit_predictions(
                dashboard.api_client,
                model_name,
                temp_path;
                progress_callback=upload_progress_callback
            )

            dashboard.operation_progress = 100.0
            dashboard.operation_details[:phase] = "Submission complete"
            add_event!(dashboard, :success, "✅ Predictions submitted: $submission_id")
        finally
            # Clean up temporary file
            isfile(temp_path) && rm(temp_path)
        end

        return true

    catch e
        add_event!(dashboard, :error, "❌ Submission failed: $(string(e))")
        return false
    finally
        dashboard.current_operation = :idle
        dashboard.pipeline_stage = :idle
        dashboard.force_render = true
    end
end

# Start the complete pipeline
function start_pipeline(dashboard::ProductionDashboard)
    if dashboard.pipeline_active
        add_event!(dashboard, :warn, "⚠️ Pipeline already running")
        return
    end

    dashboard.pipeline_active = true
    add_event!(dashboard, :info, "🚀 Starting tournament pipeline")

    @async begin
        try
            # Download data
            if download_datasets(dashboard, ["train", "validation", "live"])
                # Training happens automatically if auto_train_enabled
                if !dashboard.auto_train_enabled
                    train_models(dashboard)
                end
            end
        catch e
            add_event!(dashboard, :error, "❌ Pipeline error: $(string(e))")
        finally
            dashboard.pipeline_active = false
            dashboard.force_render = true
        end
    end
end

# Handle keyboard input
function handle_input(dashboard::ProductionDashboard, key::Char)
    # Debug logging for keyboard input
    add_event!(dashboard, :info, "🔤 Key pressed: '$key' ($(Int(key)))")

    if key == 'q' || key == 'Q'
        add_event!(dashboard, :info, "🛑 Quit command received")
        dashboard.running = false
    elseif key == 's' || key == 'S'
        add_event!(dashboard, :info, "🚀 Start pipeline command received")
        start_pipeline(dashboard)
    elseif key == 'p' || key == 'P'
        dashboard.paused = !dashboard.paused
        status = dashboard.paused ? "paused" : "resumed"
        add_event!(dashboard, :info, "⏸️ Pipeline $status")
    elseif key == 'd' || key == 'D'
        add_event!(dashboard, :info, "📥 Download command received")
        @async download_datasets(dashboard, ["train", "validation", "live"])
    elseif key == 't' || key == 'T'
        add_event!(dashboard, :info, "🏋️ Train command received")
        @async train_models(dashboard)
    elseif key == 'u' || key == 'U'
        add_event!(dashboard, :info, "📤 Upload command received")
        @async submit_predictions(dashboard)
    elseif key == 'r' || key == 'R'
        dashboard.force_render = true
        add_event!(dashboard, :info, "🔄 Refreshing display")
    elseif key == 'h' || key == 'H'
        show_help(dashboard)
    else
        # Log unrecognized keys for debugging
        add_event!(dashboard, :warn, "❓ Unrecognized key: '$key' ($(Int(key)))")
    end
end

# Show help
function show_help(dashboard::ProductionDashboard)
    help_text = """
    📋 Keyboard Commands (single key, no Enter needed):

    🛑 q/Q - Quit dashboard
    🚀 s/S - Start complete pipeline (download + train + submit)
    ⏸️ p/P - Pause/Resume pipeline
    📥 d/D - Download datasets only
    🏋️ t/T - Train models only
    📤 u/U - Upload/Submit predictions
    🔄 r/R - Refresh display
    ❓ h/H - Show this help

    Note: Commands work immediately without pressing Enter.
    Watch the Recent Events panel for confirmation.
    """
    add_event!(dashboard, :info, help_text)
end

# Render the dashboard
function render_dashboard(dashboard::ProductionDashboard)
    # Update system stats
    if time() - dashboard.last_render_time > 2.0
        try
            disk_info = Utils.get_disk_space_info()
            mem_info = Utils.get_memory_info()
            cpu_usage = Utils.get_cpu_usage()

            # Log the values for debugging (commented out to avoid macro issues)
            # @debug "System monitoring update - CPU: $cpu_usage%, Memory: $(mem_info.used_gb)/$(mem_info.total_gb) GB, Disk: $(disk_info.free_gb)/$(disk_info.total_gb) GB"

            # Update dashboard values
            dashboard.cpu_usage = cpu_usage
            dashboard.memory_used = mem_info.used_gb
            dashboard.memory_total = mem_info.total_gb
            dashboard.disk_free = disk_info.free_gb
            dashboard.disk_total = disk_info.total_gb
            dashboard.force_render = true
            dashboard.last_render_time = time()
        catch e
            # Log error to events instead of using logger macro
            add_event!(dashboard, :error, "Failed to update system stats: $e")
            # Keep previous values if update fails
        end
    end

    if !dashboard.force_render
        return
    end

    # Clear screen and move to home
    print(stdout, CLEAR_SCREEN, MOVE_HOME)

    # Header with system stats
    header = Panel(
        "CPU: $(round(dashboard.cpu_usage, digits=1))% | " *
        "Memory: $(round(dashboard.memory_used, digits=1))/$(round(dashboard.memory_total, digits=1)) GB | " *
        "Disk: $(round(dashboard.disk_free, digits=1))/$(round(dashboard.disk_total, digits=1)) GB free",
        title="Numerai Tournament Dashboard - Production",
        style="bright_blue"
    )
    println(header)

    # Enhanced current operation panel
    if dashboard.current_operation != :idle
        op_text = dashboard.operation_description

        # Add phase information if available
        if haskey(dashboard.operation_details, :phase)
            op_text *= "\nPhase: $(dashboard.operation_details[:phase])"
        end

        if dashboard.operation_progress > 0
            # Download progress with MB and speed
            if haskey(dashboard.operation_details, :current_mb) && haskey(dashboard.operation_details, :total_mb)
                current_mb = round(dashboard.operation_details[:current_mb], digits=1)
                total_mb = round(dashboard.operation_details[:total_mb], digits=1)
                op_text *= "\nSize: $current_mb / $total_mb MB"

                if haskey(dashboard.operation_details, :speed_mb_s)
                    speed = round(dashboard.operation_details[:speed_mb_s], digits=2)
                    op_text *= " ($(speed) MB/s)"
                end

                if haskey(dashboard.operation_details, :eta_seconds) && dashboard.operation_details[:eta_seconds] !== nothing
                    eta = dashboard.operation_details[:eta_seconds]
                    if eta < 60
                        op_text *= " - ETA: $(round(eta))s"
                    else
                        op_text *= " - ETA: $(round(eta/60, digits=1))m"
                    end
                end
            end

            # Training progress with epochs
            if haskey(dashboard.operation_details, :epoch) && haskey(dashboard.operation_details, :total_epochs)
                epoch = dashboard.operation_details[:epoch]
                total_epochs = dashboard.operation_details[:total_epochs]
                op_text *= "\nEpoch: $epoch / $total_epochs"
            end

            # Prediction progress with rows
            if haskey(dashboard.operation_details, :rows_processed) && haskey(dashboard.operation_details, :total_rows)
                rows_processed = dashboard.operation_details[:rows_processed]
                total_rows = dashboard.operation_details[:total_rows]
                op_text *= "\nRows: $rows_processed / $total_rows"
            end

            # Upload progress with bytes
            if haskey(dashboard.operation_details, :bytes_uploaded) && haskey(dashboard.operation_details, :total_bytes)
                bytes_uploaded = dashboard.operation_details[:bytes_uploaded]
                total_bytes = dashboard.operation_details[:total_bytes]
                uploaded_mb = round(bytes_uploaded / 1024 / 1024, digits=1)
                total_mb = round(total_bytes / 1024 / 1024, digits=1)
                op_text *= "\nUploaded: $uploaded_mb / $total_mb MB"
            end

            # Elapsed time
            if haskey(dashboard.operation_details, :elapsed_time)
                elapsed = dashboard.operation_details[:elapsed_time]
                if elapsed < 60
                    op_text *= "\nElapsed: $(round(elapsed, digits=1))s"
                else
                    op_text *= "\nElapsed: $(round(elapsed/60, digits=1))m"
                end
            end

            # Enhanced progress bar with percentage
            prog_bar = "["
            filled = Int(round(dashboard.operation_progress / 100 * 40))  # Wider progress bar
            prog_bar *= "█" ^ filled
            prog_bar *= "░" ^ (40 - filled)
            prog_bar *= "] $(round(dashboard.operation_progress, digits=1))%"
            op_text *= "\n$prog_bar"
        end

        op_panel = Panel(
            op_text,
            title="Current Operation - $(string(dashboard.current_operation))",
            style="bright_yellow"
        )
        println(op_panel)
    end

    # Recent events
    if !isempty(dashboard.events)
        recent_events = last(dashboard.events, min(10, length(dashboard.events)))
        event_lines = []
        for (timestamp, level, msg) in recent_events
            color = level == :error ? "red" : level == :warn ? "yellow" : level == :success ? "green" : "white"
            push!(event_lines, "[$color]$(Dates.format(timestamp, "HH:MM:SS")) $msg[/$color]")
        end
        event_text = join(event_lines, "\n")

        event_panel = Panel(
            event_text,
            title="Recent Events",
            style="bright_cyan"
        )
        println(event_panel)
    end

    # Commands help
    cmd_panel = Panel(
        "[q]uit | [s]tart | [p]ause | [d]ownload | [t]rain | [u]pload | [r]efresh | [h]elp",
        title="Commands",
        style="bright_magenta"
    )
    println(cmd_panel)

    dashboard.force_render = false
end

# Main dashboard loop
function run_dashboard(config::Any, api_client::Any)
    dashboard = create_dashboard(config, api_client)

    # Hide cursor
    print(stdout, HIDE_CURSOR)

    # Initialize terminal state
    terminal = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
    add_event!(dashboard, :info, "🔧 Setting up terminal for keyboard input")

    # Start keyboard input handler with improved terminal setup
    keyboard_task = @async begin
        try
            # Enable raw mode for immediate character input
            REPL.Terminals.raw!(terminal, true)
            add_event!(dashboard, :info, "✅ Terminal raw mode enabled")

            # Flush any pending input
            while bytesavailable(stdin) > 0
                read(stdin, UInt8)
            end

            while dashboard.running
                try
                    # Use a more reliable input detection method
                    if bytesavailable(stdin) > 0
                        # Read a single character
                        char_bytes = read(stdin, UInt8)

                        # Convert to character if valid
                        if char_bytes <= 0x7f  # ASCII range
                            key = Char(char_bytes)
                            add_event!(dashboard, :info, "📥 Raw input detected: byte=$(char_bytes), char='$key'")
                            put!(dashboard.keyboard_channel, key)
                        else
                            add_event!(dashboard, :warn, "⚠️ Non-ASCII input: byte=$(char_bytes)")
                        end
                    end
                    sleep(0.001)  # 1ms polling
                catch e
                    add_event!(dashboard, :error, "❌ Keyboard input error: $(string(e))")
                    sleep(0.01)  # Longer sleep on error
                end
            end

        catch e
            add_event!(dashboard, :error, "❌ Terminal setup error: $(string(e))")
        finally
            # Always restore terminal state
            try
                REPL.Terminals.raw!(terminal, false)
                add_event!(dashboard, :info, "🔧 Terminal raw mode disabled")
            catch e
                add_event!(dashboard, :error, "❌ Failed to restore terminal: $(string(e))")
            end
        end
    end

    # Give terminal setup a moment to complete
    sleep(0.1)
    add_event!(dashboard, :info, "⌨️ Keyboard input ready - try pressing a key!")

    # Auto-start if configured
    if dashboard.auto_start_enabled && !dashboard.auto_start_initiated
        dashboard.auto_start_initiated = true
        add_event!(dashboard, :info, "⏱️ Auto-start enabled, waiting $(dashboard.auto_start_delay) seconds...")
        @async begin
            sleep(dashboard.auto_start_delay)
            if dashboard.running && !dashboard.pipeline_active
                add_event!(dashboard, :info, "🚀 Auto-starting pipeline now!")
                start_pipeline(dashboard)
            else
                reason = !dashboard.running ? "dashboard not running" : "pipeline already active"
                add_event!(dashboard, :warn, "⚠️ Auto-start cancelled: $reason")
            end
        end
    elseif !dashboard.auto_start_enabled
        add_event!(dashboard, :info, "ℹ️ Auto-start disabled in configuration")
    else
        add_event!(dashboard, :info, "ℹ️ Auto-start already initiated")
    end

    # Main render loop
    try
        while dashboard.running
            # Process keyboard input
            while isready(dashboard.keyboard_channel)
                try
                    key = take!(dashboard.keyboard_channel)
                    handle_input(dashboard, key)
                catch e
                    add_event!(dashboard, :error, "❌ Input processing error: $(string(e))")
                end
            end

            # Render dashboard
            try
                render_dashboard(dashboard)
            catch e
                add_event!(dashboard, :error, "❌ Render error: $(string(e))")
                # Force a simple display on render failure
                println("Dashboard render failed. Running: $(dashboard.running)")
            end

            # Small sleep to prevent CPU spinning
            sleep(0.01)  # 10ms
        end
    finally
        # Clean up: wait for keyboard task to finish
        try
            # Signal shutdown and wait briefly for cleanup
            wait(keyboard_task)
        catch e
            add_event!(dashboard, :warn, "⚠️ Keyboard task cleanup: $(string(e))")
        end

        # Show cursor
        print(stdout, SHOW_CURSOR)
        println("\n\nDashboard terminated.")
    end
end

# Export the main function
export run_dashboard, ProductionDashboard

end # module