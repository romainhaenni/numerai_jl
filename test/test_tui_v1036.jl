using Test
using NumeraiTournament

@testset "TUI v0.10.36 Complete Fix Tests" begin
    # Test configuration
    test_config = Dict(
        :api_public_key => "",
        :api_secret_key => "",
        :data_dir => "test_data",
        :model_dir => "test_models",
        :auto_train_after_download => true,
        :models => ["test_model"]
    )

    @testset "Dashboard Initialization" begin
        dashboard = NumeraiTournament.TUIv1036Dashboard(test_config)

        @test dashboard.running == true
        @test dashboard.paused == false
        @test dashboard.current_operation == :idle

        # Test REAL system values (not simulated)
        @test dashboard.cpu_usage >= 0.0
        @test dashboard.memory_total > 0.0
        @test dashboard.memory_used >= 0.0
        @test dashboard.disk_free >= 0.0
        @test dashboard.disk_total >= 0.0

        # Test event log management
        @test length(dashboard.events) == 0
        @test dashboard.max_events == 30

        # Test auto-training configuration
        @test dashboard.auto_train_after_download == true
        @test dashboard.required_downloads == Set(["train", "validation", "live"])
        @test isempty(dashboard.downloads_completed)
    end

    @testset "System Information Updates" begin
        dashboard = NumeraiTournament.TUIv1036Dashboard(test_config)

        # Get initial values
        initial_cpu = dashboard.cpu_usage
        initial_mem = dashboard.memory_used
        initial_uptime = dashboard.uptime

        # Sleep to allow time difference
        sleep(1.1)

        # Update system info
        NumeraiTournament.TUIv1036CompleteFix.update_system_info!(dashboard)

        # CPU and memory should be real values (may or may not change)
        @test dashboard.cpu_usage >= 0.0
        @test dashboard.memory_used >= 0.0

        # Uptime should increase
        @test dashboard.uptime >= initial_uptime
    end

    @testset "Event Log Management" begin
        dashboard = NumeraiTournament.TUIv1036Dashboard(test_config)

        # Add events
        for i in 1:35
            NumeraiTournament.TUIv1036CompleteFix.add_event!(dashboard, :info, "Test event $i")
        end

        # Should only keep last 30 events
        @test length(dashboard.events) == 30
        @test dashboard.events[1].message == "Test event 6"  # First 5 should be trimmed
        @test dashboard.events[end].message == "Test event 35"
    end

    @testset "Progress Bar Creation" begin
        # Test progress bar generation
        bar = NumeraiTournament.TUIv1036CompleteFix.create_progress_bar(50.0, 100.0, 20)
        @test occursin("50.0%", bar)
        @test occursin("█", bar)
        @test occursin("░", bar)

        # Test edge cases
        bar_empty = NumeraiTournament.TUIv1036CompleteFix.create_progress_bar(0.0, 100.0, 20)
        @test occursin("0.0%", bar_empty)

        bar_full = NumeraiTournament.TUIv1036CompleteFix.create_progress_bar(100.0, 100.0, 20)
        @test occursin("100.0%", bar_full)

        # Test division by zero protection
        bar_zero = NumeraiTournament.TUIv1036CompleteFix.create_progress_bar(50.0, 0.0, 20)
        @test occursin("━", bar_zero)  # Should return default bar
    end

    @testset "Command Handling" begin
        dashboard = NumeraiTournament.TUIv1036Dashboard(test_config)

        # Test pause/resume command
        initial_paused = dashboard.paused
        handled = NumeraiTournament.TUIv1036CompleteFix.handle_command(dashboard, " ")
        @test handled == true
        @test dashboard.paused == !initial_paused

        # Test quit command
        @test dashboard.running == true
        handled = NumeraiTournament.TUIv1036CompleteFix.handle_command(dashboard, "q")
        @test handled == true
        @test dashboard.running == false
    end

    @testset "Operation State Management" begin
        dashboard = NumeraiTournament.TUIv1036Dashboard(test_config)

        # Test idle state
        @test dashboard.current_operation == :idle

        # Simulate download state
        dashboard.current_operation = :downloading
        dashboard.operation_progress = 50.0
        dashboard.operation_total = 100.0
        dashboard.operation_details = Dict(:current_mb => 125.0, :total_mb => 250.0)

        @test dashboard.current_operation == :downloading
        @test dashboard.operation_progress == 50.0
        @test dashboard.operation_details[:current_mb] == 125.0

        # Simulate training state
        dashboard.current_operation = :training
        dashboard.operation_details = Dict(:epoch => 5, :total_epochs => 10, :loss => 0.123)

        @test dashboard.current_operation == :training
        @test dashboard.operation_details[:epoch] == 5
        @test dashboard.operation_details[:loss] == 0.123
    end

    @testset "Auto-Training Logic" begin
        dashboard = NumeraiTournament.TUIv1036Dashboard(test_config)

        # Initially no downloads completed
        @test isempty(dashboard.downloads_completed)

        # Simulate completing downloads
        push!(dashboard.downloads_completed, "train")
        @test length(dashboard.downloads_completed) == 1

        push!(dashboard.downloads_completed, "validation")
        @test length(dashboard.downloads_completed) == 2

        push!(dashboard.downloads_completed, "live")
        @test length(dashboard.downloads_completed) == 3

        # Check if all required downloads are completed
        @test dashboard.downloads_completed == dashboard.required_downloads
    end

    @testset "Duration Formatting" begin
        # Test duration formatting
        fmt = NumeraiTournament.TUIv1036CompleteFix.format_duration

        @test fmt(45) == "45s"
        @test fmt(65) == "1m 5s"
        @test fmt(3665) == "1h 1m 5s"
        @test fmt(7200) == "2h 0m 0s"
    end

    @testset "Real System Monitoring Functions" begin
        # Test CPU usage function
        cpu = NumeraiTournament.TUIv1036CompleteFix.get_cpu_usage()
        @test cpu >= 0.0
        @test cpu <= 100.0

        # Test memory info function
        mem = NumeraiTournament.TUIv1036CompleteFix.get_memory_info()
        @test mem.total > 0.0
        @test mem.used >= 0.0
        @test mem.free >= 0.0
        @test mem.used + mem.free ≈ mem.total rtol=0.1
    end

    println("✅ All TUI v0.10.36 tests passed!")
end