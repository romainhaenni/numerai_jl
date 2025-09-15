#!/usr/bin/env julia
# Test script to verify dashboard can start without errors

using Test

# Load the main module
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using NumeraiTournament
using NumeraiTournament: Dashboard, TUIFixes, Utils

println("Testing dashboard initialization...")

@testset "Dashboard Startup Tests" begin
    # Test 1: Module loading
    @testset "Module Loading" begin
        @test isdefined(NumeraiTournament, :Dashboard)
        @test isdefined(NumeraiTournament, :TUIFixes)
        @test isdefined(NumeraiTournament, :Utils)
        @test isdefined(NumeraiTournament, :EnhancedDashboard)
        println("✅ All modules loaded successfully")
    end

    # Test 2: Configuration loading
    @testset "Configuration" begin
        # Create a minimal test config
        test_config = """
        tournament_id = 8
        data_dir = "test_data"
        model_dir = "test_models"
        models = []
        """

        config_path = joinpath(@__DIR__, "test_config.toml")
        open(config_path, "w") do f
            write(f, test_config)
        end

        config = NumeraiTournament.load_config(config_path)
        @test config.tournament_id == 8
        @test config.data_dir == "test_data"

        rm(config_path, force=true)
        println("✅ Configuration loading works")
    end

    # Test 3: Dashboard creation
    @testset "Dashboard Creation" begin
        config = NumeraiTournament.TournamentConfig(
            "",  # api_public_key
            "",  # api_secret_key
            String[],  # models
            "data",  # data_dir
            "models",  # model_dir
            false,  # auto_submit
            0.0,  # stake_amount
            4,  # max_workers
            8,  # tournament_id
            true,  # auto_train_after_download
            "medium",  # feature_set
            false,  # compounding_enabled
            1.0,  # min_compound_amount
            100.0,  # compound_percentage
            10000.0,  # max_stake_amount
            Dict{String, Any}(),  # tui_config
            0.1,  # sample_pct
            "target_cyrus_v4_20",  # target_col
            false,  # enable_neutralization
            0.5,  # neutralization_proportion
            true,  # enable_dynamic_sharpe
            52,  # sharpe_history_rounds
            2  # sharpe_min_data_points
        )

        dashboard = Dashboard.TournamentDashboard(config)
        @test dashboard !== nothing
        @test dashboard.running == true
        @test length(dashboard.events) > 0

        # Stop the dashboard
        dashboard.running = false

        println("✅ Dashboard can be created")
    end

    # Test 4: TUIFixes functions
    @testset "TUIFixes Functions" begin
        config = NumeraiTournament.TournamentConfig(
            "", "", String[], "data", "models", false, 0.0, 4, 8, true,
            "medium", false, 1.0, 100.0, 10000.0, Dict{String, Any}(),
            0.1, "target_cyrus_v4_20", false, 0.5, true, 52, 2
        )

        dashboard = Dashboard.TournamentDashboard(config)

        # Test key reading function exists
        @test isdefined(TUIFixes, :read_key_improved)

        # Test direct command handler
        @test isdefined(TUIFixes, :handle_direct_command)

        # Test post-download training handler
        @test isdefined(TUIFixes, :handle_post_download_training)

        # Test callback creators
        @test isdefined(TUIFixes, :create_download_callback)
        @test isdefined(TUIFixes, :create_upload_callback)
        @test isdefined(TUIFixes, :create_training_callback)
        @test isdefined(TUIFixes, :create_prediction_callback)

        dashboard.running = false

        println("✅ TUIFixes functions are available")
    end

    # Test 5: Utils functions
    @testset "Utils Functions" begin
        # Test disk space function
        disk_info = Utils.get_disk_space_info()
        @test isa(disk_info, NamedTuple)
        @test haskey(disk_info, :free_gb)
        @test haskey(disk_info, :total_gb)
        @test haskey(disk_info, :used_gb)
        @test haskey(disk_info, :used_pct)

        # On Unix systems, should get real values
        if Sys.isunix()
            @test disk_info.total_gb >= 0
        end

        println("✅ Utils functions work (disk space: $(disk_info.total_gb) GB total)")
    end

    # Test 6: Progress tracker
    @testset "Progress Tracker" begin
        tracker = NumeraiTournament.EnhancedDashboard.ProgressTracker()

        # Test initial state
        @test tracker.download_progress == 0.0
        @test tracker.is_downloading == false

        # Test update
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :download,
            progress = 50.0,
            file = "test.parquet",
            active = true
        )

        @test tracker.download_progress == 50.0
        @test tracker.download_file == "test.parquet"
        @test tracker.is_downloading == true

        println("✅ Progress tracker works")
    end

    # Test 7: Event system
    @testset "Event System" begin
        config = NumeraiTournament.TournamentConfig(
            "", "", String[], "data", "models", false, 0.0, 4, 8, true,
            "medium", false, 1.0, 100.0, 10000.0, Dict{String, Any}(),
            0.1, "target_cyrus_v4_20", false, 0.5, true, 52, 2
        )

        dashboard = Dashboard.TournamentDashboard(config)

        initial_event_count = length(dashboard.events)

        # Add various event types
        Dashboard.add_event!(dashboard, :info, "Test info")
        Dashboard.add_event!(dashboard, :warning, "Test warning")
        Dashboard.add_event!(dashboard, :error, "Test error")
        Dashboard.add_event!(dashboard, :success, "Test success")

        @test length(dashboard.events) == initial_event_count + 4

        dashboard.running = false

        println("✅ Event system works")
    end
end

println("\n🎉 All dashboard startup tests passed!")
println("The dashboard can be initialized and basic functions are working.")
println("Note: Full TUI interaction testing would require a running dashboard session.")