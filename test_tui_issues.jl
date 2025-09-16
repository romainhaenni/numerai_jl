#!/usr/bin/env julia
# Test script to verify TUI functionality and diagnose issues

using Pkg
Pkg.activate(".")

# Load the main module
using NumeraiTournament
using Logging

# Set up detailed logging
global_logger(ConsoleLogger(stdout, Logging.Debug))

println("=== Testing TUI v0.10.41 Issues ===\n")

# Test 1: Utils system monitoring functions
println("1. Testing system monitoring functions:")
try
    cpu = NumeraiTournament.Utils.get_cpu_usage()
    println("   CPU Usage: $cpu%")

    mem_info = NumeraiTournament.Utils.get_memory_info()
    println("   Memory: $(mem_info.used_gb)/$(mem_info.total_gb) GB")

    disk_info = NumeraiTournament.Utils.get_disk_space_info()
    println("   Disk: $(disk_info.free_gb)/$(disk_info.total_gb) GB free")

    if cpu == 0.0 || mem_info.total_gb == 0.0 || disk_info.total_gb == 0.0
        println("   ❌ ISSUE: System monitoring returning zero values!")
    else
        println("   ✅ System monitoring returning real values")
    end
catch e
    println("   ❌ ERROR: $e")
end

# Test 2: Configuration loading
println("\n2. Testing configuration loading:")
try
    config = NumeraiTournament.load_config("config.toml")
    println("   Config type: $(typeof(config))")

    # Check if we can access the fields
    auto_start = false
    auto_train = false

    try
        auto_start = config.auto_start_pipeline
        println("   auto_start_pipeline: $auto_start")
    catch e
        println("   ❌ Cannot access auto_start_pipeline: $e")
    end

    try
        auto_train = config.auto_train_after_download
        println("   auto_train_after_download: $auto_train")
    catch e
        println("   ❌ Cannot access auto_train_after_download: $e")
    end

    try
        auto_submit = config.auto_submit
        println("   auto_submit: $auto_submit")
    catch e
        println("   ❌ Cannot access auto_submit: $e")
    end

catch e
    println("   ❌ ERROR loading config: $e")
end

# Test 3: Check if TUIv1041Fixed module exists
println("\n3. Testing TUI module availability:")
try
    if isdefined(NumeraiTournament, :TUIv1041Fixed)
        println("   ✅ TUIv1041Fixed module is defined")

        # Check if run function exists
        if isdefined(NumeraiTournament.TUIv1041Fixed, :run_tui_v1041)
            println("   ✅ run_tui_v1041 function exists")
        else
            println("   ❌ run_tui_v1041 function not found")
        end
    else
        println("   ❌ TUIv1041Fixed module not found")
    end
catch e
    println("   ❌ ERROR: $e")
end

# Test 4: Check keyboard input capabilities
println("\n4. Testing terminal capabilities:")
try
    if isa(stdin, Base.TTY)
        println("   ✅ TTY available - raw mode keyboard input possible")
    else
        println("   ⚠️  No TTY - will use line mode (requires Enter)")
    end
catch e
    println("   ❌ ERROR: $e")
end

println("\n=== Test Complete ===")
println("\nTo test the actual TUI, run:")
println("  julia start_tui.jl")
println("\nExpected behavior when TUI works correctly:")
println("  • System info should show real CPU/Memory/Disk values")
println("  • Keyboard commands (d/t/p/s/q) should work instantly")
println("  • Auto-start should begin pipeline if configured")
println("  • Progress bars should appear during operations")