# Slash command implementations for TUI dashboard

using ..API
using ..DataLoader
using ..Pipeline

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
    else
        add_event!(dashboard, :warning, "Unknown command: /$cmd")
        add_event!(dashboard, :info, "Available commands: /train, /submit, /stake, /download, /refresh, /help, /quit")
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

export execute_command, submit_predictions_command, stake_command, download_data_command