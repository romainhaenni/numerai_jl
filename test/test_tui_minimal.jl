#!/usr/bin/env julia

# Minimal test to verify TUI can start without crashing
using Pkg
Pkg.activate(dirname(@__DIR__))

push!(LOAD_PATH, joinpath(dirname(@__DIR__), "src"))

using NumeraiTournament
using Test

@testset "Minimal TUI Tests" begin
    
    @testset "Can create dashboard without crash" begin
        # Create minimal config - simulate what happens when starting TUI
        config = NumeraiTournament.TournamentConfig(
            get(ENV, "NUMERAI_PUBLIC_ID", "test_key"),
            get(ENV, "NUMERAI_SECRET_KEY", "test_secret"),
            ["numeraijl"],  # Default model from config
            "data",
            "models",
            false,  # auto_submit
            0.1,    # stake_amount
            8,      # max_workers
            8,      # tournament_id
            "medium", # feature_set
            false,  # compounding_enabled
            0.0,    # min_compound_amount
            0.0,    # compound_percentage
            0.0,    # max_stake_amount
            Dict{String, Any}(
                "refresh_rate" => 1.0,
                "model_update_interval" => 30.0,
                "network_check_interval" => 60.0,
                "network_timeout" => 5,
                "limits" => Dict(
                    "performance_history_max" => 100,
                    "api_error_history_max" => 50,
                    "events_history_max" => 100,
                    "max_events_display" => 20
                ),
                "panels" => Dict(
                    "model_panel_width" => 60,
                    "staking_panel_width" => 40,
                    "predictions_panel_width" => 40,
                    "events_panel_width" => 60,
                    "events_panel_height" => 22,
                    "system_panel_width" => 40,
                    "training_panel_width" => 40,
                    "help_panel_width" => 40
                ),
                "charts" => Dict(
                    "sparkline_width" => 40,
                    "sparkline_height" => 8,
                    "bar_chart_width" => 40,
                    "histogram_bins" => 20,
                    "histogram_width" => 40,
                    "performance_sparkline_width" => 30,
                    "performance_sparkline_height" => 4,
                    "correlation_bar_width" => 20,
                    "mini_chart_width" => 10,
                    "correlation_positive_threshold" => 0.02,
                    "correlation_negative_threshold" => -0.02
                ),
                "training" => Dict(
                    "default_epochs" => 100,
                    "progress_bar_width" => 20
                )
            ),
            0.1,    # sample_pct
            "target_cyrus_v4_20", # target_col
            false,  # enable_neutralization
            0.5     # neutralization_proportion
        )
        
        # Test dashboard creation
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        @test dashboard !== nothing
        @test !isempty(dashboard.models)
        
        # Test that we can create events without crash
        NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Test event")
        @test length(dashboard.events) > 0
        
        # Test that status line can be created
        status_line = NumeraiTournament.Dashboard.create_status_line(dashboard)
        @test status_line !== nothing
        @test length(status_line) > 0
        
        println("✅ Dashboard creation successful")
    end
    
    @testset "Can render without crash" begin
        config = NumeraiTournament.TournamentConfig(
            "test", "test", ["test_model"], "data", "models",
            false, 0.0, 4, 8, "small", false, 0.0, 0.0, 0.0,
            Dict{String, Any}(
                "refresh_rate" => 1.0,
                "panels" => Dict(
                    "model_panel_width" => 60,
                    "staking_panel_width" => 40,
                    "predictions_panel_width" => 40,
                    "events_panel_width" => 60,
                    "events_panel_height" => 22,
                    "system_panel_width" => 40,
                    "training_panel_width" => 40,
                    "help_panel_width" => 40
                )
            ),
            0.1, "target_cyrus_v4_20", false, 0.5
        )
        
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test rendering without redirect (simpler approach)
        original_stdout = stdout
        test_passed = false
        try
            # Temporarily suppress output
            redirect_stdout(devnull)
            NumeraiTournament.Dashboard.render(dashboard)
            test_passed = true  # If we get here, it didn't crash
        catch e
            println(stderr, "Render failed with: ", e)
            test_passed = false
        finally
            redirect_stdout(original_stdout)
        end
        
        @test test_passed
        
        println("✅ Render test successful")
    end
end

println("\n✅ All minimal TUI tests passed!")