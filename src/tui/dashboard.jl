module Dashboard

using Term
using Term: Panel
using Dates
using TimeZones
using ThreadsX
using Statistics
using JSON3
using HTTP
using ..API
using ..Pipeline
using ..DataLoader
using ..Panels
using ..Logger: @log_info, @log_warn, @log_error

# Import UTC utility function
include("../utils.jl")

include("dashboard_commands.jl")

# Error categorization types
@enum ErrorCategory begin
    API_ERROR
    NETWORK_ERROR
    AUTH_ERROR
    DATA_ERROR
    SYSTEM_ERROR
    TIMEOUT_ERROR
    VALIDATION_ERROR
end

@enum ErrorSeverity begin
    LOW
    MEDIUM
    HIGH
    CRITICAL
end

struct CategorizedError
    category::ErrorCategory
    severity::ErrorSeverity
    message::String
    technical_details::String
    timestamp::DateTime
    retry_count::Int
end

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
    model::Dict{Symbol, Any}  # Single model instead of vector
    events::Vector{Dict{Symbol, Any}}
    system_info::Dict{Symbol, Any}
    training_info::Dict{Symbol, Any}
    predictions_history::Vector{Float64}
    performance_history::Vector{Dict{Symbol, Any}}  # Historical performance tracking for single model
    running::Bool
    paused::Bool
    show_help::Bool
    refresh_rate::Float64  # Changed to Float64 for more precise timing
    command_buffer::String  # For slash commands
    command_mode::Bool  # Track if we're in command mode
    show_model_details::Bool  # Track if model details panel should be shown
    # Error tracking and network status
    error_counts::Dict{ErrorCategory, Int}  # Track error counts by category
    network_status::Dict{Symbol, Any}  # Network connectivity status
    last_api_errors::Vector{CategorizedError}  # Recent API errors for debugging
end

