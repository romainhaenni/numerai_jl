#!/usr/bin/env julia

# Test script to diagnose TUI issues

using Pkg
Pkg.activate(@__DIR__)

println("\n=== Testing TUI Issues ===\n")

# Load the main module
using NumeraiTournament

println("1. Testing configuration loading...")
config = NumeraiTournament.load_config("config.toml")
println("   - Config loaded: $(typeof(config))")
println("   - Auto-start pipeline: $(config.auto_start_pipeline)")
println("   - Auto-train after download: $(config.auto_train_after_download)")
println("   - Data dir: $(config.data_dir)")

println("\n2. Testing system monitoring functions...")
disk_info = NumeraiTournament.Utils.get_disk_space_info()
println("   - Disk info: Free=$(disk_info.free_gb) GB, Total=$(disk_info.total_gb) GB")

mem_info = NumeraiTournament.Utils.get_memory_info()
println("   - Memory info: Used=$(mem_info.used_gb) GB, Total=$(mem_info.total_gb) GB")

cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
println("   - CPU usage: $(cpu_usage)%")

println("\n3. Testing API client creation...")
try
    api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)
    println("   - API client created successfully")

    # Test API connectivity
    models = NumeraiTournament.API.get_models(api_client)
    println("   - Connected to API, found $(length(models)) models")
    for model in models
        println("     • $(model["name"]) (ID: $(model["id"]))")
    end
catch e
    println("   - API client error: $e")
end

println("\n4. Testing TUIProduction module...")
using NumeraiTournament.TUIProduction
println("   - TUIProduction module loaded successfully")

println("\n=== All tests completed ===\n")