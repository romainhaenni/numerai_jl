module Scheduler

using Dates
using TimeZones
using ..API
using ..DataLoader
using ..Pipeline
using ..Dashboard
using ..Compounding
using ..Logger: @log_info, @log_warn, @log_error

# Import UTC utility function
include("../utils.jl")

# CronExpression parser and matcher
struct CronExpression
    minute::Vector{Int}
    hour::Vector{Int}
    day::Vector{Int}
    month::Vector{Int}
    weekday::Vector{Int}
    expression::String
end

function parse_cron_field(field::AbstractString, min_val::Int, max_val::Int)
    if field == "*"
        return collect(min_val:max_val)
    elseif occursin("/", field)
        # Handle step values like */2
        parts = split(field, "/")
        if parts[1] == "*"
            step = parse(Int, parts[2])
            return collect(min_val:step:max_val)
        else
            # Handle range with step like 0-10/2
            range_parts = split(parts[1], "-")
            start_val = parse(Int, range_parts[1])
            end_val = parse(Int, range_parts[2])
            step = parse(Int, parts[2])
            return collect(start_val:step:end_val)
        end
    elseif occursin("-", field)
        # Handle ranges like 2-5
        parts = split(field, "-")
        return collect(parse(Int, parts[1]):parse(Int, parts[2]))
    elseif occursin(",", field)
        # Handle lists like 1,3,5
        return [parse(Int, x) for x in split(field, ",")]
    else
        # Single value
        return [parse(Int, field)]
    end
end

function CronExpression(expr::String)
    parts = split(expr)
    if length(parts) != 5
        error("Invalid cron expression: must have 5 fields (minute hour day month weekday)")
    end
    
    minute = parse_cron_field(parts[1], 0, 59)
    hour = parse_cron_field(parts[2], 0, 23)
    day = parse_cron_field(parts[3], 1, 31)
    month = parse_cron_field(parts[4], 1, 12)
    weekday = parse_cron_field(parts[5], 0, 6)  # 0=Sunday, 6=Saturday
    
    return CronExpression(minute, hour, day, month, weekday, expr)
end

function matches(cron::CronExpression, dt::DateTime)
    # Convert Julia's dayofweek (1=Monday, 7=Sunday) to cron format (0=Sunday, 6=Saturday)
    dow = dayofweek(dt)
    cron_dow = dow == 7 ? 0 : dow
    
    return minute(dt) in cron.minute &&
           hour(dt) in cron.hour &&
           day(dt) in cron.day &&
           month(dt) in cron.month &&
           cron_dow in cron.weekday
end

function next_run_time(cron::CronExpression, from::DateTime=utc_now_datetime())
    # Find the next time this cron expression should run using mathematical calculation
    # instead of brute force iteration
    current = ceil(from, Minute)  # Round up to next minute
    
    # Maximum search: 2 years ahead (to handle leap years and edge cases)
    max_date = current + Year(2)
    
    # Keep track of attempts to prevent infinite loops
    attempts = 0
    max_attempts = 1000  # Much smaller than 525,600
    
    while current <= max_date && attempts < max_attempts
        attempts += 1
        
        # Check year/month first for early rejection
        if !(month(current) in cron.month)
            # Jump to next valid month
            next_month = find_next_in_set(cron.month, month(current), 1, 12)
            if next_month <= month(current)
                # Wrapped to next year
                current = DateTime(year(current) + 1, next_month, 1, 0, 0)
            else
                current = DateTime(year(current), next_month, 1, 0, 0)
            end
            continue
        end
        
        # Check day of month and day of week
        valid_day = (day(current) in cron.day) && (cron_dayofweek(current) in cron.weekday)
        
        if !valid_day
            # Move to next day
            current = DateTime(year(current), month(current), day(current), 0, 0) + Day(1)
            continue
        end
        
        # Check hour
        if !(hour(current) in cron.hour)
            next_hour = find_next_in_set(cron.hour, hour(current), 0, 23)
            if next_hour <= hour(current)
                # Wrapped to next day
                current = DateTime(year(current), month(current), day(current), 0, 0) + Day(1)
            else
                current = DateTime(year(current), month(current), day(current), next_hour, 0)
            end
            continue
        end
        
        # Check minute
        if !(minute(current) in cron.minute)
            next_minute = find_next_in_set(cron.minute, minute(current), 0, 59)
            if next_minute <= minute(current)
                # Wrapped to next hour
                current = current + Hour(1)
                current = DateTime(year(current), month(current), day(current), hour(current), 0)
            else
                current = DateTime(year(current), month(current), day(current), hour(current), next_minute)
            end
            continue
        end
        
        # All components match
        return current
    end
    
    return nothing  # No match found
