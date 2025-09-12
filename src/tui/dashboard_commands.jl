# Slash command implementations for TUI dashboard

using ..API
using ..DataLoader
using ..Pipeline
using Dates

# Execute slash commands
function execute_command(dashboard, command::String)
    # Remove leading slash if present
    cmd = startswith(command, "/") ? command[2:end] : command
    
    parts = split(cmd, " ")
    if isempty(parts)
        return
    end
    
    main_cmd = lowercase(parts[1])
    
    if main_cmd == "train"
        add_event!(dashboard, :info, "Starting training via command...")
        start_training(dashboard)
    elseif main_cmd == "submit"
        add_event!(dashboard, :info, "Submitting predictions...")
        submit_predictions_command(dashboard)
    elseif main_cmd == "stake"
        if length(parts) >= 2
            amount = tryparse(Float64, parts[2])
            if !isnothing(amount)
                stake_command(dashboard, amount)
            else
                add_event!(dashboard, :error, "Invalid stake amount: $(parts[2])")
            end
        else
            add_event!(dashboard, :error, "Usage: /stake <amount>")
        end
    elseif main_cmd == "download"
        add_event!(dashboard, :info, "Downloading latest data...")
        download_data_command(dashboard)
    elseif main_cmd == "help"
        dashboard.show_help = true
    elseif main_cmd == "quit" || main_cmd == "exit"
        dashboard.running = false
    elseif main_cmd == "refresh"
        update_model_performances!(dashboard)
        add_event!(dashboard, :info, "Data refreshed")
    elseif main_cmd == "pause" || main_cmd == "resume"
        dashboard.paused = !dashboard.paused
        status = dashboard.paused ? "paused" : "resumed"
        add_event!(dashboard, :info, "Dashboard $status")
    elseif main_cmd == "diag" || main_cmd == "diagnostics"
        add_event!(dashboard, :info, "Running full system diagnostics...")
        run_full_diagnostics_command(dashboard)
    elseif main_cmd == "reset"
        add_event!(dashboard, :info, "Resetting error counters...")
        reset_error_tracking!(dashboard)
    elseif main_cmd == "backup"
        add_event!(dashboard, :info, "Creating configuration backup...")
        create_configuration_backup_command(dashboard)
    elseif main_cmd == "network" || main_cmd == "net"
        add_event!(dashboard, :info, "Testing network connectivity...")
        test_network_connectivity(dashboard)
    elseif main_cmd == "save" || main_cmd == "report"
        add_event!(dashboard, :info, "Saving diagnostic report...")
        save_diagnostic_report(dashboard)
    else
        add_event!(dashboard, :warning, "Unknown command: /$cmd")
        add_event!(dashboard, :info, "Available commands: /train, /submit, /stake, /download, /refresh, /help, /quit")
        add_event!(dashboard, :info, "Recovery commands: /diag, /reset, /backup, /network, /save")
    end
end

# Command implementations
function submit_predictions_command(dashboard)
    @async begin
        try
            config = dashboard.config
            data_dir = get(config, "data_dir", "data")
            
            # Find the latest predictions file
            predictions_files = filter(f -> startswith(f, "predictions_") && endswith(f, ".csv"), 
                                      readdir(data_dir))
            
            if isempty(predictions_files)
                add_event!(dashboard, :error, "No predictions found to submit")
                return
            end
            
            latest_predictions = joinpath(data_dir, predictions_files[end])
            
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
            data_dir = get(config, "data_dir", "data")
            
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

export execute_command, submit_predictions_command, stake_command, download_data_command,
       run_full_diagnostics_command, create_configuration_backup_command