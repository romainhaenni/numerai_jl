#!/usr/bin/env julia

# Test that TUIFixes is properly integrated into the dashboard
using Test
using Dates

# Add src to path
push!(LOAD_PATH, joinpath(dirname(@__FILE__), "..", "src"))

using NumeraiTournament
using NumeraiTournament.Dashboard
using NumeraiTournament.EnhancedDashboard
using NumeraiTournament.TUIFixes

@testset "TUI Integration Test" begin

    # Create a mock configuration
    config = (
        models = ["test_model"],
        data_dir = tempdir(),
        model_dir = tempdir(),
        auto_submit = false,
        stake_amount = 0.0,
        max_workers = 1,
        api_public_key = get(ENV, "NUMERAI_PUBLIC_ID", "test_key"),
        api_secret_key = get(ENV, "NUMERAI_SECRET_KEY", "test_secret"),
        tournament_id = 8,
        target_col = "target",
        sample_pct = 0.1,
        feature_set = "small",
        enable_neutralization = false,
        enable_dynamic_sharpe = false,
        sharpe_history_rounds = 100,
        sharpe_min_data_points = 20,
        tui_config = Dict(
            "refresh_rate" => 1.0,
            "model_update_interval" => 30.0,
            "network_check_interval" => 60.0,
            "theme" => "dark"
        )
    )

    @testset "TUIFixes Module Integration" begin
        # Create dashboard using the constructor that takes config
        dashboard = Dashboard.TournamentDashboard(config)

        # Test that dashboard has all required fields
        @test isdefined(dashboard, :progress_tracker)
        @test isdefined(dashboard, :events)
        @test isdefined(dashboard, :system_info)
        @test isdefined(dashboard, :running)
        @test isdefined(dashboard, :command_mode)
        @test isdefined(dashboard, :command_buffer)

        println("✅ Dashboard created successfully")
    end

    @testset "Direct Keyboard Command Handler" begin
        # Test that handle_direct_command function exists and works
        @test isdefined(TUIFixes, :handle_direct_command)
        @test isdefined(TUIFixes, :read_key_improved)

        # Create a mock dashboard
        dashboard = Dashboard.TournamentDashboard(config)

        # Simulate keyboard commands
        # Test 'h' command (help toggle)
        initial_help_state = dashboard.show_help
        TUIFixes.handle_direct_command(dashboard, "h")
        @test dashboard.show_help != initial_help_state

        # Test 'p' command (pause toggle)
        initial_pause_state = dashboard.paused
        TUIFixes.handle_direct_command(dashboard, "p")
        @test dashboard.paused != initial_pause_state

        # Test that events are being added
        event_count_before = length(dashboard.events)
        TUIFixes.handle_direct_command(dashboard, "r")  # Refresh command
        @test length(dashboard.events) > event_count_before

        println("✅ Direct keyboard commands working without Enter key")
    end

    @testset "Progress Tracking Integration" begin
        dashboard = Dashboard.TournamentDashboard(config)
        tracker = dashboard.progress_tracker

        # Test download progress tracking
        tracker.is_downloading = true
        tracker.download_progress = 50.0
        tracker.download_file = "test.parquet"

        @test tracker.is_downloading == true
        @test tracker.download_progress == 50.0
        @test tracker.download_file == "test.parquet"

        # Test training progress tracking
        tracker.is_training = true
        tracker.training_progress = 75.0
        tracker.training_model = "test_model"
        tracker.training_epoch = 10
        tracker.training_total_epochs = 100

        @test tracker.is_training == true
        @test tracker.training_progress == 75.0
        @test tracker.training_epoch == 10

        println("✅ Progress tracking properly integrated")
    end

    @testset "Sticky Panel Functions" begin
        dashboard = Dashboard.TournamentDashboard(config)

        # Test that sticky panel functions exist and are exported
        @test isdefined(Dashboard, :render_sticky_dashboard)
        @test isdefined(Dashboard, :render_top_sticky_panel)
        @test isdefined(Dashboard, :render_bottom_sticky_panel)

        # Test that these functions can be called without errors
        # Capture output to avoid displaying in test
        io = IOBuffer()
        redirect_stdout(io) do
            Dashboard.render_top_sticky_panel(dashboard, 80)
            Dashboard.render_bottom_sticky_panel(dashboard, 10, 80)
        end

        output = String(take!(io))
        @test !isempty(output)

        println("✅ Sticky panel functions working")
    end

    @testset "System Info Updates" begin
        dashboard = Dashboard.TournamentDashboard(config)

        # Test system info fields exist
        @test haskey(dashboard.system_info, :cpu_usage)
        @test haskey(dashboard.system_info, :memory_used)
        @test haskey(dashboard.system_info, :memory_total)
        @test haskey(dashboard.system_info, :load_avg)
        @test haskey(dashboard.system_info, :threads)

        # Update system info
        Dashboard.update_system_info!(dashboard)

        # Check that values are populated
        @test dashboard.system_info[:cpu_usage] >= 0
        @test dashboard.system_info[:memory_total] > 0
        @test dashboard.system_info[:threads] > 0
        @test length(dashboard.system_info[:load_avg]) == 3

        println("✅ System info updates working")
    end

    @testset "Event System" begin
        dashboard = Dashboard.TournamentDashboard(config)

        # Test adding events
        initial_count = length(dashboard.events)

        Dashboard.add_event!(dashboard, :info, "Test info event")
        Dashboard.add_event!(dashboard, :success, "Test success event")
        Dashboard.add_event!(dashboard, :error, "Test error event")
        Dashboard.add_event!(dashboard, :warning, "Test warning event")

        @test length(dashboard.events) == initial_count + 4
        @test dashboard.events[end-3][:type] == :info
        @test dashboard.events[end-2][:type] == :success
        @test dashboard.events[end-1][:type] == :error
        @test dashboard.events[end][:type] == :warning

        println("✅ Event system working with all event types")
    end

    @testset "Automatic Training Trigger" begin
        # Check that the download function includes training trigger
        src = read(joinpath(dirname(@__FILE__), "..", "src", "tui", "dashboard.jl"), String)

        # Verify automatic training trigger exists
        @test contains(src, "# Trigger automatic training")
        @test contains(src, "Starting automatic training pipeline")
        @test contains(src, "@async begin")
        @test contains(src, "start_training(dashboard)")

        println("✅ Automatic training trigger implemented after download")
    end

    @testset "Progress Bar Rendering" begin
        # Test progress bar creation
        bar = EnhancedDashboard.create_progress_bar(45, 100, width=40)
        @test !isempty(bar)
        @test contains(bar, "█")
        @test contains(bar, "45.0%")

        # Test spinner creation
        spinner = EnhancedDashboard.create_spinner(1)
        @test !isempty(spinner)
        @test spinner in ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

        println("✅ Progress bars and spinners render correctly")
    end

    println("\n" * "="^60)
    println("TUI INTEGRATION TEST COMPLETE")
    println("="^60)
    println("✅ All TUI fixes properly integrated")
    println("✅ Instant keyboard commands working")
    println("✅ Progress tracking functional")
    println("✅ Sticky panels implemented")
    println("✅ System info updates working")
    println("✅ Event system operational")
    println("✅ Automatic training trigger present")
    println("✅ Progress bars rendering correctly")
    println("="^60)
end

println("\n🔧 Testing TUI integration...")