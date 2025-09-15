# Slash command implementations for TUI dashboard
# This file is included within the Dashboard module, so it inherits all imports

# Execute slash commands
function execute_command(dashboard, command::String)
    # Remove leading slash if present
    cmd = startswith(command, "/") ? command[2:end] : command

    parts = split(cmd, " ")
    if isempty(parts)
        return false
    end

    main_cmd = lowercase(parts[1])

    if main_cmd == "train"
        add_event!(dashboard, :info, "Starting training via command...")
        start_training(dashboard)
        return true
    elseif main_cmd == "submit"
        add_event!(dashboard, :info, "Submitting predictions...")
        submit_predictions_command(dashboard)
        return true
    elseif main_cmd == "stake"
        if length(parts) >= 2
            amount = tryparse(Float64, parts[2])
            if !isnothing(amount)
                stake_command(dashboard, amount)
                return true
            else
                add_event!(dashboard, :error, "Invalid stake amount: $(parts[2])")
                return false
            end
        else
            add_event!(dashboard, :error, "Usage: /stake <amount>")
            return false
        end
    elseif main_cmd == "download"
        add_event!(dashboard, :info, "Downloading latest data...")
        download_data_command(dashboard)
        return true
    elseif main_cmd == "help"
        dashboard.show_help = true
        return true
    elseif main_cmd == "quit" || main_cmd == "exit"
        dashboard.running = false
        return true
    elseif main_cmd == "refresh"
        update_model_performances!(dashboard)
        add_event!(dashboard, :info, "Data refreshed")
        return true
    elseif main_cmd == "pause" || main_cmd == "resume"
        dashboard.paused = !dashboard.paused
        status = dashboard.paused ? "paused" : "resumed"
        add_event!(dashboard, :info, "Dashboard $status")
        return true
    elseif main_cmd == "diag" || main_cmd == "diagnostics"
        add_event!(dashboard, :info, "Running full system diagnostics...")
        run_full_diagnostics_command(dashboard)
        return true
    elseif main_cmd == "reset"
        add_event!(dashboard, :info, "Resetting error counters...")
        reset_error_tracking!(dashboard)
        return true
    elseif main_cmd == "backup"
        add_event!(dashboard, :info, "Creating configuration backup...")
        create_configuration_backup_command(dashboard)
        return true
    elseif main_cmd == "network" || main_cmd == "net"
        add_event!(dashboard, :info, "Testing network connectivity...")
        test_network_connectivity(dashboard)
        return true
    elseif main_cmd == "save" || main_cmd == "report"
        add_event!(dashboard, :info, "Saving diagnostic report...")
        save_diagnostic_report(dashboard)
        return true
    elseif main_cmd == "new"
        add_event!(dashboard, :info, "Starting new model wizard...")
        start_model_wizard(dashboard)
        return true
    elseif main_cmd == "pipeline"
        add_event!(dashboard, :info, "Starting full tournament pipeline...")
        run_full_pipeline(dashboard)
        return true
    else
        add_event!(dashboard, :warning, "Unknown command: /$cmd")
        add_event!(dashboard, :info, "Available commands: /train, /submit, /stake, /download, /refresh, /new, /pipeline, /help, /quit")
        add_event!(dashboard, :info, "Recovery commands: /diag, /reset, /backup, /network, /save")
        return false
    end
end

# Command implementations

