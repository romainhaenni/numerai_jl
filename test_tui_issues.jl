#!/usr/bin/env julia

# Test script to verify TUI functionality issues
using Pkg
Pkg.activate(@__DIR__)

println("=" ^ 60)
println("Testing TUI Functionality Issues")
println("=" ^ 60)

# Load module
using NumeraiTournament
using NumeraiTournament.Utils

# Test 1: Check if module loads and functions exist
println("\n1. Module Loading Test:")
println("   ✓ Module loaded successfully")
println("   Functions available: ", :run_tui_v1043 in names(NumeraiTournament))

# Test 2: Disk Space Monitoring
println("\n2. Disk Space Monitoring Test:")
disk_info = Utils.get_disk_space_info()
println("   Free: $(disk_info.free_gb) GB")
println("   Total: $(disk_info.total_gb) GB")
println("   Used: $(disk_info.used_gb) GB ($(disk_info.used_pct)%)")
if disk_info.total_gb > 0
    println("   ✓ Disk monitoring returns real values")
else
    println("   ✗ Disk monitoring returns zeros")
end

# Test 3: System Monitoring
println("\n3. System Monitoring Test:")
cpu_usage = Utils.get_cpu_usage()
mem_info = Utils.get_memory_info()
println("   CPU Usage: $(round(cpu_usage, digits=1))%")
println("   Memory: $(mem_info.used_gb)/$(mem_info.total_gb) GB ($(mem_info.used_pct)%)")
if mem_info.total_gb > 0
    println("   ✓ System monitoring returns real values")
else
    println("   ✗ System monitoring returns zeros")
end

# Test 4: Config Loading
println("\n4. Configuration Test:")
config = NumeraiTournament.load_config("config.toml")
println("   Auto-start enabled: $(config.auto_start_pipeline)")
println("   Auto-train after download: $(config.auto_train_after_download)")
println("   API keys present: $(length(config.api_public_key) > 0 && length(config.api_secret_key) > 0)")
if config.auto_start_pipeline
    println("   ✓ Auto-start pipeline is enabled in config")
else
    println("   ✗ Auto-start pipeline is disabled in config")
end

# Test 5: Check TUI function chain
println("\n5. TUI Function Chain Test:")
if isdefined(NumeraiTournament, :run_tui_v1043)
    println("   ✓ run_tui_v1043 function exists")
else
    println("   ✗ run_tui_v1043 function missing")
end

if isdefined(NumeraiTournament.TUIProductionV047, :create_dashboard)
    println("   ✓ create_dashboard function exists")
else
    println("   ✗ create_dashboard function missing")
end

if isdefined(NumeraiTournament.TUIProductionV047, :run_dashboard)
    println("   ✓ run_dashboard function exists")
else
    println("   ✗ run_dashboard function missing")
end

# Test 6: API Client Creation
println("\n6. API Client Test:")
try
    api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)
    println("   ✓ API client created successfully")

    # Try to get account info
    try
        account = NumeraiTournament.API.get_account(api_client)
        if account !== nothing
            println("   ✓ API connection working")
        else
            println("   ⚠ API returned no account data")
        end
    catch e
        println("   ✗ API connection failed: ", e)
    end
catch e
    println("   ✗ Failed to create API client: ", e)
end

println("\n" * "=" ^ 60)
println("Test Summary:")
println("If all tests pass, the TUI should work correctly.")
println("To start TUI: julia start_tui.jl")
println("=" ^ 60)