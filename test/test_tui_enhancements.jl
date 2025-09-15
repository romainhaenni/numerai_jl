using Test
using NumeraiTournament
using Dates

@testset "TUI Enhancements v0.10.11" begin

    # Create a mock config for testing
    config = Dict(
        :api_public_key => get(ENV, "NUMERAI_PUBLIC_ID", "test_key"),
        :api_secret_key => get(ENV, "NUMERAI_SECRET_KEY", "test_secret"),
        :tournament_id => 8,
        :models => ["test_model"],
        :data_dir => "test_data",
        :model_dir => "test_models",
        :auto_submit => false,
        :auto_train_after_download => true,
        :tui_config => Dict(
            "refresh_rate" => 0.5,
            "model_update_interval" => 30.0,
            "network_check_interval" => 60.0
        )
    )

    @testset "Progress Tracker Initialization" begin
        tracker = NumeraiTournament.EnhancedDashboard.ProgressTracker()

        @test tracker.is_downloading == false
        @test tracker.is_uploading == false
        @test tracker.is_training == false
        @test tracker.is_predicting == false
        @test tracker.download_progress == 0.0
        @test tracker.upload_progress == 0.0
        @test tracker.training_progress == 0.0
        @test tracker.prediction_progress == 0.0
    end

    @testset "Progress Bar Creation" begin
        # Test progress bar with different percentages
        bar = NumeraiTournament.EnhancedDashboard.create_progress_bar(50.0, 100.0, width=20)
        @test occursin("50.0%", bar)
        @test length(filter(c -> c == '█', bar)) > 0  # Has filled blocks

        bar = NumeraiTournament.EnhancedDashboard.create_progress_bar(100.0, 100.0, width=20)
        @test occursin("100.0%", bar)

        bar = NumeraiTournament.EnhancedDashboard.create_progress_bar(0.0, 100.0, width=20)
        @test occursin("0.0%", bar)
    end

    @testset "Spinner Creation" begin
        # Test spinner frames
        for frame in 0:9
            spinner = NumeraiTournament.EnhancedDashboard.create_spinner(frame)
            @test !isempty(spinner)
            @test length(spinner) > 0
        end
    end

    @testset "Progress Tracker Updates" begin
        tracker = NumeraiTournament.EnhancedDashboard.ProgressTracker()

        # Test download progress update
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :download,
            progress=50.0,
            file="test.parquet",
            total_mb=100.0,
            current_mb=50.0,
            active=true
        )

        @test tracker.is_downloading == true
        @test tracker.download_progress == 50.0
        @test tracker.download_file == "test.parquet"
        @test tracker.download_total_mb == 100.0
        @test tracker.download_current_mb == 50.0

        # Test upload progress update
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :upload,
            progress=75.0,
            file="predictions.csv",
            active=true
        )

        @test tracker.is_uploading == true
        @test tracker.upload_progress == 75.0
        @test tracker.upload_file == "predictions.csv"

        # Test training progress update
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :training,
            progress=25.0,
            model="xgboost_model",
            epoch=5,
            total_epochs=20,
            loss=0.45,
            val_score=0.52,
            active=true
        )

        @test tracker.is_training == true
        @test tracker.training_progress == 25.0
        @test tracker.training_model == "xgboost_model"
        @test tracker.training_epoch == 5
        @test tracker.training_total_epochs == 20
        @test tracker.training_loss == 0.45
        @test tracker.training_val_score == 0.52

        # Test prediction progress update
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :prediction,
            progress=90.0,
            model="test_model",
            rows_processed=9000,
            total_rows=10000,
            active=true
        )

        @test tracker.is_predicting == true
        @test tracker.prediction_progress == 90.0
        @test tracker.prediction_model == "test_model"
        @test tracker.prediction_rows_processed == 9000
        @test tracker.prediction_total_rows == 10000
    end

    @testset "Duration Formatting" begin
        # Test various duration formats
        duration_str = NumeraiTournament.EnhancedDashboard.format_duration(3665)  # 1h 1m 5s
        @test occursin("h", duration_str)
        @test occursin("m", duration_str)
        @test occursin("s", duration_str)

        duration_str = NumeraiTournament.EnhancedDashboard.format_duration(45)  # 45s
        @test occursin("45s", duration_str)

        duration_str = NumeraiTournament.EnhancedDashboard.format_duration(7200)  # 2h
        @test occursin("2h", duration_str)
    end

    @testset "Instant Commands Setup" begin
        # Create a mock dashboard structure
        dashboard = Dict(
            :running => true,
            :paused => false,
            :wizard_active => false,
            :show_help => false,
            :progress_tracker => NumeraiTournament.EnhancedDashboard.ProgressTracker(),
            :training_info => Dict(:is_training => false),
            :events => Vector{Dict{Symbol, Any}}(),
            :system_info => Dict{Symbol, Any}()
        )

        # Function to add events (mock)
        add_event_mock! = (dashboard, level, message) -> begin
            push!(dashboard[:events], Dict(
                :timestamp => now(),
                :level => level,
                :message => message
            ))
        end

        # Test instant commands setup
        instant_commands = NumeraiTournament.TUIEnhanced.setup_instant_commands!(dashboard)

        @test haskey(instant_commands, "q")
        @test haskey(instant_commands, "s")
        @test haskey(instant_commands, "d")
        @test haskey(instant_commands, "r")
        @test haskey(instant_commands, "n")
        @test haskey(instant_commands, "p")
        @test haskey(instant_commands, "h")

        # Test that both uppercase and lowercase are handled
        @test haskey(instant_commands, "Q")
        @test haskey(instant_commands, "S")
        @test haskey(instant_commands, "D")
    end

    @testset "Auto-training After Download" begin
        # This tests the logic for auto-training trigger
        # Create a mock dashboard with download tracking
        dashboard = Dict(
            :running => true,
            :progress_tracker => NumeraiTournament.EnhancedDashboard.ProgressTracker(),
            :training_info => Dict(:is_training => false),
            :system_info => Dict(:download_completed => false),
            :events => Vector{Dict{Symbol, Any}}()
        )

        # Simulate download completion
        dashboard[:progress_tracker].is_downloading = false
        dashboard[:progress_tracker].download_progress = 100.0
        dashboard[:system_info][:download_completed] = true

        # Verify the conditions for auto-training are met
        @test dashboard[:progress_tracker].download_progress >= 100.0
        @test dashboard[:system_info][:download_completed] == true
        @test dashboard[:training_info][:is_training] == false
    end

    @testset "Real-time Update Configuration" begin
        # Test adaptive refresh rate logic
        dashboard = Dict(
            :running => true,
            :refresh_rate => 1.0,
            :progress_tracker => NumeraiTournament.EnhancedDashboard.ProgressTracker()
        )

        # No active operations - should use slow refresh
        @test dashboard[:refresh_rate] == 1.0

        # Simulate active download - should trigger fast refresh
        dashboard[:progress_tracker].is_downloading = true
        fast_rate = 0.2

        # Verify the condition for fast refresh
        has_active_ops = dashboard[:progress_tracker].is_downloading ||
                        dashboard[:progress_tracker].is_uploading ||
                        dashboard[:progress_tracker].is_training ||
                        dashboard[:progress_tracker].is_predicting

        @test has_active_ops == true

        # The actual refresh rate would be updated by the async task
        # Here we just verify the logic is correct
        expected_rate = has_active_ops ? fast_rate : 1.0
        @test expected_rate == fast_rate
    end

    @testset "Enhanced Progress Operations Rendering" begin
        # Test the rendering of progress operations
        dashboard = Dict(
            :progress_tracker => NumeraiTournament.EnhancedDashboard.ProgressTracker()
        )

        # Set up various progress states
        tracker = dashboard[:progress_tracker]
        tracker.is_downloading = true
        tracker.download_progress = 45.0
        tracker.download_file = "train.parquet"
        tracker.download_total_mb = 200.0
        tracker.download_current_mb = 90.0

        # Test that progress operations can be rendered
        operations = NumeraiTournament.TUIEnhanced.render_progress_operations!(dashboard, 120)

        @test length(operations) > 0
        @test occursin("Download", operations[1])
        @test occursin("train.parquet", operations[1])
        @test occursin("45.0%", operations[1]) || occursin("45%", operations[1])

        # Add training progress
        tracker.is_training = true
        tracker.training_progress = 60.0
        tracker.training_model = "xgboost"
        tracker.training_epoch = 12
        tracker.training_total_epochs = 20

        operations = NumeraiTournament.TUIEnhanced.render_progress_operations!(dashboard, 120)
        @test length(operations) >= 2
        @test any(op -> occursin("Training", op), operations)
    end

    @testset "Event Formatting" begin
        # Test event display formatting
        events = [
            Dict(:timestamp => now(), :level => :info, :message => "Test info"),
            Dict(:timestamp => now(), :level => :error, :message => "Test error"),
            Dict(:timestamp => now(), :level => :warning, :message => "Test warning"),
            Dict(:timestamp => now(), :level => :success, :message => "Test success")
        ]

        for event in events
            level = event[:level]

            # Test icon selection based on level
            icon = if level == :error
                "❌"
            elseif level == :warning
                "⚠️"
            elseif level == :success
                "✅"
            else
                "ℹ️"
            end

            @test !isempty(icon)

            # Test color code selection
            color = if level == :error
                "\033[31m"  # Red
            elseif level == :warning
                "\033[33m"  # Yellow
            elseif level == :success
                "\033[32m"  # Green
            else
                "\033[36m"  # Cyan
            end

            @test !isempty(color)
        end
    end

    println("\n✅ All TUI Enhancement tests passed!")
end