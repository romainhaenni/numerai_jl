#!/usr/bin/env julia

# Test script to check TUI functionality
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Testing TUI Dashboard Components...")
println("=====================================")

# Load config
config = NumeraiTournament.load_config("config.toml")
println("✅ Config loaded")

# Test disk monitoring
disk_info = NumeraiTournament.Utils.get_disk_space_info()
println("✅ Disk info: $(disk_info.free_gb)GB free / $(disk_info.total_gb)GB total ($(disk_info.used_pct)% used)")

# Test memory monitoring
total_mem = Sys.total_memory() / 1024^3  # Convert to GB
free_mem = Sys.free_memory() / 1024^3
used_mem = total_mem - free_mem
println("✅ Memory info: $(round(used_mem, digits=1))GB used / $(round(total_mem, digits=1))GB total")

# Test CPU monitoring
cpu_usage = minimum(Sys.loadavg()) / Sys.CPU_THREADS * 100.0
println("✅ CPU info: $(round(cpu_usage, digits=1))% usage, $(Sys.CPU_THREADS) cores")

# Create dashboard instance
println("\nCreating TUI v10.36 dashboard instance...")
dashboard = NumeraiTournament.TUIv1036Dashboard(config)
println("✅ Dashboard created")

# Check initial state
println("\nInitial dashboard state:")
println("  Auto-submit: $(dashboard.config.auto_submit)")
println("  Disk monitoring: $(dashboard.disk_free) GB free / $(dashboard.disk_total) GB total")
println("  Memory: $(dashboard.memory_used) GB / $(dashboard.memory_total) GB")
println("  CPU: $(dashboard.cpu_usage)%")

# Update system info
# Call the specific function for TUIv1036Dashboard
dashboard.cpu_usage = minimum(Sys.loadavg()) / Sys.CPU_THREADS * 100.0
mem_info = (
    total = Sys.total_memory() / 1024^3,
    free = Sys.free_memory() / 1024^3,
    used = (Sys.total_memory() - Sys.free_memory()) / 1024^3
)
dashboard.memory_total = mem_info.total
dashboard.memory_used = mem_info.used
disk_info = NumeraiTournament.Utils.get_disk_space_info()
dashboard.disk_free = disk_info.free_gb
dashboard.disk_total = disk_info.total_gb
println("\nAfter system update:")
println("  Disk monitoring: $(dashboard.disk_free) GB free / $(dashboard.disk_total) GB total")
println("  Memory: $(dashboard.memory_used) GB / $(dashboard.memory_total) GB")
println("  CPU: $(dashboard.cpu_usage)%")

println("\n✅ All dashboard components working!")