# Run the full tournament pipeline (download → train → predict → submit)
function run_full_pipeline(dashboard::TournamentDashboard)
    @async begin
        try
            add_event!(dashboard, :info, "🚀 Starting full tournament pipeline...")
            
            # Step 1: Download latest data
            add_event!(dashboard, :info, "📥 Step 1/4: Downloading tournament data...")
            if !download_data_internal(dashboard)
                add_event!(dashboard, :error, "Failed to download data. Pipeline aborted.")
                return false
            end
            add_event!(dashboard, :success, "✅ Tournament data downloaded successfully")
            
            # Step 2: Train models  
            add_event!(dashboard, :info, "🧠 Step 2/4: Training models...")
            if !train_models_internal(dashboard)
                add_event!(dashboard, :error, "Failed to train models. Pipeline aborted.")
                return false
            end
            add_event!(dashboard, :success, "✅ Models trained successfully")
            
            # Step 3: Generate predictions
            add_event!(dashboard, :info, "🔮 Step 3/4: Generating predictions...")
            predictions_path = generate_predictions_internal(dashboard)
            if isnothing(predictions_path)
                add_event!(dashboard, :error, "Failed to generate predictions. Pipeline aborted.")
                return false
            end
            add_event!(dashboard, :success, "✅ Predictions generated: $(basename(predictions_path))")
            
            # Step 4: Submit predictions
            add_event!(dashboard, :info, "📤 Step 4/4: Submitting predictions...")
            if !submit_predictions_internal(dashboard, predictions_path)
                add_event!(dashboard, :error, "Failed to submit predictions. Pipeline aborted.")
                return false
            end
            add_event!(dashboard, :success, "✅ Predictions submitted successfully")
            
            add_event!(dashboard, :success, "🎉 Full tournament pipeline completed successfully!")
            return true
            
        catch e
            add_event!(dashboard, :error, "Pipeline failed: $e")
            return false
        end
    end
end

# Internal function for downloading data
function download_data_internal(dashboard::TournamentDashboard)
    try
        config = dashboard.config
        data_dir = config.data_dir

        # Create data directory if it doesn't exist
        if !isdir(data_dir)
            mkpath(data_dir)
        end

        # Create progress callback for updating dashboard
        progress_callback = function(phase; kwargs...)
            if phase == :start
                file_name = get(kwargs, :name, "unknown")
                EnhancedDashboard.update_progress_tracker!(
                    dashboard.progress_tracker, :download,
                    active=true, file=file_name, progress=0.0
                )
                # Also update realtime tracker if available
                if !isnothing(dashboard.realtime_tracker)
                    dashboard.realtime_tracker.download_active = true
                    dashboard.realtime_tracker.download_file = file_name
                    dashboard.realtime_tracker.download_progress = 0.0
                end
                add_event!(dashboard, :info, "📥 Downloading $file_name...")
            elseif phase == :progress
                # Real-time progress update
                progress = get(kwargs, :progress, 0.0)
                current_mb = get(kwargs, :current_mb, 0.0)
                total_mb = get(kwargs, :total_mb, 0.0)
                EnhancedDashboard.update_progress_tracker!(
                    dashboard.progress_tracker, :download,
                    progress=progress, current_mb=current_mb, total_mb=total_mb
                )
                # Also update realtime tracker if available
                if !isnothing(dashboard.realtime_tracker)
                    should_train = Main.NumeraiTournament.TUIRealtime.update_download_progress!(
                        dashboard.realtime_tracker, progress * 100,
                        dashboard.realtime_tracker.download_file, total_mb, current_mb / total_mb
                    )
                end
            elseif phase == :complete
                file_name = get(kwargs, :name, "unknown")
                size_mb = get(kwargs, :size_mb, 0.0)
                EnhancedDashboard.update_progress_tracker!(
                    dashboard.progress_tracker, :download,
                    active=false, progress=100.0, total_mb=size_mb, current_mb=size_mb
                )
                # Also update realtime tracker if available
                if !isnothing(dashboard.realtime_tracker)
                    should_train = Main.NumeraiTournament.TUIRealtime.update_download_progress!(
                        dashboard.realtime_tracker, 100.0, file_name, size_mb, 0.0
                    )
                    dashboard.realtime_tracker.download_active = false
                end
                add_event!(dashboard, :success, "✅ Downloaded $file_name ($(round(size_mb, digits=1)) MB)")
            end
        end

        # Download all dataset components
        train_path = joinpath(data_dir, "train.parquet")
        val_path = joinpath(data_dir, "validation.parquet")
        live_path = joinpath(data_dir, "live.parquet")
        features_path = joinpath(data_dir, "features.json")

        API.download_dataset(dashboard.api_client, "train", train_path; progress_callback=progress_callback)
        API.download_dataset(dashboard.api_client, "validation", val_path; progress_callback=progress_callback)
        API.download_dataset(dashboard.api_client, "live", live_path; progress_callback=progress_callback)
        API.download_dataset(dashboard.api_client, "features", features_path; progress_callback=progress_callback)

        # Clear download progress
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :download, active=false
        )

        # Automatically trigger training if configured
        auto_train = get(dashboard.config, :auto_train_after_download, false) ||
                     get(ENV, "AUTO_TRAIN", "false") == "true" ||
                     dashboard.config.auto_submit

        if auto_train
            add_event!(dashboard, :info, "🚀 Starting automatic training after download...")
            # Start training in a background task
            @async begin
                sleep(1)  # Small delay to let UI update
                train_models_internal(dashboard)
            end
        else
            add_event!(dashboard, :info, "Download complete. Press 't' or use /train to start training")
        end

        return true
    catch e
        @error "Download failed" error=e
        # Clear download progress on error
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :download, active=false
        )
        return false
    end
