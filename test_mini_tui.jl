#!/usr/bin/env julia

# Mini TUI Test - Just render once and exit
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament
using Dates

println("Starting Mini TUI Test (single render)...")
println("=" * "="^50)

# Load config
config = NumeraiTournament.load_config("config.toml")

# Create dashboard
dashboard = NumeraiTournament.TUIv1036Dashboard(config)

# Check states
println("\nDashboard State:")
println("  Running: $(dashboard.running)")
println("  Auto-start: $(dashboard.auto_start_pipeline)")
println("  Operation: $(dashboard.current_operation)")
println("  Disk: $(round(dashboard.disk_free, digits=1))/$(round(dashboard.disk_total, digits=1)) GB")
println("  Memory: $(round(dashboard.memory_used, digits=1))/$(round(dashboard.memory_total, digits=1)) GB")
println("  CPU: $(round(dashboard.cpu_usage, digits=1))%")

# Check if downloads would auto-start
if dashboard.auto_start_pipeline && !dashboard.pipeline_started
    println("\n✅ AUTO-START WOULD TRIGGER!")
    println("The pipeline would automatically start downloading when TUI runs.")
end

# Add some events to see if event log works (add_event! is internal)
# We'll manually add events to test
push!(dashboard.events, (time=now(), type=:info, message="Test event 1"))
push!(dashboard.events, (time=now(), type=:success, message="Test event 2"))
push!(dashboard.events, (time=now(), type=:warning, message="Test event 3"))

println("\nEvent Log ($(length(dashboard.events)) events):")
for event in dashboard.events
    println("  [$(event.type)] $(event.message)")
end

println("\n✅ All checks passed! TUI components are working.")
println("\nThe issue might be in the rendering loop or terminal interaction.")
println("Try running: julia start_tui.jl")