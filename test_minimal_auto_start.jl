#!/usr/bin/env julia

# Minimal test to see if auto-start actually triggers
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Testing minimal auto-start pipeline...")

# Load configuration and create API client
config = NumeraiTournament.load_config("config.toml")
api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)

# Create dashboard
dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, api_client)

println("\nAuto-start configuration:")
println("  auto_start_enabled: $(dashboard.auto_start_enabled)")
println("  auto_start_initiated: $(dashboard.auto_start_initiated)")
println("  auto_start_delay: $(dashboard.auto_start_delay)")

# Simulate the auto-start check that happens in run_dashboard
if dashboard.auto_start_enabled && !dashboard.auto_start_initiated
    dashboard.auto_start_initiated = true

    println("\n⏱️ Auto-start logic triggered!")
    println("Waiting $(dashboard.auto_start_delay) seconds before starting pipeline...")

    # Wait for the delay
    sleep(dashboard.auto_start_delay)

    # Check conditions
    println("\nChecking conditions:")
    println("  dashboard.running: $(dashboard.running)")
    println("  dashboard.pipeline_active: $(dashboard.pipeline_active)")

    if dashboard.running && !dashboard.pipeline_active
        println("\n🚀 Conditions met - starting pipeline!")

        # Try to start the pipeline
        try
            NumeraiTournament.TUIProductionV047.start_pipeline(dashboard)
            println("✅ start_pipeline called successfully")

            # Wait a moment to see if pipeline starts
            sleep(1.0)
            println("Pipeline status after 1 second:")
            println("  pipeline_active: $(dashboard.pipeline_active)")
            println("  current_operation: $(dashboard.current_operation)")
            println("  pipeline_stage: $(dashboard.pipeline_stage)")

        catch e
            println("❌ Error calling start_pipeline: $e")
        end
    else
        println("❌ Conditions not met for pipeline start")
    end
else
    println("❌ Auto-start logic did not trigger")
    println("  auto_start_enabled: $(dashboard.auto_start_enabled)")
    println("  auto_start_initiated: $(dashboard.auto_start_initiated)")
end

println("\nTest complete.")