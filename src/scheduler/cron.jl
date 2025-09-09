module Scheduler

using Dates
using Cron
using ..API
using ..DataLoader
using ..Pipeline
using ..Dashboard
using ..Notifications

mutable struct TournamentScheduler
    config::Any
    api_client::API.NumeraiClient
    pipeline::Union{Nothing, Pipeline.MLPipeline}
    jobs::Vector{CronJob}
    running::Bool
    dashboard::Union{Nothing, Dashboard.TournamentDashboard}
end

function TournamentScheduler(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key)
    
    return TournamentScheduler(
        config,
        api_client,
        nothing,
        CronJob[],
        false,
        nothing
    )
end

function start_scheduler(scheduler::TournamentScheduler; with_dashboard::Bool=false)
    scheduler.running = true
    
    if with_dashboard
        scheduler.dashboard = Dashboard.TournamentDashboard(scheduler.config)
    end
    
    setup_jobs!(scheduler)
    
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

function setup_jobs!(scheduler::TournamentScheduler)
    push!(scheduler.jobs, CronJob("0 18 * * 6", () -> weekend_round_job(scheduler)))
    
    push!(scheduler.jobs, CronJob("0 */2 * * 6-7", () -> check_and_submit(scheduler)))
    
    push!(scheduler.jobs, CronJob("0 18 * * 2-5", () -> daily_round_job(scheduler)))
    
    push!(scheduler.jobs, CronJob("0 12 * * 1", () -> weekly_update_job(scheduler)))
    
    push!(scheduler.jobs, CronJob("0 * * * *", () -> hourly_monitoring(scheduler)))
    
    for job in scheduler.jobs
        start(job)
    end
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
    
    data = DataLoader.load_tournament_data(scheduler.config.data_dir)
    
    features, _ = DataLoader.load_features_json(joinpath(scheduler.config.data_dir, "features.json"))
    
    scheduler.pipeline = Pipeline.MLPipeline(
        feature_cols=features,
        target_col="target_cyrus_v4_20",
        neutralize=true,
        neutralize_proportion=0.5
    )
    
    Pipeline.train!(scheduler.pipeline, data.train, data.validation, verbose=true)
    
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
    
    live_data = DataLoader.load_parquet(joinpath(scheduler.config.data_dir, "live.parquet"))
    
    for model_name in scheduler.config.models
        try
            predictions_path = joinpath(
                scheduler.config.data_dir,
                "predictions_$(model_name)_round$(round_number).csv"
            )
            
            Pipeline.save_predictions(scheduler.pipeline, live_data, predictions_path, model_name=model_name)
            
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
    
    for job in scheduler.jobs
        stop(job)
    end
    
    log_event(scheduler, :info, "Scheduler stopped")
end

export TournamentScheduler, start_scheduler, stop_scheduler

end