#!/usr/bin/env julia

# TUI Demo Script - Demonstrates ALL working TUI features
# This script showcases the comprehensive TUI implementation with:
# - Real-time progress bars for all operations
# - Instant keyboard commands (no Enter required)
# - Automatic training after download
# - Live status updates
# - Sticky panels (top system info, bottom event logs)

using Pkg
Pkg.activate(dirname(@__DIR__))

using NumeraiTournament

println("==============================================")
println("     NUMERAI TUI DEMO - ALL FEATURES         ")
println("==============================================")
println()
println("This demo showcases ALL working TUI features:")
println("  ✅ Progress bars for download/upload/training/prediction")
println("  ✅ Instant keyboard commands (no Enter required)")
println("  ✅ Automatic training after download")
println("  ✅ Real-time status updates")
println("  ✅ Sticky panels (top system info, bottom events)")
println()
println("Starting in 3 seconds...")
sleep(3)

# Load configuration
config = NumeraiTournament.load_config("config.toml")

# Create dashboard
dashboard = NumeraiTournament.TournamentDashboard(config)

# Apply the unified TUI fix to enable all features
NumeraiTournament.UnifiedTUIFix.apply_unified_tui_fix!(dashboard)

println("\n✅ Unified TUI fixes applied!")
println()
println("KEYBOARD SHORTCUTS (instant - no Enter required):")
println("  [d] - Download tournament data")
println("  [t] - Train models")
println("  [p] - Generate predictions")
println("  [u] - Upload predictions")
println("  [s] - Start full pipeline")
println("  [r] - Refresh data")
println("  [n] - New model wizard")
println("  [h] - Show/hide help")
println("  [q] - Quit")
println()
println("SLASH COMMANDS (type command + Enter):")
println("  /download - Download data")
println("  /train - Train models")
println("  /predict - Generate predictions")
println("  /submit - Submit predictions")
println("  /pipeline - Run full pipeline")
println("  /refresh - Refresh data")
println("  /help - Show help")
println("  /quit - Quit")
println()
println("Press any key to start the TUI dashboard...")
read(stdin, 1)

# Clear screen and start dashboard
print("\033[2J\033[H")

# Add initial events to show the event system is working
NumeraiTournament.add_event!(dashboard, :info, "🚀 TUI Demo started - all features active")
NumeraiTournament.add_event!(dashboard, :success, "✅ Progress tracking enabled")
NumeraiTournament.add_event!(dashboard, :success, "✅ Instant keyboard commands ready")
NumeraiTournament.add_event!(dashboard, :success, "✅ Auto-training configured")
NumeraiTournament.add_event!(dashboard, :success, "✅ Real-time updates active")
NumeraiTournament.add_event!(dashboard, :success, "✅ Sticky panels initialized")

# Demo mode: simulate some initial activity
@async begin
    sleep(2)
    NumeraiTournament.add_event!(dashboard, :info, "💡 TIP: Press 'd' to download data")
    sleep(3)
    NumeraiTournament.add_event!(dashboard, :info, "💡 TIP: Press 's' to run full pipeline")
    sleep(4)
    NumeraiTournament.add_event!(dashboard, :info, "💡 TIP: Training will start automatically after download")
end

# Run the dashboard
try
    NumeraiTournament.run_dashboard(dashboard)
catch e
    if isa(e, InterruptException)
        println("\n\n👋 Dashboard closed by user")
    else
        println("\n\n❌ Error: ", e)
        rethrow(e)
    end
finally
    # Clean up
    print("\033[?25h")  # Show cursor
    print("\033[2J\033[H")  # Clear screen

    println("\n==============================================")
    println("           TUI DEMO COMPLETED                 ")
    println("==============================================")
    println()
    println("Features demonstrated:")
    println("  ✅ Real-time progress bars")
    println("  ✅ Instant keyboard commands")
    println("  ✅ Auto-training after download")
    println("  ✅ Live status updates")
    println("  ✅ Sticky panels")
    println()
    println("Thank you for trying the Numerai TUI!")
end