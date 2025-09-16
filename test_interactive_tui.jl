#!/usr/bin/env julia

# Test the TUI in a controlled way

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

# Load config
config = NumeraiTournament.load_config("config.toml")

# Override auto-start for testing
config.auto_start_pipeline = false  # Don't auto-start
config.auto_train_after_download = true
config.auto_submit = false

println("Starting TUI v0.10.39 Test...")
println("Configuration:")
println("  auto_start_pipeline: ", config.auto_start_pipeline)
println("  auto_train_after_download: ", config.auto_train_after_download)
println("  auto_submit: ", config.auto_submit)
println()
println("Creating simulated keyboard input task...")

# Create dashboard
dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)

# Test system info update
println("\nInitial system info:")
println("  CPU: ", dashboard.cpu_usage, "%")
println("  Memory: ", dashboard.memory_used, "/", dashboard.memory_total, " GB")
println("  Disk: ", dashboard.disk_free, "/", dashboard.disk_total, " GB")

println("\nUpdating system info...")
NumeraiTournament.TUIv1039.update_system_info!(dashboard)

println("\nUpdated system info:")
println("  CPU: ", dashboard.cpu_usage, "%")
println("  Memory: ", dashboard.memory_used, "/", dashboard.memory_total, " GB")
println("  Disk: ", dashboard.disk_free, "/", dashboard.disk_total, " GB")

# Test event logging
NumeraiTournament.TUIv1039.add_event!(dashboard, :info, "Test event 1")
NumeraiTournament.TUIv1039.add_event!(dashboard, :success, "Test success event")
NumeraiTournament.TUIv1039.add_event!(dashboard, :warn, "Test warning")

println("\nEvents logged: ", length(dashboard.events))

# Test operation tracking
dashboard.current_operation = :downloading
dashboard.operation_description = "Test download"
dashboard.operation_progress = 50.0
dashboard.operation_details = Dict(:show_mb => true, :current_mb => 100.0, :total_mb => 200.0)

println("\nOperation status:")
println("  Operation: ", dashboard.current_operation)
println("  Description: ", dashboard.operation_description)
println("  Progress: ", dashboard.operation_progress, "%")

println("\nTest complete!")
println("\nTo run the full TUI, use: julia start_tui.jl")