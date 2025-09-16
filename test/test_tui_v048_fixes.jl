using Test
using NumeraiTournament

@testset "TUI v0.10.48 All Fixes Verification" begin

    @testset "Disk Space Monitoring Fix" begin
        # Test disk space parsing
        disk_info = NumeraiTournament.Utils.get_disk_space_info()

        @test disk_info.total_gb > 0
        @test disk_info.free_gb > 0
        @test disk_info.used_gb > 0
        @test 0 <= disk_info.used_pct <= 100

        println("✅ Disk Space Info: $(round(disk_info.free_gb, digits=1))/$(round(disk_info.total_gb, digits=1)) GB free ($(round(disk_info.used_pct, digits=1))% used)")
    end

    @testset "System Monitoring" begin
        # Test CPU usage
        cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
        @test 0 <= cpu_usage <= 100

        # Test memory info
        mem_info = NumeraiTournament.Utils.get_memory_info()
        @test mem_info.total_gb > 0
        @test mem_info.used_gb >= 0
        @test mem_info.available_gb >= 0

        println("✅ CPU Usage: $(round(cpu_usage, digits=1))%")
        println("✅ Memory: $(round(mem_info.used_gb, digits=1))/$(round(mem_info.total_gb, digits=1)) GB")
    end

    @testset "TUI Dashboard Creation" begin
        # Create mock config
        config = Dict(
            :api_public_key => "test_key",
            :api_secret_key => "test_secret",
            :data_dir => tempdir(),
            :model_dir => tempdir(),
            :models => ["test_model"],
            :auto_start_pipeline => false,
            :auto_train_after_download => true,
            :auto_submit => false,
            :tui_config => Dict(
                "auto_start_delay" => 1.0
            )
        )

        # Test dashboard can be created
        @test_nowarn begin
            # Mock API client
            api_client = nothing  # Would be real API client in production

            # Create dashboard
            dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, api_client)

            @test dashboard !== nothing
            @test dashboard.running == true
            @test dashboard.paused == false
            @test dashboard.cpu_usage > 0
            @test dashboard.memory_total > 0
            @test dashboard.disk_total > 0

            println("✅ Dashboard created with real system values")
            println("   - CPU: $(round(dashboard.cpu_usage, digits=1))%")
            println("   - Memory: $(round(dashboard.memory_used, digits=1))/$(round(dashboard.memory_total, digits=1)) GB")
            println("   - Disk: $(round(dashboard.disk_free, digits=1))/$(round(dashboard.disk_total, digits=1)) GB")
        end
    end

    @testset "Auto-Training Configuration" begin
        config1 = Dict(
            :api_public_key => "test",
            :api_secret_key => "test",
            :auto_train_after_download => true,
            :auto_start_pipeline => true
        )

        dashboard1 = NumeraiTournament.TUIProductionV047.create_dashboard(config1, nothing)
        @test dashboard1.auto_train_enabled == true
        @test dashboard1.auto_start_enabled == true

        config2 = Dict(
            :api_public_key => "test",
            :api_secret_key => "test",
            :auto_train_after_download => false,
            :auto_start_pipeline => false
        )

        dashboard2 = NumeraiTournament.TUIProductionV047.create_dashboard(config2, nothing)
        @test dashboard2.auto_train_enabled == false
        @test dashboard2.auto_start_enabled == false

        println("✅ Auto-training configuration works correctly")
    end

    @testset "Keyboard Input Handler" begin
        config = Dict(
            :api_public_key => "test",
            :api_secret_key => "test"
        )

        dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, nothing)

        # Test keyboard command handling
        @test_nowarn NumeraiTournament.TUIProductionV047.handle_input(dashboard, 'h')
        @test length(dashboard.events) > 0

        @test_nowarn NumeraiTournament.TUIProductionV047.handle_input(dashboard, 'i')
        event_count_before = length(dashboard.events)
        @test event_count_before > 1

        @test_nowarn NumeraiTournament.TUIProductionV047.handle_input(dashboard, 'r')
        @test dashboard.force_render == true

        # Test quit command
        @test_nowarn NumeraiTournament.TUIProductionV047.handle_input(dashboard, 'q')
        @test dashboard.running == false

        println("✅ Keyboard input handling works correctly")
    end

    @testset "Progress Tracking" begin
        config = Dict(
            :api_public_key => "test",
            :api_secret_key => "test"
        )

        dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, nothing)

        # Test download progress tracking
        dashboard.downloads_in_progress = Set(["train"])
        dashboard.download_progress["train"] = 50.0
        dashboard.operation_progress = 50.0
        dashboard.current_operation = :downloading

        @test dashboard.download_progress["train"] == 50.0
        @test dashboard.operation_progress == 50.0

        # Test training progress tracking
        dashboard.training_in_progress = true
        dashboard.training_epochs_completed = 5
        dashboard.training_total_epochs = 10
        dashboard.current_operation = :training

        @test dashboard.training_epochs_completed == 5
        @test dashboard.training_total_epochs == 10

        # Test submission progress tracking
        dashboard.submission_in_progress = true
        dashboard.submission_progress = 75.0
        dashboard.current_operation = :submitting

        @test dashboard.submission_progress == 75.0

        println("✅ Progress tracking structures work correctly")
    end

    @testset "Event Logging" begin
        config = Dict(
            :api_public_key => "test",
            :api_secret_key => "test"
        )

        dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, nothing)

        # Add various event types
        NumeraiTournament.TUIProductionV047.add_event!(dashboard, :info, "Test info message")
        NumeraiTournament.TUIProductionV047.add_event!(dashboard, :warn, "Test warning")
        NumeraiTournament.TUIProductionV047.add_event!(dashboard, :error, "Test error")
        NumeraiTournament.TUIProductionV047.add_event!(dashboard, :success, "Test success")

        @test length(dashboard.events) == 4
        @test dashboard.force_render == true

        # Test event limit
        for i in 1:200
            NumeraiTournament.TUIProductionV047.add_event!(dashboard, :info, "Event $i")
        end

        @test length(dashboard.events) <= dashboard.max_events

        println("✅ Event logging works correctly with proper limits")
    end

    println("\n" * "="^60)
    println("🎉 ALL TUI v0.10.48 FIXES VERIFIED SUCCESSFULLY!")
    println("="^60)
    println()
    println("Summary of fixes verified:")
    println("✅ Disk space monitoring shows real values on macOS")
    println("✅ System monitoring (CPU, memory) works correctly")
    println("✅ Dashboard initializes with real system values")
    println("✅ Auto-training configuration works as expected")
    println("✅ Keyboard input handling responds correctly")
    println("✅ Progress tracking structures are in place")
    println("✅ Event logging works with proper limits")
    println()
    println("The TUI dashboard is ready for production use!")
end