end

# Internal function for training models
function train_models_internal(dashboard::TournamentDashboard)
    try
        # Use the existing training functionality
        dashboard.training_info[:is_training] = true
        dashboard.training_info[:model_name] = dashboard.model[:name]
        dashboard.training_info[:progress] = 0
        dashboard.training_info[:total_epochs] = 100

        # Update progress tracker for training
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :training,
            active=true, model=dashboard.model[:name],
            epoch=0, total_epochs=100
        )

        # Also update realtime tracker if available
        if !isnothing(dashboard.realtime_tracker)
            dashboard.realtime_tracker.training_active = true
            dashboard.realtime_tracker.training_model = dashboard.model[:name]
            dashboard.realtime_tracker.training_progress = 0.0
            dashboard.realtime_tracker.training_epoch = 0
            dashboard.realtime_tracker.training_total_epochs = 100
        end

        # Run the actual training
        run_real_training(dashboard)

        # Wait for training to complete and update progress
        while dashboard.training_info[:is_training]
            # Update progress tracker with current epoch
            current_epoch = Int(round(dashboard.training_info[:progress]))
            EnhancedDashboard.update_progress_tracker!(
                dashboard.progress_tracker, :training,
                epoch=current_epoch,
                loss=get(dashboard.training_info, :loss, 0.0),
                val_score=get(dashboard.training_info, :val_score, 0.0)
            )

            # Also update realtime tracker if available
            if !isnothing(dashboard.realtime_tracker)
                Main.NumeraiTournament.TUIRealtime.update_training_progress!(
                    dashboard.realtime_tracker,
                    dashboard.training_info[:progress],
                    current_epoch,
                    100,
                    get(dashboard.training_info, :loss, 0.0),
                    dashboard.model[:name]
                )
            end

            sleep(1)
        end

        # Clear training progress
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :training, active=false
        )

        return dashboard.training_info[:progress] >= 100
    catch e
        @error "Training failed" error=e
        dashboard.training_info[:is_training] = false
        # Clear training progress on error
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :training, active=false
        )
        return false
    end
end

