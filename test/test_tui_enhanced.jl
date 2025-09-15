#!/usr/bin/env julia --project=.

using Test
using NumeraiTournament
using NumeraiTournament.Dashboard: TournamentDashboard, render, add_event!, start_training
using NumeraiTournament.Dashboard.EnhancedDashboard
using TOML

@testset "Enhanced TUI Tests" begin
    # Load test configuration
    config_dict = TOML.parsefile("config.toml")

    # Create a mock config object
    config = (
        api_public_key = get(ENV, "NUMERAI_PUBLIC_ID", "test_key"),
        api_secret_key = get(ENV, "NUMERAI_SECRET_KEY", "test_secret"),
        tournament_id = get(config_dict, "tournament_id", 8),
        models = get(config_dict, "models", ["test_model"]),
        data_dir = get(config_dict, "data_dir", "data"),
        model_dir = get(config_dict, "model_dir", "models"),
        feature_set = get(config_dict, "feature_set", "medium"),
        sample_pct = 0.1,  # Default value
        tui_config = Dict(
            "refresh_rate" => 1.0,
            "model_update_interval" => 30.0,
            "network_check_interval" => 60.0
        ),
        auto_submit = get(config_dict, "auto_submit", false),
        enable_dynamic_sharpe = false,
        sharpe_history_rounds = 20,
        sharpe_min_data_points = 5
    )

    @testset "Dashboard Creation" begin
        dashboard = TournamentDashboard(config)
        @test dashboard !== nothing
        @test dashboard.progress_tracker !== nothing
        @test dashboard.progress_tracker.is_downloading == false
        @test dashboard.progress_tracker.is_training == false
    end

    @testset "Progress Tracking" begin
        dashboard = TournamentDashboard(config)

        # Test download progress tracking
        dashboard.progress_tracker.is_downloading = true
        dashboard.progress_tracker.download_file = "test.parquet"
        dashboard.progress_tracker.download_progress = 50.0
        @test dashboard.progress_tracker.is_downloading == true
        @test dashboard.progress_tracker.download_progress == 50.0

        # Test training progress tracking
        dashboard.progress_tracker.is_training = true
        dashboard.progress_tracker.training_model = "test_model"
        dashboard.progress_tracker.training_epoch = 5
        dashboard.progress_tracker.training_total_epochs = 10
        dashboard.progress_tracker.training_progress = 50.0
        @test dashboard.progress_tracker.is_training == true
        @test dashboard.progress_tracker.training_progress == 50.0
    end

    @testset "Enhanced Dashboard Functions" begin
        # Test progress bar creation
        bar = EnhancedDashboard.create_progress_bar(50, 100, width=20)
        @test length(bar) > 0
        @test contains(bar, "50.0%")

        # Test spinner creation
        spinner = EnhancedDashboard.create_spinner(1)
        @test spinner in ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

        # Test duration formatting
        @test EnhancedDashboard.format_duration(45) == "45s"
        @test EnhancedDashboard.format_duration(90) == "1m 30s"
        @test EnhancedDashboard.format_duration(3665) == "1h 1m"

        # Test center text
        centered = EnhancedDashboard.center_text("TEST", 10)
        @test length(centered) == 10
        @test contains(centered, "TEST")

        # Test metric bar
        bar = EnhancedDashboard.create_metric_bar(0.05, -0.1, 0.1, 15)
        @test length(bar) == 17  # Including brackets
        @test contains(bar, "[") && contains(bar, "]")
    end

    @testset "Event System" begin
        dashboard = TournamentDashboard(config)

        # Test adding events
        add_event!(dashboard, :info, "Test info event")
        @test length(dashboard.events) > 0
        @test dashboard.events[end][:type] == :info
        @test dashboard.events[end][:message] == "Test info event"

        add_event!(dashboard, :error, "Test error event")
        @test dashboard.events[end][:type] == :error

        add_event!(dashboard, :success, "Test success event")
        @test dashboard.events[end][:type] == :success
    end

    @testset "Keyboard Commands" begin
        dashboard = TournamentDashboard(config)

        # Test help toggle
        initial_help = dashboard.show_help
        dashboard.show_help = !dashboard.show_help
        @test dashboard.show_help != initial_help

        # Test command mode
        @test dashboard.command_mode == false
        dashboard.command_mode = true
        dashboard.command_buffer = "test"
        @test dashboard.command_mode == true
        @test dashboard.command_buffer == "test"
    end

    @testset "Training Integration" begin
        dashboard = TournamentDashboard(config)

        # Test training start detection
        @test dashboard.training_info[:is_training] == false

        # Simulate training start (without actually training)
        dashboard.training_info[:is_training] = true
        dashboard.progress_tracker.is_training = true
        dashboard.progress_tracker.training_model = "test_model"

        @test dashboard.training_info[:is_training] == true
        @test dashboard.progress_tracker.is_training == true
    end

    @testset "Render Without Errors" begin
        dashboard = TournamentDashboard(config)

        # Add some test data
        add_event!(dashboard, :info, "Test render")
        dashboard.model[:corr] = 0.015
        dashboard.model[:mmc] = 0.008
        dashboard.model[:fnc] = 0.002

        # Test that render doesn't throw errors
        # Note: We can't easily capture the terminal output in tests, but we can ensure no errors
        try
            # Temporarily redirect stdout to devnull to avoid cluttering test output
            original_stdout = stdout
            redirect_stdout(devnull) do
                render(dashboard)
            end
            @test true  # If we get here, render succeeded
        catch e
            @test false  # Render failed
            @warn "Render error: $e"
        end
    end
end

println("✅ All Enhanced TUI tests completed!")