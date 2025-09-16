#!/usr/bin/env julia

# Test auto-start pipeline functionality

using Pkg
Pkg.activate(@__DIR__)

# Load the main module
using NumeraiTournament

println("Testing Auto-Start Pipeline Functionality")
println("="^50)

# Load config
config = NumeraiTournament.load_config("config.toml")

# Check config values
println("\nConfiguration:")
println("  auto_start_pipeline: $(config.auto_start_pipeline)")
println("  auto_train_after_download: $(config.auto_train_after_download)")
println("  data_dir: $(config.data_dir)")

# Create API client
println("\nCreating API client...")
api_client = nothing
try
    global api_client
    if !isempty(config.api_public_key) && !isempty(config.api_secret_key)
        api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)
        println("  ✅ API client created successfully")
    else
        println("  ⚠️ No API credentials - pipeline will fail")
    end
catch e
    println("  ❌ Failed to create API client: $e")
end

# Create dashboard
println("\nCreating dashboard...")
dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, api_client)
println("  ✅ Dashboard created")

# Check auto-start settings
println("\nAuto-start Settings:")
println("  auto_start_enabled: $(dashboard.auto_start_enabled)")
println("  auto_train_enabled: $(dashboard.auto_train_enabled)")
println("  auto_start_delay: $(dashboard.auto_start_delay) seconds")

# Test starting pipeline manually
println("\nTesting manual pipeline start...")
NumeraiTournament.TUIProductionV047.start_pipeline(dashboard)

# Wait a bit to see events
sleep(2.0)

# Check events
println("\nEvents generated:")
for (timestamp, level, msg) in dashboard.events
    color = level == :error ? "31" :    # Red
            level == :warn ? "33" :      # Yellow
            level == :success ? "32" :   # Green
            "37"                          # White
    println("  \033[$(color)m[$(level)] $(msg)\033[0m")
end

# Check pipeline state
println("\nPipeline State:")
println("  pipeline_active: $(dashboard.pipeline_active)")
println("  pipeline_stage: $(dashboard.pipeline_stage)")
println("  current_operation: $(dashboard.current_operation)")

# Check if downloads started
println("\nDownload State:")
println("  downloads_in_progress: $(dashboard.downloads_in_progress)")
println("  downloads_completed: $(dashboard.downloads_completed)")

# Stop dashboard
dashboard.running = false

println("\n" * "="^50)
println("Test Complete")

# Summary
if api_client === nothing
    println("\n⚠️ No API client - pipeline cannot download data")
    println("   This is why auto-start might appear to not work!")
else
    println("\n✅ API client available - pipeline should work")
end