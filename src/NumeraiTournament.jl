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
include("gpu/metal_acceleration.jl")
include("gpu/benchmarks.jl")
include("ml/models.jl")
include("ml/linear_models.jl")
include("ml/neural_networks.jl")
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

export run_tournament, TournamentConfig, TournamentDashboard,
       XGBoostModel, LightGBMModel, EvoTreesModel, get_models_gpu_status,
       MLPModel, ResNetModel, TabNetModel, NeuralNetworkModel,
       has_metal_gpu, get_gpu_info, gpu_standardize!, run_comprehensive_gpu_benchmark
using .Logger: init_logger, @log_info, @log_warn, @log_error
using .Models: XGBoostModel, LightGBMModel, EvoTreesModel, get_models_gpu_status
using .NeuralNetworks: MLPModel, ResNetModel, TabNetModel, NeuralNetworkModel
using .MetalAcceleration: has_metal_gpu, get_gpu_info, gpu_standardize!
using .GPUBenchmarks: run_comprehensive_gpu_benchmark

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
    # Tournament configuration
    tournament_id::Int  # 8 for Classic, 11 for Signals
    # Feature set configuration
    feature_set::String
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
            8,       # tournament_id default (Classic)
            "medium",  # feature_set default
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
        get(config, "tournament_id", 8),  # Classic by default
        get(config, "feature_set", "medium"),
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