#!/usr/bin/env julia

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Testing Auto-Start Pipeline...")
println("==============================")

# Load config
config = NumeraiTournament.load_config("config.toml")
println("Config loaded:")
println("  auto_submit: $(config.auto_submit)")
println("  auto_start_pipeline: $(config.auto_start_pipeline)")
println("  auto_train_after_download: $(config.auto_train_after_download)")

# Create dashboard
dashboard = NumeraiTournament.TUIv1036Dashboard(config)
println("\nDashboard created:")
println("  auto_start_pipeline: $(dashboard.auto_start_pipeline)")
println("  pipeline_started: $(dashboard.pipeline_started)")

# Check if the auto-start should trigger
if dashboard.auto_start_pipeline && !dashboard.pipeline_started
    println("\n✅ Auto-start conditions met! Pipeline should start automatically.")
else
    println("\n❌ Auto-start conditions NOT met:")
    println("  auto_start_pipeline: $(dashboard.auto_start_pipeline)")
    println("  pipeline_started: $(dashboard.pipeline_started)")
end

println("\nEvent log (should show initial events):")
for (i, event) in enumerate(dashboard.events)
    println("  $i. [$(event.type)] $(event.message)")
end

println("\n✅ Auto-start test complete!")