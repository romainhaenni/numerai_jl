module NumeraiTournament

using Dates
using TOML
using Distributed
using ThreadsX

include("api/schemas.jl")
include("api/client.jl")
include("ml/dataloader.jl")
include("data/preprocessor.jl")
include("ml/neutralization.jl")
include("ml/models.jl")
include("ml/ensemble.jl")
include("ml/pipeline.jl")
include("notifications.jl")
include("performance/optimization.jl")
include("tui/charts.jl")
include("tui/panels.jl")
include("tui/dashboard.jl")
include("scheduler/cron.jl")

export run_tournament, TournamentConfig, TournamentDashboard

mutable struct TournamentConfig
    api_public_key::String
    api_secret_key::String
    models::Vector{String}
    data_dir::String
    model_dir::String
    auto_submit::Bool
    stake_amount::Float64
    max_workers::Int
    notification_enabled::Bool
end

function load_config(path::String="config.toml")::TournamentConfig
    # Default values for testing
    default_public_id = get(ENV, "NUMERAI_PUBLIC_ID", "test_public_id")
    default_secret_key = get(ENV, "NUMERAI_SECRET_KEY", "test_secret_key")
    
    if !isfile(path)
        return TournamentConfig(
            default_public_id,
            default_secret_key,
            ["default_model"],
            "data",
            "models",
            true,
            0.0,
            Sys.CPU_THREADS,
            true
        )
    end
    
    config = TOML.parsefile(path)
    return TournamentConfig(
        get(config, "api_public_key", default_public_id),
        get(config, "api_secret_key", default_secret_key),
        get(config, "models", ["default_model"]),
        get(config, "data_dir", "data"),
        get(config, "model_dir", "models"),
        get(config, "auto_submit", true),
        get(config, "stake_amount", 0.0),
        get(config, "max_workers", Sys.CPU_THREADS),
        get(config, "notification_enabled", true)
    )
end

function run_tournament(; config_path::String="config.toml", headless::Bool=false)
    config = load_config(config_path)
    
    # Optimize for M4 Max performance
    perf_info = Performance.optimize_for_m4_max()
    println("🚀 Optimized for M4 Max: $(perf_info[:threads]) threads, $(perf_info[:memory_gb])GB RAM")
    
    mkpath(config.data_dir)
    mkpath(config.model_dir)
    
    if headless
        scheduler = Scheduler.TournamentScheduler(config)
        Scheduler.start_scheduler(scheduler)
    else
        dashboard = Dashboard.TournamentDashboard(config)
        Dashboard.run_dashboard(dashboard)
    end
end

end