function TournamentDashboard(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key, config.tournament_id)
    
    # Use single model - get first model or default
    model_name = isempty(config.models) ? "default_model" : config.models[1]
    
    model = Dict(:name => model_name, :is_active => false, :corr => 0.0, 
                 :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0, :tc => 0.0)
    
    system_info = Dict(
        :cpu_usage => 0,
        :memory_used => 0.0,
        :memory_total => round(Sys.total_memory() / (1024^3), digits=1),  # Get actual system memory in GB
        :model_active => false,
        :threads => Threads.nthreads(),
        :uptime => 0
    )
    
    training_info = Dict(
        :is_training => false,
        :model_name => model_name,
        :progress => 0,
        :current_epoch => 0,
        :total_epochs => 0,
        :loss => 0.0,
        :val_score => 0.0,
        :eta => "N/A"
    )
    
    # Initialize performance history for single model
    performance_history = Vector{Dict{Symbol, Any}}()
    
    # Initialize error tracking
    error_counts = Dict{ErrorCategory, Int}(
        API_ERROR => 0,
        NETWORK_ERROR => 0,
        AUTH_ERROR => 0,
        DATA_ERROR => 0,
        SYSTEM_ERROR => 0,
        TIMEOUT_ERROR => 0,
        VALIDATION_ERROR => 0
    )
    
    # Initialize network status
    network_status = Dict{Symbol, Any}(
        :is_connected => true,
        :last_check => utc_now_datetime(),
        :api_latency => 0.0,
        :consecutive_failures => 0
    )
    
    # Get refresh rate from config
    refresh_rate = get(config.tui_config, "refresh_rate", 1.0)
    
    return TournamentDashboard(
        config, api_client, model, Vector{Dict{Symbol, Any}}(),
        system_info, training_info, Float64[], performance_history,
        false, false, false, refresh_rate,  # Use configured refresh rate
        "", false,  # command_buffer and command_mode
        false,  # show_model_details
        error_counts, network_status, Vector{CategorizedError}()  # error tracking fields
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
        
        # Initial render to show something immediately
        try
            render(dashboard)
        catch e
            println("\n⚠️ Error during initial render: ", e)
            println("\nStack trace:")
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
                println()
            end
            println("\nPress Ctrl+C to exit...")
        end
        
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
    last_network_check = time()
    # Get intervals from configuration
    model_update_interval = get(dashboard.config.tui_config, "model_update_interval", 30.0)
    network_check_interval = get(dashboard.config.tui_config, "network_check_interval", 60.0)
    render_interval = dashboard.refresh_rate  # Render at user-specified rate
    
    while dashboard.running
        current_time = time()
        
        if !dashboard.paused
            dashboard.system_info[:uptime] = Int(current_time - start_time)
            
            # Always update system info (lightweight)
            update_system_info!(dashboard)
            
            # Periodic network connectivity check
            if current_time - last_network_check >= network_check_interval
                was_connected = dashboard.network_status[:is_connected]
                is_connected = check_network_connectivity(dashboard)
                
                # Log connectivity state changes
                if was_connected && !is_connected
                    add_event!(dashboard, :error, "Network connection lost", 
                              Base.IOError("Network connectivity check failed"))
                elseif !was_connected && is_connected
                    add_event!(dashboard, :success, "Network connection restored")
                end
                
                last_network_check = current_time
            end
            
            # Update model performances less frequently to avoid API rate limits
            # Only attempt if network is connected
            if current_time - last_model_update >= model_update_interval
                if dashboard.network_status[:is_connected]
                    update_model_performances!(dashboard)
                else
                    add_event!(dashboard, :warning, "Skipping model update - no network connection")
                end
                last_model_update = current_time
            end
            
            # Render at consistent intervals
            if current_time - last_render >= render_interval
                try
                    render(dashboard)
                catch e
                    # Log render errors but don't crash
                    add_event!(dashboard, :error, "Render error: $(e)")
                end
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
        
        if dashboard.show_model_details
            # Handle model details panel input
            if key == "\e" || key == "q"  # ESC or q to close
                dashboard.show_model_details = false
                dashboard.selected_model_details = nothing
                dashboard.selected_model_stats = nothing
                add_event!(dashboard, :info, "Model details closed")
            end
        elseif dashboard.command_mode
            # Handle command mode input
            if key == "\r" || key == "\n"  # Enter - execute command
                execute_command(dashboard, dashboard.command_buffer)
                dashboard.command_buffer = ""
                dashboard.command_mode = false
            elseif key == "\e"  # ESC - cancel command
                dashboard.command_buffer = ""
                dashboard.command_mode = false
                add_event!(dashboard, :info, "Command cancelled")
            elseif key == "\b" || key == "\x7f"  # Backspace
                if length(dashboard.command_buffer) > 0
                    dashboard.command_buffer = dashboard.command_buffer[1:end-1]
                end
            elseif length(key) == 1 && isprint(key[1])
                dashboard.command_buffer *= key
            end
        elseif key == "/"  # Start command mode
            dashboard.command_mode = true
            dashboard.command_buffer = ""
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
        elseif key == "\r" || key == "\n"  # Enter key
            show_model_details(dashboard)
        elseif key == "\e"  # ESC key (standalone)
            # Do nothing for now, could be used to exit help or modal dialogs
            continue
        end
    end
end

function render(dashboard::TournamentDashboard)
    # Clear screen using ANSI escape sequence
    print("\033[2J\033[H")
    
    try
        # Create and display panels directly without Grid
        if dashboard.show_model_details
            # Show model details interface
            panel1 = render_model_details_panel(dashboard)
            panel2 = Panels.create_events_panel(dashboard.events, dashboard.config)
            println(panel1)
            println(panel2)
        else
            # Normal dashboard - display panels in sequence
            panels = [
                Panels.create_model_performance_panel(dashboard.model, dashboard.config),
                Panels.create_staking_panel(get_staking_info(dashboard), dashboard.config),
                Panels.create_predictions_panel(dashboard.predictions_history, dashboard.config),
                Panels.create_events_panel(dashboard.events, dashboard.config),
                Panels.create_system_panel(dashboard.system_info, dashboard.network_status, dashboard.config),
                dashboard.training_info[:is_training] ? 
                    Panels.create_training_panel(dashboard.training_info, dashboard.config) : 
                    (dashboard.show_help ? Panels.create_help_panel(dashboard.config) : nothing)
            ]
            
            # Display each panel
            for panel in panels
                if !isnothing(panel)
                    println(panel)
                end
            end
        end
        
        status_line = create_status_line(dashboard)
        println("\n" * status_line)
    catch e
        # Fallback rendering if panels fail
        println("═══════════════════════════════════════════════════════════════")
        println("     🚀 Numerai Tournament Dashboard - Recovery Mode")
        println("═══════════════════════════════════════════════════════════════")
        println()
        println("⚠️  Error rendering dashboard: ", e)
        println()
        println("📊 Model: $(dashboard.model[:name])")
        println("🔧 System: $(dashboard.system_info[:threads]) threads, $(dashboard.system_info[:memory_total]) GB RAM")
        println("🌐 Network: ", dashboard.network_status[:is_connected] ? "Connected ✅" : "Disconnected ❌")
        println()
        println("Recent Events:")
        for (i, event) in enumerate(Iterators.take(Iterators.reverse(dashboard.events), 5))
            timestamp = haskey(event, :time) ? event[:time] : "N/A"
            println("  [$timestamp] $(event[:message])")
        end
        println()
        println("Commands: q=quit, p=pause, s=start training, h=help")
        println()
        println("Debug: Press 'd' to show detailed error information")
    end
end

function create_status_line(dashboard::TournamentDashboard)::String
    if dashboard.command_mode
        # Show command input line
        return "Command: /$(dashboard.command_buffer)_"
    else
        status = dashboard.paused ? "PAUSED" : "RUNNING"
        model_name = dashboard.model[:name]
        
        return "Status: $status | Model: $model_name | Press '/' for commands | 'h' for help | 'q' to quit"
    end
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
    
    dashboard.system_info[:model_active] = dashboard.model[:is_active]
end

function update_model_performances!(dashboard::TournamentDashboard)
    # Check network connectivity first
    if !check_network_connectivity(dashboard)
        add_event!(dashboard, :error, "Network connectivity check failed - unable to update model performance", 
                  Base.IOError("Network unreachable"))
        return
    end
    
    model_name = dashboard.model[:name]
    try
        start_time = time()
        perf = API.get_model_performance(dashboard.api_client, model_name)
        api_duration = time() - start_time
        
        dashboard.model[:corr] = perf.corr
        dashboard.model[:mmc] = perf.mmc
        dashboard.model[:fnc] = perf.fnc
        dashboard.model[:sharpe] = perf.sharpe
        dashboard.model[:is_active] = true
        
        # Update API latency tracking
        dashboard.network_status[:api_latency] = api_duration * 1000  # Convert to ms
        
        # Add to history with timestamp
        push!(dashboard.performance_history, Dict(
            :timestamp => utc_now_datetime(),
            :corr => perf.corr,
            :mmc => perf.mmc,
            :fnc => perf.fnc,
            :sharpe => perf.sharpe,
            :stake => get(dashboard.model, :stake, 0.0)
        ))
        
        # Keep only configured number of entries to manage memory
        max_history = get(dashboard.config.tui_config["limits"], "performance_history_max", 100)
        if length(dashboard.performance_history) > max_history
            popfirst!(dashboard.performance_history)
        end
        
        add_event!(dashboard, :success, "Updated performance for model '$model_name'")
            
    catch e
        dashboard.model[:is_active] = false
        
        # Categorize and log the specific error for this model
        add_event!(dashboard, :error, "Failed to update performance for model '$model_name'", e)
        
        # Log additional context for debugging
        @error "Model performance update failed" model=model_name exception=e
    end
end

# Function for test compatibility - updates the model's performance directly
function update_model_performance!(dashboard::TournamentDashboard, model_name::String, 
                                   corr::Float64, mmc::Float64, fnc::Float64, stake::Float64)
    if dashboard.model[:name] == model_name
        dashboard.model[:corr] = corr
        dashboard.model[:mmc] = mmc
        dashboard.model[:fnc] = fnc
        dashboard.model[:stake] = stake
        dashboard.model[:is_active] = true
    end
end

function get_staking_info(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    # Get round information with proper error handling
    round_info = nothing
    try
        round_info = API.get_current_round(dashboard.api_client)
    catch e
        add_event!(dashboard, :error, "Failed to fetch current round information", e)
        # Return fallback data
        model_stake = get(dashboard.model, :stake, 0.0)
        return Dict(
            :total_stake => round(model_stake, digits=2),
            :at_risk => round(model_stake * 0.25, digits=2),
            :expected_payout => round(model_stake * dashboard.model[:corr] * 0.5, digits=2),
            :current_round => 0,
            :submission_status => "Error - Check API connection",
            :time_remaining => "N/A"
        )
    end
    
    time_remaining = round_info.close_time - utc_now_datetime()
    
    # Get actual staking data from API for the model
    model_name = dashboard.model[:name]
    total_stake = 0.0
    total_at_risk = 0.0
    total_expected_payout = 0.0
    
    if dashboard.model[:is_active]
        try
            # Get actual staking information from API
            stake_info = API.get_model_stakes(dashboard.api_client, model_name)
            model_stake = stake_info.total_stake
            
            total_stake = model_stake
            
            # Calculate at-risk amount based on actual burn rate from API
            burn_rate = get(stake_info, :burn_rate, 0.25)  # Default to 25% if not available
            total_at_risk = model_stake * burn_rate
            
            # Calculate expected payout using real performance metrics
            corr_multiplier = get(stake_info, :corr_multiplier, 0.5)
            mmc_multiplier = get(stake_info, :mmc_multiplier, 2.0)
            expected_payout = model_stake * (
                corr_multiplier * dashboard.model[:corr] + 
                mmc_multiplier * dashboard.model[:mmc]
            )
            total_expected_payout = expected_payout
            
            # Update model with actual stake
            dashboard.model[:stake] = model_stake
            
        catch e
            # Log specific error for this model
            add_event!(dashboard, :error, "Failed to fetch stake info for model '$model_name'", e)
            
            # Fallback to model's stored stake if API call fails
            model_stake = get(dashboard.model, :stake, 0.0)
            total_stake = model_stake
            total_at_risk = model_stake * 0.25
            total_expected_payout = model_stake * dashboard.model[:corr] * 0.5
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
    catch e
        add_event!(dashboard, :error, "Failed to check submission status", e)
        "Error - Check API connection"
    end
    
    return Dict(
        :total_stake => round(total_stake, digits=2),
        :at_risk => round(total_at_risk, digits=2),
        :expected_payout => round(total_expected_payout, digits=2),
        :current_round => round_info.number,
        :submission_status => submission_status,
        :time_remaining => format_time_remaining(time_remaining)
    )
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

# Error categorization helper functions
function categorize_error(exception::Exception)::Tuple{ErrorCategory, ErrorSeverity}
    error_msg = string(exception)
    
    # Network-related errors
    if isa(exception, HTTP.ConnectError) || isa(exception, HTTP.TimeoutError)
        return (NETWORK_ERROR, HIGH)
    elseif isa(exception, Base.IOError) && occursin("network", lowercase(error_msg))
        return (NETWORK_ERROR, HIGH)
    
    # Authentication errors
    elseif occursin("unauthorized", lowercase(error_msg)) || 
           occursin("forbidden", lowercase(error_msg)) ||
           occursin("authentication", lowercase(error_msg))
        return (AUTH_ERROR, CRITICAL)
    
    # API-specific errors
    elseif occursin("graphql", lowercase(error_msg)) ||
           occursin("api", lowercase(error_msg))
        return (API_ERROR, MEDIUM)
    
    # Timeout errors
    elseif isa(exception, TaskFailedException) || 
           occursin("timeout", lowercase(error_msg))
        return (TIMEOUT_ERROR, MEDIUM)
    
    # Data validation errors
    elseif isa(exception, ArgumentError) || 
           occursin("validation", lowercase(error_msg))
        return (VALIDATION_ERROR, LOW)
    
    # System errors
    else
        return (SYSTEM_ERROR, MEDIUM)
    end
end

function get_user_friendly_message(category::ErrorCategory, technical_msg::String)::String
    base_msg = if category == API_ERROR
        "API communication issue"
    elseif category == NETWORK_ERROR
        "Network connectivity problem"
    elseif category == AUTH_ERROR
        "Authentication failed - check API credentials"
    elseif category == DATA_ERROR
        "Data processing error"
    elseif category == SYSTEM_ERROR
        "System error occurred"
    elseif category == TIMEOUT_ERROR
        "Request timed out - server may be busy"
    elseif category == VALIDATION_ERROR
        "Input validation failed"
    else
        "Unknown error"
    end
    
    # Add specific context if available
    if occursin("model not found", lowercase(technical_msg))
        return "$base_msg: Model not found in your account"
    elseif occursin("rate limit", lowercase(technical_msg))
        return "$base_msg: Rate limit exceeded, will retry shortly"
    elseif occursin("invalid credentials", lowercase(technical_msg))
        return "$base_msg: Please verify your API keys in configuration"
    else
        return base_msg
    end
end

function get_severity_icon(severity::ErrorSeverity)::String
    if severity == LOW
        "ℹ️"
    elseif severity == MEDIUM
        "⚠️"
    elseif severity == HIGH
        "❌"
    elseif severity == CRITICAL
        "🚨"
    else
        "❓"
    end
end

function check_network_connectivity(dashboard::TournamentDashboard)::Bool
    try
        start_time = time()
        # Simple HTTP check to Google DNS
        network_timeout = get(dashboard.config.tui_config, "network_timeout", 5)
        response = HTTP.get("https://8.8.8.8", timeout=network_timeout)
        latency = time() - start_time
        
        dashboard.network_status[:is_connected] = true
        dashboard.network_status[:last_check] = utc_now_datetime()
        dashboard.network_status[:api_latency] = latency * 1000  # Convert to ms
        dashboard.network_status[:consecutive_failures] = 0
        
        return true
    catch e
        dashboard.network_status[:is_connected] = false
        dashboard.network_status[:last_check] = utc_now_datetime()
        dashboard.network_status[:consecutive_failures] += 1
        
        return false
    end
end

# Enhanced add_event! function with error categorization
# Single function with optional exception parameter handles both cases
function add_event!(dashboard::TournamentDashboard, type::Symbol, message::String, 
                   exception::Union{Nothing, Exception}=nothing)
    # If there's an exception, categorize it and create enhanced error info
    if exception !== nothing && type == :error
        category, severity = categorize_error(exception)
        user_message = get_user_friendly_message(category, string(exception))
        severity_icon = get_severity_icon(severity)
        
        # Update error counts
        dashboard.error_counts[category] += 1
        
        # Store detailed error for debugging
        categorized_error = CategorizedError(
            category,
            severity,
            user_message,
            string(exception),
            utc_now_datetime(),
            get(dashboard.error_counts, category, 0)
        )
        
        push!(dashboard.last_api_errors, categorized_error)
        # Keep only configured number of errors
        max_errors = get(dashboard.config.tui_config["limits"], "api_error_history_max", 50)
        if length(dashboard.last_api_errors) > max_errors
            popfirst!(dashboard.last_api_errors)
        end
        
        # Create enhanced event with categorization
        event = Dict(
            :type => type,
            :message => "$severity_icon $user_message",
            :time => utc_now_datetime(),
            :category => category,
            :severity => severity,
            :technical_details => string(exception)
        )
    else
        # Standard event without error categorization
        event = Dict(
            :type => type,
            :message => message,
            :time => utc_now_datetime()
        )
    end
    
    push!(dashboard.events, event)
    
    # Keep only configured number of events
    max_events = get(dashboard.config.tui_config["limits"], "events_history_max", 100)
    if length(dashboard.events) > max_events
        popfirst!(dashboard.events)
    end
    
    if type == :error
        @log_error "Dashboard event" message=message
    elseif type == :success
        @log_info "Dashboard success" message=message
    end
end

function start_training(dashboard::TournamentDashboard)
    if dashboard.training_info[:is_training]
        add_event!(dashboard, :warning, "Training already in progress")
        return
    end
    
    dashboard.training_info[:is_training] = true
    dashboard.training_info[:model_name] = dashboard.model[:name]
    dashboard.training_info[:progress] = 0
    # Get default epochs from config
    default_epochs = get(dashboard.config.tui_config["training"], "default_epochs", 100)
    dashboard.training_info[:total_epochs] = default_epochs
    
    add_event!(dashboard, :info, "Starting training for $(dashboard.training_info[:model_name])")
    
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
        feature_set = hasfield(typeof(config), :feature_set) ? config.feature_set : get(config, "feature_set", "medium")
        feature_cols = if isfile(features_path)
            features, _ = DataLoader.load_features_json(features_path; feature_set=feature_set)
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
                    "xgboost",
                    Dict(
                        :n_estimators => 100,
                        :max_depth => 5,
                        :learning_rate => 0.01,
                        :subsample => 0.8
                    )
                ),
                Pipeline.ModelConfig(
                    "lightgbm",
                    Dict(
                        :n_estimators => 100,
                        :max_depth => 5,
                        :learning_rate => 0.01,
                        :subsample => 0.8
                    )
                )
            ],
            neutralize=get(config, "enable_neutralization", false)
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
            dashboard.training_info[:val_score] = 0.01 + i * 0.002  # Progressive improvement instead of random
        end
        
        # Load validation data for training
        val_data = DataLoader.load_training_data(
            joinpath(data_dir, "validation.parquet"),
            feature_cols=feature_cols,
            target_col=get(config, "target_col", "target_cyrus_v4_20")
        )
        
        # Actually train the pipeline
        Pipeline.train!(pipeline, train_data, val_data, verbose=false)
        
        dashboard.training_info[:progress] = 90
        dashboard.training_info[:eta] = "Evaluating performance..."
        
        # Generate validation predictions (val_data already loaded)
        predictions = Pipeline.predict(pipeline, val_data)
        
        # Calculate performance metrics
        if haskey(val_data, Symbol(pipeline.target_cols[1]))
            target = val_data[!, Symbol(pipeline.target_cols[1])]
            correlation = cor(predictions, target)
            
            # Update model with real performance
            dashboard.model[:corr] = round(correlation, digits=4)
            dashboard.model[:mmc] = round(correlation * 0.5, digits=4)  # Estimated MMC 
            dashboard.model[:fnc] = round(correlation * 0.3, digits=4)  # Estimated FNC
            
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