end

# Helper function to find next value in a collection
function find_next_in_set(valid_set::Union{Vector{Int}, Set{Int}}, current_val::Int, min_val::Int, max_val::Int)::Int
    # Find the smallest value in the set that is greater than current_val
    for val in min_val:max_val
        if val in valid_set && val > current_val
            return val
        end
    end
    # If no value found, wrap around and return the smallest value in the set
    for val in min_val:max_val
        if val in valid_set
            return val
        end
    end
    return min_val  # Fallback (shouldn't happen with valid cron expressions)
end

# Helper to convert Julia's dayofweek to cron format
function cron_dayofweek(dt::DateTime)::Int
    dow = dayofweek(dt)
    return dow == 7 ? 0 : dow  # Convert Sunday from 7 to 0
end

# CronJob structure
mutable struct CronJob
    name::String
    cron_expression::CronExpression
    task::Function
    active::Bool
    last_run::Union{Nothing, DateTime}
    next_run::Union{Nothing, DateTime}
    # Lock to prevent race conditions when updating job state
    lock::ReentrantLock
end

function CronJob(expr::String, task::Function, name::String="")
    cron_expr = CronExpression(expr)
    next_time = next_run_time(cron_expr)
    return CronJob(name, cron_expr, task, false, nothing, next_time, ReentrantLock())
end

# Main scheduler structure
mutable struct TournamentScheduler
    config::Any
    api_client::API.NumeraiClient
    pipeline::Union{Nothing, Pipeline.MLPipeline}
    cron_jobs::Vector{CronJob}
    running::Bool
    dashboard::Union{Nothing, Dashboard.TournamentDashboard}
    scheduler_task::Union{Nothing, Task}
    compounding_manager::Union{Nothing, Compounding.CompoundingManager}
end

function TournamentScheduler(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key, config.tournament_id)
    
    # Create compounding manager if enabled
    compounding_manager = if config.compounding_enabled
        compound_config = Compounding.CompoundingConfig(
            enabled = config.compounding_enabled,
            min_compound_amount = config.min_compound_amount,
            compound_percentage = config.compound_percentage,
            max_stake_amount = config.max_stake_amount,
            models = config.models
        )
        Compounding.CompoundingManager(api_client, compound_config)
    else
        nothing
    end
    
    return TournamentScheduler(
        config,
        api_client,
        nothing,
        CronJob[],
        false,
        nothing,
        nothing,
        compounding_manager
    )
end

function start_scheduler(scheduler::TournamentScheduler; with_dashboard::Bool=false)
    scheduler.running = true
    
    if with_dashboard
        scheduler.dashboard = Dashboard.TournamentDashboard(scheduler.config)
    end
    
    setup_cron_jobs!(scheduler)
    
    println("🚀 Numerai Tournament Scheduler Started (Cron-based)")
    println("Configured for $(length(scheduler.config.models)) models")
    println("Auto-submit: $(scheduler.config.auto_submit)")
    println("Active cron jobs: $(length(scheduler.cron_jobs))")
    
    # Display job schedules
    for job in scheduler.cron_jobs
        println("  - $(job.name): $(job.cron_expression.expression)")
        next_time = job.next_run
        if next_time !== nothing
            println("    Next run: $(Dates.format(next_time, "yyyy-mm-dd HH:MM:SS"))")
        end
    end
    
    # Start the scheduler task
    scheduler.scheduler_task = @async run_scheduler_loop(scheduler)
    
    if with_dashboard
        Dashboard.run_dashboard(scheduler.dashboard)
    else
        while scheduler.running
            sleep(60)
        end
    end
end

function run_scheduler_loop(scheduler::TournamentScheduler)
    while scheduler.running
        current_time = utc_now_datetime()
        current_minute = floor(current_time, Minute)
        
        for job in scheduler.cron_jobs
            if !job.active
                continue
            end
            
            # Check if this job should run at this minute
            if matches(job.cron_expression, current_minute)
                # Use synchronized access to check and update job state
                should_run = lock(job.lock) do
                    # Check if we haven't already run it this minute
                    if job.last_run === nothing || job.last_run < current_minute
                        # Mark that we're about to run this job to prevent duplicate execution
                        job.last_run = current_minute
                        true
                    else
                        false
                    end
                end
                
                if should_run
                    # Run the job asynchronously
                    @async begin
                        try
                            log_event(scheduler, :info, "Running cron job: $(job.name)")
                            job.task()
                            # Update next_run time after successful execution
                            lock(job.lock) do
                                job.next_run = next_run_time(job.cron_expression, current_minute + Minute(1))
                            end
                        catch e
                            log_event(scheduler, :error, "Cron job $(job.name) failed: $e")
                            # On failure, reset last_run to allow retry on next cycle
                            lock(job.lock) do
                                job.last_run = nothing
                                job.next_run = next_run_time(job.cron_expression, current_minute + Minute(1))
                            end
                        end
                    end
                end
            end
        end
        
        # Sleep until the next minute
        next_minute = current_minute + Minute(1)
        sleep_duration = (next_minute - utc_now_datetime()).value / 1000  # Convert to seconds
        if sleep_duration > 0
            sleep(sleep_duration)
        end
    end
