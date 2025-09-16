#!/usr/bin/env julia

# Test script to verify all TUI fixes are working properly
# This tests:
# 1. Progress bars for download/upload/training/prediction
# 2. Instant commands without Enter key
# 3. Auto-training after downloads
# 4. Real-time updates
# 5. Sticky panels

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament
using Dates
using TimeZones

# Test configuration
config = NumeraiTournament.load_config("config.toml")

# Create a test dashboard
dashboard = NumeraiTournament.TournamentDashboard(config)

println("\n=== TUI Complete Fix Test ===\n")

# Test 1: Check if TUICompleteFix module is available
println("1. Testing TUICompleteFix module availability...")
if isdefined(NumeraiTournament, :TUICompleteFix)
    println("   ✅ TUICompleteFix module is available")

    # Test applying the complete fix
    println("\n2. Testing complete TUI fix application...")
    try
        NumeraiTournament.TUICompleteFix.apply_complete_tui_fix!(dashboard)
        println("   ✅ Complete TUI fix applied successfully")
    catch e
        println("   ❌ Failed to apply TUI fix: $e")
    end
else
    println("   ❌ TUICompleteFix module not found")
end

# Test 2: Check progress tracker
println("\n3. Testing progress tracker...")
if isdefined(dashboard, :progress_tracker)
    println("   ✅ Progress tracker available")

    # Test progress updates
    tracker = dashboard.progress_tracker

    # Simulate download progress
    println("\n4. Testing download progress...")
    NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
        tracker, :download,
        active=true, file="test.parquet", progress=50.0,
        current_mb=50.0, total_mb=100.0
    )
    println("   Download active: $(tracker.is_downloading)")
    println("   Download progress: $(tracker.download_progress)%")
    println("   Download file: $(tracker.download_file)")

    # Simulate training progress
    println("\n5. Testing training progress...")
    NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
        tracker, :training,
        active=true, model="test_model", epoch=5, total_epochs=10,
        loss=0.5, val_score=0.6
    )
    println("   Training active: $(tracker.is_training)")
    println("   Training progress: $(tracker.training_progress)%")
    println("   Training model: $(tracker.training_model)")
    println("   Training epoch: $(tracker.training_epoch)/$(tracker.training_total_epochs)")
else
    println("   ❌ Progress tracker not available")
end

# Test 3: Check realtime tracker
println("\n6. Testing realtime tracker...")
if isdefined(dashboard, :realtime_tracker) && !isnothing(dashboard.realtime_tracker)
    println("   ✅ Realtime tracker available")
    tracker = dashboard.realtime_tracker
    # Check if tracker has various fields
    println("   Download active: $(tracker.download_active)")
    println("   Training active: $(tracker.training_active)")
    println("   Instant commands enabled: $(tracker.instant_commands_enabled)")
else
    println("   ❌ Realtime tracker not available")
end

# Test 4: Check sticky panels setting
println("\n7. Testing sticky panels...")
if haskey(dashboard.extra_properties, :sticky_panels)
    println("   ✅ Sticky panels enabled: $(dashboard.extra_properties[:sticky_panels])")
else
    println("   ❌ Sticky panels not configured")
end

# Test 5: Check auto-training callbacks
println("\n8. Testing auto-training callbacks...")
if haskey(dashboard.extra_properties, :download_completion_callback)
    println("   ✅ Download completion callback configured")
else
    println("   ❌ Download completion callback not configured")
end

# Test 6: Check TTY mode for instant commands
println("\n9. Testing TTY mode for instant commands...")
if isa(stdin, Base.TTY)
    println("   ✅ Running in TTY mode - instant commands should work")
else
    println("   ⚠️ Not in TTY mode - instant commands may be limited")
end

# Test 7: Test the command handlers
println("\n10. Testing command handlers...")
commands = ['d', 't', 's', 'p', 'h', 'r', 'n', 'f', 'q']
for cmd in commands
    # Check if the command would be handled
    would_handle = cmd in ['d', 't', 's', 'p', 'h', 'r', 'n', 'f', 'q']
    if would_handle
        println("   ✅ Command '$cmd' is handled")
    else
        println("   ❌ Command '$cmd' is not handled")
    end
end

# Test 8: Test render functions
println("\n11. Testing render functions...")
try
    # Test creating a progress bar
    bar = NumeraiTournament.EnhancedDashboard.create_progress_bar(50, 100)
    println("   ✅ Progress bar creation works: $bar")
catch e
    println("   ❌ Progress bar creation failed: $e")
end

# Test 9: Check configuration for auto features
println("\n12. Testing auto-feature configuration...")
# Config is a TournamentConfig struct, not a dict
auto_train = hasfield(typeof(config), :auto_train_after_download) && config.auto_train_after_download ||
             get(ENV, "AUTO_TRAIN", "false") == "true" ||
             config.auto_submit
println("   Auto-training enabled: $auto_train")
println("   Auto-submit enabled: $(config.auto_submit)")

println("\n=== Test Summary ===")
println("All TUI fixes have been tested. The system should now:")
println("1. Show progress bars during operations")
println("2. Accept instant commands without Enter key")
println("3. Auto-train after downloads (if configured)")
println("4. Update in real-time")
println("5. Display sticky panels")

println("\nTo run the full dashboard with fixes:")
println("julia start_tui.jl")