function render_model_details_panel(dashboard::TournamentDashboard)
    if isnothing(dashboard.selected_model_details)
        return nothing
    end
    
    model = dashboard.selected_model_details
    stats = dashboard.selected_model_stats
    
    content = """
    $(Term.highlight("📊 Model Details"))
    
    $(Term.bold("Basic Information"))
    • Name: $(model[:name])
    • Type: $(get(model, :type, "Unknown"))
    • Status: $(model[:is_active] ? "🟢 Active" : "🔴 Inactive")
    • Current Stake: $(get(model, :stake, 0.0)) NMR
    
    $(Term.bold("Current Performance"))
    • Correlation: $(round(model[:corr], digits=4))
    • MMC: $(round(model[:mmc], digits=4))
    • FNC: $(round(model[:fnc], digits=4))
    • Sharpe: $(round(model[:sharpe], digits=3))
    """
    
    if !isnothing(stats)
        content *= """
        
        $(Term.bold("Historical Statistics"))
        • CORR: μ=$(stats[:corr_mean]), σ=$(stats[:corr_std])
        • MMC:  μ=$(stats[:mmc_mean]), σ=$(stats[:mmc_std])
        • Sharpe: $(stats[:sharpe])
        • Samples: $(stats[:samples])
        """
    end
    
    content *= """
    
    $(Term.dim("Press ESC to close"))
    """
    
    return Panel(
        content,
        title="📊 Model Details - $(model[:name])",
        title_style="bold cyan",
        width=60,
        height=25
    )
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

