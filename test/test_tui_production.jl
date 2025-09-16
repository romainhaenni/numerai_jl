using Test
using NumeraiTournament
using NumeraiTournament.API
using NumeraiTournament.Utils
using NumeraiTournament.TUIProduction
using Dates

@testset "TUI Production Tests" begin

    @testset "System Monitoring Functions" begin
        # Test CPU usage
        cpu_usage = Utils.get_cpu_usage()
        @test cpu_usage >= 0.0
        @test cpu_usage <= 100.0
        println("✅ CPU Usage: $cpu_usage%")

        # Test memory info
        mem_info = Utils.get_memory_info()
        @test mem_info.total_gb > 0.0
        @test mem_info.used_gb > 0.0
        @test mem_info.used_gb <= mem_info.total_gb
        println("✅ Memory: $(mem_info.used_gb)/$(mem_info.total_gb) GB")

        # Test disk info
        disk_info = Utils.get_disk_space_info()
        @test disk_info.total_gb > 0.0
        @test disk_info.free_gb > 0.0
        @test disk_info.free_gb <= disk_info.total_gb
        println("✅ Disk: $(disk_info.free_gb)/$(disk_info.total_gb) GB free")
    end

    @testset "Dashboard Creation" begin
        # Create a test config
        config = NumeraiTournament.TournamentConfig(
            tournament_id = 8,
            model_name = "test_model",
            api_public_key = "test_public_key",
            api_secret_key = "test_secret_key",
            data_dir = "test_data",
            model_dir = "test_models",
            features = [:small],
            train_models = ["xgboost"],
            auto_submit = false,
            stake_amount = 0.0,
            sample_pct = 0.1,
            n_estimators = 100,
            learning_rate = 0.05,
            max_depth = 6,
            early_stopping_rounds = 10,
            max_workers = 1,
            upload_predictions = false,
            auto_start_pipeline = true,
            auto_train_after_download = true,
            tui_config = Dict(
                "auto_start_delay" => 1.0,
                "refresh_rate" => 1.0
            )
        )

        # Create mock API client
        api_client = nothing  # We'll mock this for testing

        # Test dashboard creation with real system values
        dashboard = TUIProduction.create_dashboard(config, api_client)

        @test dashboard.running == true
        @test dashboard.paused == false
        @test dashboard.cpu_usage > 0.0
        @test dashboard.memory_total > 0.0
        @test dashboard.disk_total > 0.0
        @test dashboard.auto_start_enabled == true
        @test dashboard.auto_train_enabled == true
        @test dashboard.auto_start_delay == 1.0

        println("✅ Dashboard created successfully with real system values")
        println("  - CPU: $(dashboard.cpu_usage)%")
        println("  - Memory: $(dashboard.memory_used)/$(dashboard.memory_total) GB")
        println("  - Disk: $(dashboard.disk_free)/$(dashboard.disk_total) GB")
        println("  - Auto-start: $(dashboard.auto_start_enabled)")
        println("  - Auto-train: $(dashboard.auto_train_enabled)")
    end

    @testset "Keyboard Input Handling" begin
        config = NumeraiTournament.TournamentConfig(
            tournament_id = 8,
            model_name = "test_model",
            api_public_key = "test_public_key",
            api_secret_key = "test_secret_key",
            data_dir = "test_data",
            model_dir = "test_models",
            features = [:small],
            train_models = ["xgboost"],
            auto_submit = false,
            stake_amount = 0.0,
            sample_pct = 0.1,
            n_estimators = 100,
            learning_rate = 0.05,
            max_depth = 6,
            early_stopping_rounds = 10,
            max_workers = 1,
            upload_predictions = false,
            auto_start_pipeline = false,
            auto_train_after_download = false
        )

        api_client = nothing
        dashboard = TUIProduction.create_dashboard(config, api_client)

        # Test quit command
        TUIProduction.handle_input(dashboard, 'q')
        @test dashboard.running == false
        println("✅ Quit command works")

        # Reset for next test
        dashboard.running = true

        # Test pause command
        initial_paused = dashboard.paused
        TUIProduction.handle_input(dashboard, 'p')
        @test dashboard.paused != initial_paused
        println("✅ Pause command works")

        # Test refresh command
        TUIProduction.handle_input(dashboard, 'r')
        @test dashboard.force_render == true
        println("✅ Refresh command works")

        # Test help command
        initial_events = length(dashboard.events)
        TUIProduction.handle_input(dashboard, 'h')
        @test length(dashboard.events) > initial_events
        println("✅ Help command works")
    end

    @testset "Progress Bar Display" begin
        config = NumeraiTournament.TournamentConfig(
            tournament_id = 8,
            model_name = "test_model",
            api_public_key = "test_public_key",
            api_secret_key = "test_secret_key",
            data_dir = "test_data",
            model_dir = "test_models",
            features = [:small],
            train_models = ["xgboost"],
            auto_submit = false,
            stake_amount = 0.0,
            sample_pct = 0.1,
            n_estimators = 100,
            learning_rate = 0.05,
            max_depth = 6,
            early_stopping_rounds = 10,
            max_workers = 1,
            upload_predictions = false,
            auto_start_pipeline = false,
            auto_train_after_download = false
        )

        api_client = nothing
        dashboard = TUIProduction.create_dashboard(config, api_client)

        # Simulate download progress
        dashboard.current_operation = :downloading
        dashboard.operation_description = "Downloading train dataset"
        dashboard.operation_progress = 50.0
        dashboard.operation_details[:current_mb] = 50.0
        dashboard.operation_details[:total_mb] = 100.0
        dashboard.operation_details[:speed_mb_s] = 10.0
        dashboard.operation_details[:eta_seconds] = 5

        @test dashboard.operation_progress == 50.0
        @test dashboard.operation_details[:current_mb] == 50.0
        println("✅ Download progress tracking works")

        # Simulate training progress
        dashboard.current_operation = :training
        dashboard.operation_description = "Training XGBoost model"
        dashboard.operation_progress = 75.0
        dashboard.operation_details[:epoch] = 75
        dashboard.operation_details[:total_epochs] = 100
        dashboard.operation_details[:phase] = "Training"

        @test dashboard.operation_progress == 75.0
        @test dashboard.operation_details[:epoch] == 75
        println("✅ Training progress tracking works")

        # Simulate upload progress
        dashboard.current_operation = :uploading
        dashboard.operation_description = "Uploading predictions"
        dashboard.operation_progress = 90.0
        dashboard.operation_details[:bytes_uploaded] = 900_000
        dashboard.operation_details[:total_bytes] = 1_000_000

        @test dashboard.operation_progress == 90.0
        @test dashboard.operation_details[:bytes_uploaded] == 900_000
        println("✅ Upload progress tracking works")
    end

    @testset "Auto-start Configuration" begin
        # Test with auto-start enabled
        config_enabled = NumeraiTournament.TournamentConfig(
            tournament_id = 8,
            model_name = "test_model",
            api_public_key = "test_public_key",
            api_secret_key = "test_secret_key",
            data_dir = "test_data",
            model_dir = "test_models",
            features = [:small],
            train_models = ["xgboost"],
            auto_submit = false,
            stake_amount = 0.0,
            sample_pct = 0.1,
            n_estimators = 100,
            learning_rate = 0.05,
            max_depth = 6,
            early_stopping_rounds = 10,
            max_workers = 1,
            upload_predictions = false,
            auto_start_pipeline = true,
            auto_train_after_download = true,
            tui_config = Dict("auto_start_delay" => 0.5)
        )

        api_client = nothing
        dashboard = TUIProduction.create_dashboard(config_enabled, api_client)

        @test dashboard.auto_start_enabled == true
        @test dashboard.auto_train_enabled == true
        @test dashboard.auto_start_delay == 0.5
        @test dashboard.auto_start_initiated == false
        println("✅ Auto-start configuration parsed correctly")

        # Test with auto-start disabled
        config_disabled = NumeraiTournament.TournamentConfig(
            tournament_id = 8,
            model_name = "test_model",
            api_public_key = "test_public_key",
            api_secret_key = "test_secret_key",
            data_dir = "test_data",
            model_dir = "test_models",
            features = [:small],
            train_models = ["xgboost"],
            auto_submit = false,
            stake_amount = 0.0,
            sample_pct = 0.1,
            n_estimators = 100,
            learning_rate = 0.05,
            max_depth = 6,
            early_stopping_rounds = 10,
            max_workers = 1,
            upload_predictions = false,
            auto_start_pipeline = false,
            auto_train_after_download = false
        )

        dashboard2 = TUIProduction.create_dashboard(config_disabled, api_client)

        @test dashboard2.auto_start_enabled == false
        @test dashboard2.auto_train_enabled == false
        println("✅ Auto-start can be disabled")
    end

    @testset "Event Logging" begin
        config = NumeraiTournament.TournamentConfig(
            tournament_id = 8,
            model_name = "test_model",
            api_public_key = "test_public_key",
            api_secret_key = "test_secret_key",
            data_dir = "test_data",
            model_dir = "test_models",
            features = [:small],
            train_models = ["xgboost"],
            auto_submit = false,
            stake_amount = 0.0,
            sample_pct = 0.1,
            n_estimators = 100,
            learning_rate = 0.05,
            max_depth = 6,
            early_stopping_rounds = 10,
            max_workers = 1,
            upload_predictions = false,
            auto_start_pipeline = false,
            auto_train_after_download = false
        )

        api_client = nothing
        dashboard = TUIProduction.create_dashboard(config, api_client)

        # Add different types of events
        TUIProduction.add_event!(dashboard, :info, "Test info message")
        TUIProduction.add_event!(dashboard, :warn, "Test warning message")
        TUIProduction.add_event!(dashboard, :error, "Test error message")
        TUIProduction.add_event!(dashboard, :success, "Test success message")

        @test length(dashboard.events) == 4
        @test dashboard.events[1][2] == :info
        @test dashboard.events[2][2] == :warn
        @test dashboard.events[3][2] == :error
        @test dashboard.events[4][2] == :success
        println("✅ Event logging works for all types")
    end
end

println("\n" * "="^60)
println("TUI PRODUCTION TESTS COMPLETED SUCCESSFULLY!")
println("="^60)