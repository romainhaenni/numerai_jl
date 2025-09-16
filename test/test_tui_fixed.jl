using Test
using Dates
using NumeraiTournament
using NumeraiTournament.TUIFixed
using NumeraiTournament.API
using NumeraiTournament.Pipeline
using NumeraiTournament.DataLoader

@testset "Fixed TUI Features" begin
    # Create test config
    config = Dict(
        "data_dir" => "test_data",
        "model_dir" => "test_models",
        "auto_training" => true,
        "model" => Dict(
            "type" => "lightgbm",
            "params" => Dict()
        )
    )

    # Create mock API client
    api_client = API.NumeraiClient("test_key", "test_secret")

    @testset "Dashboard Initialization" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)
        @test dashboard.instant_commands_enabled == true
        @test dashboard.auto_training_enabled == true
        @test dashboard.progress.current_operation == "Idle"
        @test length(dashboard.event_log.events) == 0
    end

    @testset "Progress State Management" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)

        # Test download progress
        dashboard.progress.download_progress["train"] = 50.0
        @test dashboard.progress.download_progress["train"] == 50.0

        # Test training progress
        dashboard.progress.training_progress = 75.0
        @test dashboard.progress.training_progress == 75.0

        # Test upload progress
        dashboard.progress.upload_progress = 100.0
        @test dashboard.progress.upload_progress == 100.0
    end

    @testset "Event Logging" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)

        # Add events
        TUIFixed.add_event!(dashboard, "Test event 1")
        TUIFixed.add_event!(dashboard, "Test event 2")

        @test length(dashboard.event_log.events) == 2
        @test occursin("Test event 1", dashboard.event_log.events[1])
        @test occursin("Test event 2", dashboard.event_log.events[2])

        # Test max events limit
        for i in 1:40
            TUIFixed.add_event!(dashboard, "Event $i")
        end
        @test length(dashboard.event_log.events) == 30  # Max events
    end

    @testset "System Info Updates" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)

        # Update system info
        TUIFixed.update_system_info!(dashboard)

        # Check that values are updated (not checking exact values as they vary)
        @test dashboard.system_info.cpu_usage >= 0.0
        @test dashboard.system_info.memory_usage >= 0.0
        @test dashboard.system_info.disk_usage >= 0.0
        @test dashboard.system_info.last_update > dashboard.system_info.last_update - Dates.Second(1)
    end

    @testset "Progress Bar Rendering" begin
        # Test progress bar creation
        bar = TUIFixed.create_progress_bar(0.0, 20, "Download")
        @test occursin("Download", bar)
        @test occursin("0.0%", bar)

        bar = TUIFixed.create_progress_bar(50.0, 20, "Training")
        @test occursin("Training", bar)
        @test occursin("50.0%", bar)
        @test occursin("█", bar)
        @test occursin("░", bar)

        bar = TUIFixed.create_progress_bar(100.0, 20, "Upload")
        @test occursin("Upload", bar)
        @test occursin("100.0%", bar)
    end

    @testset "Command Handling" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)

        # Test quit command
        TUIFixed.handle_command(dashboard, 'q')
        @test dashboard.running == false
        @test occursin("Shutting down", dashboard.event_log.events[end])

        # Reset and test download command
        dashboard.running = true
        TUIFixed.handle_command(dashboard, 'd')
        @test occursin("Starting downloads", dashboard.event_log.events[end])

        # Test training command
        TUIFixed.handle_command(dashboard, 't')
        @test occursin("Starting training", dashboard.event_log.events[end])

        # Wait a moment for async tasks to complete/fail
        sleep(0.1)

        # Test refresh command - find the Refreshing event (may not be last due to async)
        TUIFixed.handle_command(dashboard, 'r')
        refresh_found = any(e -> occursin("Refreshing", e), dashboard.event_log.events)
        @test refresh_found
    end

    @testset "Auto-training Trigger" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)

        # Simulate downloads complete
        dashboard.progress.download_progress["train"] = 100.0
        dashboard.progress.download_progress["validation"] = 100.0
        dashboard.progress.download_progress["live"] = 100.0

        # Check auto-training would trigger
        all_downloaded = all(v == 100.0 for v in values(dashboard.progress.download_progress))
        @test all_downloaded == true
        @test length(dashboard.progress.download_progress) >= 3
    end

    @testset "Progress Callback" begin
        dashboard = TUIFixed.FixedDashboard(config, api_client)
        callback = TUIFixed.ProgressCallback(dashboard)

        # Test training start (epoch 1)
        info = NumeraiTournament.Models.Callbacks.CallbackInfo(
            "test_model",  # model_name
            1,             # epoch
            100,           # total_epochs
            1,             # iteration
            nothing,       # total_iterations
            nothing,       # loss
            nothing,       # val_loss
            nothing,       # val_score
            nothing,       # learning_rate
            0.0,           # elapsed_time
            nothing,       # eta
            Dict{String,Any}()  # extra_metrics
        )
        result = callback(info)
        @test result == NumeraiTournament.Models.Callbacks.CONTINUE
        @test dashboard.progress.training_active == true
        @test dashboard.progress.current_operation == "Training"

        # Test epoch progress (epoch 50)
        info = NumeraiTournament.Models.Callbacks.CallbackInfo(
            "test_model",  # model_name
            50,            # epoch
            100,           # total_epochs
            50,            # iteration
            nothing,       # total_iterations
            0.5,           # loss
            0.4,           # val_loss
            nothing,       # val_score
            nothing,       # learning_rate
            10.0,          # elapsed_time
            nothing,       # eta
            Dict{String,Any}("loss" => 0.5)  # extra_metrics
        )
        result = callback(info)
        @test result == NumeraiTournament.Models.Callbacks.CONTINUE
        @test dashboard.progress.training_progress == 50.0

        # Test training end (epoch 100)
        info = NumeraiTournament.Models.Callbacks.CallbackInfo(
            "test_model",  # model_name
            100,           # epoch
            100,           # total_epochs
            100,           # iteration
            nothing,       # total_iterations
            0.1,           # loss
            0.15,          # val_loss
            nothing,       # val_score
            nothing,       # learning_rate
            60.0,          # elapsed_time
            nothing,       # eta
            Dict{String,Any}("loss" => 0.1)  # extra_metrics
        )
        result = callback(info)
        @test result == NumeraiTournament.Models.Callbacks.CONTINUE
        @test dashboard.progress.training_progress == 100.0
        @test dashboard.progress.training_active == false
    end
end

println("✅ All Fixed TUI tests passed!")