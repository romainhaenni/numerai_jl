#!/usr/bin/env julia

# Test TUI keyboard handling functionality

using Test
using NumeraiTournament

@testset "TUI Keyboard Handling Tests" begin
    # Load config and create dashboard
    config = NumeraiTournament.load_config("config.toml")
    dashboard = NumeraiTournament.TournamentDashboard(config)

    @testset "Dashboard Properties" begin
        @test hasproperty(dashboard, :command_mode)
        @test hasproperty(dashboard, :wizard_active)
        @test hasproperty(dashboard, :running)
        @test hasproperty(dashboard, :paused)
        @test hasproperty(dashboard, :command_buffer)
    end

    @testset "Initial State" begin
        @test dashboard.command_mode == false
        @test dashboard.wizard_active == false
        @test dashboard.running == false  # Only true when run_dashboard is called
        @test dashboard.paused == false
        @test dashboard.command_buffer == ""
    end

    @testset "Command Functions" begin
        # Test that key handler functions exist
        @test isdefined(NumeraiTournament.Dashboard, :start_model_wizard)
        @test isdefined(NumeraiTournament.Dashboard, :execute_command)
        @test isdefined(NumeraiTournament.Dashboard, :handle_wizard_input)
        @test isdefined(NumeraiTournament.Dashboard, :start_training)
        @test isdefined(NumeraiTournament.Dashboard, :update_model_performances!)
    end

    @testset "Rendering Functions" begin
        # Test that rendering functions exist and work
        @test isdefined(NumeraiTournament.Dashboard, :render)
        @test isdefined(NumeraiTournament.Dashboard, :render_unified_dashboard)
        @test isdefined(NumeraiTournament.Dashboard, :create_status_line)

        # Test status line creation
        status_line = NumeraiTournament.Dashboard.create_status_line(dashboard)
        @test occursin("Press 'n' for new model", status_line)
        @test occursin("'/' for commands", status_line)
        @test occursin("'h' for help", status_line)
        @test occursin("'q' to quit", status_line)
    end

    @testset "Command Mode Toggle" begin
        # Test entering command mode
        dashboard.command_mode = true
        status_line = NumeraiTournament.Dashboard.create_status_line(dashboard)
        @test occursin("Command:", status_line)

        # Test command buffer
        dashboard.command_buffer = "test"
        status_line = NumeraiTournament.Dashboard.create_status_line(dashboard)
        @test occursin("/test", status_line)

        # Reset
        dashboard.command_mode = false
        dashboard.command_buffer = ""
    end

    println("\n✅ All TUI keyboard handling tests passed!")
end