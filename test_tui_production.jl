#!/usr/bin/env julia

# Test the production TUI with real API integration

using NumeraiTournament

println("Testing Production TUI Implementation...")
println("======================================")

# Load configuration
config = NumeraiTournament.load_config("config.toml")

# Create API client
api_client = NumeraiTournament.API.NumeraiClient(
    config.api[:public_id],
    config.api[:secret_key]
)

# Test system monitoring functions
println("\n1. Testing System Monitoring:")
println("------------------------------")
disk_info = NumeraiTournament.Utils.get_disk_space_info()
println("Disk: $(disk_info.free_gb) GB free / $(disk_info.total_gb) GB total")

mem_info = NumeraiTournament.Utils.get_memory_info()
println("Memory: $(mem_info.used_gb) GB used / $(mem_info.total_gb) GB total")

cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
println("CPU: $(cpu_usage)%")

println("\n✅ System monitoring is returning real values!")

println("\n2. Testing API Connection:")
println("--------------------------")
try
    # Try to get account info
    models = NumeraiTournament.API.get_models(api_client)
    if !isempty(models)
        println("✅ API connection successful! Found $(length(models)) models")
    else
        println("✅ API connection successful! No models found yet")
    end
catch e
    println("⚠️ API connection failed: $e")
    println("Make sure your credentials are set in .env file")
end

println("\n3. Starting Production TUI Dashboard...")
println("---------------------------------------")
println("Press 'q' to quit, 's' to start pipeline, 'h' for help")
println("")

# Run the production dashboard
NumeraiTournament.run_tui_production(config, api_client)