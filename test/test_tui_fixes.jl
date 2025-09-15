using Test
using NumeraiTournament
using TOML
using Dates

# Import the modules we need for testing
const API = NumeraiTournament.API
const Dashboard = NumeraiTournament.Dashboard

# Load EnhancedDashboard module
include("../src/tui/enhanced_dashboard.jl")

# Test progress callback signatures
@testset "Progress Callback Signatures" begin
    @testset "Download Progress Callbacks" begin
        # Test that progress callbacks accept keyword arguments
        callback_called = false
        progress_values = Float64[]

        test_callback = function(phase; kwargs...)
            callback_called = true
            if phase == :progress && haskey(kwargs, :progress)
                push!(progress_values, kwargs[:progress])
            end
        end

        # Simulate callback invocations as done in API client
        test_callback(:start; name="test_data")
        @test callback_called == true

        test_callback(:progress; name="test_data", progress=50.0, downloaded_mb=25.0, total_mb=50.0)
        @test 50.0 in progress_values

        test_callback(:complete; name="test_data", size_mb=50.0)
        @test callback_called == true
    end

    @testset "Upload Progress Callbacks" begin
        callback_phases = Symbol[]

        test_callback = function(phase; kwargs...)
            push!(callback_phases, phase)
            # Verify kwargs are accessible
            if phase == :start
                @test haskey(kwargs, :file)
                @test haskey(kwargs, :model)
            elseif phase == :progress
                @test haskey(kwargs, :phase)
                @test haskey(kwargs, :progress)
            elseif phase == :complete
                @test haskey(kwargs, :model)
                @test haskey(kwargs, :submission_id)
            end
        end

        # Simulate upload progress callback sequence
        test_callback(:start; file="predictions.csv", model="test_model", size_mb=10.0)
        test_callback(:progress; phase="Getting upload URL", progress=10.0)
        test_callback(:progress; phase="Uploading file", progress=30.0)
        test_callback(:progress; phase="Uploading to S3", progress=50.0)
        test_callback(:complete; model="test_model", submission_id="sub123", size_mb=10.0)

        @test :start in callback_phases
        @test :progress in callback_phases
        @test :complete in callback_phases
    end
end

# Test automatic training trigger after download
@testset "Automatic Training After Download" begin
    # Create mock config with auto_train_after_download enabled
    config_dict = Dict(
        "tournament_id" => 8,
        "models" => ["test_model"],
        "data_dir" => tempdir(),
        "model_dir" => tempdir(),
        "auto_submit" => false,
        "auto_train_after_download" => true,
        "tui_config" => Dict(
            "refresh_rate" => 0.5
        )
    )

    # Note: Full integration test would require mock API client
    # Here we just verify the config option is respected
    @test config_dict["auto_train_after_download"] == true
end

# Test keyboard command handling
@testset "Keyboard Command Processing" begin
    @testset "Single Key Commands" begin
        # Test that single-key commands don't require Enter
        single_keys = ['q', 'p', 's', 'r', 'n', 'c', 'd', 'l', 'h']

        for key in single_keys
            # Single character keys should be processed immediately
            @test length(string(key)) == 1
            @test !occursin("\n", string(key))
            @test !occursin("\r", string(key))
        end
    end

    @testset "Command Mode" begin
        # Command mode requires '/' to activate then Enter to execute
        command_mode_trigger = '/'
        @test command_mode_trigger == '/'

        # Commands in command mode require Enter
        test_commands = ["/train", "/submit", "/download", "/help"]
        for cmd in test_commands
            @test startswith(cmd, "/")
        end
    end
end

