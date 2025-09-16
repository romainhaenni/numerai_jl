#!/usr/bin/env julia

# Test TUI startup and auto-pipeline
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Testing TUI Startup and Auto-Pipeline...")
println("========================================")

# Load config
config = NumeraiTournament.load_config("config.toml")
println("Config loaded:")
println("  auto_submit: $(config.auto_submit)")
println("  data_dir: $(config.data_dir)")
println("  model_dir: $(config.model_dir)")

# Create dashboard
dashboard = NumeraiTournament.TUIv1036Dashboard(config)
println("\nDashboard created successfully!")
println("  Current operation: $(dashboard.current_operation)")
println("  Auto-submit enabled: $(dashboard.config.auto_submit)")
println("  Auto-train after download: $(dashboard.auto_train_after_download)")

# Check if auto-start works
if dashboard.config.auto_submit
    println("\n✅ Auto-submit is enabled, pipeline should start automatically")
else
    println("\n❌ Auto-submit is disabled in config")
end

# Check keyboard handler
println("\nChecking keyboard setup...")
println("  Keyboard task: $(dashboard.keyboard_task != nothing ? "initialized" : "not initialized")")
println("  Command channel: $(dashboard.command_channel != nothing ? "initialized" : "not initialized")")

# Check progress tracking
println("\nChecking progress tracking setup...")
println("  Operation progress: $(dashboard.operation_progress) / $(dashboard.operation_total)")
println("  Current operation: $(dashboard.current_operation)")
println("  Operation description: $(dashboard.operation_description)")

# Check if download_data_internal exists or if it uses start_download
println("\nChecking function implementations...")
if isdefined(NumeraiTournament, :start_download)
    println("  ✅ start_download function exists")
else
    println("  ❌ start_download function not found")
end

if isdefined(NumeraiTournament, :download_data_internal)
    println("  ⚠️  download_data_internal exists (old broken function)")
else
    println("  ✅ download_data_internal not defined (good, should use start_download)")
end

println("\n✅ TUI startup test complete!")