end

function setup_cron_jobs!(scheduler::TournamentScheduler)
    # Weekend round job - every Saturday at 18:00
    push!(scheduler.cron_jobs, CronJob(
        "0 18 * * 6",  # At 18:00 on Saturday
        () -> weekend_round_job(scheduler),
        "Weekend Round Processing"
    ))
    
    # Check and submit - every 2 hours on weekends
    push!(scheduler.cron_jobs, CronJob(
        "0 */2 * * 0,6",  # Every 2 hours on Saturday and Sunday
        () -> check_and_submit(scheduler),
        "Weekend Check and Submit"
    ))
    
    # Daily round job - weekdays at 18:00
    push!(scheduler.cron_jobs, CronJob(
        "0 18 * * 2-6",  # At 18:00 on Tuesday through Saturday (UTC)
        () -> daily_round_job(scheduler),
        "Daily Round Processing"
    ))
    
    # Weekly update - every Monday at 12:00
    push!(scheduler.cron_jobs, CronJob(
        "0 12 * * 1",  # At 12:00 on Monday
        () -> weekly_update_job(scheduler),
        "Weekly Model Update"
    ))
    
    # Hourly monitoring
    push!(scheduler.cron_jobs, CronJob(
        "0 * * * *",  # At the start of every hour
        () -> hourly_monitoring(scheduler),
        "Hourly Performance Monitoring"
    ))
    
    # Compounding job - every Wednesday at 14:30 UTC (after payouts)
    if !isnothing(scheduler.compounding_manager) && scheduler.config.compounding_enabled
        push!(scheduler.cron_jobs, CronJob(
            "30 14 * * 3",  # At 14:30 on Wednesday
            () -> compounding_job(scheduler),
            "Automatic Earnings Compounding"
        ))
    end
    
    # Activate all jobs
    for job in scheduler.cron_jobs
        job.active = true
    end
    
    log_event(scheduler, :info, "Cron jobs configured: $(length(scheduler.cron_jobs)) jobs active")
end

# Helper function for testing
function is_weekend()
    return dayofweek(utc_now_datetime()) in [6, 7]
end

function weekend_round_job(scheduler::TournamentScheduler)
    log_event(scheduler, :info, "Starting weekend round processing")
    
    try
        round_info = API.get_current_round(scheduler.api_client)
        log_event(scheduler, :info, "Processing round #$(round_info.number)")
        
        download_latest_data(scheduler)
        
        if scheduler.pipeline === nothing
            train_models(scheduler)
        else
            log_event(scheduler, :info, "Using existing trained models")
        end
        
        generate_and_submit_predictions(scheduler, round_info.number)
        
        log_event(scheduler, :success, "Weekend round processing completed")
        
    catch e
        log_event(scheduler, :error, "Weekend round failed: $e")
        @log_error "Weekend round processing failed" error=e
    end
end

function daily_round_job(scheduler::TournamentScheduler)
    log_event(scheduler, :info, "Starting daily round processing")
    
    try
        round_info = API.get_current_round(scheduler.api_client)
        
        if scheduler.pipeline === nothing
            log_event(scheduler, :warning, "No trained models available, skipping daily round")
            return
        end
        
        download_live_data(scheduler)
        
        generate_and_submit_predictions(scheduler, round_info.number)
        
        log_event(scheduler, :success, "Daily round completed")
        
    catch e
        log_event(scheduler, :error, "Daily round failed: $e")
    end
end

function weekly_update_job(scheduler::TournamentScheduler)
    log_event(scheduler, :info, "Running weekly update")
    
    try
        download_latest_data(scheduler, force=true)
        
        retrain_models(scheduler)
        
        check_model_performances(scheduler)
        
        log_event(scheduler, :success, "Weekly update completed")
        
    catch e
        log_event(scheduler, :error, "Weekly update failed: $e")
    end
end