# Internal function for generating predictions
function generate_predictions_internal(dashboard::TournamentDashboard)
    try
        config = dashboard.config
        data_dir = config.data_dir
        model_dir = config.model_dir

        # Set prediction progress tracker
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :prediction,
            active=true, model=dashboard.model[:name],
            rows_processed=0, total_rows=0
        )

        # Load live data
        live_path = joinpath(data_dir, "live.parquet")
        if !isfile(live_path)
            @error "Live data not found"
            EnhancedDashboard.update_progress_tracker!(
                dashboard.progress_tracker, :prediction, active=false
            )
            return nothing
        end

        add_event!(dashboard, :info, "Loading live data...")
        live_df = DataLoader.load_training_data(live_path)
        total_rows = size(live_df, 1)

        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :prediction,
            rows_processed=Int(total_rows * 0.2), total_rows=total_rows
        )
        
        # Get feature columns
        dashboard.progress_tracker.prediction_progress = 25.0  # Data loaded, now getting features
        features_path = joinpath(data_dir, "features.json")
        feature_cols = if isfile(features_path)
            features, _ = DataLoader.load_features_json(features_path; feature_set=config.feature_set)
            features
        else
            DataLoader.get_feature_columns(live_df)
        end

        dashboard.progress_tracker.prediction_progress = 30.0  # Features loaded

        # Load the trained model or create a new pipeline
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

        dashboard.progress_tracker.prediction_progress = 35.0  # Pipeline created

        # Load saved model if available
        model_path = joinpath(model_dir, "model_latest.jld2")
        if isfile(model_path)
            pipeline = Pipeline.load_pipeline(model_path)
        end

        dashboard.progress_tracker.prediction_progress = 40.0  # Model loaded, ready for predictions

        # Generate predictions with progress updates
        add_event!(dashboard, :info, "Generating predictions for $(size(live_df, 1)) samples...")

        # Real batch processing with accurate progress tracking
        n_samples = size(live_df, 1)
        batch_size = max(1000, n_samples ÷ 10)
        predictions = []

        for i in 1:batch_size:n_samples
            batch_end = min(i + batch_size - 1, n_samples)
            batch_df = live_df[i:batch_end, :]

            batch_predictions = Pipeline.predict(pipeline, batch_df)
            append!(predictions, batch_predictions)

            # Calculate real progress: 40% base + 50% for prediction phase
            progress = 40.0 + (batch_end / n_samples) * 50.0
            dashboard.progress_tracker.prediction_progress = progress
        end

        dashboard.progress_tracker.prediction_progress = 90.0  # Predictions complete, saving...

        # Save predictions
        timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
        predictions_path = joinpath(data_dir, "predictions_$(timestamp).csv")

        # Create submission DataFrame
        submission_df = DataFrame(
            id = live_df[!, "id"],
            prediction = predictions
        )

        CSV.write(predictions_path, submission_df)
        dashboard.progress_tracker.prediction_progress = 100.0
        
        return predictions_path

    catch e
        @error "Prediction generation failed" error=e
        return nothing
    finally
        # Clear prediction progress immediately
        dashboard.progress_tracker.is_predicting = false
        dashboard.progress_tracker.prediction_progress = 0.0
        dashboard.progress_tracker.prediction_model = ""
    end
end

# Internal function for submitting predictions
function submit_predictions_internal(dashboard::TournamentDashboard, predictions_path::String)
    try
        config = dashboard.config

        # Set upload progress tracker
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :upload,
            active=true, file=basename(predictions_path), progress=0.0
        )

        # Also update realtime tracker if available
        if !isnothing(dashboard.realtime_tracker)
            dashboard.realtime_tracker.upload_active = true
            dashboard.realtime_tracker.upload_file = basename(predictions_path)
            dashboard.realtime_tracker.upload_progress = 0.0
        end

        # Submit for each model
        total_models = length(config.models)
        for (idx, model_name) in enumerate(config.models)
            base_progress = ((idx - 1) / total_models) * 100.0

            add_event!(dashboard, :info, "Uploading predictions for model: $model_name")

            # Create progress callback for the upload
            progress_callback = (phase; kwargs...) -> begin
                if phase == :start
                    file = get(kwargs, :file, basename(predictions_path))
                    size_mb = get(kwargs, :size_mb, 0.0)
                    EnhancedDashboard.update_progress_tracker!(
                        dashboard.progress_tracker, :upload,
                        file=file, total_mb=size_mb, progress=base_progress + 5.0
                    )
                elseif phase == :progress
                    progress = get(kwargs, :progress, 0.0)
                    phase_desc = get(kwargs, :phase, "")
                    # Scale progress within this model's allocation
                    segment_progress = base_progress + (progress * 100.0 / (total_models * 100.0))
                    EnhancedDashboard.update_progress_tracker!(
                        dashboard.progress_tracker, :upload,
                        progress=segment_progress
                    )
                    # Also update realtime tracker if available
                    if !isnothing(dashboard.realtime_tracker)
                        Main.NumeraiTournament.TUIRealtime.update_upload_progress!(
                            dashboard.realtime_tracker, segment_progress,
                            dashboard.realtime_tracker.upload_file, 0.0
                        )
                    end
                elseif phase == :complete
                    submission_id = get(kwargs, :submission_id, "")
                    size_mb = get(kwargs, :size_mb, 0.0)
                    segment_progress = base_progress + (100.0 / total_models)
                    EnhancedDashboard.update_progress_tracker!(
                        dashboard.progress_tracker, :upload,
                        progress=segment_progress
                    )
                    add_event!(dashboard, :success, "✅ Uploaded for $model_name (ID: $submission_id)")
                elseif phase == :error
                    message = get(kwargs, :message, "Unknown error")
                    add_event!(dashboard, :error, "❌ Upload failed for $model_name: $message")
                end
            end

            # Submit with progress callback
            API.submit_predictions(dashboard.api_client, model_name, predictions_path;
                                  progress_callback=progress_callback)
        end

        # Set to 100% completion
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :upload,
            progress=100.0
        )
        sleep(0.5)  # Show completion briefly

        return true
    catch e
        @error "Submission failed" error=e
        return false
    finally
        # Clear upload progress immediately
        EnhancedDashboard.update_progress_tracker!(
            dashboard.progress_tracker, :upload, active=false
        )
        dashboard.progress_tracker.upload_file = ""
    end
