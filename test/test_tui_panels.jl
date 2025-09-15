#!/usr/bin/env julia

# Test the TUI panels functionality
using Test
using Dates

# Add project path
push!(LOAD_PATH, joinpath(dirname(@__DIR__), "src"))

# Load the main module
using NumeraiTournament
using NumeraiTournament.Dashboard
using NumeraiTournament.Dashboard.EnhancedDashboard

@testset "TUI Panel Tests" begin
    @testset "Progress Tracker" begin
        tracker = EnhancedDashboard.ProgressTracker()

        @test tracker.is_downloading == false
        @test tracker.is_training == false
        @test tracker.is_predicting == false
        @test tracker.is_uploading == false

        # Test download progress update
        EnhancedDashboard.update_progress_tracker!(
            tracker, :download,
            active=true, file="test.parquet", progress=0.5,
            total_mb=100.0, current_mb=50.0
        )

        @test tracker.is_downloading == true
        @test tracker.download_file == "test.parquet"
        @test tracker.download_progress == 0.5
        @test tracker.download_total_mb == 100.0
        @test tracker.download_current_mb == 50.0
    end

    @testset "Progress Bar Creation" begin
        # Test progress bar creation
        bar = EnhancedDashboard.create_progress_bar(50, 100; width=20)
        @test occursin("50.0%", bar)
        @test length(bar) > 20  # Should have bar + percentage

        # Test edge cases
        bar_empty = EnhancedDashboard.create_progress_bar(0, 100; width=20)
        @test occursin("0.0%", bar_empty)

        bar_full = EnhancedDashboard.create_progress_bar(100, 100; width=20)
        @test occursin("100.0%", bar_full)

        # Test zero total
        bar_zero = EnhancedDashboard.create_progress_bar(0, 0; width=20)
        @test length(bar_zero) == 20  # Should return just dashes
    end

    @testset "Duration Formatting" begin
        # Test duration formatting
        @test EnhancedDashboard.format_duration(0) == "0s"
        @test EnhancedDashboard.format_duration(45) == "45s"
        @test EnhancedDashboard.format_duration(90) == "1m 30s"
        @test EnhancedDashboard.format_duration(3665) == "1h 1m 5s"
        @test EnhancedDashboard.format_duration(86400) == "1d 0h 0m 0s"
    end

    @testset "Unified Status Panel" begin
        # Create a mock dashboard
        config = NumeraiTournament.TournamentConfig(
            "test_key", "test_secret", ["test_model"],
            "data", "models", false, 0.0, 16, 8, "medium",
            false, 100.0, 0.8, 10000.0,  # compounding settings
            Dict{String, Any}(),  # tui_config
            1.0, "target", false, 0.5,  # ML pipeline settings
            false, 52, 2  # Sharpe settings
        )

        api_client = NumeraiTournament.API.NumeraiClient("test_key", "test_secret", 8)

        dashboard = Dashboard.TournamentDashboard(
            config, api_client,
            Dict(:name => "test_model", :is_active => false, :corr => 0.0,
                 :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0, :tc => 0.0),
            [Dict(:name => "test_model", :is_active => false, :corr => 0.0,
                  :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0, :tc => 0.0)],
            Vector{Dict{Symbol, Any}}(),  # events
            Dict(:cpu_usage => 50, :memory_used => 10.0, :memory_total => 48.0,
                 :model_active => false, :threads => 16, :uptime => 100,
                 :julia_version => string(VERSION), :load_avg => (1.0, 2.0, 3.0),
                 :process_memory => 100.0),  # system_info
            Dict(:is_training => false, :model_name => "test_model",
                 :progress => 0, :total_epochs => 0, :current_epoch => 0,
                 :loss => 0.0, :val_score => 0.0, :eta => "N/A"),  # training_info
            Float64[],  # performance_history
            Dict{Symbol, Any}[],  # performance_history
            false, false, false, 1.0,  # running, paused, show_help, refresh_rate
            "", false,  # command_buffer, command_mode
            false,  # show_model_details
            nothing, nothing, nothing, false,  # selected_model_details, selected_model_stats, wizard_state, wizard_active
            Dict(Dashboard.API_ERROR => 0, Dashboard.NETWORK_ERROR => 0,
                 Dashboard.AUTH_ERROR => 0, Dashboard.DATA_ERROR => 0,
                 Dashboard.SYSTEM_ERROR => 0, Dashboard.TIMEOUT_ERROR => 0,
                 Dashboard.VALIDATION_ERROR => 0),  # error_counts
            Dict(:is_connected => true, :last_check => now(),
                 :api_latency => 10.0, :consecutive_failures => 0),  # network_status
            Dashboard.CategorizedError[],  # error_history
            EnhancedDashboard.ProgressTracker()  # progress_tracker
        )

        # Test rendering unified status panel
        panel = EnhancedDashboard.render_unified_status_panel(dashboard)

        @test occursin("SYSTEM DIAGNOSTICS", panel)
        @test occursin("CONFIGURATION STATUS", panel)
        @test occursin("CURRENT MODEL STATUS", panel)
        @test occursin("LOCAL DATA FILES", panel)
        @test occursin("NETWORK STATUS", panel)
        @test occursin("TROUBLESHOOTING SUGGESTIONS", panel)
        @test occursin("RECOVERY COMMANDS", panel)

        # Test with active downloads
        dashboard.progress_tracker.is_downloading = true
        dashboard.progress_tracker.download_file = "train.parquet"
        dashboard.progress_tracker.download_total_mb = 1000.0
        dashboard.progress_tracker.download_current_mb = 500.0

        panel_with_download = EnhancedDashboard.render_unified_status_panel(dashboard)
        @test occursin("DOWNLOADING", panel_with_download)
        @test occursin("train.parquet", panel_with_download)
    end

    @testset "Events Panel" begin
        # Create a mock dashboard with events
        config = NumeraiTournament.TournamentConfig(
            "test_key", "test_secret", ["test_model"],
            "data", "models", false, 0.0, 16, 8, "medium",
            false, 100.0, 0.8, 10000.0,  # compounding settings
            Dict{String, Any}(),  # tui_config
            1.0, "target", false, 0.5,  # ML pipeline settings
            false, 52, 2  # Sharpe settings
        )

        api_client = NumeraiTournament.API.NumeraiClient("test_key", "test_secret", 8)

        events = [
            Dict(:type => :info, :message => "Test info", :time => now()),
            Dict(:type => :warning, :message => "Test warning", :time => now()),
            Dict(:type => :error, :message => "Test error", :time => now()),
            Dict(:type => :success, :message => "Test success", :time => now())
        ]

        dashboard = Dashboard.TournamentDashboard(
            config, api_client,
            Dict(:name => "test_model", :is_active => false, :corr => 0.0,
                 :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0, :tc => 0.0),
            [Dict(:name => "test_model", :is_active => false, :corr => 0.0,
                  :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0, :tc => 0.0)],
            events,
            Dict(:cpu_usage => 50, :memory_used => 10.0, :memory_total => 48.0,
                 :model_active => false, :threads => 16, :uptime => 100,
                 :julia_version => string(VERSION), :load_avg => (1.0, 2.0, 3.0),
                 :process_memory => 100.0),
            Dict(:is_training => false, :model_name => "test_model",
                 :progress => 0, :total_epochs => 0, :current_epoch => 0,
                 :loss => 0.0, :val_score => 0.0, :eta => "N/A"),
            Float64[],
            Dict{Symbol, Any}[],
            false, false, false, 1.0,
            "", false,
            false,
            nothing, nothing, nothing, false,
            Dict(Dashboard.API_ERROR => 0, Dashboard.NETWORK_ERROR => 0,
                 Dashboard.AUTH_ERROR => 0, Dashboard.DATA_ERROR => 0,
                 Dashboard.SYSTEM_ERROR => 0, Dashboard.TIMEOUT_ERROR => 0,
                 Dashboard.VALIDATION_ERROR => 0),
            Dict(:is_connected => true, :last_check => now(),
                 :api_latency => 10.0, :consecutive_failures => 0),
            Dashboard.CategorizedError[],
            EnhancedDashboard.ProgressTracker()
        )

        # Test events panel rendering
        panel = EnhancedDashboard.render_events_panel(dashboard; max_events=10)

        @test occursin("RECENT EVENTS", panel)
        @test occursin("Test info", panel)
        @test occursin("Test warning", panel)
        @test occursin("Test error", panel)
        @test occursin("Test success", panel)

        # Test with empty events
        dashboard.events = Vector{Dict{Symbol, Any}}()
        panel_empty = EnhancedDashboard.render_events_panel(dashboard)
        @test occursin("No events recorded yet", panel_empty)
    end
end

println("\n✅ All TUI panel tests passed!")