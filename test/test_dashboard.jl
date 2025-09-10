#!/usr/bin/env julia

# Test script to verify dashboard works with fixes
using Pkg
Pkg.activate(@__DIR__)

# Force recompilation
println("Force recompiling NumeraiTournament...")
Pkg.precompile()

push!(LOAD_PATH, joinpath(@__DIR__, "src"))

using NumeraiTournament

println("\n=== Testing Dashboard Creation ===")

# Load config
config = NumeraiTournament.load_config("config.toml")

println("Config loaded successfully")
println("Models: ", config.models)

# Create dashboard
println("\n=== Creating Dashboard ===")
dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
println("✅ Dashboard created successfully")

# Test rendering
println("\n=== Testing Render Function ===")
try
    NumeraiTournament.Dashboard.render(dashboard)
    println("✅ Render completed successfully")
catch e
    println("❌ Render failed with error:")
    println(e)
    println("\nStack trace:")
    for (exc, bt) in Base.catch_stack()
        showerror(stdout, exc, bt)
        println()
    end
end

println("\n=== Testing complete ===")