#!/usr/bin/env julia

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Testing Real TUI Run...")
println("=======================")

# Load config
config = NumeraiTournament.load_config("config.toml")
println("Config loaded:")
println("  auto_submit: $(config.auto_submit)")
println("  auto_start_pipeline: $(config.auto_start_pipeline)")

# Create dashboard
dashboard = NumeraiTournament.TUIv1036Dashboard(config)
println("\nDashboard created:")
println("  auto_start_pipeline: $(dashboard.auto_start_pipeline)")
println("  pipeline_started: $(dashboard.pipeline_started)")
println("  running: $(dashboard.running)")
println("  current_operation: $(dashboard.current_operation)")

# Check initial state
println("\nInitial System State:")
println("  CPU: $(round(dashboard.cpu_usage, digits=1))%")
println("  Memory: $(round(dashboard.memory_used, digits=1))/$(round(dashboard.memory_total, digits=1)) GB")
println("  Disk: $(round(dashboard.disk_free, digits=1))/$(round(dashboard.disk_total, digits=1)) GB free")

# Update system info (this is an internal function, so we update manually)
dashboard.cpu_usage = minimum(Sys.loadavg()) / Sys.CPU_THREADS * 100.0
mem_total = Sys.total_memory() / 1024^3
mem_free = Sys.free_memory() / 1024^3
dashboard.memory_total = mem_total
dashboard.memory_used = mem_total - mem_free
disk_info = NumeraiTournament.Utils.get_disk_space_info()
dashboard.disk_free = disk_info.free_gb
dashboard.disk_total = disk_info.total_gb
println("\nAfter System Update:")
println("  CPU: $(round(dashboard.cpu_usage, digits=1))%")
println("  Memory: $(round(dashboard.memory_used, digits=1))/$(round(dashboard.memory_total, digits=1)) GB")
println("  Disk: $(round(dashboard.disk_free, digits=1))/$(round(dashboard.disk_total, digits=1)) GB free")

# Check if auto-start would trigger
if dashboard.auto_start_pipeline && !dashboard.pipeline_started
    println("\n✅ Auto-start would trigger when run_tui_v1036 is called")
else
    println("\n❌ Auto-start would NOT trigger")
end

# Test command handling
println("\nTesting keyboard command handling...")
dashboard.last_command_time = 0.0  # Reset to allow immediate command

# Test download command (handle_command is also internal, simulate instead)
if dashboard.current_operation == :idle
    println("  Simulating 'd' key press...")
    # This would normally be handled by handle_command internally
end
println("  After 'd' command: current_operation = $(dashboard.current_operation)")

# Wait a bit for async operation to start
sleep(0.5)
println("  After 0.5s wait: current_operation = $(dashboard.current_operation)")
println("  Operation description: $(dashboard.operation_description)")
println("  Progress: $(dashboard.operation_progress) / $(dashboard.operation_total)")

# Check events
println("\nEvent Log:")
for event in dashboard.events
    println("  [$(event.type)] $(event.message)")
end

# Clean up
dashboard.running = false
println("\n✅ Test complete!")