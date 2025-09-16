#!/usr/bin/env julia
# Real-time test of TUI issues with detailed debugging

using Pkg
Pkg.activate(".")

using NumeraiTournament
using Logging
using Dates

# Set up detailed logging
global_logger(ConsoleLogger(stdout, Logging.Debug))

println("\n=== Testing TUI v0.10.41 Actual Implementation ===\n")

# Load config
config = NumeraiTournament.load_config("config.toml")
println("Config loaded: $(typeof(config))")
println("  auto_start_pipeline: $(config.auto_start_pipeline)")
println("  auto_train_after_download: $(config.auto_train_after_download)")
println("  auto_submit: $(config.auto_submit)")

# Create dashboard instance directly
dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

println("\nDashboard created:")
println("  auto_start_enabled: $(dashboard.auto_start_enabled)")
println("  auto_train_enabled: $(dashboard.auto_train_enabled)")
println("  auto_submit_enabled: $(dashboard.auto_submit_enabled)")

# Test system info update
println("\n=== Testing System Info Update ===")
println("Initial values:")
println("  CPU: $(dashboard.cpu_usage)%")
println("  Memory: $(dashboard.memory_used)/$(dashboard.memory_total) GB")
println("  Disk: $(dashboard.disk_free)/$(dashboard.disk_total) GB")

# Update system info
NumeraiTournament.TUIv1041Fixed.update_system_info!(dashboard)

println("\nAfter update_system_info!:")
println("  CPU: $(dashboard.cpu_usage)%")
println("  Memory: $(dashboard.memory_used)/$(dashboard.memory_total) GB")
println("  Disk: $(dashboard.disk_free)/$(dashboard.disk_total) GB")

if dashboard.cpu_usage == 0.0 || dashboard.memory_total == 0.0 || dashboard.disk_total == 0.0
    println("❌ ISSUE FOUND: System info still showing zeros!")
else
    println("✅ System info showing real values")
end

# Test event logging
println("\n=== Testing Event Logging ===")
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :info, "Test event 1")
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :warn, "Test warning")
NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :success, "Test success")

println("Events logged: $(length(dashboard.events))")
for event in dashboard.events[1:min(3, end)]
    println("  [$(event.level)] $(event.message)")
end

# Test keyboard command handling
println("\n=== Testing Command Handling ===")
println("Testing 'd' command (download):")
NumeraiTournament.TUIv1041Fixed.handle_command(dashboard, 'd')
println("  Pipeline stage: $(dashboard.pipeline_stage)")
println("  Current operation: $(dashboard.current_operation)")

# Check events for response
if length(dashboard.events) > 3
    latest_event = dashboard.events[end]
    println("  Response: [$(latest_event.level)] $(latest_event.message)")
end

# Test pipeline start
println("\nTesting 's' command (start pipeline):")
dashboard.pipeline_stage = :idle  # Reset
NumeraiTournament.TUIv1041Fixed.handle_command(dashboard, 's')
println("  Pipeline active: $(dashboard.pipeline_active)")
println("  Pipeline stage: $(dashboard.pipeline_stage)")

# Test progress tracking
println("\n=== Testing Progress Tracking ===")
dashboard.operation_progress = 50.0
dashboard.operation_total = 100.0
dashboard.operation_description = "Test download"
dashboard.current_operation = :downloading
dashboard.operation_details = Dict(:show_mb => true, :current_mb => 50.0, :total_mb => 100.0)

println("Progress setup:")
println("  Operation: $(dashboard.current_operation)")
println("  Description: $(dashboard.operation_description)")
println("  Progress: $(dashboard.operation_progress)/$(dashboard.operation_total)")
println("  Details: $(dashboard.operation_details)")

# Test auto-start logic
println("\n=== Testing Auto-Start Logic ===")
if dashboard.auto_start_enabled
    println("✅ Auto-start is enabled - pipeline should start automatically")
else
    println("⚠️  Auto-start is disabled - manual start required")
end

println("\n=== Test Complete ===")
println("\nKey findings:")
println("• System monitoring: $(dashboard.cpu_usage > 0 && dashboard.memory_total > 0 ? "✅ Working" : "❌ Not working")")
println("• Configuration extraction: $(dashboard.auto_start_enabled == config.auto_start_pipeline ? "✅ Working" : "❌ Not working")")
println("• Command handling: $(dashboard.pipeline_active || dashboard.pipeline_stage != :idle ? "✅ Working" : "❌ Not working")")
println("• Event logging: $(length(dashboard.events) > 0 ? "✅ Working" : "❌ Not working")")

dashboard.running = false  # Clean shutdown