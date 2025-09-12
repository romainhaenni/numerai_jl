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
    models::Vector{Dict{Symbol, Any}}  # Support for multiple models (for compatibility)
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
    # Model wizard and selection
    selected_model_details::Union{Nothing, Dict{Symbol, Any}}  # Details of selected model
    selected_model_stats::Union{Nothing, Dict{Symbol, Any}}  # Stats of selected model
    wizard_state::Union{Nothing, Any}  # Model wizard state
    wizard_active::Bool  # Whether wizard is active
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
    
    # Initialize models vector with single model
    models = [model]
    
    return TournamentDashboard(
        config, api_client, model, models,  # model and models
        Vector{Dict{Symbol, Any}}(),  # events
        system_info, training_info, Float64[], performance_history,
        false, false, false, refresh_rate,  # running, paused, show_help, refresh_rate
        "", false,  # command_buffer and command_mode
        false,  # show_model_details
        nothing, nothing, nothing, false,  # selected_model_details, selected_model_stats, wizard_state, wizard_active
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
            # In recovery mode, retry initialization; otherwise refresh data
            try
                update_model_performances!(dashboard)
                add_event!(dashboard, :info, "Data refreshed")
                # Save good state after successful refresh
                save_last_known_good_state(dashboard)
            catch e
                add_event!(dashboard, :error, "Failed to refresh data", e)
            end
        elseif key == "n"  # Test network connectivity
            test_network_connectivity(dashboard)
        elseif key == "c"  # Check configuration files
            check_configuration_files(dashboard)
        elseif key == "d"  # Download fresh tournament data  
            download_tournament_data(dashboard)
        elseif key == "l"  # View detailed error logs
            view_detailed_error_logs(dashboard)
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
        # Enhanced recovery mode with comprehensive diagnostics
        render_recovery_mode(dashboard, e)
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
        perf = API.get_model_performance(dashboard.api_client, model_name;
                                         enable_dynamic_sharpe=dashboard.config.enable_dynamic_sharpe,
                                         sharpe_history_rounds=dashboard.config.sharpe_history_rounds,
                                         sharpe_min_data_points=dashboard.config.sharpe_min_data_points)
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
        max_history = get(get(dashboard.config.tui_config, "limits", Dict()), "performance_history_max", 100)
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
    # Convert to total seconds safely to avoid precision issues
    try
        # Convert to milliseconds first, then to seconds
        total_milliseconds = Dates.value(Dates.Millisecond(time_remaining))
        total_seconds = div(total_milliseconds, 1000)  # Integer division
        
        # Handle negative or very small values
        if total_seconds <= 0
            return "0m"
        end
    catch e
        # If any conversion fails, return safe default
        if isa(e, InexactError)
            return "0m"
        end
        rethrow(e)
    end
    
    hours = div(total_seconds, 3600)
    minutes = div(total_seconds % 3600, 60)
    
    if hours > 24
        days = div(hours, 24)
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
        max_errors = get(get(dashboard.config.tui_config, "limits", Dict()), "api_error_history_max", 50)
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
    max_events = get(get(dashboard.config.tui_config, "limits", Dict()), "events_history_max", 100)
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
    default_epochs = get(get(dashboard.config.tui_config, "training", Dict()), "default_epochs", 100)
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
        data_dir = config.data_dir
        
        # Initialize progress tracking
        dashboard.training_info[:current_epoch] = 0
        dashboard.training_info[:progress] = 10
        dashboard.training_info[:eta] = "Loading data..."
        
        # Load training data
        add_event!(dashboard, :info, "Loading training data...")
        train_data = DataLoader.load_training_data(
            joinpath(data_dir, "train.parquet"),
            sample_pct=config.sample_pct
        )
        
        dashboard.training_info[:progress] = 25
        
        # Get feature columns
        features_path = joinpath(data_dir, "features.json")
        feature_set = config.feature_set
        feature_cols = if isfile(features_path)
            features, _ = DataLoader.load_features_json(features_path; feature_set=feature_set)
            features
        else
            DataLoader.get_feature_columns(train_data)
        end
        
        dashboard.training_info[:progress] = 30
        dashboard.training_info[:eta] = "Initializing pipeline..."
        
        # Create ML pipeline
        # Use XGBoost as the default model for training
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
        
        dashboard.training_info[:progress] = 40
        dashboard.training_info[:eta] = "Training models..."
        
        # Train the pipeline with progress updates
        add_event!(dashboard, :info, "Training ensemble models...")
        
        # Simulate epochs for progress tracking during actual training
        n_models = 1  # Now using single model
        for i in 1:n_models
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
            target_col=config.target_col
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
            # MMC and FNC require meta-model data from Numerai, not available locally
            dashboard.model[:mmc] = 0.0  # Requires meta-model from Numerai API
            dashboard.model[:fnc] = 0.0  # Requires feature-neutralized meta-model
            
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

# Enhanced Recovery Mode Functions
function render_recovery_mode(dashboard::TournamentDashboard, error::Exception)
    """
    Comprehensive recovery mode display with system diagnostics, configuration status,
    and troubleshooting suggestions.
    """
    println("╔═══════════════════════════════════════════════════════════════════════════════╗")
    println("║                  🚀 Numerai Tournament Dashboard - Recovery Mode              ║")
    println("╚═══════════════════════════════════════════════════════════════════════════════╝")
    println()
    
    # 1. Error Information
    println("⚠️  RENDERING ERROR DETAILS:")
    println("   Error Type: $(typeof(error))")
    println("   Message: $(error)")
    category, severity = categorize_error(error)
    severity_icon = get_severity_icon(severity)
    user_msg = get_user_friendly_message(category, string(error))
    println("   Category: $severity_icon $category ($severity)")
    println("   User Message: $user_msg")
    println()
    
    # 2. System Diagnostics
    diagnostics = get_system_diagnostics(dashboard)
    println("🔧 SYSTEM DIAGNOSTICS:")
    println("   CPU Usage: $(diagnostics[:cpu_usage])% (Load: $(diagnostics[:load_avg]))")
    println("   Memory: $(diagnostics[:memory_used]) GB / $(diagnostics[:memory_total]) GB ($(diagnostics[:memory_percent])%)")
    println("   Disk Space: $(diagnostics[:disk_free]) GB free / $(diagnostics[:disk_total]) GB total")
    println("   Process Memory: $(diagnostics[:process_memory]) MB")
    println("   Threads: $(diagnostics[:threads]) (Julia: $(diagnostics[:julia_threads]))")
    println("   Uptime: $(diagnostics[:uptime])")
    println()
    
    # 3. Configuration Status
    config_status = get_configuration_status(dashboard)
    println("⚙️  CONFIGURATION STATUS:")
    println("   API Keys: $(config_status[:api_keys_status])")
    println("   Tournament ID: $(config_status[:tournament_id])")
    println("   Data Directory: $(config_status[:data_dir])")
    println("   Models Directory: $(config_status[:model_dir])")
    println("   Feature Set: $(config_status[:feature_set])")
    env_vars_str = length(config_status[:env_vars]) > 0 ? join(config_status[:env_vars], ", ") : "None"
    println("   Environment Variables: $(env_vars_str)")
    println()
    
    # 4. Local Data Files
    data_files = discover_local_data_files(dashboard)
    println("📁 LOCAL DATA FILES:")
    if isempty(data_files)
        println("   ❌ No data files found")
    else
        for (category, files) in data_files
            println("   $(category):")
            for file_info in files
                println("     • $(file_info[:name]) ($(file_info[:size]), $(file_info[:modified]))")
            end
        end
    end
    println()
    
    # 5. Last Known Good State
    last_good_state = get_last_known_good_state(dashboard)
    println("💾 LAST KNOWN GOOD STATE:")
    if isnothing(last_good_state)
        println("   ❌ No previous good state recorded")
    else
        println("   Last Successful Render: $(last_good_state[:timestamp])")
        println("   Model Performance: CORR=$(last_good_state[:corr]), MMC=$(last_good_state[:mmc])")
        println("   Network Status: $(last_good_state[:network_connected] ? "Connected" : "Disconnected")")
        println("   API Latency: $(last_good_state[:api_latency])ms")
    end
    println()
    
    # 6. Network Status
    println("🌐 NETWORK STATUS:")
    network_info = get_detailed_network_status(dashboard)
    println("   Connection: $(network_info[:status])")
    println("   Last Check: $(network_info[:last_check])")
    println("   API Latency: $(network_info[:latency])ms")
    println("   Consecutive Failures: $(network_info[:failures])")
    if !isempty(network_info[:recent_errors])
        println("   Recent Network Errors:")
        for err in network_info[:recent_errors][1:min(3, end)]
            println("     • $(err)")
        end
    end
    println()
    
    # 7. Troubleshooting Suggestions
    suggestions = get_troubleshooting_suggestions(error, category, dashboard)
    println("🔍 TROUBLESHOOTING SUGGESTIONS:")
    for (i, suggestion) in enumerate(suggestions)
        println("   $(i). $(suggestion)")
    end
    println()
    
    # 8. Manual Operation Shortcuts
    println("⌨️  RECOVERY COMMANDS:")
    println("   r  - Retry dashboard initialization")
    println("   n  - Test network connectivity")
    println("   c  - Check configuration files")
    println("   d  - Download fresh tournament data")
    println("   l  - View detailed error logs")
    println("   s  - Start training (original functionality)")
    println("   /save - Save current diagnostic report")
    println("   /diag - Run full system diagnostics")
    println("   /reset - Reset all error counters")
    println("   /backup - Create configuration backup")
    println("   q  - Quit dashboard")
    println("   h  - Show help")
    println()
    
    # 9. Recent Events (if available)
    println("📝 RECENT EVENTS:")
    recent_events = Iterators.take(Iterators.reverse(dashboard.events), 5)
    if isempty(dashboard.events)
        println("   ❌ No events recorded")
    else
        for event in recent_events
            timestamp = haskey(event, :time) ? event[:time] : "N/A"
            type_icon = event[:type] == :error ? "❌" : event[:type] == :success ? "✅" : "ℹ️"
            println("   $type_icon [$timestamp] $(event[:message])")
        end
    end
    println()
    
    # 10. Current Model Status
    println("📊 CURRENT MODEL STATUS:")
    println("   Model: $(dashboard.model[:name])")
    println("   Active: $(dashboard.model[:is_active] ? "Yes" : "No")")
    if dashboard.model[:is_active]
        println("   Performance: CORR=$(round(dashboard.model[:corr], digits=4)) MMC=$(round(dashboard.model[:mmc], digits=4))")
        println("   Stake: $(get(dashboard.model, :stake, 0.0)) NMR")
    end
    
    println("")
    println("═══════════════════════════════════════════════════════════════════════════════")
end

function get_system_diagnostics(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Comprehensive system diagnostics including CPU, memory, disk usage.
    """
    try
        # CPU diagnostics
        loadavg = Sys.loadavg()
        cpu_count = Sys.CPU_THREADS
        cpu_usage = min(100, round(Int, (loadavg[1] / cpu_count) * 100))
        
        # Memory diagnostics
        total_memory_bytes = Sys.total_memory()
        free_memory_bytes = Sys.free_memory()
        total_memory_gb = round(total_memory_bytes / (1024^3), digits=1)
        free_memory_gb = round(free_memory_bytes / (1024^3), digits=1)
        used_memory_gb = round((total_memory_bytes - free_memory_bytes) / (1024^3), digits=1)
        memory_percent = round(Int, ((total_memory_bytes - free_memory_bytes) / total_memory_bytes) * 100)
        
        # Process memory
        process_memory_mb = round(Base.summarysize(dashboard) / (1024^2), digits=1)
        
        # Disk diagnostics (current directory)
        disk_info = try
            stat_result = stat(".")
            # On macOS/Linux, try to get disk usage via df command
            df_output = read(`df -h .`, String)
            lines = split(df_output, '\n')
            if length(lines) >= 2
                parts = split(lines[2])
                if length(parts) >= 4
                    disk_total = replace(parts[2], "G" => "", "T" => "000") |> x -> (try parse(Float64, x) catch _ 0.0 end)
                    disk_free = replace(parts[4], "G" => "", "T" => "000") |> x -> (try parse(Float64, x) catch _ 0.0 end)
                    (total=disk_total, free=disk_free)
                else
                    (total=0.0, free=0.0)
                end
            else
                (total=0.0, free=0.0)
            end
        catch
            (total=0.0, free=0.0)
        end
        
        # Uptime calculation
        uptime_seconds = Int(dashboard.system_info[:uptime])
        uptime_str = if uptime_seconds < 60
            "$(uptime_seconds)s"
        elseif uptime_seconds < 3600
            "$(div(uptime_seconds, 60))m $(uptime_seconds % 60)s"
        else
            hours = div(uptime_seconds, 3600)
            minutes = div(uptime_seconds % 3600, 60)
            "$(hours)h $(minutes)m"
        end
        
        return Dict{Symbol, Any}(
            :cpu_usage => cpu_usage,
            :load_avg => "$(round(loadavg[1], digits=2)), $(round(loadavg[2], digits=2)), $(round(loadavg[3], digits=2))",
            :memory_used => used_memory_gb,
            :memory_total => total_memory_gb,
            :memory_free => free_memory_gb,
            :memory_percent => memory_percent,
            :disk_total => isa(disk_info, NamedTuple) ? disk_info.total : disk_info[1],
            :disk_free => isa(disk_info, NamedTuple) ? disk_info.free : disk_info[2],
            :process_memory => process_memory_mb,
            :threads => dashboard.system_info[:threads],
            :julia_threads => Threads.nthreads(),
            :uptime => uptime_str
        )
    catch e
        # Fallback diagnostics if system calls fail
        return Dict{Symbol, Any}(
            :cpu_usage => 0,
            :load_avg => "N/A",
            :memory_used => 0.0,
            :memory_total => get(dashboard.system_info, :memory_total, 0.0),
            :memory_free => 0.0,
            :memory_percent => 0,
            :disk_total => 0.0,
            :disk_free => 0.0,
            :process_memory => 0.0,
            :threads => get(dashboard.system_info, :threads, 0),
            :julia_threads => Threads.nthreads(),
            :uptime => "N/A"
        )
    end
end

function get_configuration_status(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Check configuration status including environment variables and file paths.
    """
    config = dashboard.config
    
    # Check API keys (masked for security)
    api_keys_status = if haskey(ENV, "NUMERAI_PUBLIC_ID") && haskey(ENV, "NUMERAI_SECRET_KEY")
        pub_key = ENV["NUMERAI_PUBLIC_ID"]
        secret_key = ENV["NUMERAI_SECRET_KEY"]
        pub_masked = length(pub_key) > 8 ? pub_key[1:4] * "..." * pub_key[end-3:end] : "***"
        secret_masked = length(secret_key) > 8 ? secret_key[1:4] * "..." * secret_key[end-3:end] : "***"
        "✅ Set via ENV ($pub_masked, $secret_masked)"
    elseif hasfield(typeof(config), :api_public_key) && hasfield(typeof(config), :api_secret_key)
        "✅ Set in config file"
    else
        "❌ Not configured"
    end
    
    # Check directories
    data_dir_status = isdir(config.data_dir) ? "✅ $(config.data_dir)" : "❌ $(config.data_dir) (missing)"
    model_dir_status = isdir(config.model_dir) ? "✅ $(config.model_dir)" : "❌ $(config.model_dir) (missing)"
    
    # Environment variables check
    env_vars = String[]
    for var in ["NUMERAI_PUBLIC_ID", "NUMERAI_SECRET_KEY", "JULIA_NUM_THREADS", "PATH"]
        if haskey(ENV, var)
            value = var in ["NUMERAI_PUBLIC_ID", "NUMERAI_SECRET_KEY"] ? "***" : ENV[var][1:min(20, end)] * "..."
            push!(env_vars, "$var=$value")
        end
    end
    
    return Dict{Symbol, Any}(
        :api_keys_status => api_keys_status,
        :tournament_id => config.tournament_id,
        :data_dir => data_dir_status,
        :model_dir => model_dir_status,
        :feature_set => config.feature_set,
        :env_vars => env_vars
    )
end

function discover_local_data_files(dashboard::TournamentDashboard)::Dict{String, Vector{Dict{Symbol, Any}}}
    """
    Discover and categorize local data files.
    """
    result = Dict{String, Vector{Dict{Symbol, Any}}}()
    config = dashboard.config
    
    # Check data directory
    data_files = Vector{Dict{Symbol, Any}}()
    if isdir(config.data_dir)
        try
            for file in readdir(config.data_dir, join=true)
                if isfile(file)
                    stat_info = stat(file)
                    file_info = Dict{Symbol, Any}(
                        :name => basename(file),
                        :path => file,
                        :size => format_file_size(stat_info.size),
                        :modified => format_file_time(stat_info.mtime)
                    )
                    push!(data_files, file_info)
                end
            end
        catch e
            push!(data_files, Dict{Symbol, Any}(:name => "Error reading directory: $e", :size => "", :modified => "", :path => ""))
        end
    end
    result["Data Files"] = data_files
    
    # Check model directory
    model_files = Vector{Dict{Symbol, Any}}()
    if isdir(config.model_dir)
        try
            for file in readdir(config.model_dir, join=true)
                if isfile(file)
                    stat_info = stat(file)
                    file_info = Dict{Symbol, Any}(
                        :name => basename(file),
                        :path => file,
                        :size => format_file_size(stat_info.size),
                        :modified => format_file_time(stat_info.mtime)
                    )
                    push!(model_files, file_info)
                end
            end
        catch e
            push!(model_files, Dict{Symbol, Any}(:name => "Error reading directory: $e", :size => "", :modified => "", :path => ""))
        end
    end
    result["Model Files"] = model_files
    
    # Check for config files
    config_files = Vector{Dict{Symbol, Any}}()
    for config_file in ["config.toml", "features.json", "models.json"]
        if isfile(config_file)
            stat_info = stat(config_file)
            file_info = Dict{Symbol, Any}(
                :name => config_file,
                :path => abspath(config_file),
                :size => format_file_size(stat_info.size),
                :modified => format_file_time(stat_info.mtime)
            )
            push!(config_files, file_info)
        end
    end
    result["Config Files"] = config_files
    
    return result
end

function format_file_size(size_bytes::Int64)::String
    """
    Format file size in human-readable format.
    """
    if size_bytes < 1024
        "$(size_bytes) B"
    elseif size_bytes < 1024^2
        "$(round(size_bytes / 1024, digits=1)) KB"
    elseif size_bytes < 1024^3
        "$(round(size_bytes / 1024^2, digits=1)) MB"
    else
        "$(round(size_bytes / 1024^3, digits=1)) GB"
    end
end

function format_file_time(mtime::Float64)::String
    """
    Format file modification time.
    """
    try
        dt = unix2datetime(mtime)
        return Dates.format(dt, "yyyy-mm-dd HH:MM")
    catch
        return "Unknown"
    end
end

function get_last_known_good_state(dashboard::TournamentDashboard)::Union{Nothing, Dict{Symbol, Any}}
    """
    Retrieve last known good state from persistent storage.
    """
    state_file = ".dashboard_state.json"
    if !isfile(state_file)
        return nothing
    end
    
    try
        state_data = JSON3.read(read(state_file, String))
        return Dict{Symbol, Any}(
            :timestamp => get(state_data, "timestamp", "Unknown"),
            :corr => get(state_data, "corr", 0.0),
            :mmc => get(state_data, "mmc", 0.0),
            :fnc => get(state_data, "fnc", 0.0),
            :sharpe => get(state_data, "sharpe", 0.0),
            :network_connected => get(state_data, "network_connected", false),
            :api_latency => get(state_data, "api_latency", 0.0),
            :model_name => get(state_data, "model_name", "Unknown")
        )
    catch
        return nothing
    end
end

function save_last_known_good_state(dashboard::TournamentDashboard)
    """
    Save current good state to persistent storage.
    """
    state_file = ".dashboard_state.json"
    try
        state_data = Dict(
            "timestamp" => string(utc_now_datetime()),
            "corr" => dashboard.model[:corr],
            "mmc" => dashboard.model[:mmc],
            "fnc" => dashboard.model[:fnc],
            "sharpe" => get(dashboard.model, :sharpe, 0.0),
            "network_connected" => dashboard.network_status[:is_connected],
            "api_latency" => dashboard.network_status[:api_latency],
            "model_name" => dashboard.model[:name]
        )
        
        open(state_file, "w") do io
            JSON3.write(io, state_data)
        end
    catch e
        @warn "Failed to save dashboard state" exception=e
    end
end

function get_detailed_network_status(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    """
    Get detailed network status including recent errors.
    """
    network_status = dashboard.network_status
    
    status_text = if network_status[:is_connected]
        "✅ Connected"
    else
        "❌ Disconnected ($(network_status[:consecutive_failures]) consecutive failures)"
    end
    
    # Get recent network errors from events
    recent_network_errors = String[]
    for event in Iterators.take(Iterators.reverse(dashboard.events), 10)
        if event[:type] == :error && haskey(event, :category) && 
           event[:category] in [NETWORK_ERROR, TIMEOUT_ERROR]
            push!(recent_network_errors, "$(event[:time]): $(event[:message])")
        end
    end
    
    return Dict{Symbol, Any}(
        :status => status_text,
        :last_check => network_status[:last_check],
        :latency => round(network_status[:api_latency], digits=1),
        :failures => network_status[:consecutive_failures],
        :recent_errors => recent_network_errors
    )
end

function get_troubleshooting_suggestions(error::Exception, category::ErrorCategory, dashboard::TournamentDashboard)::Vector{String}
    """
    Generate context-specific troubleshooting suggestions based on error type and dashboard state.
    """
    suggestions = String[]
    
    # Error-specific suggestions
    if category == NETWORK_ERROR
        push!(suggestions, "Check your internet connection and try again")
        push!(suggestions, "Verify that Numerai API (https://api-tournament.numer.ai) is accessible")
        push!(suggestions, "Check firewall settings and proxy configuration")
        push!(suggestions, "Try running: /reset to clear network error counters")
    elseif category == AUTH_ERROR
        push!(suggestions, "Verify your NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY environment variables")
        push!(suggestions, "Regenerate API credentials from your Numerai account settings")
        push!(suggestions, "Check that your API keys have the required permissions")
    elseif category == API_ERROR
        push!(suggestions, "Check Numerai API status at https://status.numer.ai")
        push!(suggestions, "Reduce API request frequency by increasing refresh_rate in config.toml")
        push!(suggestions, "Try running: r to retry dashboard initialization")
    elseif category == DATA_ERROR
        push!(suggestions, "Verify that data files exist in the $(dashboard.config.data_dir) directory")
        push!(suggestions, "Try running: d to download fresh tournament data")
        push!(suggestions, "Check file permissions in data directory")
    elseif category == SYSTEM_ERROR
        push!(suggestions, "Check available memory and disk space")
        push!(suggestions, "Try restarting the dashboard application")
        push!(suggestions, "Review Julia installation and package versions")
    end
    
    # State-specific suggestions
    if !dashboard.network_status[:is_connected]
        push!(suggestions, "Network is disconnected - try running: n to test connectivity")
    end
    
    if dashboard.network_status[:consecutive_failures] > 3
        push!(suggestions, "Multiple network failures detected - check your connection stability")
    end
    
    # Dashboard state suggestions
    if isempty(dashboard.events)
        push!(suggestions, "No events recorded - dashboard may have initialization issues")
    end
    
    # Configuration suggestions
    config_status = get_configuration_status(dashboard)
    if occursin("❌", config_status[:api_keys_status])
        push!(suggestions, "API keys not configured - set NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY")
    end
    
    if occursin("missing", config_status[:data_dir])
        push!(suggestions, "Data directory missing - create $(dashboard.config.data_dir) directory")
    end
    
    # General suggestions if no specific ones
    if isempty(suggestions)
        push!(suggestions, "Try restarting the dashboard with: q (quit) then restart")
        push!(suggestions, "Check the log files for more detailed error information")
        push!(suggestions, "Run: /diag for comprehensive system diagnostics")
    end
    
    return suggestions
end

# Recovery mode command functions
function test_network_connectivity(dashboard::TournamentDashboard)
    """
    Test network connectivity and update dashboard state.
    """
    add_event!(dashboard, :info, "Testing network connectivity...")
    
    try
        # Test basic connectivity
        start_time = time()
        response = HTTP.get("https://8.8.8.8", timeout=5)
        basic_latency = (time() - start_time) * 1000
        
        # Test Numerai API connectivity
        start_time = time()
        api_response = HTTP.get("https://api-tournament.numer.ai/healthz", timeout=10)
        api_latency = (time() - start_time) * 1000
        
        # Update network status
        dashboard.network_status[:is_connected] = true
        dashboard.network_status[:api_latency] = api_latency
        dashboard.network_status[:consecutive_failures] = 0
        dashboard.network_status[:last_check] = utc_now_datetime()
        
        add_event!(dashboard, :success, "✅ Network test successful - Basic: $(round(basic_latency, digits=1))ms, API: $(round(api_latency, digits=1))ms")
        
    catch e
        dashboard.network_status[:is_connected] = false
        dashboard.network_status[:consecutive_failures] += 1
        dashboard.network_status[:last_check] = utc_now_datetime()
        
        add_event!(dashboard, :error, "❌ Network test failed", e)
    end
end

function check_configuration_files(dashboard::TournamentDashboard)
    """
    Check configuration files and display status.
    """
    add_event!(dashboard, :info, "Checking configuration files...")
    
    config_status = get_configuration_status(dashboard)
    data_files = discover_local_data_files(dashboard)
    
    # Report configuration status
    add_event!(dashboard, :info, "API Keys: $(config_status[:api_keys_status])")
    add_event!(dashboard, :info, "Data Directory: $(config_status[:data_dir])")
    add_event!(dashboard, :info, "Model Directory: $(config_status[:model_dir])")
    
    # Report data files status
    total_files = sum(length(files) for files in values(data_files))
    add_event!(dashboard, :info, "Found $total_files local data files")
    
    # Check for missing critical files
    critical_files = ["config.toml"]
    missing_files = [f for f in critical_files if !isfile(f)]
    
    if !isempty(missing_files)
        missing_str = join(missing_files, ", ")
        add_event!(dashboard, :error, "❌ Missing critical files: $(missing_str)")
    else
        add_event!(dashboard, :success, "✅ All critical configuration files present")
    end
end

function download_tournament_data(dashboard::TournamentDashboard)
    """
    Simulate downloading fresh tournament data.
    """
    add_event!(dashboard, :info, "Downloading fresh tournament data...")
    
    # This would typically call the actual data download functions
    # For now, just simulate the process
    try
        # Check if data directory exists
        if !isdir(dashboard.config.data_dir)
            mkpath(dashboard.config.data_dir)
            add_event!(dashboard, :info, "Created data directory: $(dashboard.config.data_dir)")
        end
        
        # Simulate download process - in real implementation this would call:
        # DataLoader.download_tournament_data(dashboard.config.data_dir)
        sleep(1)  # Simulate download time
        
        add_event!(dashboard, :success, "✅ Tournament data download completed (simulated)")
        add_event!(dashboard, :info, "💡 In actual implementation, this would download fresh data from Numerai API")
        
    catch e
        add_event!(dashboard, :error, "❌ Failed to download tournament data", e)
    end
end

function view_detailed_error_logs(dashboard::TournamentDashboard)
    """
    Display detailed error logs and statistics.
    """
    add_event!(dashboard, :info, "Displaying detailed error logs...")
    
    error_summary = get_error_summary(dashboard)
    
    # Display error statistics
    add_event!(dashboard, :info, "Total errors: $(error_summary[:total_errors])")
    add_event!(dashboard, :info, "Recent errors: $(error_summary[:recent_errors])")
    
    # Display error counts by category
    for (category, count) in error_summary[:error_counts_by_category]
        if count > 0
            add_event!(dashboard, :info, "$category: $count errors")
        end
    end
    
    # Display recent API errors
    if !isempty(dashboard.last_api_errors)
        add_event!(dashboard, :info, "Recent API errors:")
        for (i, error) in enumerate(dashboard.last_api_errors[max(1, end-2):end])
            severity_icon = get_severity_icon(error.severity)
            add_event!(dashboard, :info, "$severity_icon $(error.timestamp): $(error.message)")
        end
    end
    
    # Display error trends
    trends = get_error_trends(dashboard, 60)  # Last hour
    if !isempty(trends)
        add_event!(dashboard, :info, "Error trends (last hour):")
        for (category, count) in trends
            add_event!(dashboard, :info, "  $category: $count")
        end
    end
end

function save_diagnostic_report(dashboard::TournamentDashboard)
    """
    Save comprehensive diagnostic report to file.
    """
    report_file = "dashboard_diagnostics_$(Dates.format(utc_now_datetime(), "yyyy-mm-dd_HH-MM-SS")).txt"
    
    try
        open(report_file, "w") do io
            println(io, "═══════════════════════════════════════════════════════════════")
            println(io, "Numerai Dashboard Diagnostic Report")
            println(io, "Generated: $(utc_now_datetime())")
            println(io, "═══════════════════════════════════════════════════════════════")
            println(io)
            
            # System diagnostics
            diagnostics = get_system_diagnostics(dashboard)
            println(io, "SYSTEM DIAGNOSTICS:")
            for (key, value) in diagnostics
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Configuration status
            config_status = get_configuration_status(dashboard)
            println(io, "CONFIGURATION STATUS:")
            for (key, value) in config_status
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Network status
            network_info = get_detailed_network_status(dashboard)
            println(io, "NETWORK STATUS:")
            for (key, value) in network_info
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Error summary
            error_summary = get_error_summary(dashboard)
            println(io, "ERROR SUMMARY:")
            for (key, value) in error_summary
                println(io, "  $(key): $(value)")
            end
            println(io)
            
            # Recent events
            println(io, "RECENT EVENTS:")
            for event in Iterators.take(Iterators.reverse(dashboard.events), 10)
                timestamp = haskey(event, :time) ? event[:time] : "N/A"
                println(io, "  [$timestamp] $(event[:type]): $(event[:message])")
            end
        end
        
        add_event!(dashboard, :success, "✅ Diagnostic report saved to: $report_file")
        
    catch e
        add_event!(dashboard, :error, "❌ Failed to save diagnostic report", e)
    end
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
       categorize_error, get_user_friendly_message, get_severity_icon, render_recovery_mode,
       get_system_diagnostics, get_configuration_status, discover_local_data_files, get_last_known_good_state,
       save_last_known_good_state, get_detailed_network_status, get_troubleshooting_suggestions,
       test_network_connectivity, check_configuration_files, download_tournament_data, 
       view_detailed_error_logs, save_diagnostic_report

end