end

function submit_predictions_command(dashboard)
    @async begin
        try
            config = dashboard.config
            data_dir = config.data_dir

            # Find the latest predictions file
            predictions_files = filter(f -> startswith(f, "predictions_") && endswith(f, ".csv"),
                                      readdir(data_dir))

            if isempty(predictions_files)
                add_event!(dashboard, :error, "No predictions found to submit")
                return
            end

            latest_predictions = joinpath(data_dir, predictions_files[end])

            # Set upload progress tracker
            dashboard.progress_tracker.is_uploading = true
            dashboard.progress_tracker.upload_file = predictions_files[end]
            dashboard.progress_tracker.upload_progress = 0.0
            
            # Submit for each model
            for model_name in config.models
                add_event!(dashboard, :info, "Submitting predictions for $model_name...")
                try
                    # Call the actual API submission
                    API.submit_predictions(dashboard.api_client, model_name, latest_predictions)
                    add_event!(dashboard, :success, "Submitted predictions for $model_name")
                catch e
                    add_event!(dashboard, :error, "Failed to submit $model_name: $e")
                end
            end
        catch e
            add_event!(dashboard, :error, "Submission failed: $e")
        end
    end
end

function stake_command(dashboard, amount::Float64)
    @async begin
        try
            add_event!(dashboard, :info, "Setting stake to $(amount) NMR...")
            
            # Get the first model or allow user to specify model
            if isempty(dashboard.models)
                add_event!(dashboard, :error, "No models found to stake on")
                return
            end
            
            # Use the first model by default (could be enhanced to allow model selection)
            model_name = dashboard.models[1][:name]
            
            # Get current stake to determine if we need to increase or decrease
            current_stake_info = API.get_model_stakes(dashboard.api_client, model_name)
            current_stake = get(current_stake_info, :total_stake, 0.0)
            
            # Determine if we're increasing or decreasing stake
            result = if amount > current_stake
                change_amount = amount - current_stake
                add_event!(dashboard, :info, "Increasing stake by $(change_amount) NMR...")
                API.stake_increase(dashboard.api_client, model_name, change_amount)
            elseif amount < current_stake
                change_amount = current_stake - amount
                add_event!(dashboard, :info, "Decreasing stake by $(change_amount) NMR...")
                API.stake_decrease(dashboard.api_client, model_name, change_amount)
            else
                add_event!(dashboard, :info, "Stake already at $(amount) NMR")
                nothing
            end
            
            if !isnothing(result)
                # Update staking info in dashboard
                for model in dashboard.models
                    if model[:name] == model_name && haskey(model, :stake)
                        model[:stake] = amount
                    end
                end
                
                due_date = get(result, :due_date, "unknown")
                add_event!(dashboard, :success, "Stake change successful! Due date: $due_date")
            end
        catch e
            add_event!(dashboard, :error, "Staking failed: $e")
        end
    end
