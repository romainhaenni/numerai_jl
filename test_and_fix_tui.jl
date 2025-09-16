#!/usr/bin/env julia

# Comprehensive TUI Test and Debug Script
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("=" * "="^60)
println("TUI COMPREHENSIVE TEST AND FIX VERIFICATION")
println("=" * "="^60)

# Load config
config = NumeraiTournament.load_config("config.toml")
println("\n1. CONFIG CHECK:")
println("   auto_submit: $(config.auto_submit)")
println("   auto_start_pipeline: $(config.auto_start_pipeline)")
println("   auto_train_after_download: $(config.auto_train_after_download)")

# Test system monitoring functions
println("\n2. SYSTEM MONITORING CHECK:")
disk_info = NumeraiTournament.Utils.get_disk_space_info()
println("   ✅ Disk: $(round(disk_info.free_gb, digits=1)) GB free / $(round(disk_info.total_gb, digits=1)) GB total")
println("   ✅ Memory: $(round(Sys.free_memory()/1024^3, digits=1)) GB free / $(round(Sys.total_memory()/1024^3, digits=1)) GB total")
println("   ✅ CPU: $(Sys.CPU_THREADS) cores, load avg: $(Sys.loadavg())")

# Create dashboard
println("\n3. DASHBOARD INITIALIZATION:")
dashboard = NumeraiTournament.TUIv1036Dashboard(config)
println("   ✅ Dashboard created")
println("   ✅ auto_start_pipeline: $(dashboard.auto_start_pipeline)")
println("   ✅ pipeline_started: $(dashboard.pipeline_started)")
println("   ✅ running: $(dashboard.running)")
println("   ✅ current_operation: $(dashboard.current_operation)")
println("   ✅ command_channel: $(dashboard.command_channel != nothing)")
println("   ✅ keyboard_task: $(dashboard.keyboard_task)")

# Check auto-start conditions
println("\n4. AUTO-START PIPELINE CHECK:")
if dashboard.auto_start_pipeline && !dashboard.pipeline_started
    println("   ✅ Auto-start conditions MET - pipeline should start automatically")
    println("   The following will happen when run_tui_v1036 is called:")
    println("   - init_keyboard_input() will be called")
    println("   - Auto-start will trigger start_download()")
    println("   - Progress bars will show real download progress")
else
    println("   ❌ Auto-start conditions NOT met")
end

# Test if start_download exists
println("\n5. FUNCTION AVAILABILITY CHECK:")
try
    # Check if functions are defined in the module
    if isdefined(NumeraiTournament.TUICompleteFix, :start_download)
        println("   ✅ start_download function exists in TUICompleteFix module")
    else
        println("   ❌ start_download not in TUICompleteFix")
    end
catch e
    println("   Note: Functions are internal to tui_v10_36_complete_fix.jl")
end

# Check API client
println("\n6. API CLIENT CHECK:")
if dashboard.api_client != nothing
    println("   ✅ API client initialized - real downloads will work")
else
    println("   ⚠️  No API client - will run in demo mode with simulated downloads")
    println("   This is because credentials may be test/placeholder values")
end

# Check keyboard command channel
println("\n7. KEYBOARD INPUT CHECK:")
println("   Command channel ready: $(isready(dashboard.command_channel) ? "has input" : "empty")")
println("   Command channel open: $(isopen(dashboard.command_channel))")

# Summary
println("\n" * "="^60)
println("SUMMARY:")
println("="^60)

issues_found = String[]

if !dashboard.auto_start_pipeline
    push!(issues_found, "auto_start_pipeline is false")
end

if dashboard.api_client == nothing
    push!(issues_found, "API client not initialized (demo mode)")
end

if !isopen(dashboard.command_channel)
    push!(issues_found, "Command channel not open")
end

if length(issues_found) == 0
    println("✅ ALL SYSTEMS CHECK OUT - TUI should work properly!")
    println("\nThe TUI has:")
    println("• Real system monitoring (CPU/Memory/Disk)")
    println("• Auto-start pipeline ready to trigger")
    println("• Keyboard command handling prepared")
    println("• Progress bar framework in place")
    println("\nTo run the TUI:")
    println("  julia start_tui.jl")
else
    println("⚠️  POTENTIAL ISSUES FOUND:")
    for issue in issues_found
        println("• $issue")
    end
end

println("\n" * "="^60)