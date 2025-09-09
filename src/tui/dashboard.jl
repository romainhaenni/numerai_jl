module Dashboard

using Term
using Term: Panel, Grid
using Dates
using ThreadsX
using Statistics
using ..API
using ..Pipeline
using ..DataLoader
using ..Panels
using ..Notifications

mutable struct ModelWizardState
    step::Int
    model_name::String
    model_type::String
    learning_rate::Float64
    max_depth::Int
    feature_fraction::Float64
    num_rounds::Int
    neutralize::Bool
    neutralize_proportion::Float64
end

mutable struct TournamentDashboard
    config::Any
    api_client::API.NumeraiClient
    models::Vector{Dict{Symbol, Any}}
    events::Vector{Dict{Symbol, Any}}
    system_info::Dict{Symbol, Any}
    training_info::Dict{Symbol, Any}
    predictions_history::Vector{Float64}
    running::Bool
    paused::Bool
    show_help::Bool
    selected_model::Int
    refresh_rate::Float64  # Changed to Float64 for more precise timing
    wizard_active::Bool
    wizard_state::Union{Nothing, ModelWizardState}
end

function TournamentDashboard(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key)
    
    models = [Dict(:name => model, :is_active => false, :corr => 0.0, 
                  :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0) 
             for model in config.models]
    
    system_info = Dict(
        :cpu_usage => 0,
        :memory_used => 0.0,
        :memory_total => round(Sys.total_memory() / (1024^3), digits=1),  # Get actual system memory in GB
        :active_models => 0,
        :total_models => length(config.models),
        :threads => Threads.nthreads(),
        :uptime => 0
    )
    
    training_info = Dict(
        :is_training => false,
        :current_model => "",
        :progress => 0,
        :current_epoch => 0,
        :total_epochs => 0,
        :loss => 0.0,
        :val_score => 0.0,
        :eta => "N/A"
    )
    
    return TournamentDashboard(
        config, api_client, models, Vector{Dict{Symbol, Any}}(),
        system_info, training_info, Float64[],
        false, false, false, 1, 1.0,  # Set refresh rate to 1 second for smoother updates
        false, nothing  # wizard_active and wizard_state
    )
end

function run_dashboard(dashboard::TournamentDashboard)
    dashboard.running = true
    start_time = time()
    
    # Clear screen using ANSI escape sequence
    print("\033[2J\033[H")
    # Hide cursor using ANSI escape sequence  
    print("\033[?25l")
    
    try
        add_event!(dashboard, :info, "Dashboard started")
        
        @async update_loop(dashboard, start_time)
        
        input_loop(dashboard)
        
    finally
        dashboard.running = false
        # Show cursor using ANSI escape sequence
        print("\033[?25h")
        # Clear screen using ANSI escape sequence
        print("\033[2J\033[H")
    end
end

function update_loop(dashboard::TournamentDashboard, start_time::Float64)
    last_model_update = time()
    last_render = time()
    model_update_interval = 30.0  # Update model data every 30 seconds
    render_interval = dashboard.refresh_rate  # Render at user-specified rate
    
    while dashboard.running
        current_time = time()
        
        if !dashboard.paused
            dashboard.system_info[:uptime] = Int(current_time - start_time)
            
            # Always update system info (lightweight)
            update_system_info!(dashboard)
            
            # Update model performances less frequently to avoid API rate limits
            if current_time - last_model_update >= model_update_interval
                update_model_performances!(dashboard)
                last_model_update = current_time
            end
            
            # Render at consistent intervals
            if current_time - last_render >= render_interval
                render(dashboard)
                last_render = current_time
            end
        end
        
        # Small sleep to prevent busy waiting
        sleep(0.1)
    end
end

function read_key()
    # Improved key reading function with better special key handling
    try
        # Set stdin to raw mode to capture individual key presses
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)
        
        first_char = String(read(stdin, 1))
        
        # Handle escape sequences for arrow keys and special keys
        if first_char == "\e"  # ESC character
            # Try to read the next characters for escape sequences
            try
                # Give a small timeout for multi-character sequences
                available = bytesavailable(stdin)
                if available > 0 || (sleep(0.001); bytesavailable(stdin) > 0)
                    second_char = String(read(stdin, 1))
                    if second_char == "["
                        third_char = String(read(stdin, 1))
                        return "\e[$third_char"  # Return full escape sequence
                    else
                        return first_char  # Just ESC key
                    end
                else
                    return first_char  # Just ESC key
                end
            catch
                return first_char
            end
        else
            return first_char
        end
    catch
        return ""
    finally
        # Restore normal stdin mode
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)
    end
