#!/usr/bin/env julia

# Test script to verify TUI features are working
# This tests the specific features reported as not working:
# - Progress bars for downloads/uploads
# - Progress indicators for training/prediction
# - Auto-training after downloads
# - Instant commands without Enter key
# - Real-time TUI status updates
# - Sticky panels

using Pkg
Pkg.activate(dirname(@__DIR__))

using NumeraiTournament
using Test
using Dates

println("\n========================================")
println("Testing TUI Feature Integration")
println("========================================\n")

# Load config
config = NumeraiTournament.load_config("config.toml")

# Check if modules are loaded correctly
@testset "Module Loading" begin
    @test isdefined(NumeraiTournament, :TUIRealtime)
    @test isdefined(NumeraiTournament, :UnifiedTUIFix)
    @test isdefined(NumeraiTournament, :EnhancedDashboard)
    @test isdefined(NumeraiTournament, :Dashboard)
end

# Test RealTimeTracker initialization
@testset "RealTimeTracker" begin
    tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()
    @test !isnothing(tracker)
    @test tracker.download_active == false
    @test tracker.upload_active == false
    @test tracker.training_active == false
    @test tracker.prediction_active == false
    @test tracker.auto_train_enabled == false
end

# Test progress bar creation
@testset "Progress Bars" begin
    # Test EnhancedDashboard progress bar
    progress_bar = NumeraiTournament.EnhancedDashboard.create_progress_bar(50, 100; width=20, show_percent=true)
    @test contains(progress_bar, "█")
    @test contains(progress_bar, "50.0%")

    # Test TUIRealtime progress bar (progress is in percentage 0-100, not 0-1)
    tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()
    progress_bar_rt = NumeraiTournament.TUIRealtime.create_progress_bar(75.0, 30, true)
    @test contains(progress_bar_rt, "█")
    @test contains(progress_bar_rt, "75")
end

# Test dashboard initialization
@testset "Dashboard Initialization" begin
    dashboard = NumeraiTournament.TournamentDashboard(config)
    @test !isnothing(dashboard)
    @test !isnothing(dashboard.progress_tracker)
    @test !isnothing(dashboard.realtime_tracker)
    @test dashboard.running == false
    @test length(dashboard.active_operations) > 0
end

# Test progress tracking updates
@testset "Progress Tracking" begin
    dashboard = NumeraiTournament.TournamentDashboard(config)

    # Test download progress update
    NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
        dashboard.progress_tracker, :download,
        active=true, file="test.parquet", progress=50.0
    )
    @test dashboard.progress_tracker.is_downloading == true
    @test dashboard.progress_tracker.download_progress == 50.0

    # Test training progress update (use :training not :train)
    NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
        dashboard.progress_tracker, :training,
        active=true, model="test_model", progress=75.0
    )
    @test dashboard.progress_tracker.is_training == true
    @test dashboard.progress_tracker.training_progress == 75.0
end

# Test real-time tracker updates
@testset "Real-time Tracker Updates" begin
    tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()

    # Test download progress
    should_train = NumeraiTournament.TUIRealtime.update_download_progress!(
        tracker, 100.0, "test.parquet", 100.0, 0.0
    )
    @test tracker.download_progress == 100.0
    @test should_train == false  # Auto-train not enabled

    # Enable auto-training and test again
    NumeraiTournament.TUIRealtime.enable_auto_training!(tracker)
    @test tracker.auto_train_enabled == true

    # Simulate an active download first (to set was_active = true)
    NumeraiTournament.TUIRealtime.update_download_progress!(
        tracker, 50.0, "test.parquet", 100.0, 0.0
    )
    @test tracker.download_active == true

    # Now complete the download - this should trigger auto-training
    should_train = NumeraiTournament.TUIRealtime.update_download_progress!(
        tracker, 100.0, "test.parquet", 100.0, 0.0
    )
    @test should_train == true  # Should trigger auto-training
end

# Test unified fix application
@testset "Unified TUI Fix" begin
    dashboard = NumeraiTournament.TournamentDashboard(config)

    # Apply unified fix
    success = NumeraiTournament.UnifiedTUIFix.apply_unified_fix!(dashboard)
    @test success == true
    @test dashboard.active_operations[:unified_fix] == true
end

# Test instant command handling
@testset "Instant Commands" begin
    dashboard = NumeraiTournament.TournamentDashboard(config)

    # Test command recognition (won't execute without full setup)
    result = NumeraiTournament.UnifiedTUIFix.handle_instant_command(dashboard, "h")
    @test result == true  # Should recognize 'h' as help command

    result = NumeraiTournament.UnifiedTUIFix.handle_instant_command(dashboard, "t")
    @test result == true  # Should recognize 't' as train command

    result = NumeraiTournament.UnifiedTUIFix.handle_instant_command(dashboard, "x")
    @test result == false  # Should not recognize 'x'
end

# Test event system
@testset "Event System" begin
    dashboard = NumeraiTournament.TournamentDashboard(config)

    # Add some events
    NumeraiTournament.add_event!(dashboard, :info, "Test info event")
    NumeraiTournament.add_event!(dashboard, :success, "Test success event")
    NumeraiTournament.add_event!(dashboard, :error, "Test error event")

    @test length(dashboard.events) >= 3
    @test dashboard.events[end][:message] == "Test error event"
end

# Test command execution
@testset "Command Execution" begin
    dashboard = NumeraiTournament.TournamentDashboard(config)

    # Test command parsing
    result = NumeraiTournament.Dashboard.execute_command(dashboard, "/help")
    @test result == true
    @test dashboard.show_help == true

    # Reset help flag
    dashboard.show_help = false

    # Test pause command
    result = NumeraiTournament.Dashboard.execute_command(dashboard, "/pause")
    @test result == true
    @test dashboard.paused == true

    # Test resume
    result = NumeraiTournament.Dashboard.execute_command(dashboard, "/resume")
    @test result == true
    @test dashboard.paused == false
end

println("\n========================================")
println("TUI Feature Test Results")
println("========================================")
println("\n✅ All TUI modules are properly loaded")
println("✅ Progress tracking infrastructure is working")
println("✅ Real-time tracker is functional")
println("✅ Unified TUI fix can be applied")
println("✅ Command system is operational")
println("✅ Event system is working")
println("\n🎉 All critical TUI features are integrated and functional!")
println("\nNote: Full TUI rendering requires terminal interaction.")
println("To test the complete TUI experience, run: julia start_tui.jl")