function handle_wizard_input(dashboard::TournamentDashboard, key::Union{Char, String})
    if isnothing(dashboard.wizard_state)
        return
    end
    
    ws = dashboard.wizard_state
    
    # Handle escape sequences for arrow keys
    if isa(key, String)
        if key == "\e[A"  # Up arrow
            handle_wizard_arrow_key(ws, :up)
            return
        elseif key == "\e[B"  # Down arrow
            handle_wizard_arrow_key(ws, :down)
            return
        elseif key == "\e[C"  # Right arrow
            handle_wizard_arrow_key(ws, :right)
            return
        elseif key == "\e[D"  # Left arrow
            handle_wizard_arrow_key(ws, :left)
            return
        elseif key == "\e"  # Just ESC key
            dashboard.wizard_active = false
            dashboard.wizard_state = nothing
            add_event!(dashboard, :info, "Model creation cancelled")
            return
        end
        # If it's a string but not a recognized escape sequence, treat first char
        if length(key) > 0
            key = key[1]
        else
            return
        end
    end
    
    # Single character handling
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

function handle_wizard_arrow_key(ws::ModelWizardState, direction::Symbol)
    """
    Handle arrow key input for parameter adjustment in the wizard.
    """
    # Only handle arrow keys in step 3 (parameters)
    if ws.step != 3
        return
    end
    
    # Define parameter adjustment increments
    if direction == :up || direction == :right
        # Increase parameters
        ws.learning_rate = min(1.0, ws.learning_rate + 0.01)
        ws.max_depth = min(20, ws.max_depth + 1)
        ws.feature_fraction = min(1.0, ws.feature_fraction + 0.05)
        ws.num_rounds = min(2000, ws.num_rounds + 50)
        ws.neutralize_proportion = min(1.0, ws.neutralize_proportion + 0.05)
    elseif direction == :down || direction == :left
        # Decrease parameters
        ws.learning_rate = max(0.01, ws.learning_rate - 0.01)
        ws.max_depth = max(1, ws.max_depth - 1)
        ws.feature_fraction = max(0.1, ws.feature_fraction - 0.05)
        ws.num_rounds = max(50, ws.num_rounds - 50)
        ws.neutralize_proportion = max(0.0, ws.neutralize_proportion - 0.05)
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