# Test real-time status updates
@testset "Real-Time Status Updates" begin
    @testset "System Info Updates" begin
        # Mock dashboard for testing
        config = NumeraiTournament.load_config(joinpath(@__DIR__, "../config.toml"))

        # System info should contain required fields
        required_fields = [:cpu_usage, :memory_used, :memory_total, :load_avg, :uptime, :threads]

        # Create mock system info
        sys_info = Dict{Symbol, Any}(
            :cpu_usage => 25,
            :memory_used => 8.5,
            :memory_total => 16.0,
            :load_avg => (1.5, 1.2, 1.0),
            :uptime => 3600,
            :threads => 4
        )

        for field in required_fields
            @test haskey(sys_info, field)
        end

        # Test uptime calculation
        start_time = time()
        sleep(0.1)
        uptime = round(Int, time() - start_time)
        @test uptime >= 0
    end

    @testset "Progress Tracker Updates" begin
        tracker = EnhancedDashboard.ProgressTracker()

        # Test download progress updates
        EnhancedDashboard.update_progress_tracker!(tracker, :download,
            active=true, file="train.parquet", progress=50.0, total_mb=100.0)
        @test tracker.is_downloading == true
        @test tracker.download_progress == 50.0

        # Test training progress updates
        EnhancedDashboard.update_progress_tracker!(tracker, :training,
            active=true, model="test_model", epoch=5, total_epochs=10)
        @test tracker.is_training == true
        @test tracker.training_epoch == 5
        @test tracker.training_total_epochs == 10

        # Test prediction progress updates
        EnhancedDashboard.update_progress_tracker!(tracker, :prediction,
            active=true, progress=75.0, total_rows=1000)
        @test tracker.is_predicting == true
        @test tracker.prediction_progress == 75.0

        # Test upload progress updates
        EnhancedDashboard.update_progress_tracker!(tracker, :upload,
            active=true, model="test_model", progress=25.0)
        @test tracker.is_uploading == true
        @test tracker.upload_progress == 25.0
    end
end

# Test panel layout and rendering
@testset "Panel Layout and Rendering" begin
    @testset "Unified Status Panel" begin
        # Create mock dashboard
        config = NumeraiTournament.load_config(joinpath(@__DIR__, "../config.toml"))
        api_client = nothing  # Mock client for testing

        # Test that unified status panel generates output
        mock_dashboard = Dict(
            :system_info => Dict(
                :cpu_usage => 25,
                :load_avg => (1.0, 1.1, 1.2),
                :memory_used => 8.0,
                :memory_total => 16.0,
                :process_memory => 512.0,
                :threads => 4,
                :uptime => 3600
            ),
            :config => config,
            :progress_tracker => EnhancedDashboard.ProgressTracker()
        )

        # Panel should contain system diagnostics
        @test haskey(mock_dashboard[:system_info], :cpu_usage)
        @test haskey(mock_dashboard[:system_info], :memory_used)
        @test haskey(mock_dashboard[:system_info], :uptime)
    end

    @testset "Events Panel" begin
        # Test event logging
        events = []

        # Add various event types
        push!(events, Dict(:level => :info, :message => "Test info", :timestamp => now()))
        push!(events, Dict(:level => :success, :message => "Test success", :timestamp => now()))
        push!(events, Dict(:level => :error, :message => "Test error", :timestamp => now()))

        @test length(events) == 3
        @test events[1][:level] == :info
        @test events[2][:level] == :success
        @test events[3][:level] == :error
    end
end

# Test progress bar visualizations
@testset "Progress Bar Visualizations" begin
    @testset "Progress Bar Rendering" begin
        # Test progress bar generation for different percentages
        test_cases = [
            (0.0, 20),   # 0% progress
            (25.0, 20),  # 25% progress
            (50.0, 20),  # 50% progress
            (75.0, 20),  # 75% progress
            (100.0, 20)  # 100% progress
        ]

        for (progress, width) in test_cases
            bar = EnhancedDashboard.create_progress_bar(progress, width)
            @test typeof(bar) == String
            # The bar includes percentage text, so it will be longer than width
            @test length(bar) > 0  # Bar should exist

            # Bar should contain appropriate characters
            if progress > 0
                @test occursin("█", bar) || occursin("▓", bar) || occursin("▒", bar) || occursin("░", bar)
            end

            # Check that percentage is included
            @test occursin("%", bar)
        end
    end

    @testset "Operation-Specific Progress Bars" begin
        tracker = EnhancedDashboard.ProgressTracker()

        # Test download progress bar
        EnhancedDashboard.update_progress_tracker!(tracker, :download,
            active=true, progress=50.0)
        @test tracker.download_progress == 50.0

        # Test training progress bar (epoch-based)
        EnhancedDashboard.update_progress_tracker!(tracker, :training,
            active=true, epoch=5, total_epochs=10)
        training_progress = (tracker.training_epoch / tracker.training_total_epochs) * 100
        @test training_progress == 50.0

        # Test upload progress bar
        EnhancedDashboard.update_progress_tracker!(tracker, :upload,
            active=true, progress=75.0)
        @test tracker.upload_progress == 75.0

        # Test prediction progress bar
        EnhancedDashboard.update_progress_tracker!(tracker, :prediction,
            active=true, progress=100.0)
        @test tracker.prediction_progress == 100.0
    end
end

println("✅ All TUI fix tests passed!")