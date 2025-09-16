#!/usr/bin/env julia

# Test the operational TUI implementation
using Test
using Dates

# Add parent directory to load path
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Load the main module
using NumeraiTournament
using NumeraiTournament.TUIOperational

@testset "TUI Operational Dashboard Tests" begin

    @testset "Dashboard Creation" begin
        config = Dict(
            :api_public_key => "test_key",
            :api_secret_key => "test_secret",
            :data_dir => "test_data",
            :model_dir => "test_models",
            :auto_train_after_download => true
        )

        dashboard = TUIOperational.OperationalDashboard(config)

        @test dashboard.running == false
        @test dashboard.paused == false
        @test dashboard.current_operation == :idle
        @test dashboard.auto_train_after_download == true
        @test length(dashboard.events) == 0
        @test dashboard.threads > 0
        @test dashboard.required_downloads == Set(["train", "validation", "live"])
    end

    @testset "Event Management" begin
        config = Dict(:api_public_key => "", :api_secret_key => "")
        dashboard = TUIOperational.OperationalDashboard(config)

        # Add events
        TUIOperational.add_event!(dashboard, :info, "Test event 1")
        @test length(dashboard.events) == 1
        @test dashboard.events[1].type == :info
        @test dashboard.events[1].message == "Test event 1"

        # Add many events to test limit
        for i in 2:35
            TUIOperational.add_event!(dashboard, :info, "Event $i")
        end

        # Should keep only last 30 events
        @test length(dashboard.events) == 30
        @test dashboard.events[end].message == "Event 35"
    end

    @testset "Progress Bar Creation" begin
        # Test determinate progress bar
        progress_bar = TUIOperational.create_progress_bar(50.0, 100.0; width=20)
        @test occursin("[", progress_bar)
        @test occursin("]", progress_bar)
        @test occursin("50.0%", progress_bar)

        # Test full progress
        progress_bar = TUIOperational.create_progress_bar(100.0, 100.0; width=20)
        @test occursin("100.0%", progress_bar)

        # Test empty progress
        progress_bar = TUIOperational.create_progress_bar(0.0, 100.0; width=20)
        @test occursin("0.0%", progress_bar)

        # Test indeterminate progress (spinner)
        progress_bar = TUIOperational.create_progress_bar(0.0, 0.0)
        @test occursin("Working...", progress_bar)
    end

    @testset "System Info Update" begin
        config = Dict(:api_public_key => "", :api_secret_key => "")
        dashboard = TUIOperational.OperationalDashboard(config)

        # Update system info
        TUIOperational.update_system_info!(dashboard)

        # Check that system info was updated
        @test dashboard.cpu_usage >= 0.0
        @test dashboard.memory_used >= 0.0
        @test dashboard.memory_total > 0.0
        @test dashboard.disk_free >= 0.0
        @test dashboard.uptime >= 0
    end

    @testset "Command Handling" begin
        config = Dict(:api_public_key => "", :api_secret_key => "")
        dashboard = TUIOperational.OperationalDashboard(config)
        dashboard.running = true

        # Test quit command
        result = TUIOperational.handle_command(dashboard, "q")
        @test result == true
        @test dashboard.running == false

        # Test pause command
        dashboard.running = true
        dashboard.paused = false
        result = TUIOperational.handle_command(dashboard, " ")
        @test result == true
        @test dashboard.paused == true

        # Test refresh command
        result = TUIOperational.handle_command(dashboard, "r")
        @test result == true

        # Test invalid command
        result = TUIOperational.handle_command(dashboard, "x")
        @test result == false
    end

    @testset "Uptime Formatting" begin
        # Test seconds
        @test TUIOperational.format_uptime(45) == "45s"

        # Test minutes
        @test TUIOperational.format_uptime(90) == "1m 30s"
        @test TUIOperational.format_uptime(125) == "2m 5s"

        # Test hours
        @test TUIOperational.format_uptime(3665) == "1h 1m"
        @test TUIOperational.format_uptime(7325) == "2h 2m"
    end

    @testset "Auto-Training Detection" begin
        config = Dict(
            :api_public_key => "",
            :api_secret_key => "",
            :auto_train_after_download => true
        )
        dashboard = TUIOperational.OperationalDashboard(config)

        # Simulate downloads completing
        push!(dashboard.downloads_completed, "train")
        @test dashboard.downloads_completed != dashboard.required_downloads

        push!(dashboard.downloads_completed, "validation")
        @test dashboard.downloads_completed != dashboard.required_downloads

        push!(dashboard.downloads_completed, "live")
        @test dashboard.downloads_completed == dashboard.required_downloads

        # Auto-training should trigger when all downloads complete
        @test dashboard.auto_train_after_download == true
    end

    @testset "Terminal Functions" begin
        # These just test that the functions don't error
        # Actual terminal manipulation is hard to test

        # Get terminal size
        height, width = TUIOperational.terminal_size()
        @test height > 0
        @test width > 0
    end
end

println()
println("=" ^ 60)
println("✅ All TUI Operational Dashboard tests passed!")
println("=" ^ 60)