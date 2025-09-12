#!/usr/bin/env julia

"""
Dashboard Demo Example

This example demonstrates how to:
1. Start the TUI dashboard programmatically
2. Monitor model performance in real-time
3. Handle dashboard events and commands
4. Integrate with the tournament scheduler

This example shows how to use the interactive dashboard features.
"""

using Pkg
Pkg.activate(@__DIR__ * "/..")

using NumeraiTournament
using Dates

function demo_dashboard()
    println("🚀 Starting Dashboard Demo")
    println("=" ^ 50)
    println()
    
    # Load configuration
    config = NumeraiTournament.load_config("config.toml")
    
    # Initialize API client
    println("📡 Connecting to Numerai API...")
    api_client = NumeraiTournament.API.create_client_from_env()
    
    # Get current round information
    round_info = NumeraiTournament.API.get_current_round(api_client)
    println("📅 Current Round: $(round_info["number"])")
    println("   Opens: $(round_info["openTime"])")
    println("   Closes: $(round_info["closeTime"])")
    println()
    
    # Get user's models
    println("🤖 Loading your models...")
    models = NumeraiTournament.API.get_models_for_user(api_client)
    
    if isempty(models)
        println("⚠️  No models found. Please create a model on numer.ai first.")
        return
    end
    
    println("Found $(length(models)) model(s):")
    for model in models
        println("   - $(model["name"]) (ID: $(model["id"]))")
    end
    println()
    
    # Create dashboard configuration
    dashboard_config = Dict(
        :api_client => api_client,
        :config => config,
        :refresh_rate => 30,  # Refresh every 30 seconds
        :show_charts => true,
        :enable_notifications => true
    )
    
    # Demo: Show what the dashboard would display
    println("📊 Dashboard Preview")
    println("=" ^ 50)
    
    # Performance Panel
    println("\n📈 Model Performance Panel:")
    for model in models[1:min(3, length(models))]
        perf = NumeraiTournament.API.get_model_performance(
            api_client, 
            model["name"]
        )
        
        if !isnothing(perf) && haskey(perf, "latestRoundSubmission")
            latest = perf["latestRoundSubmission"]
            println("   $(model["name"]):")
            println("     CORR: $(round(get(latest, "correlation", 0.0), digits=4))")
            println("     MMC:  $(round(get(latest, "mmc", 0.0), digits=4))")
            println("     FNC:  $(round(get(latest, "fnc", 0.0), digits=4))")
        end
    end
    
    # System Status Panel
    println("\n💻 System Status Panel:")
    sys_info = NumeraiTournament.Performance.get_system_info()
    println("   CPU: $(sys_info[:cpu_cores]) cores")
    println("   Memory: $(sys_info[:memory_gb]) GB total, $(sys_info[:free_memory_gb]) GB free")
    println("   Threads: $(sys_info[:threads])")
    println("   Julia: v$(sys_info[:julia_version])")
    
    # Training Status Panel
    println("\n🏋️ Training Status Panel:")
    println("   Status: Ready")
    println("   Last training: Never")
    println("   Auto-submit: $(get(config, "auto_submit", false))")
    
    # Event Log Panel
    println("\n📝 Recent Events:")
    println("   [$(Dates.format(now(), "HH:MM:SS"))] Dashboard demo started")
    println("   [$(Dates.format(now(), "HH:MM:SS"))] Connected to Numerai API")
    println("   [$(Dates.format(now(), "HH:MM:SS"))] Loaded $(length(models)) models")
    
    println("\n" * "=" * 50)
    
    # Instructions for running the actual dashboard
    println("\n📖 To run the full interactive dashboard:")
    println("   julia -t 16 ./numerai")
    println()
    println("🎮 Dashboard Controls:")
    println("   q - Quit")
    println("   p - Pause/Resume")
    println("   s - Start Training")
    println("   h - Show Help")
    println("   n - Create New Model")
    println()
    println("💡 Tips:")
    println("   - The dashboard updates in real-time")
    println("   - Use multiple threads for better performance")
    println("   - Configure refresh rates in config.toml")
    println("   - Enable notifications for important events")
    
    # Demo: Simulate dashboard updates
    println("\n🔄 Simulating dashboard updates...")
    for i in 1:3
        sleep(1)
        println("   Update $i: Refreshing model performance...")
    end
    
    println("\n✅ Dashboard demo completed!")
    println("   Run './numerai' to start the full interactive dashboard")
end

# Additional utility functions for dashboard interaction

function create_mock_dashboard_data()
    """Create mock data for testing dashboard without API"""
    return Dict(
        :models => [
            Dict("name" => "model_1", "stake" => 100.0, "status" => "active"),
            Dict("name" => "model_2", "stake" => 50.0, "status" => "active")
        ],
        :performance => Dict(
            "model_1" => Dict(
                "correlation" => 0.0234,
                "mmc" => 0.0156,
                "fnc" => 0.0089,
                "sharpe" => 0.89
            ),
            "model_2" => Dict(
                "correlation" => 0.0189,
                "mmc" => 0.0203,
                "fnc" => 0.0112,
                "sharpe" => 0.76
            )
        ),
        :events => [
            (now(), "INFO", "Dashboard started"),
            (now() - Minute(5), "SUCCESS", "Model trained successfully"),
            (now() - Minute(10), "WARNING", "Low correlation detected"),
            (now() - Hour(1), "INFO", "Data downloaded")
        ]
    )
end

function format_performance_bar(value::Float64, width::Int=20)
    """Create a simple text-based performance bar"""
    filled = Int(round(abs(value) * width * 100))
    filled = min(filled, width)
    
    if value >= 0
        bar = "█" ^ filled * "░" ^ (width - filled)
        return "[$bar] $(round(value, digits=4))"
    else
        bar = "░" ^ (width - filled) * "█" ^ filled
        return "[$bar] $(round(value, digits=4))"
    end
end

# Run the demo
if abspath(PROGRAM_FILE) == @__FILE__
    demo_dashboard()
end