function hourly_monitoring(scheduler::TournamentScheduler)
    try
        for model in scheduler.config.models
            try
                perf = API.get_model_performance(scheduler.api_client, model)
                
                if perf.corr < -0.05
                    @log_warn "Model performance alert" model=model correlation=perf.corr
                    # Send notification for performance alert
                    Notifications.notify_performance_alert(model, "correlation", perf.corr, -0.05)
                end
            catch model_error
                log_event(scheduler, :error, "Failed to get performance for $model: $model_error")
                @log_error "Failed to get performance for model" model=model error=model_error
            end
        end
    catch e
        log_event(scheduler, :error, "Hourly monitoring failed: $e")
        @log_error "Hourly monitoring failed" error=e
    end
end

function compounding_job(scheduler::TournamentScheduler)
    """
    Job to automatically compound earnings into stake.
    Runs on Wednesdays after payouts are processed.
    """
    if isnothing(scheduler.compounding_manager)
        return
    end
    
    try
        log_event(scheduler, :info, "Starting automatic compounding process...")
        
        # Check if compounding should run
        if !Compounding.should_run_compounding(scheduler.compounding_manager)
            log_event(scheduler, :info, "Compounding conditions not met, skipping")
            return
        end
        
        # Process compounding for all models
        total_compounded = Compounding.process_all_compounding(scheduler.compounding_manager)
        
        if total_compounded > 0
            log_event(scheduler, :success, "Compounded $(total_compounded) NMR total across all models")
            
            # Log compounding success
            @log_info "Compounding completed successfully" amount_compounded=total_compounded
        else
            log_event(scheduler, :info, "No earnings to compound at this time")
        end
        
    catch e
        log_event(scheduler, :error, "Compounding failed: $e")
        @log_error "Automatic compounding failed" error=e
    end
end

function download_latest_data(scheduler::TournamentScheduler; force::Bool=false)
    data_dir = scheduler.config.data_dir
    
    train_path = joinpath(data_dir, "train.parquet")
    val_path = joinpath(data_dir, "validation.parquet")
    live_path = joinpath(data_dir, "live.parquet")
    features_path = joinpath(data_dir, "features.json")
    
    should_download = force || !isfile(train_path) || 
                     (time() - mtime(train_path)) > 7 * 24 * 3600
    
    if should_download
        log_event(scheduler, :info, "Downloading tournament data...")
        
        API.download_dataset(scheduler.api_client, "train", train_path)
        API.download_dataset(scheduler.api_client, "validation", val_path)
        API.download_dataset(scheduler.api_client, "features", features_path)
        
        log_event(scheduler, :success, "Data download completed")
    else
        log_event(scheduler, :info, "Using cached training data")
    end
    
    API.download_dataset(scheduler.api_client, "live", live_path)
end

function download_live_data(scheduler::TournamentScheduler)
    live_path = joinpath(scheduler.config.data_dir, "live.parquet")
    API.download_dataset(scheduler.api_client, "live", live_path)
    log_event(scheduler, :info, "Live data downloaded")
end

function train_models(scheduler::TournamentScheduler)
    log_event(scheduler, :info, "Training models...")
    
    train_path = joinpath(scheduler.config.data_dir, "train.parquet")
    val_path = joinpath(scheduler.config.data_dir, "validation.parquet")
    
    # Use configuration values instead of hardcoded parameters
    train_df = DataLoader.load_training_data(train_path, sample_pct=scheduler.config.sample_pct)
    val_df = DataLoader.load_training_data(val_path)
    
    feature_cols = filter(name -> startswith(name, "feature_"), names(train_df))
    
    scheduler.pipeline = Pipeline.MLPipeline(
        feature_cols=feature_cols,
        target_col=scheduler.config.target_col,
        neutralize=scheduler.config.enable_neutralization,
        neutralize_proportion=scheduler.config.neutralization_proportion
    )
    
    Pipeline.train!(scheduler.pipeline, train_df, val_df, verbose=true)
    
    log_event(scheduler, :success, "Model training completed")
end

function retrain_models(scheduler::TournamentScheduler)
    log_event(scheduler, :info, "Retraining models with latest data...")
    train_models(scheduler)
end

