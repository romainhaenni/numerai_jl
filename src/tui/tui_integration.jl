"""
TUI Integration Module - Properly connects all TUI components.
This module ensures proper integration between dashboard, real-time updates, and user commands.
"""
module TUIIntegration

using Term
using Printf
using Dates
using ..TUIRealtime
using ..Dashboard
using ..API
using ..Pipeline

# Main module functions will be accessed dynamically

export integrate_tui_system!,
       handle_instant_command,
       trigger_download,
       trigger_upload,
       trigger_training,
       trigger_prediction,
       monitor_operations

# Integrate the real-time TUI system with the main dashboard
function integrate_tui_system!(dashboard)
    # Initialize the real-time tracker
    if !isdefined(dashboard, :realtime_tracker) || isnothing(dashboard.realtime_tracker)
        dashboard.realtime_tracker = TUIRealtime.init_realtime_tracker()
    end

    tracker = dashboard.realtime_tracker

    # Enable features
    TUIRealtime.enable_auto_training!(tracker)
    TUIRealtime.setup_instant_commands!(dashboard, tracker)

    # Start monitoring thread for real-time updates
    @async monitor_operations(dashboard)

    # Don't create a separate input loop - the main dashboard already has one
    # The dashboard input_loop will use our improved keyboard handling

    # Don't create a separate render loop - integrate with existing dashboard rendering
    # The dashboard update_loop will call our render function

    Dashboard.add_event!(dashboard, :success, "TUI integration complete - all features active")
end

# Monitor operations and update progress in real-time
function monitor_operations(dashboard)
    tracker = dashboard.realtime_tracker

    while dashboard.running
        try
            # Monitor actual progress from dashboard.progress_tracker
            if dashboard.progress_tracker.is_downloading
                progress = dashboard.progress_tracker.download_progress
                file = dashboard.progress_tracker.download_file
                size = dashboard.progress_tracker.download_size_mb
                speed = dashboard.progress_tracker.download_speed

                should_train = TUIRealtime.update_download_progress!(
                    tracker, progress, file, size, speed
                )

                if progress >= 100.0 && should_train && tracker.auto_train_enabled
                    # Check if all required files are downloaded
                    if check_all_downloads_complete(dashboard)
                        # Trigger automatic training
                        Dashboard.add_event!(dashboard, :info, "All downloads complete - starting automatic training")
                        @async Dashboard.start_training(dashboard)
                    end
                end
            end

            # Monitor actual upload progress
            if dashboard.progress_tracker.is_uploading
                progress = dashboard.progress_tracker.upload_progress
                file = dashboard.progress_tracker.upload_file
                size = dashboard.progress_tracker.upload_size_mb

                TUIRealtime.update_upload_progress!(tracker, progress, file, size)
            end

            # Monitor actual training progress
            if dashboard.progress_tracker.is_training || dashboard.training_info[:is_training]
                progress = max(dashboard.progress_tracker.training_progress, dashboard.training_info[:progress])
                epoch = max(dashboard.progress_tracker.training_epoch, dashboard.training_info[:current_epoch])
                total_epochs = max(dashboard.progress_tracker.training_total_epochs, dashboard.training_info[:total_epochs])
                loss = dashboard.training_info[:loss]
                model = !isempty(dashboard.progress_tracker.training_model) ? dashboard.progress_tracker.training_model : dashboard.training_info[:model_name]

                TUIRealtime.update_training_progress!(
                    tracker, progress, epoch, total_epochs, loss, model
                )
            end

            # Monitor actual prediction progress
            if dashboard.progress_tracker.is_predicting
                progress = dashboard.progress_tracker.prediction_progress
                rows = dashboard.progress_tracker.prediction_rows
                total_rows = dashboard.progress_tracker.prediction_total_rows
                model = dashboard.progress_tracker.prediction_model

                TUIRealtime.update_prediction_progress!(
                    tracker, progress, rows, total_rows, model
                )
            end

            # Update system status based on actual operations
            if dashboard.progress_tracker.is_downloading
                tracker.system_status = "Downloading"
            elseif dashboard.progress_tracker.is_uploading
                tracker.system_status = "Uploading"
            elseif dashboard.progress_tracker.is_training || dashboard.training_info[:is_training]
                tracker.system_status = "Training"
            elseif dashboard.progress_tracker.is_predicting
                tracker.system_status = "Predicting"
            else
                tracker.system_status = "Idle"
            end

            # Copy events to tracker
            for event in dashboard.events
                if !haskey(event, :added_to_tracker)
                    level = event[:type]
                    message = event[:message]
                    TUIRealtime.add_tracker_event!(tracker, level, message)
                    event[:added_to_tracker] = true
                end
            end

        catch e
            @error "Error in operation monitoring" exception=e
        end

        sleep(0.1)  # Check every 100ms for smooth updates
    end
end

# Helper function to check if all required downloads are complete
function check_all_downloads_complete(dashboard)
    data_dir = dashboard.config.data_dir

    # Check for required files
    required_files = ["train.parquet", "validation.parquet", "live.parquet"]

    for file in required_files
        filepath = joinpath(data_dir, file)
        if !isfile(filepath)
            return false
        end
    end

    return true
end

