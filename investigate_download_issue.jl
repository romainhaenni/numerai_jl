#!/usr/bin/env julia

# Investigation to understand download behavior in the pipeline
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Investigating download behavior...")

# Load configuration and create API client
config = NumeraiTournament.load_config("config.toml")
api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)

# Create dashboard with debug mode enabled
ENV["TUI_DEBUG"] = "true"
dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, api_client)

println("\nDashboard created with debug mode: $(dashboard.debug_mode)")
println("Events so far: $(length(dashboard.events))")

# Try a small download test
println("\nTesting download functionality...")
try
    # Call download_datasets directly
    datasets = ["train"]  # Start with just one dataset
    success = NumeraiTournament.TUIProductionV047.download_datasets(dashboard, datasets)

    println("\nDownload result: $success")
    println("Downloads completed: $(collect(dashboard.downloads_completed))")
    println("Downloads in progress: $(collect(dashboard.downloads_in_progress))")
    println("Current operation: $(dashboard.current_operation)")
    println("Pipeline active: $(dashboard.pipeline_active)")

    # Show recent events
    println("\nRecent events:")
    for (i, (timestamp, level, message)) in enumerate(dashboard.events)
        if i > length(dashboard.events) - 5  # Last 5 events
            println("  [$level] $message")
        end
    end

catch e
    println("❌ Download test failed: $e")
    println("Error type: $(typeof(e))")
    if isa(e, MethodError)
        println("Methods available: $(methods(e.f))")
    end
end

println("\nInvestigation complete.")