end

function download_data_command(dashboard)
    @async begin
        try
            config = dashboard.config
            data_dir = config.data_dir
            
            # Create data directory if it doesn't exist
            if !isdir(data_dir)
                mkpath(data_dir)
            end
            
            add_event!(dashboard, :info, "Downloading training data...")
            API.download_dataset(dashboard.api_client, "train", joinpath(data_dir, "train.parquet"))
            
            add_event!(dashboard, :info, "Downloading validation data...")
            API.download_dataset(dashboard.api_client, "validation", joinpath(data_dir, "validation.parquet"))
            
            add_event!(dashboard, :info, "Downloading live data...")
            API.download_dataset(dashboard.api_client, "live", joinpath(data_dir, "live.parquet"))
            
            add_event!(dashboard, :info, "Downloading features metadata...")
            API.download_dataset(dashboard.api_client, "features", joinpath(data_dir, "features.json"))
            
            add_event!(dashboard, :success, "All data downloaded successfully")
        catch e
            add_event!(dashboard, :error, "Download failed: $e")
        end
    end
end

function run_full_diagnostics_command(dashboard)
    """
    Run comprehensive system diagnostics and display results.
    """
    @async begin
        try
            add_event!(dashboard, :info, "=== SYSTEM DIAGNOSTICS ===")
            
            # System diagnostics
            diagnostics = get_system_diagnostics(dashboard)
            add_event!(dashboard, :info, "CPU Usage: $(diagnostics[:cpu_usage])%")
            add_event!(dashboard, :info, "Memory: $(diagnostics[:memory_used])/$(diagnostics[:memory_total]) GB")
            add_event!(dashboard, :info, "Disk Free: $(diagnostics[:disk_free]) GB")
            add_event!(dashboard, :info, "Uptime: $(diagnostics[:uptime])")
            
            # Configuration status
            config_status = get_configuration_status(dashboard)
            add_event!(dashboard, :info, "=== CONFIGURATION STATUS ===")
            add_event!(dashboard, :info, "API Keys: $(config_status[:api_keys_status])")
            add_event!(dashboard, :info, "Data Dir: $(config_status[:data_dir])")
            add_event!(dashboard, :info, "Feature Set: $(config_status[:feature_set])")
            
            # Network diagnostics
            add_event!(dashboard, :info, "=== NETWORK DIAGNOSTICS ===")
            test_network_connectivity(dashboard)
            
            # Error summary
            error_summary = get_error_summary(dashboard)
            add_event!(dashboard, :info, "=== ERROR SUMMARY ===")
            add_event!(dashboard, :info, "Total Errors: $(error_summary[:total_errors])")
            
            # Data files
            data_files = discover_local_data_files(dashboard)
            total_files = sum(length(files) for files in values(data_files))
            add_event!(dashboard, :info, "=== DATA FILES ===")
            add_event!(dashboard, :info, "Total Files: $total_files")
            
            add_event!(dashboard, :success, "✅ Full diagnostics completed")
            
        catch e
            add_event!(dashboard, :error, "❌ Diagnostics failed", e)
        end
    end
end

function create_configuration_backup_command(dashboard)
    """
    Create a backup of configuration files.
    """
    @async begin
        try
            backup_dir = "config_backup_$(Dates.format(utc_now_datetime(), "yyyy-mm-dd_HH-MM-SS"))"
            mkpath(backup_dir)
            
            # Files to backup
            config_files = ["config.toml", "features.json", "models.json", ".dashboard_state.json"]
            backed_up = 0
            
            for config_file in config_files
                if isfile(config_file)
                    backup_path = joinpath(backup_dir, config_file)
                    cp(config_file, backup_path)
                    backed_up += 1
                    add_event!(dashboard, :info, "Backed up: $config_file")
                end
            end
            
            # Also backup data directory structure (without large files)
            if isdir(dashboard.config.data_dir)
                data_backup_dir = joinpath(backup_dir, "data_structure")
                mkpath(data_backup_dir)
                
                for file in readdir(dashboard.config.data_dir)
                    file_path = joinpath(dashboard.config.data_dir, file)
                    if isfile(file_path)
                        file_size = filesize(file_path)
                        # Only backup small files (< 10MB)
                        if file_size < 10 * 1024 * 1024
                            cp(file_path, joinpath(data_backup_dir, file))
                            add_event!(dashboard, :info, "Backed up data file: $file")
                        else
                            # Just create a placeholder for large files
                            open(joinpath(data_backup_dir, "$file.info"), "w") do io
                                println(io, "Large file ($(round(file_size / (1024*1024), digits=1)) MB) - not backed up")
                                println(io, "Original path: $file_path")
                                println(io, "Modified: $(Dates.unix2datetime(stat(file_path).mtime))")
                            end
                        end
                    end
                end
            end
            
            add_event!(dashboard, :success, "✅ Configuration backup created: $backup_dir ($backed_up files)")
            
        catch e
            add_event!(dashboard, :error, "❌ Backup failed", e)
        end
    end