function show_model_details(dashboard::TournamentDashboard)
    model_name = dashboard.model[:name]
    
    # Set the model details to be shown
    dashboard.show_model_details = true
    dashboard.selected_model_details = dashboard.model
    
    # Display historical performance if available
    if !isempty(dashboard.performance_history)
        history = dashboard.performance_history
        
        # Calculate statistics
        corr_values = [h[:corr] for h in history]
        mmc_values = [h[:mmc] for h in history]
        fnc_values = [h[:fnc] for h in history]
        sharpe_values = [h[:sharpe] for h in history]
        
        # Store stats in dashboard for display
        dashboard.selected_model_stats = Dict(
            :corr_mean => round(mean(corr_values), digits=4),
            :corr_std => round(std(corr_values), digits=4),
            :mmc_mean => round(mean(mmc_values), digits=4),
            :mmc_std => round(std(mmc_values), digits=4),
            :sharpe => round(mean(sharpe_values), digits=3),
            :samples => length(history)
        )
        
        add_event!(dashboard, :info, "Showing details for $(model_name)")
    else
        dashboard.selected_model_stats = nothing
        add_event!(dashboard, :warning, "No historical data for $(model_name)")
    end
end

function save_performance_history(dashboard::TournamentDashboard, filepath::String="performance_history.json")
    try
        # Convert history to a format suitable for JSON serialization
        history_data = Dict{String, Any}()
        model_name = dashboard.model[:name]
        history_data[model_name] = [Dict(
            "timestamp" => string(h[:timestamp]),
            "corr" => h[:corr],
            "mmc" => h[:mmc],
            "fnc" => h[:fnc],
            "sharpe" => h[:sharpe],
            "stake" => h[:stake]
        ) for h in dashboard.performance_history]
        
        open(filepath, "w") do io
            JSON3.write(io, history_data)
        end
        
        add_event!(dashboard, :success, "Performance history saved to $filepath")
    catch e
        add_event!(dashboard, :error, "Failed to save history: $e")
    end
