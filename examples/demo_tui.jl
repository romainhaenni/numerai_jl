#!/usr/bin/env julia

"""
Demo script for the Working TUI Dashboard

This demonstrates all the new features:
- Progress bars during operations
- Instant commands (no Enter key needed)
- Auto-training after downloads
- Real-time system updates
- Sticky panels (top system info, bottom events)

Usage:
    julia --project=. examples/demo_tui.jl
"""

using Pkg
Pkg.activate(@__DIR__ * "/..")

using NumeraiTournament
using NumeraiTournament.TUIWorking

println("""
╔══════════════════════════════════════════════════════════════════════════════╗
║                      Numerai TUI Dashboard Demo                              ║
║                           Version 0.10.31                                    ║
╚══════════════════════════════════════════════════════════════════════════════╝

This demo will showcase the new TUI features:

✅ Progress Bars
   - Real progress tracking for downloads, uploads, training, and predictions
   - Both determinate (percentage) and indeterminate (spinner) progress

✅ Instant Commands
   - Single key press triggers commands immediately (no Enter needed)
   - Commands: [d]ownload, [t]rain, [s]ubmit, [p]redict, [r]efresh, [q]uit

✅ Auto-Training
   - Automatically starts training after all datasets are downloaded
   - Configurable via auto_train_after_download setting

✅ Real-Time Updates
   - System info (CPU, memory, disk) updates every second
   - Live progress tracking during operations

✅ Sticky Panels
   - Top panel: System status always visible
   - Bottom panel: Last 30 events with timestamps

Press any key to start the demo...
""")

readline()

# Create a demo config
config = NumeraiTournament.load_config("config.toml")

println("\nStarting TUI Dashboard...")
println("Try these commands:")
println("  • Press 'd' to simulate downloads (watch the progress bars!)")
println("  • Press 't' to simulate training")
println("  • Press 's' to simulate submission")
println("  • Press 'r' to refresh system info")
println("  • Press 'q' to quit")
println("\nNote: Commands work instantly without pressing Enter!")
println("\nStarting in 3 seconds...")
sleep(3)

# Run the working dashboard
NumeraiTournament.TUIWorking.run_working_dashboard(config)