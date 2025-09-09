module Scheduler

using Dates
using ..API
using ..DataLoader
using ..Pipeline
using ..Dashboard
using ..Notifications

mutable struct TournamentScheduler
    config::Any
    api_client::API.NumeraiClient
    pipeline::Union{Nothing, Pipeline.MLPipeline}
    timers::Vector{Timer}
    running::Bool
    dashboard::Union{Nothing, Dashboard.TournamentDashboard}
end

function TournamentScheduler(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key)
    
    return TournamentScheduler(
        config,
        api_client,
        nothing,
        Timer[],
        false,
        nothing
    )
end

function start_scheduler(scheduler::TournamentScheduler; with_dashboard::Bool=false)
    scheduler.running = true
    
    if with_dashboard
        scheduler.dashboard = Dashboard.TournamentDashboard(scheduler.config)
    end
    
    setup_timers!(scheduler)
    
    println("🚀 Numerai Tournament Scheduler Started")
    println("Configured for $(length(scheduler.config.models)) models")
    println("Auto-submit: $(scheduler.config.auto_submit)")
    
    if with_dashboard
        Dashboard.run_dashboard(scheduler.dashboard)
    else
        while scheduler.running
            sleep(60)
        end
    end
end

function setup_timers!(scheduler::TournamentScheduler)
    # Weekend round job - every Saturday at 18:00
    push!(scheduler.timers, Timer(0.0, interval=3600.0) do timer
        if is_weekend_round_time()
            weekend_round_job(scheduler)
        end
    end)
    
    # Check and submit - every 2 hours on weekends
    push!(scheduler.timers, Timer(0.0, interval=7200.0) do timer
        if is_weekend()
            check_and_submit(scheduler)
        end
    end)
    
    # Daily round job - weekdays at 18:00
    push!(scheduler.timers, Timer(0.0, interval=3600.0) do timer
        if is_daily_round_time()
            daily_round_job(scheduler)
        end
    end)
    
    # Weekly update - every Monday at 12:00
    push!(scheduler.timers, Timer(0.0, interval=3600.0) do timer
        if is_weekly_update_time()
            weekly_update_job(scheduler)
        end
    end)
    
    # Hourly monitoring
    push!(scheduler.timers, Timer(0.0, interval=3600.0) do timer
        hourly_monitoring(scheduler)
    end)
end

function is_weekend_round_time()
    now_time = now()
    return dayofweek(now_time) == 6 && hour(now_time) == 18 && minute(now_time) < 5
end

function is_weekend()
    return dayofweek(now()) in [6, 7]
end

function is_daily_round_time()
    now_time = now()
    return dayofweek(now_time) in [2, 3, 4, 5] && hour(now_time) == 18 && minute(now_time) < 5
end

function is_weekly_update_time()
    now_time = now()
    return dayofweek(now_time) == 1 && hour(now_time) == 12 && minute(now_time) < 5
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
        Notifications.send_notification(
            "Numerai Tournament Error",
            "Weekend round processing failed: $e",
            :error
        )
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
            perf = API.get_model_performance(scheduler.api_client, model)
            
            if perf.corr < -0.05
                Notifications.send_notification(
                    "Numerai Alert",
                    "Model $model has negative correlation: $(perf.corr)",
                    :warning
                )
            end
        end
    catch e
        # Silent fail for monitoring
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
    
    train_df = DataLoader.load_training_data(train_path, sample_pct=0.1)
    val_df = DataLoader.load_training_data(val_path)
    
    feature_cols = filter(name -> startswith(name, "feature_"), names(train_df))
    
    scheduler.pipeline = Pipeline.MLPipeline(
        feature_cols=feature_cols,
        target_col="target_cyrus_v4_20",
        neutralize=true,
        neutralize_proportion=0.5
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
                API.submit_predictions(scheduler.api_client, model_name, predictions_path)
                log_event(scheduler, :success, "Submitted predictions for $model_name")
                
                Notifications.send_notification(
                    "Numerai Submission",
                    "Successfully submitted predictions for $model_name",
                    :success
                )
            end
            
        catch e
            log_event(scheduler, :error, "Failed to submit $model_name: $e")
        end
    end
end

function check_and_submit(scheduler::TournamentScheduler)
    try
        round_info = API.get_current_round(scheduler.api_client)
        
        for model in scheduler.config.models
            status = API.get_submission_status(scheduler.api_client, model, round_info.number)
            
            if isempty(status)
                log_event(scheduler, :warning, "No submission found for $model, generating...")
                generate_and_submit_predictions(scheduler, round_info.number)
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
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    println("[$timestamp] $message")
    
    if scheduler.dashboard !== nothing
        Dashboard.add_event!(scheduler.dashboard, type, message)
    end
end

function stop_scheduler(scheduler::TournamentScheduler)
    scheduler.running = false
    
    for timer in scheduler.timers
        close(timer)
    end
    
    log_event(scheduler, :info, "Scheduler stopped")
end

export TournamentScheduler, start_scheduler, stop_scheduler

end