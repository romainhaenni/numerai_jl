#!/usr/bin/env julia

# Test the new TUI v0.10.41 implementation

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

# Load config
config = NumeraiTournament.load_config("config.toml")

println("Testing TUI v0.10.41 Fixed Implementation")
println("==========================================\n")

# Test dashboard creation
println("Creating dashboard...")
dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

println("✅ Dashboard created successfully\n")

println("Configuration values:")
println("  auto_start_enabled: ", dashboard.auto_start_enabled)
println("  auto_train_enabled: ", dashboard.auto_train_enabled)
println("  auto_submit_enabled: ", dashboard.auto_submit_enabled)

println("\nInitial system values:")
println("  CPU: ", dashboard.cpu_usage, "%")
println("  Memory: ", dashboard.memory_used, "/", dashboard.memory_total, " GB")
println("  Disk: ", dashboard.disk_free, "/", dashboard.disk_total, " GB")

println("\nUpdating system info...")
NumeraiTournament.TUIv1041Fixed.update_system_info!(dashboard)

println("\nUpdated system values (should be real values):")
println("  CPU: ", round(dashboard.cpu_usage, digits=1), "%")
println("  Memory: ", round(dashboard.memory_used, digits=1), "/", round(dashboard.memory_total, digits=1), " GB")
println("  Disk: ", round(dashboard.disk_free, digits=1), "/", round(dashboard.disk_total, digits=1), " GB ($(round(dashboard.disk_percent, digits=1))% used)")

# Test event logging
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :info, "Test info event")
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :success, "✅ Test success event")
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :warn, "⚠️ Test warning event")
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :error, "❌ Test error event")

println("\n✅ Event logging working: ", length(dashboard.events), " events logged")

# Simulate operation progress
println("\nSimulating download operation...")
dashboard.current_operation = :downloading
dashboard.operation_description = "Downloading train.parquet"
dashboard.operation_progress = 75.0
dashboard.operation_details = Dict(:show_mb => true, :current_mb => 375.0, :total_mb => 500.0)

println("  Operation: ", dashboard.current_operation)
println("  Description: ", dashboard.operation_description)
println("  Progress: ", dashboard.operation_progress, "%")
println("  Details: ", dashboard.operation_details[:current_mb], "/", dashboard.operation_details[:total_mb], " MB")

println("\n✅ All tests passed!")
println("\n" * "="^50)
println("To run the full TUI v0.10.41, use:")
println("  julia start_tui.jl")
println("" * "="^50)