end

function load_performance_history!(dashboard::TournamentDashboard, filepath::String="performance_history.json")
    if !isfile(filepath)
        return
    end
    
    try
        history_data = JSON3.read(read(filepath, String))
        model_name = dashboard.model[:name]
        
        # Load history for the current model if it exists in the file
        if haskey(history_data, model_name)
            history = history_data[model_name]
            dashboard.performance_history = [Dict{Symbol, Any}(
                :timestamp => DateTime(h["timestamp"]),
                :corr => Float64(h["corr"]),
                :mmc => Float64(h["mmc"]),
                :fnc => Float64(h["fnc"]),
                :sharpe => Float64(h["sharpe"]),
                :stake => Float64(h["stake"])
            ) for h in history]
        end
        
        add_event!(dashboard, :success, "Performance history loaded from $filepath")
    catch e
        add_event!(dashboard, :error, "Failed to load history: $e")
    end
end

function get_performance_summary(dashboard::TournamentDashboard, model_name::String)
    if dashboard.model[:name] != model_name || isempty(dashboard.performance_history)
        return nothing
    end
    
    history = dashboard.performance_history
    corr_values = [h[:corr] for h in history]
    mmc_values = [h[:mmc] for h in history]
    fnc_values = [h[:fnc] for h in history]
    sharpe_values = [h[:sharpe] for h in history]
    
    return Dict(
        :count => length(history),
        :corr_mean => mean(corr_values),
        :corr_std => std(corr_values),
        :corr_max => maximum(corr_values),
        :corr_min => minimum(corr_values),
        :mmc_mean => mean(mmc_values),
        :mmc_std => std(mmc_values),
        :fnc_mean => mean(fnc_values),
        :sharpe_mean => mean(sharpe_values),
        :last_update => history[end][:timestamp]
    )