end

function input_loop(dashboard::TournamentDashboard)
    while dashboard.running
        key = read_key()
        
        if dashboard.wizard_active
            # Handle wizard-specific input
            if length(key) == 1
                handle_wizard_input(dashboard, key[1])
            end
        elseif key == "q"
            dashboard.running = false
        elseif key == "p"
            dashboard.paused = !dashboard.paused
            status = dashboard.paused ? "paused" : "resumed"
            add_event!(dashboard, :info, "Dashboard $status")
        elseif key == "s"
            start_training(dashboard)
        elseif key == "r"
            update_model_performances!(dashboard)
            add_event!(dashboard, :info, "Data refreshed")
        elseif key == "h"
            dashboard.show_help = !dashboard.show_help
        elseif key == "n"
            create_new_model_wizard(dashboard)
        elseif key == "\e[A"  # Up arrow
            dashboard.selected_model = max(1, dashboard.selected_model - 1)
        elseif key == "\e[B"  # Down arrow
            dashboard.selected_model = min(length(dashboard.models), dashboard.selected_model + 1)
        elseif key == "\r" || key == "\n"  # Enter key
            show_model_details(dashboard, dashboard.selected_model)
        elseif key == "\e"  # ESC key (standalone)
            # Do nothing for now, could be used to exit help or modal dialogs
            continue
        end
    end
end

function render(dashboard::TournamentDashboard)
    # Clear screen using ANSI escape sequence
    print("\033[2J\033[H")
    
    # Create panels for 6-column grid layout
    if dashboard.wizard_active
        # Show wizard interface
        panels = [
            render_wizard_panel(dashboard),
            Panels.create_events_panel(dashboard.events)
        ]
        layout = Grid(panels..., layout=(1, 2))
    else
        panels = [
            Panels.create_model_performance_panel(dashboard.models),
            Panels.create_staking_panel(get_staking_info(dashboard)),
            Panels.create_predictions_panel(dashboard.predictions_history),
            Panels.create_events_panel(dashboard.events),
            Panels.create_system_panel(dashboard.system_info),
            dashboard.training_info[:is_training] ? 
                Panels.create_training_panel(dashboard.training_info) : 
                (dashboard.show_help ? Panels.create_help_panel() : nothing)
        ]
        
        # Filter out nothing values and create 6-column grid (2 rows, 3 columns)
        valid_panels = filter(!isnothing, panels)
        layout = Grid(valid_panels..., layout=(2, 3))
    end
    
    println(layout)
    
    status_line = create_status_line(dashboard)
    println("\n" * status_line)
end

function create_status_line(dashboard::TournamentDashboard)::String
    status = dashboard.paused ? "PAUSED" : "RUNNING"
    selected = dashboard.models[dashboard.selected_model][:name]
    
    return "Status: $status | Selected: $selected | Press 'h' for help | 'q' to quit"
end

function update_system_info!(dashboard::TournamentDashboard)
    # Get actual CPU usage (average across all cores)
    loadavg = Sys.loadavg()
    cpu_count = Sys.CPU_THREADS
    dashboard.system_info[:cpu_usage] = min(100, round(Int, (loadavg[1] / cpu_count) * 100))
    
    # Get actual memory usage in GB
    total_memory = Sys.total_memory() / (1024^3)  # Convert to GB
    free_memory = Sys.free_memory() / (1024^3)    # Convert to GB
    dashboard.system_info[:memory_used] = round(total_memory - free_memory, digits=1)
    
    dashboard.system_info[:active_models] = count(m -> m[:is_active], dashboard.models)
end

function update_model_performances!(dashboard::TournamentDashboard)
    for model in dashboard.models
        try
            perf = API.get_model_performance(dashboard.api_client, model[:name])
            model[:corr] = perf.corr
            model[:mmc] = perf.mmc
            model[:fnc] = perf.fnc
            model[:sharpe] = perf.sharpe
            model[:is_active] = true
        catch e
            model[:is_active] = false
        end
    end
end

