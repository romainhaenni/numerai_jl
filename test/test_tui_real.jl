using Test
using NumeraiTournament
using DataFrames

@testset "TUI Real Operations Integration Tests" begin

    @testset "RealDashboard Initialization" begin
        # Test dashboard creation with mock config
        config = Dict(
            :api_public_key => ENV["NUMERAI_PUBLIC_ID"],
            :api_secret_key => ENV["NUMERAI_SECRET_KEY"],
            :data_dir => "test_data",
            :model_dir => "test_models",
            :auto_train_after_download => true,
            :model => Dict(:type => "XGBoost"),
            :model_name => "test_model"
        )

        dashboard = NumeraiTournament.RealDashboard(config)

        @test dashboard !== nothing
        @test dashboard.running == false
        @test dashboard.paused == false
        @test dashboard.progress.operation == :idle
        @test dashboard.auto_train_enabled == true
        @test length(dashboard.events) == 0
        @test dashboard.instant_commands_enabled == true
    end

    @testset "Progress Update Functions" begin
        config = Dict(
            :api_public_key => ENV["NUMERAI_PUBLIC_ID"],
            :api_secret_key => ENV["NUMERAI_SECRET_KEY"],
            :data_dir => "test_data",
            :model_dir => "test_models"
        )

        dashboard = NumeraiTournament.RealDashboard(config)

        # Test progress update
        NumeraiTournament.TUIReal.update_progress!(dashboard, :download, 50.0, 100.0, "Downloading...")
        @test dashboard.progress.operation == :download
        @test dashboard.progress.current == 50.0
        @test dashboard.progress.total == 100.0
        @test dashboard.progress.description == "Downloading..."

        # Test idle state
        NumeraiTournament.TUIReal.update_progress!(dashboard, :idle, 0.0, 0.0)
        @test dashboard.progress.operation == :idle
    end

    @testset "Event Management" begin
        config = Dict(
            :api_public_key => ENV["NUMERAI_PUBLIC_ID"],
            :api_secret_key => ENV["NUMERAI_SECRET_KEY"],
            :data_dir => "test_data",
            :model_dir => "test_models"
        )

        dashboard = NumeraiTournament.RealDashboard(config)

        # Test adding events
        NumeraiTournament.TUIReal.add_event!(dashboard, :info, "Test event 1")
        @test length(dashboard.events) == 1
        @test dashboard.events[1][:type] == :info
        @test dashboard.events[1][:message] == "Test event 1"

        # Test event overflow handling
        for i in 1:35
            NumeraiTournament.TUIReal.add_event!(dashboard, :info, "Event $i")
        end
        @test length(dashboard.events) == dashboard.max_events  # Should be capped at 30
        @test dashboard.events[end][:message] == "Event 35"
    end

    @testset "Instant Command Handler" begin
        config = Dict(
            :api_public_key => ENV["NUMERAI_PUBLIC_ID"],
            :api_secret_key => ENV["NUMERAI_SECRET_KEY"],
            :data_dir => "test_data",
            :model_dir => "test_models"
        )

        dashboard = NumeraiTournament.RealDashboard(config)
        dashboard.running = true

        # Test quit command
        handled = NumeraiTournament.TUIReal.instant_command_handler(dashboard, "q")
        @test handled == true
        @test dashboard.running == false

        # Test invalid command
        dashboard.running = true
        handled = NumeraiTournament.TUIReal.instant_command_handler(dashboard, "x")
        @test handled == false
        @test dashboard.running == true

        # Test refresh command
        handled = NumeraiTournament.TUIReal.instant_command_handler(dashboard, "r")
        @test handled == true
    end

    @testset "Auto-Train Trigger Logic" begin
        config = Dict(
            :api_public_key => ENV["NUMERAI_PUBLIC_ID"],
            :api_secret_key => ENV["NUMERAI_SECRET_KEY"],
            :data_dir => "test_data",
            :model_dir => "test_models",
            :auto_train_after_download => true
        )

        dashboard = NumeraiTournament.RealDashboard(config)

        # Test auto-train not triggered when downloads incomplete
        push!(dashboard.downloads_completed, "train")
        should_train = NumeraiTournament.TUIReal.check_auto_train(dashboard)
        @test should_train == false

        # Test auto-train triggered when all downloads complete
        push!(dashboard.downloads_completed, "validation")
        push!(dashboard.downloads_completed, "live")
        should_train = NumeraiTournament.TUIReal.check_auto_train(dashboard)
        @test should_train == true

        # Test downloads reset after auto-train
        NumeraiTournament.TUIReal.reset_downloads!(dashboard)
        @test length(dashboard.downloads_completed) == 0
    end

    @testset "Progress Bar Creation" begin
        # Test progress bar with valid values
        bar = NumeraiTournament.TUIReal.create_progress_bar(50.0, 100.0, width=20)
        @test occursin("██████████", bar)  # Should have filled blocks
        @test occursin("░░░░░░░░░░", bar)  # Should have empty blocks
        @test occursin("50.0%", bar)

        # Test progress bar with zero total
        bar = NumeraiTournament.TUIReal.create_progress_bar(0.0, 0.0, width=20)
        @test occursin("?", bar)  # Should show unknown progress

        # Test progress bar at 100%
        bar = NumeraiTournament.TUIReal.create_progress_bar(100.0, 100.0, width=20)
        @test occursin("100.0%", bar)
        @test !occursin("░", bar)  # Should have no empty blocks
    end

    @testset "System Info Update" begin
        config = Dict(
            :api_public_key => ENV["NUMERAI_PUBLIC_ID"],
            :api_secret_key => ENV["NUMERAI_SECRET_KEY"],
            :data_dir => "test_data",
            :model_dir => "test_models"
        )

        dashboard = NumeraiTournament.RealDashboard(config)

        # Update system info
        NumeraiTournament.TUIReal.update_system_info!(dashboard)

        # Check that system info was populated
        @test haskey(dashboard.system_info, :cpu_usage)
        @test haskey(dashboard.system_info, :memory_used)
        @test haskey(dashboard.system_info, :memory_total)
        @test haskey(dashboard.system_info, :disk_free)
        @test dashboard.system_info[:threads] == Threads.nthreads()
        @test dashboard.system_info[:julia_version] == string(VERSION)
    end
end

println("✅ All TUI Real Operations tests passed!")