function generate_and_submit_predictions(scheduler::TournamentScheduler, round_number::Int)
    if scheduler.pipeline === nothing
        log_event(scheduler, :error, "No trained models available")
        return
    end
    
    # Validate submission window before generating predictions
    try
        window_status = API.validate_submission_window(scheduler.api_client)
        
        if !window_status.is_open
            time_closed = abs(window_status.time_remaining)
            log_event(scheduler, :warning, "Submission window is closed for $(window_status.round_type) round $(window_status.round_number). Window closed $(round(time_closed, digits=1)) hours ago")
            
            @log_warn "Submission window closed" hours_ago=round(time_closed, digits=1) round_number=window_status.round_number
            return
        end
        
        log_event(scheduler, :info, "Submission window is open for $(window_status.round_type) round $(window_status.round_number) ($(round(window_status.time_remaining, digits=1))h remaining)")
    catch e
        log_event(scheduler, :warning, "Could not validate submission window: $e. Proceeding anyway...")
    end
    
    log_event(scheduler, :info, "Generating predictions for round #$round_number")
    
    live_path = joinpath(scheduler.config.data_dir, "live.parquet")
    live_df = DataLoader.load_live_data(live_path)
    
    for model_name in scheduler.config.models
        try
            predictions = Pipeline.predict(scheduler.pipeline, live_df)
            
            # Create submission dataframe
            submission_df = DataLoader.create_submission_dataframe(
                live_df.id,
                predictions
            )
            
            predictions_path = joinpath(
                scheduler.config.data_dir,
                "predictions_$(model_name)_round$(round_number).csv"
            )
            
            DataLoader.save_predictions(submission_df, predictions_path)
            
            if scheduler.config.auto_submit
                # Submit with validation enabled (default behavior)
                API.submit_predictions(scheduler.api_client, model_name, predictions_path)
                log_event(scheduler, :success, "Submitted predictions for $model_name")
                
                @log_info "Predictions submitted successfully" model=model_name round=round_number
            else
                log_event(scheduler, :info, "Predictions saved for $model_name (auto-submit disabled)")
            end
            
        catch e
            log_event(scheduler, :error, "Failed to process $model_name: $e")
            
            @log_error "Failed to submit predictions" model=model_name error=e
        end
    end
end

function check_and_submit(scheduler::TournamentScheduler)
    try
        # First validate submission window
        window_status = API.validate_submission_window(scheduler.api_client)
        
        if !window_status.is_open
            time_closed = abs(window_status.time_remaining)
            log_event(scheduler, :info, "Submission window is closed for round $(window_status.round_number). Window closed $(round(time_closed, digits=1)) hours ago - skipping check")
            return
        end
        
        log_event(scheduler, :info, "Checking submissions for round $(window_status.round_number) ($(round(window_status.time_remaining, digits=1))h remaining)")
        
        round_info = API.get_current_round(scheduler.api_client)
        
        for model in scheduler.config.models
            status = API.get_submission_status(scheduler.api_client, model, round_info.number)
            
            if isempty(status)
                log_event(scheduler, :warning, "No submission found for $model, generating...")
                generate_and_submit_predictions(scheduler, round_info.number)
            else
                log_event(scheduler, :info, "Submission already exists for $model")
            end
        end
    catch e
        log_event(scheduler, :error, "Check and submit failed: $e")
    end
end

function check_model_performances(scheduler::TournamentScheduler)
    for model in scheduler.config.models
        try
            perf = API.get_model_performance(scheduler.api_client, model)
            log_event(scheduler, :info, "$model - CORR: $(perf.corr), MMC: $(perf.mmc)")
        catch e
            log_event(scheduler, :error, "Failed to get performance for $model")
        end
    end
end

function log_event(scheduler::TournamentScheduler, type::Symbol, message::String)
    timestamp = Dates.format(utc_now_datetime(), "yyyy-mm-dd HH:MM:SS")
    println("[$timestamp] $message")
    
    if scheduler.dashboard !== nothing
        Dashboard.add_event!(scheduler.dashboard, type, message)
    end
end

function stop_scheduler(scheduler::TournamentScheduler)
    scheduler.running = false
    
    # Deactivate all cron jobs
    for job in scheduler.cron_jobs
        job.active = false
    end
    
    # Wait for scheduler task to finish
    if scheduler.scheduler_task !== nothing
        wait(scheduler.scheduler_task)
    end
    
    log_event(scheduler, :info, "Scheduler stopped - $(length(scheduler.cron_jobs)) cron jobs terminated")
end

function get_scheduler_status(scheduler::TournamentScheduler)
    status = Dict{String, Any}()
    status["running"] = scheduler.running
    status["active_jobs"] = length(scheduler.cron_jobs)
    status["job_details"] = []
    
    for job in scheduler.cron_jobs
        push!(status["job_details"], Dict(
            "name" => job.name,
            "schedule" => job.cron_expression.expression,
            "active" => job.active,
            "last_run" => job.last_run,
            "next_run" => job.next_run
        ))
    end
    
    return status
end

export TournamentScheduler, start_scheduler, stop_scheduler, get_scheduler_status

end