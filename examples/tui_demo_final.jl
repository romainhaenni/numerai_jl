#!/usr/bin/env julia

"""
TUI Demo - Final Test
Tests all TUI fixes in the actual dashboard
"""

using Pkg
Pkg.activate(".")

using NumeraiTournament
using NumeraiTournament.Dashboard

println("🚀 Starting TUI Dashboard with all fixes enabled...")
println("=" ^ 60)
println()
println("The dashboard will start with:")
println("✅ Real-time progress bars for all operations")
println("✅ Instant keyboard commands (no Enter required)")
println("✅ Automatic training after downloads")
println("✅ Real-time status updates")
println("✅ Sticky panels (top: system status, bottom: events)")
println()
println("Commands:")
println("  q - Quit")
println("  d - Download data")
println("  t - Train models")
println("  s - Submit predictions")
println("  p - Predict")
println("  r - Refresh")
println("  n - New model wizard")
println("  h - Help")
println()
println("Press any key to start the dashboard...")
readline()

# Load config
config = NumeraiTournament.load_config("config.toml")

# Enable auto-training for demo
ENV["AUTO_TRAIN"] = "true"
config.auto_train_after_download = true

# Create and run dashboard
dashboard = Dashboard.TournamentDashboard(config)

# Start the dashboard
Dashboard.run_dashboard(dashboard)