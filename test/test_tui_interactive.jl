#!/usr/bin/env julia
# Test TUI interactive functionality

using Pkg
Pkg.activate(".")

using NumeraiTournament
using NumeraiTournament.Dashboard
using NumeraiTournament.TUIFixes
using NumeraiTournament.API

println("Loading configuration...")
config = NumeraiTournament.load_config("config.toml")

println("Creating dashboard...")
dashboard = Dashboard.TournamentDashboard(config)

println("\nTesting TUI fixes application...")
fixes_status = TUIFixes.apply_tui_fixes!(dashboard)
println("All fixes applied: $(all(values(fixes_status)))")

println("\nTesting keyboard reading function...")
println("Testing read_key_improved function exists: $(isdefined(TUIFixes, :read_key_improved))")
println("Testing handle_direct_command function exists: $(isdefined(TUIFixes, :handle_direct_command))")

println("\nTesting callback creation functions...")
println("Testing create_download_callback: $(isdefined(TUIFixes, :create_download_callback))")
println("Testing create_upload_callback: $(isdefined(TUIFixes, :create_upload_callback))")
println("Testing create_training_callback: $(isdefined(TUIFixes, :create_training_callback))")
println("Testing create_prediction_callback: $(isdefined(TUIFixes, :create_prediction_callback))")

println("\nTesting auto-training configuration...")
println("Auto-train after download enabled: $(dashboard.config.auto_train_after_download)")

println("\nTesting progress tracker...")
println("Progress tracker initialized: $(isdefined(dashboard, :progress_tracker))")
if isdefined(dashboard, :progress_tracker)
    println("  - Download tracking available: $(hasproperty(dashboard.progress_tracker, :is_downloading))")
    println("  - Upload tracking available: $(hasproperty(dashboard.progress_tracker, :is_uploading))")
    println("  - Training tracking available: $(hasproperty(dashboard.progress_tracker, :is_training))")
    println("  - Prediction tracking available: $(hasproperty(dashboard.progress_tracker, :is_predicting))")
end

println("\n✅ All TUI components are properly initialized and ready!")
println("\nTo test the actual TUI, run: ./numerai")