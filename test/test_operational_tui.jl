#!/usr/bin/env julia

# Test script for the operational TUI

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

# Load config
config = NumeraiTournament.load_config("config.toml")

println("Starting operational TUI test...")
println("Press Ctrl+C to exit")
println()

# Run the operational dashboard directly
NumeraiTournament.run_operational_dashboard(config)