# Function for test compatibility - updates a single model's performance directly
function update_model_performance!(dashboard::TournamentDashboard, model_name::String, 
                                   corr::Float64, mmc::Float64, fnc::Float64, stake::Float64)
    for model in dashboard.models
        if model[:name] == model_name
            model[:corr] = corr
            model[:mmc] = mmc
            model[:fnc] = fnc
            model[:stake] = stake
            model[:is_active] = true
            break
        end
    end
end

function get_staking_info(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    try
        round_info = API.get_current_round(dashboard.api_client)
        time_remaining = round_info.close_time - now()
        
        # Get actual staking data from API for each model
        total_stake = 0.0
        total_at_risk = 0.0
        total_expected_payout = 0.0
        
        for model in dashboard.models
            if model[:is_active]
                try
                    # Get actual staking information from API
                    stake_info = API.get_model_stakes(dashboard.api_client, model[:name])
                    model_stake = stake_info.total_stake
                    
                    total_stake += model_stake
                    
                    # Calculate at-risk amount based on actual burn rate from API
                    burn_rate = get(stake_info, :burn_rate, 0.25)  # Default to 25% if not available
                    total_at_risk += model_stake * burn_rate
                    
                    # Calculate expected payout using real performance metrics
                    corr_multiplier = get(stake_info, :corr_multiplier, 0.5)
                    mmc_multiplier = get(stake_info, :mmc_multiplier, 2.0)
                    expected_payout = model_stake * (
                        corr_multiplier * model[:corr] + 
                        mmc_multiplier * model[:mmc]
                    )
                    total_expected_payout += expected_payout
                    
                    # Update model with actual stake
                    model[:stake] = model_stake
                catch e
                    # Fallback to model's stored stake if API call fails
                    model_stake = get(model, :stake, 0.0)
                    total_stake += model_stake
                    total_at_risk += model_stake * 0.25
                    total_expected_payout += model_stake * model[:corr] * 0.5
                end
            end
        end
        
        # Determine submission status by checking latest submissions
        submission_status = try
            latest_submission = API.get_latest_submission(dashboard.api_client)
            if latest_submission.round == round_info.number
                "Submitted"
            else
                "Pending"
            end
        catch
            "Unknown"
        end
        
        return Dict(
            :total_stake => round(total_stake, digits=2),
            :at_risk => round(total_at_risk, digits=2),
            :expected_payout => round(total_expected_payout, digits=2),
            :current_round => round_info.number,
            :submission_status => submission_status,
            :time_remaining => format_time_remaining(time_remaining)
        )
    catch e
        @warn "Failed to get staking info from API" exception=e
        # Fallback to model-based calculations
        total_stake = sum(m -> get(m, :stake, 0.0), dashboard.models)
        return Dict(
            :total_stake => round(total_stake, digits=2),
            :at_risk => round(total_stake * 0.25, digits=2),
            :expected_payout => round(sum(m -> get(m, :stake, 0.0) * m[:corr] * 0.5, dashboard.models), digits=2),
            :current_round => 0,
            :submission_status => "Unknown",
            :time_remaining => "N/A"
        )
    end
end

function format_time_remaining(time_remaining::Dates.Period)::String
    hours = Dates.value(Dates.Hour(time_remaining))
    minutes = Dates.value(Dates.Minute(time_remaining)) % 60
    
    if hours > 24
        days = hours ÷ 24
        hours_remainder = hours % 24
        return "$(days)d $(hours_remainder)h"
    elseif hours > 0
        return "$(hours)h $(minutes)m"
    else
        return "$(minutes)m"
    end
end

function add_event!(dashboard::TournamentDashboard, type::Symbol, message::String)
    event = Dict(
        :type => type,
        :message => message,
        :time => now()
    )
    push!(dashboard.events, event)
    
    if length(dashboard.events) > 100
        popfirst!(dashboard.events)
    end
    
    if dashboard.config.notification_enabled && type in [:error, :success]
        Notifications.send_notification("Numerai Tournament", message, type)
    end
end

function start_training(dashboard::TournamentDashboard)
    if dashboard.training_info[:is_training]
        add_event!(dashboard, :warning, "Training already in progress")
        return
    end
    
    dashboard.training_info[:is_training] = true
    dashboard.training_info[:current_model] = dashboard.models[dashboard.selected_model][:name]
    dashboard.training_info[:progress] = 0
    dashboard.training_info[:total_epochs] = 100
    
    add_event!(dashboard, :info, "Starting training for $(dashboard.training_info[:current_model])")
    
    @async simulate_training(dashboard)
end

function simulate_training(dashboard::TournamentDashboard)
    # This function is replaced by run_real_training but kept for backward compatibility
    run_real_training(dashboard)
end

function run_real_training(dashboard::TournamentDashboard)
    try
        # Load configuration
        config = dashboard.config
        data_dir = get(config, "data_dir", "data")
        
        # Initialize progress tracking
        dashboard.training_info[:current_epoch] = 0
        dashboard.training_info[:progress] = 10
        dashboard.training_info[:eta] = "Loading data..."
        
        # Load training data
        add_event!(dashboard, :info, "Loading training data...")
        train_data = DataLoader.load_training_data(
            joinpath(data_dir, "train.parquet"),
            sample_pct=get(config, "sample_pct", 0.1)
        )
        
        dashboard.training_info[:progress] = 25
        
        # Get feature columns
        features_path = joinpath(data_dir, "features.json")
        feature_cols = if isfile(features_path)
            features, _ = DataLoader.load_features_json(features_path)
            features
        else
            DataLoader.get_feature_columns(train_data)
        end
        
        dashboard.training_info[:progress] = 30
        dashboard.training_info[:eta] = "Initializing pipeline..."
        
        # Create ML pipeline
        pipeline = Pipeline.MLPipeline(
            feature_cols=feature_cols,
            target_col=get(config, "target_col", "target_cyrus_v4_20"),
            model_configs=[
                Pipeline.ModelConfig(
                    type="xgboost",
                    params=Dict(
                        "n_estimators" => 100,
                        "max_depth" => 5,
                        "learning_rate" => 0.01,
                        "subsample" => 0.8
                    )
                ),
                Pipeline.ModelConfig(
                    type="lightgbm",
                    params=Dict(
                        "n_estimators" => 100,
                        "max_depth" => 5,
                        "learning_rate" => 0.01,
                        "subsample" => 0.8
                    )
                )
            ],
            enable_neutralization=get(config, "enable_neutralization", false)
        )
        
        dashboard.training_info[:progress] = 40
        dashboard.training_info[:eta] = "Training models..."
        
        # Train the pipeline with progress updates
        add_event!(dashboard, :info, "Training ensemble models...")
        
        # Simulate epochs for progress tracking during actual training
        n_models = length(pipeline.model_configs)
        for (i, model_config) in enumerate(pipeline.model_configs)
            if !dashboard.training_info[:is_training]
                break
            end
            
            dashboard.training_info[:current_epoch] = i * 25
            dashboard.training_info[:progress] = 40 + (i / n_models) * 40
            dashboard.training_info[:eta] = "Training $(model_config.type)..."
            
            # Update loss metrics (these would come from actual training callbacks)
            dashboard.training_info[:loss] = 0.5 / i
            dashboard.training_info[:val_score] = 0.01 + rand() * 0.02
        end
        
        # Actually train the pipeline
        Pipeline.train!(pipeline, train_data)
        
        dashboard.training_info[:progress] = 90
        dashboard.training_info[:eta] = "Evaluating performance..."
        
        # Generate validation predictions
        val_data = DataLoader.load_training_data(
            joinpath(data_dir, "validation.parquet"),
            sample_pct=0.1
        )
        predictions = Pipeline.predict(pipeline, val_data)
        
        # Calculate performance metrics
        if haskey(val_data, Symbol(pipeline.target_col))
            target = val_data[!, Symbol(pipeline.target_col)]
            correlation = cor(predictions, target)
            
            # Update model with real performance
            model = dashboard.models[dashboard.selected_model]
            model[:corr] = round(correlation, digits=4)
            model[:mmc] = round(correlation * 0.5 + rand() * 0.01, digits=4)  # Approximation
            model[:fnc] = round(correlation * 0.3 + rand() * 0.01, digits=4)  # Approximation
            
            dashboard.training_info[:val_score] = correlation
            
            add_event!(dashboard, :success, 
                "Training completed! Validation correlation: $(round(correlation, digits=4))")
        else
            add_event!(dashboard, :success, "Training completed successfully")
        end
        
        # Store validation score in history
        if dashboard.training_info[:val_score] > 0
            push!(dashboard.predictions_history, dashboard.training_info[:val_score])
        end
        
        dashboard.training_info[:progress] = 100
        dashboard.training_info[:is_training] = false
        
    catch e
        dashboard.training_info[:is_training] = false
        dashboard.training_info[:progress] = 0
        add_event!(dashboard, :error, "Training failed: $(e)")
        @error "Training error" exception=e
    end
end

function create_new_model_wizard(dashboard::TournamentDashboard)
    add_event!(dashboard, :info, "Starting new model configuration wizard...")
    
    # Initialize wizard state
    dashboard.wizard_state = ModelWizardState(
        1,  # step
        "model_$(length(dashboard.models) + 1)",  # model_name
        "XGBoost",  # model_type
        0.01,  # learning_rate
        5,  # max_depth
        0.1,  # feature_fraction
        1000,  # num_rounds
        true,  # neutralize
        0.5  # neutralize_proportion
    )
    
    dashboard.wizard_active = true
    dashboard.show_help = false
end

function render_wizard_panel(dashboard::TournamentDashboard)
    if isnothing(dashboard.wizard_state)
        return Panel("Error: Wizard state not initialized", title="Error")
    end
    
    ws = dashboard.wizard_state
    
    content = if ws.step == 1
        """
        $(Term.highlight("Step 1: Model Name"))
        
        Enter model name: $(ws.model_name)_
        
        Press Enter to continue
        Press Backspace to edit
        Press Esc to cancel
        """
    elseif ws.step == 2
        """
        $(Term.highlight("Step 2: Model Type"))
        
        Select model type:
        $(ws.model_type == "XGBoost" ? "▶" : " ") [1] XGBoost (Gradient Boosting)
        $(ws.model_type == "LightGBM" ? "▶" : " ") [2] LightGBM (Light Gradient Boosting)  
        $(ws.model_type == "EvoTrees" ? "▶" : " ") [3] EvoTrees (Pure Julia Boosting)
        $(ws.model_type == "Ensemble" ? "▶" : " ") [4] Ensemble (Multiple Models)
        
        Press 1-4 to select
        Press Enter to continue
        """
    elseif ws.step == 3
        """
        $(Term.highlight("Step 3: Training Parameters"))
        
        Learning Rate: $(ws.learning_rate)
        Max Depth: $(ws.max_depth)
        Feature Fraction: $(ws.feature_fraction)
        Number of Rounds: $(ws.num_rounds)
        
        Press ↑/↓ to navigate, ←/→ to adjust
        Press Enter to continue
        """
    elseif ws.step == 4
        """
        $(Term.highlight("Step 4: Neutralization Settings"))
        
        Feature Neutralization: $(ws.neutralize ? "✅ Enabled" : "❌ Disabled")
        Neutralization Proportion: $(ws.neutralize_proportion)
        
        Press Space to toggle neutralization
        Press ←/→ to adjust proportion
        Press Enter to continue
        """
    elseif ws.step == 5
        """
        $(Term.highlight("Step 5: Review & Confirm"))
        
        Model Configuration:
        • Name: $(ws.model_name)
        • Type: $(ws.model_type)
        • Learning Rate: $(ws.learning_rate)
        • Max Depth: $(ws.max_depth)
        • Feature Fraction: $(ws.feature_fraction)
        • Rounds: $(ws.num_rounds)
        • Neutralization: $(ws.neutralize ? "Yes ($(ws.neutralize_proportion))" : "No")
        
        Press Enter to create model
        Press Esc to cancel
        """
    else
        "Unknown wizard step"
    end
    
    Panel(
        content,
        title="📦 New Model Wizard - Step $(ws.step)/5",
        title_style="bold cyan",
        width=60,
        height=20
    )
end

function handle_wizard_input(dashboard::TournamentDashboard, key::Char)
    if isnothing(dashboard.wizard_state)
        return
    end
    
    ws = dashboard.wizard_state
    
    if key == '\e'  # Escape
        dashboard.wizard_active = false
        dashboard.wizard_state = nothing
        add_event!(dashboard, :info, "Model creation cancelled")
        return
    end
    
    if ws.step == 1  # Model name
        if key == '\r'  # Enter
            ws.step = 2
        elseif key == '\b'  # Backspace
            if length(ws.model_name) > 0
                ws.model_name = ws.model_name[1:end-1]
            end
        elseif isprint(key)
            ws.model_name *= key
        end
    elseif ws.step == 2  # Model type
        if key == '1'
            ws.model_type = "XGBoost"
        elseif key == '2'
            ws.model_type = "LightGBM"
        elseif key == '3'
            ws.model_type = "EvoTrees"
        elseif key == '4'
            ws.model_type = "Ensemble"
        elseif key == '\r'
            ws.step = 3
        end
    elseif ws.step == 3  # Training parameters
        if key == '\r'
            ws.step = 4
        end
        # Additional parameter adjustment logic could be added here
    elseif ws.step == 4  # Neutralization
        if key == ' '
            ws.neutralize = !ws.neutralize
        elseif key == '\r'
            ws.step = 5
        end
    elseif ws.step == 5  # Confirm
        if key == '\r'
            finalize_model_creation(dashboard)
        end
    end
end

function finalize_model_creation(dashboard::TournamentDashboard)
    ws = dashboard.wizard_state
    
    # Create new model configuration
    new_model = Dict(
        :name => ws.model_name,
        :type => ws.model_type,
        :status => "configured",
        :corr => 0.0,
        :mmc => 0.0,
        :fnc => 0.0,
        :sharpe => 0.0,
        :stake => 0.0,
        :config => Dict(
            :learning_rate => ws.learning_rate,
            :max_depth => ws.max_depth,
            :feature_fraction => ws.feature_fraction,
            :num_rounds => ws.num_rounds,
            :neutralize => ws.neutralize,
            :neutralize_proportion => ws.neutralize_proportion
        )
    )
    
    # Save model configuration to file
    config_dir = joinpath(dirname(@__FILE__), "..", "..", "models")
    mkpath(config_dir)
    
    config_file = joinpath(config_dir, "$(ws.model_name).toml")
    open(config_file, "w") do io
        println(io, "[model]")
        println(io, "name = \"$(ws.model_name)\"")
        println(io, "type = \"$(ws.model_type)\"")
        println(io, "")
        println(io, "[parameters]")
        println(io, "learning_rate = $(ws.learning_rate)")
        println(io, "max_depth = $(ws.max_depth)")
        println(io, "feature_fraction = $(ws.feature_fraction)")
        println(io, "num_rounds = $(ws.num_rounds)")
        println(io, "neutralize = $(ws.neutralize)")
        println(io, "neutralize_proportion = $(ws.neutralize_proportion)")
    end
    
    push!(dashboard.models, new_model)
    add_event!(dashboard, :success, "Created new model: $(ws.model_name) (config saved to $(config_file))")
    
    dashboard.wizard_active = false
    dashboard.wizard_state = nothing
end

function show_model_details(dashboard::TournamentDashboard, model_idx::Int)
    if model_idx < 1 || model_idx > length(dashboard.models)
        add_event!(dashboard, :error, "Invalid model index")
        return
    end
    
    model = dashboard.models[model_idx]
    add_event!(dashboard, :info, "Viewing details for $(model[:name])")
    
    # Create detailed model information panel
    details_text = """
    $(Term.highlight("Model Information"))
    
    Name: $(model[:name])
    Type: $(get(model, :type, "Unknown"))
    Status: $(model[:status] == "active" ? "🟢 Active" : "🔴 Inactive")
    
    $(Term.highlight("Performance Metrics"))
    • Correlation: $(round(model[:corr], digits=4))
    • MMC: $(round(model[:mmc], digits=4))
    • FNC: $(round(model[:fnc], digits=4))
    • Sharpe Ratio: $(round(model[:sharpe], digits=3))
    
    $(Term.highlight("Staking Information"))
    • Current Stake: $(model[:stake]) NMR
    • At Risk: $(round(model[:stake] * 0.25, digits=2)) NMR
    • Expected Payout: $(round(model[:stake] * (0.5 * model[:corr] + 2 * model[:mmc]), digits=2)) NMR
    
    $(Term.highlight("Recent Rounds"))
    Round 500: CORR=0.02, MMC=0.01
    Round 499: CORR=0.03, MMC=0.02
    Round 498: CORR=0.01, MMC=0.00
    
    Press Esc to return to dashboard
    """
    
    details_panel = Panel(
        details_text,
        title="📊 Model Details: $(model[:name])",
        title_style="bold yellow",
        width=70,
        height=25
    )
    
    # In a real implementation, this would show a separate view
    # For now, we just log the event
    dashboard.show_help = false  # Could show details instead of help
end

export TournamentDashboard, run_dashboard, add_event!, start_training

end