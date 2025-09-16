#!/usr/bin/env julia

"""
Demo script showing the working TUI with all features fixed.

This demonstrates:
- Progress bars during downloads
- Instant single-key commands
- Auto-training after downloads
- Real-time system info updates
- Sticky panels

Usage:
    julia --project=. examples/demo_tui_fixed.jl

Available commands (single keypress, no Enter needed):
    d - Download datasets
    t - Train models
    p - Generate predictions
    s - Submit predictions
    r - Refresh system info
    q - Quit
"""

using NumeraiTournament

# Load configuration
config = NumeraiTournament.load_config("config.toml")

# Initialize API client
println("Initializing Numerai API client...")
api_client = NumeraiTournament.API.NumeraiClient(
    ENV["NUMERAI_PUBLIC_ID"],
    ENV["NUMERAI_SECRET_KEY"]
)

println("""
╔════════════════════════════════════════════════════════════════╗
║           Numerai TUI Dashboard - FIXED VERSION                 ║
║                                                                  ║
║  All TUI features are now working:                             ║
║  • Progress bars show during all operations                    ║
║  • Single keypress commands (no Enter needed)                  ║
║  • Auto-training triggers after downloads                      ║
║  • Real-time system info updates                               ║
║  • Sticky panels (top: system, bottom: events)                 ║
║                                                                  ║
║  Commands: [d]ownload [t]rain [p]redict [s]ubmit [r]efresh [q]uit ║
╚════════════════════════════════════════════════════════════════╝
""")

println("\nStarting TUI dashboard...")
sleep(1)

# Run the fixed dashboard
NumeraiTournament.TUIFixed.run_fixed_dashboard(config, api_client)