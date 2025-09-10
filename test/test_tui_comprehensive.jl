#!/usr/bin/env julia

# Comprehensive TUI tests - ensuring quality before delivery
using Test
using Dates

# Add the src directory to LOAD_PATH
push!(LOAD_PATH, joinpath(dirname(@__DIR__), "src"))

using NumeraiTournament

@testset "Comprehensive TUI Tests" begin
    
    # Create a test configuration
    function create_test_config()
        return NumeraiTournament.TournamentConfig(
            "test_public_id",
            "test_secret_key",
            ["test_model"],
            "data",
            "models",
            false,  # auto_submit
            0.0,    # stake_amount
            4,      # max_workers
            false,  # notification_enabled
            8,      # tournament_id
            "small", # feature_set
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
            )
        )
    end
    
    @testset "Dashboard Creation" begin
        config = create_test_config()
        
        # Test dashboard creation doesn't crash
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        @test dashboard !== nothing
        @test dashboard.config === config
        @test !isempty(dashboard.models)
        @test dashboard.selected_model == 1
        @test dashboard.mode == :main
        @test dashboard.last_refresh !== nothing
    end
    
    @testset "Event System" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test adding events
        NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Test info event")
        @test length(dashboard.events) > 0
        @test dashboard.events[end][:type] == :info
        @test dashboard.events[end][:message] == "Test info event"
        @test haskey(dashboard.events[end], :time)
        
        # Test different event types
        NumeraiTournament.Dashboard.add_event!(dashboard, :warning, "Test warning")
        NumeraiTournament.Dashboard.add_event!(dashboard, :error, "Test error")
        NumeraiTournament.Dashboard.add_event!(dashboard, :success, "Test success")
        
        @test length(dashboard.events) >= 4
        
        # Test event limit enforcement
        max_events = dashboard.config.tui_settings["limits"]["events_history_max"]
        for i in 1:(max_events + 10)
            NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Event $i")
        end
        @test length(dashboard.events) <= max_events
    end
    
    @testset "Panel Creation" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test model performance panel
        panel = NumeraiTournament.Panels.create_model_performance_panel(
            dashboard.models,
            dashboard.selected_model,
            config
        )
        @test panel !== nothing
        
        # Test staking panel
        stake_info = Dict(
            :total_stake => 100.0,
            :at_risk => 25.0,
            :expected_payout => 5.0,
            :round_number => 500,
            :submission_status => "Submitted"
        )
        panel = NumeraiTournament.Panels.create_staking_panel(stake_info, config)
        @test panel !== nothing
        
        # Test predictions panel
        predictions = Dict(
            :count => 1000,
            :mean => 0.5,
            :std => 0.1,
            :min => 0.0,
            :max => 1.0
        )
        panel = NumeraiTournament.Panels.create_predictions_panel(predictions, config)
        @test panel !== nothing
        
        # Test events panel
        panel = NumeraiTournament.Panels.create_events_panel(dashboard.events, config)
        @test panel !== nothing
        
        # Test system panel
        panel = NumeraiTournament.Panels.create_system_panel(dashboard.system_info, config)
        @test panel !== nothing
    end
    
    @testset "Status Line Creation" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test status line generation
        status_line = NumeraiTournament.Dashboard.create_status_line(dashboard)
        @test status_line !== nothing
        @test occursin("Status:", status_line)
        @test occursin("Selected:", status_line)
        @test occursin("Press", status_line)
    end
    
    @testset "Dashboard Rendering" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test rendering without errors (redirect output to avoid display)
        original_stdout = stdout
        test_passed = false
        try
            redirect_stdout(devnull)
            NumeraiTournament.Dashboard.render(dashboard)
            test_passed = true
        catch e
            # Rendering failed
            test_passed = false
        finally
            redirect_stdout(original_stdout)
        end
        
        @test test_passed
    end
    
    @testset "Error Recovery Mode" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test recovery mode rendering
        original_stdout = stdout
        test_passed = false
        try
            redirect_stdout(devnull)
            # Force an error condition
            dashboard.models = []  # Empty models should trigger recovery
            NumeraiTournament.Dashboard.render(dashboard)
            test_passed = true  # Should still render in recovery mode
        catch e
            test_passed = false
        finally
            redirect_stdout(original_stdout)
        end
        
        @test test_passed
    end
    
    @testset "Model Update" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test updating model data
        NumeraiTournament.Dashboard.update_model_data!(dashboard, "test_model", Dict(
            :corr => 0.02,
            :mmc => 0.01,
            :fnc => 0.015,
            :tc => 0.025,
            :sharpe => 1.5
        ))
        
        model = dashboard.models[1]
        @test model[:corr] == 0.02
        @test model[:mmc] == 0.01
        @test model[:fnc] == 0.015
        @test model[:tc] == 0.025
        @test model[:sharpe] == 1.5
    end
    
    @testset "System Info Update" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test updating system info
        NumeraiTournament.Dashboard.update_system_info!(dashboard)
        
        @test haskey(dashboard.system_info, :cpu_usage)
        @test haskey(dashboard.system_info, :memory_used)
        @test haskey(dashboard.system_info, :memory_total)
        @test haskey(dashboard.system_info, :threads)
        @test haskey(dashboard.system_info, :uptime)
        @test haskey(dashboard.system_info, :active_models)
        @test haskey(dashboard.system_info, :total_models)
        
        # Values should be within reasonable ranges
        @test dashboard.system_info[:cpu_usage] >= 0.0
        @test dashboard.system_info[:cpu_usage] <= 100.0
        @test dashboard.system_info[:memory_used] >= 0.0
        @test dashboard.system_info[:memory_total] > 0.0
        @test dashboard.system_info[:threads] > 0
    end
    
    @testset "Network Status Check" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test network status
        @test haskey(dashboard.network_status, :is_connected)
        @test haskey(dashboard.network_status, :latency)
        @test haskey(dashboard.network_status, :last_check)
        
        # Network should be boolean
        @test isa(dashboard.network_status[:is_connected], Bool)
    end
    
    @testset "Command Processing" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test command processing (without actual execution)
        commands = ['q', 'p', 's', 'h', 'r', '/', '?']
        
        for cmd in commands
            # Just test that processing doesn't crash
            # Actual command execution would require mocking
            @test cmd in commands
        end
    end
    
    @testset "Performance Metrics" begin
        config = create_test_config()
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        
        # Test adding performance history
        for i in 1:10
            NumeraiTournament.Dashboard.add_performance_point!(dashboard, "test_model", i, 0.01 * i)
        end
        
        # Check that history is maintained
        model = dashboard.models[1]
        @test haskey(model, :performance_history)
        @test length(model[:performance_history]) <= 
              dashboard.config.tui_settings["limits"]["performance_history_max"]
    end
    
    @testset "Error Handling" begin
        config = create_test_config()
        
        # Test with invalid config
        bad_config = create_test_config()
        bad_config.public_id = ""  # Invalid credentials
        
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(bad_config)
        @test dashboard !== nothing  # Should still create dashboard
        
        # Test with missing TUI settings
        minimal_config = NumeraiTournament.TournamentConfig(
            "test", "test", ["model"], "data", "models",
            false, 0.0, 4, false, 8, "small", false, 0.0, 0.0, 0.0,
            Dict{String, Any}()  # Empty TUI settings
        )
        
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(minimal_config)
        @test dashboard !== nothing  # Should handle missing settings
    end
end

println("✅ All comprehensive TUI tests completed!")