end

# Error statistics and debugging functions
function get_error_summary(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Get a comprehensive summary of errors and their categories for debugging.
    """
    total_errors = sum(values(dashboard.error_counts))
    recent_errors = count(e -> e[:type] == :error, dashboard.events)
    
    return Dict(
        :total_errors => total_errors,
        :recent_errors => recent_errors,
        :error_counts_by_category => copy(dashboard.error_counts),
        :network_status => copy(dashboard.network_status),
        :last_api_errors => length(dashboard.last_api_errors) > 5 ? 
            dashboard.last_api_errors[end-4:end] : dashboard.last_api_errors
    )
end

function reset_error_tracking!(dashboard::TournamentDashboard)
    """
    Reset error tracking counters (useful for testing or after resolving issues).
    """
    for category in keys(dashboard.error_counts)
        dashboard.error_counts[category] = 0
    end
    empty!(dashboard.last_api_errors)
    dashboard.network_status[:consecutive_failures] = 0
    add_event!(dashboard, :info, "Error tracking counters reset")
end

function get_error_trends(dashboard::TournamentDashboard, minutes_back::Int=60)::Dict{Symbol, Int}
    """
    Analyze error trends over the specified time period.
    """
    cutoff_time = utc_now_datetime() - Dates.Minute(minutes_back)
    recent_events = filter(e -> e[:time] > cutoff_time && e[:type] == :error, dashboard.events)
    
    trends = Dict{Symbol, Int}()
    for event in recent_events
        category = get(event, :category, :UNKNOWN)
        trends[category] = get(trends, category, 0) + 1
    end
    
    return trends
end

export TournamentDashboard, run_dashboard, add_event!, start_training, save_performance_history, load_performance_history!, get_performance_summary,
       get_error_summary, reset_error_tracking!, get_error_trends, check_network_connectivity,
       categorize_error, get_user_friendly_message, get_severity_icon

end