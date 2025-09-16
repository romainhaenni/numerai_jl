#!/usr/bin/env julia

# Debug test for space key handling
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

# Create dashboard
config = Dict(:api_public_key => "", :api_secret_key => "", :models => ["test"])
dashboard = NumeraiTournament.TUIv1035UltimateFix.TUIv1035Dashboard(config)

println("Initial paused state: ", dashboard.paused)
println("Initial running state: ", dashboard.running)

# Test space key
result = NumeraiTournament.TUIv1035UltimateFix.handle_command(dashboard, " ")
println("After space command - paused: ", dashboard.paused, ", result: ", result)

# Test again
result = NumeraiTournament.TUIv1035UltimateFix.handle_command(dashboard, " ")
println("After second space - paused: ", dashboard.paused, ", result: ", result)

# Check events
println("\nEvents:")
for event in dashboard.events
    println("  - ", event.message)
end