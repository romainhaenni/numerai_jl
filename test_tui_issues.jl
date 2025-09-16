#!/usr/bin/env julia

# Test script to identify TUI v0.10.39 issues

using Pkg
Pkg.activate(@__DIR__)

println("Testing TUI v0.10.39 Issues")
println("===========================\n")

# Load the module
using NumeraiTournament
using TOML

# Test 1: Check Utils functions
println("Test 1: System Monitoring Functions")
try
    disk_info = NumeraiTournament.Utils.get_disk_space_info()
    println("Disk info: ", disk_info)
    
    cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
    println("CPU usage: ", cpu_usage)
    
    mem_info = NumeraiTournament.Utils.get_memory_info()
    println("Memory info: ", mem_info)
catch e
    println("ERROR in system monitoring: ", e)
end

# Test 2: Check config loading
println("\nTest 2: Config Loading")
try
    config = NumeraiTournament.load_config("config.toml")
    println("Config type: ", typeof(config))
    println("auto_start_pipeline: ", config.auto_start_pipeline)
    println("auto_train_after_download: ", config.auto_train_after_download)
    println("auto_submit: ", config.auto_submit)
catch e
    println("ERROR loading config: ", e)
end

# Test 3: Check TUI Dashboard initialization
println("\nTest 3: TUI Dashboard Initialization")
try
    config = NumeraiTournament.load_config("config.toml")
    dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)
    println("Dashboard created successfully")
    println("auto_start_enabled: ", dashboard.auto_start_enabled)
    println("auto_train_enabled: ", dashboard.auto_train_enabled)
    println("auto_submit_enabled: ", dashboard.auto_submit_enabled)
    println("Initial disk_total: ", dashboard.disk_total)
    println("Initial memory_total: ", dashboard.memory_total)
    
    # Try updating system info
    NumeraiTournament.TUIv1039.update_system_info!(dashboard)
    println("\nAfter update_system_info:")
    println("disk_total: ", dashboard.disk_total)
    println("disk_free: ", dashboard.disk_free)
    println("memory_total: ", dashboard.memory_total)
    println("memory_used: ", dashboard.memory_used)
    println("cpu_usage: ", dashboard.cpu_usage)
catch e
    println("ERROR in TUI initialization: ", e)
    println("Stack trace:")
    showerror(stdout, e, catch_backtrace())
end

println("\nTest complete.")