#!/usr/bin/env julia

# Start the Numerai Tournament TUI Dashboard
# Usage: julia start_tui.jl [options]

using Pkg
Pkg.activate(@__DIR__)

# Parse command line arguments
headless = "--headless" in ARGS || "-h" in ARGS
download_only = "--download" in ARGS || "-d" in ARGS
train_only = "--train" in ARGS || "-t" in ARGS
submit_only = "--submit" in ARGS || "-s" in ARGS
performance_only = "--performance" in ARGS || "-p" in ARGS

# Load the main module
using NumeraiTournament

if download_only
    println("Downloading tournament data...")
    NumeraiTournament.download_tournament_data()
elseif train_only
    println("Training models...")
    NumeraiTournament.train_all_models()
elseif submit_only
    println("Submitting predictions...")
    NumeraiTournament.submit_predictions()
elseif performance_only
    println("Fetching model performance...")
    NumeraiTournament.show_performance()
elseif headless
    println("Starting in headless mode...")
    NumeraiTournament.run_headless()
else
    # Start the TUI dashboard v0.10.41 - COMPLETE FIX with ALL issues resolved
    println("Starting Numerai Tournament TUI Dashboard v0.10.41 - ALL ISSUES FIXED...")
    println("✅ FIXED: Configuration extraction from TournamentConfig struct")
    println("✅ FIXED: Real system monitoring with actual CPU/memory/disk values")
    println("✅ FIXED: Instant keyboard command response (raw mode)")
    println("✅ FIXED: Enhanced progress bars with MB/percentage displays")
    println("✅ FIXED: Auto-training automatically starts after downloads complete")
    println("✅ FIXED: Auto-start pipeline on startup when configured")
    println("✅ FIXED: Regular system info updates every 3 seconds")
    println("Tip: For best performance, run with multiple threads: julia -t auto start_tui.jl")

    # Load config and run the fixed dashboard
    config = NumeraiTournament.load_config("config.toml")
    NumeraiTournament.run_tui_v1041(config)
end