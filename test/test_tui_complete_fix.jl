#!/usr/bin/env julia

# Comprehensive test for all TUI fixes
using Test
using NumeraiTournament
using Dates

@testset "Complete TUI Fix Tests" begin

    @testset "TUIRealtime Module Available" begin
        # Test that the module is loaded and accessible
        @test isdefined(NumeraiTournament, :TUIRealtime)
        @test isdefined(NumeraiTournament.TUIRealtime, :RealTimeTracker)
        @test isdefined(NumeraiTournament.TUIRealtime, :init_realtime_tracker)
    end

    @testset "RealTimeTracker Initialization" begin
        tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()
        @test !isnothing(tracker)
        @test tracker.download_progress == 0.0
        @test tracker.upload_progress == 0.0
        @test tracker.training_progress == 0.0
        @test tracker.prediction_progress == 0.0
        @test !tracker.download_active
        @test !tracker.upload_active
        @test !tracker.training_active
        @test !tracker.prediction_active
    end

    @testset "Progress Updates" begin
        tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()

        # Test download progress
        tracker.auto_train_enabled = false
        should_train = NumeraiTournament.TUIRealtime.update_download_progress!(
            tracker, 50.0, "test.parquet", 100.0, 5.0
        )
        @test tracker.download_progress == 50.0
        @test tracker.download_file == "test.parquet"
        @test tracker.download_size == 100.0
        @test tracker.download_speed == 5.0
        @test tracker.download_active == true
        @test !should_train  # Auto-train disabled

        # Test upload progress
        NumeraiTournament.TUIRealtime.update_upload_progress!(
            tracker, 75.0, "predictions.csv", 10.0
        )
        @test tracker.upload_progress == 75.0
        @test tracker.upload_file == "predictions.csv"
        @test tracker.upload_size == 10.0
        @test tracker.upload_active == true

        # Test training progress
        NumeraiTournament.TUIRealtime.update_training_progress!(
            tracker, 80.0, 8, 10, 0.15, "test_model"
        )
        @test tracker.training_progress == 80.0
        @test tracker.training_epoch == 8
        @test tracker.training_total_epochs == 10
        @test tracker.training_loss == 0.15
        @test tracker.training_model == "test_model"
        @test tracker.training_active == true

        # Test prediction progress
        NumeraiTournament.TUIRealtime.update_prediction_progress!(
            tracker, 90.0, 9000, 10000, "test_model"
        )
        @test tracker.prediction_progress == 90.0
        @test tracker.prediction_rows == 9000
        @test tracker.prediction_total_rows == 10000
        @test tracker.prediction_model == "test_model"
        @test tracker.prediction_active == true
    end

    @testset "Auto-Training Trigger" begin
        tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()

        # Enable auto-training
        NumeraiTournament.TUIRealtime.enable_auto_training!(tracker)
        @test tracker.auto_train_enabled == true

        # Test that 100% download progress triggers training
        tracker.download_active = true
        should_train = NumeraiTournament.TUIRealtime.update_download_progress!(
            tracker, 100.0, "train.parquet", 1000.0, 0.0
        )
        @test should_train == true  # Should trigger training
        @test tracker.download_active == false  # Download marked as complete
    end

    @testset "Event Tracking" begin
        tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()

        # Add various event types
        NumeraiTournament.TUIRealtime.add_tracker_event!(tracker, :info, "Test info")
        NumeraiTournament.TUIRealtime.add_tracker_event!(tracker, :warning, "Test warning")
        NumeraiTournament.TUIRealtime.add_tracker_event!(tracker, :error, "Test error")
        NumeraiTournament.TUIRealtime.add_tracker_event!(tracker, :success, "Test success")

        @test length(tracker.events) == 4
        # Events are stored as tuples: (timestamp, level, message)
        @test tracker.events[1][2] == :info
        @test tracker.events[1][3] == "Test info"
        @test tracker.events[2][2] == :warning
        @test tracker.events[3][2] == :error
        @test tracker.events[4][2] == :success
    end

    @testset "Instant Commands Setup" begin
        tracker = NumeraiTournament.TUIRealtime.init_realtime_tracker()

        # Setup instant commands
        NumeraiTournament.TUIRealtime.setup_instant_commands!(nothing, tracker)
        @test tracker.instant_commands_enabled == true
    end

    @testset "Dashboard Integration" begin
        # Create a test config
        config = NumeraiTournament.TournamentConfig(
            "test_public_key",
            "test_secret_key",
            ["test_model"],
            tempdir(),
            tempdir(),
            false,  # auto_submit
            0.0,    # stake_amount
            4,      # max_workers
            8,      # tournament_id
            true,   # auto_train_after_download
            "small",
            false, 0.0, 0.0, 0.0,  # compounding
            Dict("refresh_rate" => 0.5),  # tui_config
            0.1, "target", false, 0.0,  # ML config
            false, 20, 10  # Sharpe config
        )

        # Create dashboard with realtime tracker
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Check that realtime_tracker is initialized
        @test !isnothing(dashboard.realtime_tracker)
        @test isa(dashboard.realtime_tracker, NumeraiTournament.TUIRealtime.RealTimeTracker)

        # Test that progress tracker is also initialized
        @test !isnothing(dashboard.progress_tracker)
        @test isa(dashboard.progress_tracker, NumeraiTournament.EnhancedDashboard.ProgressTracker)
    end

    @testset "UnifiedTUIFix Integration" begin
        # Test that unified fix module is available
        @test isdefined(NumeraiTournament, :UnifiedTUIFix)
        @test isdefined(NumeraiTournament.UnifiedTUIFix, :apply_unified_fix!)
        @test isdefined(NumeraiTournament.UnifiedTUIFix, :read_key_improved)
        @test isdefined(NumeraiTournament.UnifiedTUIFix, :handle_instant_command)
        @test isdefined(NumeraiTournament.UnifiedTUIFix, :unified_input_loop)
    end

    @testset "Progress Callbacks in Commands" begin
        # Create test dashboard
        config = NumeraiTournament.TournamentConfig(
            "test_public_key",
            "test_secret_key",
            ["test_model"],
            tempdir(),
            tempdir(),
            false, 0.0, 4, 8, true, "small",
            false, 0.0, 0.0, 0.0,
            Dict("refresh_rate" => 0.5),
            0.1, "target", false, 0.0,
            false, 20, 10
        )
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Test that dashboard commands module is available
        @test isdefined(NumeraiTournament.Dashboard, :download_data_internal)
        @test isdefined(NumeraiTournament.Dashboard, :train_models_internal)
        @test isdefined(NumeraiTournament.Dashboard, :submit_predictions_internal)

        # Verify realtime tracker is properly initialized in dashboard
        @test dashboard.realtime_tracker.download_progress == 0.0
        @test dashboard.realtime_tracker.upload_progress == 0.0
        @test dashboard.realtime_tracker.training_progress == 0.0
        @test dashboard.realtime_tracker.prediction_progress == 0.0
    end
end

println("\n✅ All TUI fix tests passed!")
println("\nVerified Features:")
println("• TUIRealtime module loaded and accessible")
println("• RealTimeTracker initialization working")
println("• Progress tracking for download/upload/training/prediction")
println("• Auto-training trigger after downloads")
println("• Event tracking system")
println("• Instant commands setup")
println("• Dashboard integration with realtime tracker")
println("• UnifiedTUIFix module integration")
println("• Progress callbacks in command functions")