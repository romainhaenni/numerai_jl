#!/usr/bin/env julia
"""
Tournament ID Configuration Demo

This script demonstrates how to use the new tournament_id configuration
to support both Numerai Classic (8) and Signals (11) tournaments.
"""

using NumeraiTournament

# Example 1: Using environment variables for Classic tournament (default)
ENV["NUMERAI_PUBLIC_ID"] = "your_public_id"
ENV["NUMERAI_SECRET_KEY"] = "your_secret_key"

# Classic tournament client (default behavior)
classic_client = NumeraiTournament.API.NumeraiClient(
    ENV["NUMERAI_PUBLIC_ID"], 
    ENV["NUMERAI_SECRET_KEY"]
)

# Signals tournament client (explicit)
signals_client = NumeraiTournament.API.NumeraiClient(
    ENV["NUMERAI_PUBLIC_ID"], 
    ENV["NUMERAI_SECRET_KEY"], 
    NumeraiTournament.API.TOURNAMENT_SIGNALS
)

println("Classic Tournament Client - ID: ", classic_client.tournament_id)
println("Signals Tournament Client - ID: ", signals_client.tournament_id)

# Example 2: Using configuration file
# Create a config.toml file with:
# tournament_id = 11  # for Signals
# tournament_id = 8   # for Classic (default)

config = NumeraiTournament.load_config("config.toml")
client_from_config = NumeraiTournament.API.NumeraiClient(
    config.api_public_key, 
    config.api_secret_key, 
    config.tournament_id
)

println("Config-based Client - Tournament ID: ", client_from_config.tournament_id)

# Example 3: Using constants for clarity
using NumeraiTournament.API: TOURNAMENT_CLASSIC, TOURNAMENT_SIGNALS

classic_with_const = NumeraiTournament.API.NumeraiClient(
    "test", "test", TOURNAMENT_CLASSIC
)

signals_with_const = NumeraiTournament.API.NumeraiClient(
    "test", "test", TOURNAMENT_SIGNALS
)

println("Classic with constant: ", classic_with_const.tournament_id)
println("Signals with constant: ", signals_with_const.tournament_id)

println("\nDemo complete! Tournament ID is now configurable for both Classic and Signals tournaments.")