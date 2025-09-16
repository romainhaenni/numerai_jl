using Test
using NumeraiTournament

@testset "TUI v0.10.41 Functionality Tests" begin
    # Load config
    config = NumeraiTournament.load_config("config.toml")

    @testset "Dashboard Creation" begin
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        @test dashboard !== nothing
        @test dashboard.auto_start_enabled == config.auto_start_pipeline
        @test dashboard.auto_train_enabled == config.auto_train_after_download
        @test dashboard.auto_submit_enabled == config.auto_submit
    end

    @testset "System Monitoring" begin
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        NumeraiTournament.TUIv1041Fixed.update_system_info!(dashboard)

        # Should have real values, not zeros
        @test dashboard.cpu_usage > 0.0
        @test dashboard.memory_total > 0.0
        @test dashboard.disk_total > 0.0
        @test dashboard.memory_used > 0.0
        @test dashboard.disk_free > 0.0
    end

    @testset "Event Logging" begin
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :info, "Test info")
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :warn, "Test warning")
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :error, "Test error")
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :success, "Test success")

        @test length(dashboard.events) == 4
        @test dashboard.events[1].level == :info
        @test dashboard.events[2].level == :warn
        @test dashboard.events[3].level == :error
        @test dashboard.events[4].level == :success
    end

    @testset "Command Handling" begin
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

        # Test refresh command
        NumeraiTournament.TUIv1041Fixed.handle_command(dashboard, 'r')
        @test length(dashboard.events) > 0
        @test occursin("refresh", lowercase(dashboard.events[end].message))

        # Test download command
        initial_events = length(dashboard.events)
        NumeraiTournament.TUIv1041Fixed.handle_command(dashboard, 'd')
        @test length(dashboard.events) > initial_events

        # Test quit command
        NumeraiTournament.TUIv1041Fixed.handle_command(dashboard, 'q')
        @test dashboard.running == false
    end

    @testset "Progress Tracking" begin
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

        # Set up progress
        dashboard.current_operation = :downloading
        dashboard.operation_description = "Test download"
        dashboard.operation_progress = 50.0
        dashboard.operation_total = 100.0
        dashboard.operation_details = Dict(:show_mb => true, :current_mb => 50.0, :total_mb => 100.0)

        @test dashboard.current_operation == :downloading
        @test dashboard.operation_progress == 50.0
        @test dashboard.operation_details[:current_mb] == 50.0
        @test dashboard.operation_details[:total_mb] == 100.0
    end

    @testset "Configuration Extraction" begin
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

        # These should match the config values
        @test dashboard.auto_start_enabled == config.auto_start_pipeline
        @test dashboard.auto_train_enabled == config.auto_train_after_download
        @test dashboard.auto_submit_enabled == config.auto_submit
    end
end

println("\n✅ All TUI v0.10.41 tests passed!")