end

# Helper functions for diagnostics
function get_system_diagnostics(dashboard)
    return Dict(
        :cpu_usage => get(dashboard.system_info, :cpu_usage, 0.0),
        :memory_used => get(dashboard.system_info, :memory_used, 0.0),
        :memory_total => get(dashboard.system_info, :memory_total, 16.0),
        :disk_free => round(Sys.free_memory() / 1024^3, digits=1),
        :uptime => get(dashboard.system_info, :uptime, "0m")
    )
end

function get_configuration_status(dashboard)
    return Dict(
        :api_keys_status => (!isempty(dashboard.config.api_public_key) && !isempty(dashboard.config.api_secret_key)) ? "Configured" : "Missing",
        :data_dir => dashboard.config.data_dir,
        :feature_set => dashboard.config.feature_set
    )
end

function test_network_connectivity(dashboard)
    @async begin
        try
            # Test API connectivity
            response = API.test_connection(dashboard.api_client)
            if response
                add_event!(dashboard, :success, "✅ API connection successful")
            else
                add_event!(dashboard, :error, "❌ API connection failed")
            end
        catch e
            add_event!(dashboard, :error, "❌ Network test failed: $e")
        end
    end
end

function get_error_summary(dashboard)
    return Dict(
        :total_errors => get(dashboard, :total_errors, 0)
    )
end

function discover_local_data_files(dashboard)
    data_dir = dashboard.config.data_dir
    files = Dict{String, Vector{String}}()

    if isdir(data_dir)
        all_files = readdir(data_dir)
        files["parquet"] = filter(f -> endswith(f, ".parquet"), all_files)
        files["csv"] = filter(f -> endswith(f, ".csv"), all_files)
        files["json"] = filter(f -> endswith(f, ".json"), all_files)
    end

    return files
end

function save_diagnostic_report(dashboard)
    @async begin
        try
            timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
            report_file = "diagnostic_report_$timestamp.txt"

            open(report_file, "w") do io
                println(io, "=== Numerai Tournament System Diagnostic Report ===")
                println(io, "Generated: ", now())
                println(io, "\nSystem Info:")
                for (key, value) in dashboard.system_info
                    println(io, "  $key: $value")
                end
                println(io, "\nConfiguration:")
                println(io, "  Tournament ID: ", dashboard.config.tournament_id)
                println(io, "  Feature Set: ", dashboard.config.feature_set)
                println(io, "  Models: ", join(dashboard.config.models, ", "))
            end

            add_event!(dashboard, :success, "✅ Diagnostic report saved: $report_file")
        catch e
            add_event!(dashboard, :error, "❌ Failed to save report: $e")
        end
    end
end

function reset_error_tracking!(dashboard)
    # Reset error counters
    if haskey(dashboard, :total_errors)
        dashboard.total_errors = 0
    end
    if haskey(dashboard, :error_counts)
        empty!(dashboard.error_counts)
    end
    add_event!(dashboard, :info, "Error tracking reset")
end

function utc_now_datetime()
    return Dates.now(Dates.UTC)
end

export execute_command, submit_predictions_command, stake_command, download_data_command,
       run_full_diagnostics_command, create_configuration_backup_command