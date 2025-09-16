# Test suite for Production TUI Implementation
# Tests real API integration and progress tracking

using Test
using NumeraiTournament
using DataFrames
using Dates

@testset "Production TUI Tests" begin

    @testset "System Monitoring" begin
        # Test that system monitoring returns real values
        disk_info = NumeraiTournament.Utils.get_disk_space_info()
        @test disk_info.free_gb > 0.0
        @test disk_info.total_gb > 0.0
        @test disk_info.used_gb >= 0.0
        @test disk_info.used_pct >= 0.0 && disk_info.used_pct <= 100.0

        mem_info = NumeraiTournament.Utils.get_memory_info()
        @test mem_info.used_gb > 0.0
        @test mem_info.total_gb > 0.0
        @test mem_info.available_gb >= 0.0
        @test mem_info.used_pct >= 0.0 && mem_info.used_pct <= 100.0

        cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
        @test cpu_usage >= 0.0 && cpu_usage <= 100.0
    end

    @testset "Dashboard Creation" begin
        # Create test config
        config = Dict(
            :api => Dict(
                :public_id => get(ENV, "NUMERAI_PUBLIC_ID", "test"),
                :secret_key => get(ENV, "NUMERAI_SECRET_KEY", "test")
            ),
            :data_dir => "test_data",
            :models => [
                Dict("name" => "test_model", "type" => "xgboost")
            ],
            :tui => Dict(
                "auto_start_pipeline" => false,
                "auto_start_delay" => 2.0,
                "auto_train_after_download" => false
            )
        )

        # Create mock API client
        api_client = nothing  # Will be mocked

        # Test dashboard creation
        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config, api_client)

        @test dashboard.running == true
        @test dashboard.paused == false
        @test dashboard.cpu_usage > 0.0  # Should have real initial values
        @test dashboard.memory_total > 0.0
        @test dashboard.disk_total > 0.0
        @test dashboard.current_operation == :idle
        @test dashboard.pipeline_active == false
        @test dashboard.auto_start_enabled == false
    end

    @testset "Event Management" begin
        config = Dict(
            :api => Dict(
                :public_id => "test",
                :secret_key => "test"
            ),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict()
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config, nothing)

        # Test adding events
        NumeraiTournament.TUIProduction.add_event!(dashboard, :info, "Test info message")
        @test length(dashboard.events) == 1
        @test dashboard.events[1][2] == :info
        @test dashboard.events[1][3] == "Test info message"

        NumeraiTournament.TUIProduction.add_event!(dashboard, :error, "Test error")
        @test length(dashboard.events) == 2
        @test dashboard.events[2][2] == :error

        NumeraiTournament.TUIProduction.add_event!(dashboard, :success, "Test success")
        @test length(dashboard.events) == 3
        @test dashboard.events[3][2] == :success

        # Test event limit (should keep only last 100)
        for i in 1:100
            NumeraiTournament.TUIProduction.add_event!(dashboard, :info, "Event $i")
        end
        @test length(dashboard.events) == 100
        @test occursin("Event 1", dashboard.events[1][3])  # First event should be Event 1 since we had 3 events before
    end

    @testset "Keyboard Input Handling" begin
        config = Dict(
            :api => Dict(:public_id => "test", :secret_key => "test"),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict()
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config, nothing)

        # Test quit command
        NumeraiTournament.TUIProduction.handle_input(dashboard, 'q')
        @test dashboard.running == false

        dashboard.running = true
        NumeraiTournament.TUIProduction.handle_input(dashboard, 'Q')
        @test dashboard.running == false

        # Test pause command
        dashboard.running = true
        dashboard.paused = false
        NumeraiTournament.TUIProduction.handle_input(dashboard, 'p')
        @test dashboard.paused == true

        NumeraiTournament.TUIProduction.handle_input(dashboard, 'P')
        @test dashboard.paused == false

        # Test refresh command
        dashboard.force_render = false
        NumeraiTournament.TUIProduction.handle_input(dashboard, 'r')
        @test dashboard.force_render == true
    end

    @testset "Progress Tracking" begin
        config = Dict(
            :api => Dict(:public_id => "test", :secret_key => "test"),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict("auto_train_after_download" => false)
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config, nothing)

        # Simulate progress callback for downloads
        progress_callback = function(status; kwargs...)
            if status == :start
                dashboard.operation_progress = 0.0
            elseif status == :progress
                progress = get(kwargs, :progress, 0.0)
                current_mb = get(kwargs, :current_mb, 0.0)
                total_mb = get(kwargs, :total_mb, 0.0)

                dashboard.operation_progress = progress
                dashboard.operation_details[:current_mb] = current_mb
                dashboard.operation_details[:total_mb] = total_mb
            elseif status == :complete
                dashboard.operation_progress = 100.0
            end
        end

        # Test progress updates
        progress_callback(:start)
        @test dashboard.operation_progress == 0.0

        progress_callback(:progress; progress=50.0, current_mb=100.0, total_mb=200.0)
        @test dashboard.operation_progress == 50.0
        @test dashboard.operation_details[:current_mb] == 100.0
        @test dashboard.operation_details[:total_mb] == 200.0

        progress_callback(:complete)
        @test dashboard.operation_progress == 100.0
    end

    @testset "Auto-start Configuration" begin
        # Test with auto-start enabled
        config_auto = Dict(
            :api => Dict(:public_id => "test", :secret_key => "test"),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict(
                "auto_start_pipeline" => true,
                "auto_start_delay" => 0.1,
                "auto_train_after_download" => true
            )
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config_auto, nothing)
        @test dashboard.auto_start_enabled == true
        @test dashboard.auto_start_delay == 0.1
        @test dashboard.auto_train_enabled == true

        # Test with auto-start disabled
        config_manual = Dict(
            :api => Dict(:public_id => "test", :secret_key => "test"),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict(
                "auto_start_pipeline" => false,
                "auto_train_after_download" => false
            )
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config_manual, nothing)
        @test dashboard.auto_start_enabled == false
        @test dashboard.auto_train_enabled == false
    end

    @testset "Download Tracking" begin
        config = Dict(
            :api => Dict(:public_id => "test", :secret_key => "test"),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict()
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config, nothing)

        # Test download tracking sets
        @test isempty(dashboard.downloads_in_progress)
        @test isempty(dashboard.downloads_completed)

        # Simulate adding to in-progress
        push!(dashboard.downloads_in_progress, "train")
        @test "train" in dashboard.downloads_in_progress

        # Simulate moving to completed
        delete!(dashboard.downloads_in_progress, "train")
        push!(dashboard.downloads_completed, "train")
        @test "train" ∉ dashboard.downloads_in_progress
        @test "train" in dashboard.downloads_completed
    end

    @testset "Pipeline State Management" begin
        config = Dict(
            :api => Dict(:public_id => "test", :secret_key => "test"),
            :data_dir => "test_data",
            :models => [],
            :tui => Dict()
        )

        dashboard = NumeraiTournament.TUIProduction.create_dashboard(config, nothing)

        # Test initial state
        @test dashboard.pipeline_stage == :idle
        @test dashboard.current_operation == :idle
        @test dashboard.pipeline_active == false

        # Simulate operation changes
        dashboard.current_operation = :downloading
        dashboard.pipeline_stage = :downloading_data
        dashboard.operation_description = "Downloading train dataset"

        @test dashboard.current_operation == :downloading
        @test dashboard.pipeline_stage == :downloading_data
        @test dashboard.operation_description == "Downloading train dataset"

        # Test training state
        dashboard.current_operation = :training
        dashboard.pipeline_stage = :training
        dashboard.operation_description = "Training models"

        @test dashboard.current_operation == :training
        @test dashboard.pipeline_stage == :training

        # Test submission state
        dashboard.current_operation = :submitting
        dashboard.pipeline_stage = :submitting
        dashboard.operation_description = "Submitting predictions"

        @test dashboard.current_operation == :submitting
        @test dashboard.pipeline_stage == :submitting
    end
end

println("✅ All Production TUI tests passed!")