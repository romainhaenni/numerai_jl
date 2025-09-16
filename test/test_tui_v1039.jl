#!/usr/bin/env julia

# Test the TUI v0.10.39 implementation
using Test
using NumeraiTournament

@testset "TUI v0.10.39 Tests" begin
    @testset "Module Loading" begin
        # Test that the function is exported
        @test isdefined(NumeraiTournament, :run_tui_v1039)
    end

    @testset "Dashboard Creation" begin
        # Create a test configuration
        config = Dict(
            :auto_start_pipeline => false,
            :auto_train_after_download => true,
            :auto_submit => false,
            :data_dir => "test_data",
            :models => ["test_model"]
        )

        # Test that we can create a dashboard
        dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)
        @test !isnothing(dashboard)
        @test dashboard.running == true
        @test dashboard.paused == false
        @test dashboard.pipeline_stage == :idle
        @test isempty(dashboard.downloads_completed)
        @test isempty(dashboard.downloads_in_progress)
    end

    @testset "Disk Space Function" begin
        # Test the fixed disk space function
        disk_info = NumeraiTournament.TUIv1039.get_disk_space_info_fixed()
        @test haskey(disk_info, :free_gb)
        @test haskey(disk_info, :total_gb)
        @test haskey(disk_info, :used_gb)
        @test haskey(disk_info, :used_pct)

        # On a real system, these should be non-zero
        if Sys.isunix()
            @test disk_info.total_gb > 0
            println("Disk info: Total=$(disk_info.total_gb)GB, Free=$(disk_info.free_gb)GB, Used=$(disk_info.used_gb)GB")
        end
    end

    @testset "Event Logging" begin
        config = Dict(:auto_start_pipeline => false)
        dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)

        # Test adding events
        NumeraiTournament.TUIv1039.add_event!(dashboard, :info, "Test info message")
        NumeraiTournament.TUIv1039.add_event!(dashboard, :error, "Test error message")
        NumeraiTournament.TUIv1039.add_event!(dashboard, :success, "Test success message")

        @test length(dashboard.events) == 3
        @test dashboard.events[1].level == :info
        @test dashboard.events[2].level == :error
        @test dashboard.events[3].level == :success
    end

    @testset "System Info Update" begin
        config = Dict(:auto_start_pipeline => false)
        dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)

        # Update system info
        NumeraiTournament.TUIv1039.update_system_info!(dashboard)

        # Check that values are set (they may be 0 in test environment)
        @test dashboard.cpu_usage >= 0
        @test dashboard.memory_total >= 0
        @test dashboard.disk_total >= 0

        # On a real system, memory should be > 0
        if Sys.isunix()
            @test dashboard.memory_total > 0
            println("System info: CPU=$(dashboard.cpu_usage)%, Memory=$(dashboard.memory_used)/$(dashboard.memory_total)GB")
        end
    end

    @testset "Command Handling" begin
        config = Dict(:auto_start_pipeline => false)
        dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)

        # Test quit command
        @test dashboard.running == true
        NumeraiTournament.TUIv1039.handle_command(dashboard, 'q')
        @test dashboard.running == false

        # Test pause command
        dashboard.running = true
        @test dashboard.paused == false
        NumeraiTournament.TUIv1039.handle_command(dashboard, 'p')
        @test dashboard.paused == true
        NumeraiTournament.TUIv1039.handle_command(dashboard, 'p')
        @test dashboard.paused == false
    end
end

println("\n✅ All TUI v0.10.39 tests passed!")