# This function will be called from the main dashboard input loop
# No need for a separate input loop that conflicts with the main one
function process_instant_key(dashboard, key::String)
    # Convert string key to char if it's a single character
    if length(key) == 1
        handle_instant_command(dashboard, key[1])
        return true  # Key was handled
    end
    return false  # Key not handled
end

# Handle instant keyboard commands
function handle_instant_command(dashboard, key::Char)
    tracker = dashboard.realtime_tracker

    # Skip if in command mode or wizard active
    if get(dashboard, :command_mode, false) || get(dashboard, :wizard_active, false)
        return
    end

    case_insensitive_key = lowercase(key)

    if case_insensitive_key == 'q'
        # Quit
        dashboard.running = false
        TUIRealtime.add_tracker_event!(tracker, :info, "Shutting down...")

    elseif case_insensitive_key == 'd'
        # Download data
        if !get(dashboard.active_operations, :download, false)
            trigger_download(dashboard)
        else
            TUIRealtime.add_tracker_event!(tracker, :warning, "Download already in progress")
        end

    elseif case_insensitive_key == 'u'
        # Upload predictions
        if !get(dashboard.active_operations, :upload, false)
            trigger_upload(dashboard)
        else
            TUIRealtime.add_tracker_event!(tracker, :warning, "Upload already in progress")
        end

    elseif case_insensitive_key == 's' || case_insensitive_key == 't'
        # Start training
        if !get(dashboard.active_operations, :training, false)
            trigger_training(dashboard)
        else
            TUIRealtime.add_tracker_event!(tracker, :warning, "Training already in progress")
        end

    elseif case_insensitive_key == 'p'
        # Make predictions
        if !get(dashboard.active_operations, :prediction, false)
            trigger_prediction(dashboard)
        else
            TUIRealtime.add_tracker_event!(tracker, :warning, "Prediction already in progress")
        end

    elseif case_insensitive_key == 'r'
        # Refresh
        TUIRealtime.add_tracker_event!(tracker, :info, "Refreshing model performances...")
        @async Dashboard.update_model_performances!(dashboard)

    elseif case_insensitive_key == 'h'
        # Help
        show_help(dashboard)

    elseif case_insensitive_key == 'n'
        # New model wizard
        dashboard.wizard_active = true
        TUIRealtime.add_tracker_event!(tracker, :info, "Starting model creation wizard")
    end
end

# Trigger operations
function trigger_download(dashboard)
    tracker = dashboard.realtime_tracker
    dashboard.active_operations[:download] = true
    tracker.download_progress = 0.0
    TUIRealtime.add_tracker_event!(tracker, :info, "Starting data download...")

    @async begin
        try
            # Call actual download function
            parentmodule(TUIIntegration).download_tournament_data()
        catch e
            dashboard.active_operations[:download] = false
            TUIRealtime.add_tracker_event!(tracker, :error, "Download failed: $(e)")
        end
    end
end

function trigger_upload(dashboard)
    tracker = dashboard.realtime_tracker
    dashboard.active_operations[:upload] = true
    tracker.upload_progress = 0.0
    TUIRealtime.add_tracker_event!(tracker, :info, "Starting prediction upload...")

    @async begin
        try
            # Call actual upload function
            if !isempty(dashboard.config.models)
                parentmodule(TUIIntegration).submit_predictions(dashboard.config.models[1])
            end
        catch e
            dashboard.active_operations[:upload] = false
            TUIRealtime.add_tracker_event!(tracker, :error, "Upload failed: $(e)")
        end
    end
end

function trigger_training(dashboard)
    tracker = dashboard.realtime_tracker
    dashboard.active_operations[:training] = true
    tracker.training_progress = 0.0
    TUIRealtime.add_tracker_event!(tracker, :info, "Starting model training...")

    @async begin
        try
            # Call actual training function
            parentmodule(TUIIntegration).train_all_models()
        catch e
            dashboard.active_operations[:training] = false
            TUIRealtime.add_tracker_event!(tracker, :error, "Training failed: $(e)")
        end
    end
end

function trigger_prediction(dashboard)
    tracker = dashboard.realtime_tracker
    dashboard.active_operations[:prediction] = true
    tracker.prediction_progress = 0.0
    TUIRealtime.add_tracker_event!(tracker, :info, "Starting predictions...")

    @async begin
        try
            # Call actual prediction function
            # Predictions are part of submit_predictions
            if !isempty(dashboard.config.models)
                parentmodule(TUIIntegration).submit_predictions(dashboard.config.models[1])
            end
        catch e
            dashboard.active_operations[:prediction] = false
            TUIRealtime.add_tracker_event!(tracker, :error, "Prediction failed: $(e)")
        end
    end
end

function show_help(dashboard)
    tracker = dashboard.realtime_tracker
    help_msg = """
    Instant Commands (no Enter required):
    q - Quit
    d - Download data
    u - Upload predictions
    s/t - Start training
    p - Make predictions
    r - Refresh performances
    n - New model wizard
    h - Show this help
    """

    for line in split(help_msg, '\n')
        if !isempty(strip(line))
            TUIRealtime.add_tracker_event!(tracker, :info, strip(line))
        end
    end
end

end # module