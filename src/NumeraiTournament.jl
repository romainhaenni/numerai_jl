module NumeraiTournament

using Dates
using TOML
using Distributed
using ThreadsX
using TimeZones

include("logger.jl")
include("utils.jl")
include("api/schemas.jl")
include("api/client.jl")
include("ml/dataloader.jl")
include("data/preprocessor.jl")
include("data/database.jl")
include("ml/neutralization.jl")
include("ml/models.jl")
include("ml/ensemble.jl")
include("ml/metrics.jl")
include("ml/pipeline.jl")
include("notifications.jl")
include("notifications/macos.jl")
include("performance/optimization.jl")
include("compounding.jl")
include("tui/charts.jl")
include("tui/panels.jl")
include("tui/dashboard.jl")
include("scheduler/cron.jl")

export run_tournament, TournamentConfig, TournamentDashboard
using .Logger: init_logger, @log_info, @log_warn, @log_error

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
    # Compounding configuration
    compounding_enabled::Bool
    min_compound_amount::Float64
    compound_percentage::Float64
    max_stake_amount::Float64
end

function load_config(path::String="config.toml")::TournamentConfig
    # Get API credentials from environment variables
    default_public_id = get(ENV, "NUMERAI_PUBLIC_ID", "")
    default_secret_key = get(ENV, "NUMERAI_SECRET_KEY", "")
    
    # Warn if API credentials are not set
    if isempty(default_public_id) || isempty(default_secret_key)
        @log_warn "NUMERAI_PUBLIC_ID and/or NUMERAI_SECRET_KEY environment variables not set. API operations will fail without valid credentials."
    end
    
    if !isfile(path)
        @log_info "No config file found at $path. Using default configuration."
        @log_info "Please create a config.toml file or set environment variables for API credentials."
        return TournamentConfig(
            default_public_id,
            default_secret_key,
            String[],  # Empty array instead of default_model placeholder
            "data",
            "models",
            true,
            0.0,
            Sys.CPU_THREADS,
            true,
            false,  # compounding_enabled
            1.0,    # min_compound_amount
            100.0,  # compound_percentage
            10000.0 # max_stake_amount
        )
    end
    
    config = TOML.parsefile(path)
    return TournamentConfig(
        get(config, "api_public_key", default_public_id),
        get(config, "api_secret_key", default_secret_key),
        get(config, "models", String[]),  # Empty array instead of default_model
        get(config, "data_dir", "data"),
        get(config, "model_dir", "models"),
        get(config, "auto_submit", true),
        get(config, "stake_amount", 0.0),
        get(config, "max_workers", Sys.CPU_THREADS),
        get(config, "notification_enabled", true),
        get(config, "compounding_enabled", false),
        get(config, "min_compound_amount", 1.0),
        get(config, "compound_percentage", 100.0),
        get(config, "max_stake_amount", 10000.0)
    )
end

function run_tournament(; config_path::String="config.toml", headless::Bool=false)
    # Initialize logging first
    init_logger()
    
    config = load_config(config_path)
    
    # Optimize for M4 Max performance
    perf_info = Performance.optimize_for_m4_max()
    @log_info "Optimized for M4 Max" threads=perf_info[:threads] memory_gb=perf_info[:memory_gb]
    
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