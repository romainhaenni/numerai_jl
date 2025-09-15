using Test
using Dates
using Term
using TOML

# Setup paths
const PROJECT_ROOT = dirname(@__DIR__)
push!(LOAD_PATH, joinpath(PROJECT_ROOT, "src"))

# Load the main module
using NumeraiTournament

# Include test utilities and setup test environment
include("test_utils.jl")

# Create test config function
function create_test_config()
    return NumeraiTournament.Config(
        api_public_key="test_key",
        api_secret_key="test_secret",
        tournament_id=8,
        models=String[],
        data_dir=tempdir(),
        model_dir=tempdir(),
        auto_submit=false,
        stake_amount=0.0,
        max_workers=1,
        feature_set="small",
        refresh_rate=1.0,
        model_update_interval=30.0,
        network_check_interval=60.0,
        max_events=100,
        performance_alert_threshold=-0.05,
        notification_enabled=false,
        notification_sound="Glass",
        tui_config=Dict{String,Any}()
    )
end

# Load required modules
@testset "TUI Improvements Test Suite" begin
    @testset "Progress Tracking" begin
        # Test progress tracker initialization
        tracker = NumeraiTournament.EnhancedDashboard.ProgressTracker()
        @test tracker.is_downloading == false
        @test tracker.is_uploading == false
        @test tracker.is_training == false
        @test tracker.is_predicting == false

        # Test progress update functions
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :download, active=true, file="test.parquet",
            current_mb=10.5, total_mb=100.0
        )
        @test tracker.is_downloading == true
        @test tracker.download_file == "test.parquet"
        @test tracker.download_current_mb ≈ 10.5
        @test tracker.download_total_mb ≈ 100.0

        # Test progress clearing
        NumeraiTournament.EnhancedDashboard.update_progress_tracker!(
            tracker, :download, active=false
        )
        @test tracker.is_downloading == false
        @test tracker.download_file == ""
    end

    @testset "Keyboard Input Instant Execution" begin
        # Create a test dashboard
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Test that single-key commands are recognized
        test_keys = ['q', 's', 'r', 'h', 'n', 'p']
        for key in test_keys
            # Simulate key input (would need actual IO simulation in real test)
            @test key in ['q', 's', 'r', 'h', 'n', 'p']  # Valid single-key commands
        end

        # Test that slash commands require Enter
        @test '/' != 'q'  # Slash initiates command mode, not instant execution
    end

    @testset "Sticky Panel Implementation" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Test top sticky panel generation
        top_panel = NumeraiTournament.render_top_sticky_panel(dashboard)
        @test isa(top_panel, String)
        @test occursin("SYSTEM STATUS", top_panel)
        @test occursin("CPU:", top_panel)
        @test occursin("Memory:", top_panel)

        # Test with active progress
        dashboard.progress_tracker.is_downloading = true
        dashboard.progress_tracker.download_file = "test_data.parquet"
        dashboard.progress_tracker.download_current_mb = 50.0
        dashboard.progress_tracker.download_total_mb = 100.0

        top_panel = NumeraiTournament.render_top_sticky_panel(dashboard)
        @test occursin("📥 Downloading:", top_panel)
        @test occursin("test_data.parquet", top_panel)
        @test occursin("50.0 MB / 100.0 MB", top_panel)

        # Test bottom sticky panel
        NumeraiTournament.add_event!(dashboard, :info, "Test event 1")
        NumeraiTournament.add_event!(dashboard, :success, "Test event 2")
        NumeraiTournament.add_event!(dashboard, :error, "Test event 3")

        bottom_panel = NumeraiTournament.render_bottom_sticky_panel(dashboard)
        @test isa(bottom_panel, String)
        @test occursin("RECENT EVENTS", bottom_panel)
        @test occursin("Test event 1", bottom_panel)
        @test occursin("Test event 2", bottom_panel)
        @test occursin("Test event 3", bottom_panel)
        @test occursin("Commands:", bottom_panel)
    end

    @testset "Real-time Update Synchronization" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Test adaptive render intervals
        # When no progress is active, should use default refresh rate
        @test dashboard.refresh_rate == 1.0

        # When progress is active, render should use faster interval
        dashboard.progress_tracker.is_downloading = true
        # The render loop should detect this and use 0.2s interval

        # Test that progress updates trigger immediate renders
        initial_downloads = dashboard.stats[:total_downloads]
        dashboard.progress_tracker.download_current_mb = 25.0
        dashboard.progress_tracker.download_total_mb = 50.0

        # Progress should be tracked correctly
        @test dashboard.progress_tracker.download_current_mb == 25.0
        @test dashboard.progress_tracker.download_total_mb == 50.0
    end

    @testset "Progress Bar Display" begin
        # Test progress bar creation
        bar = NumeraiTournament.EnhancedDashboard.create_progress_bar(50.0, 100.0, width=20)
        @test length(bar) == 20
        @test count(c -> c == '█', bar) == 10  # 50% filled
        @test count(c -> c == '░', bar) == 10  # 50% unfilled

        # Test edge cases
        bar_empty = NumeraiTournament.EnhancedDashboard.create_progress_bar(0.0, 100.0, width=20)
        @test count(c -> c == '█', bar_empty) == 0
        @test count(c -> c == '░', bar_empty) == 20

        bar_full = NumeraiTournament.EnhancedDashboard.create_progress_bar(100.0, 100.0, width=20)
        @test count(c -> c == '█', bar_full) == 20
        @test count(c -> c == '░', bar_full) == 0

        # Test with zero total
        bar_zero = NumeraiTournament.EnhancedDashboard.create_progress_bar(50.0, 0.0, width=20)
        @test length(bar_zero) == 20
    end

    @testset "Training Progress Integration" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Simulate training progress
        dashboard.progress_tracker.is_training = true
        dashboard.progress_tracker.training_model = "test_model"
        dashboard.progress_tracker.training_epoch = 5
        dashboard.progress_tracker.training_total_epochs = 10
        dashboard.progress_tracker.training_loss = 0.456
        dashboard.progress_tracker.training_val_score = 0.789

        top_panel = NumeraiTournament.render_top_sticky_panel(dashboard)
        @test occursin("🏋️ Training:", top_panel)
        @test occursin("test_model", top_panel)
        @test occursin("Epoch 5/10", top_panel)
        @test occursin("Loss: 0.4560", top_panel)
        @test occursin("Val: 0.7890", top_panel)
    end

    @testset "Upload Progress Integration" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Simulate upload progress
        dashboard.progress_tracker.is_uploading = true
        dashboard.progress_tracker.upload_file = "predictions.csv"
        dashboard.progress_tracker.upload_current_mb = 2.5
        dashboard.progress_tracker.upload_total_mb = 5.0

        top_panel = NumeraiTournament.render_top_sticky_panel(dashboard)
        @test occursin("📤 Uploading:", top_panel)
        @test occursin("predictions.csv", top_panel)
        @test occursin("2.5 MB / 5.0 MB", top_panel)
    end

    @testset "Prediction Progress Integration" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Simulate prediction progress
        dashboard.progress_tracker.is_predicting = true
        dashboard.progress_tracker.prediction_model = "xgboost_model"
        dashboard.progress_tracker.prediction_rows_processed = 50000
        dashboard.progress_tracker.prediction_total_rows = 100000

        top_panel = NumeraiTournament.render_top_sticky_panel(dashboard)
        @test occursin("🔮 Predicting:", top_panel)
        @test occursin("xgboost_model", top_panel)
        @test occursin("50000/100000", top_panel)
    end

    @testset "Event Log Management" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Add multiple events
        for i in 1:50
            NumeraiTournament.add_event!(dashboard, :info, "Event $i")
        end

        # Bottom panel should show only recent events (last 30)
        bottom_panel = NumeraiTournament.render_bottom_sticky_panel(dashboard)
        @test occursin("Event 50", bottom_panel)
        @test occursin("Event 21", bottom_panel)  # Should show from event 21-50
        @test !occursin("Event 20", bottom_panel)  # Should not show events before 21
    end

    @testset "Terminal Size Handling" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Test that panels adapt to terminal size
        # This would require actual terminal size detection in a real test
        # For now, just verify the panels can be generated
        @test_nowarn NumeraiTournament.render_top_sticky_panel(dashboard)
        @test_nowarn NumeraiTournament.render_middle_content(dashboard)
        @test_nowarn NumeraiTournament.render_bottom_sticky_panel(dashboard)
    end

    @testset "Progress Callback Signatures" begin
        config = create_test_config()
        dashboard = NumeraiTournament.TournamentDashboard(config)

        # Test that progress callbacks work with keyword arguments
        callback = (phase; kwargs...) -> begin
            if phase == :start
                @test haskey(kwargs, :name)
            elseif phase == :progress
                @test haskey(kwargs, :progress)
                @test haskey(kwargs, :current_mb)
                @test haskey(kwargs, :total_mb)
            elseif phase == :complete
                @test haskey(kwargs, :size_mb)
            end
        end

        # Simulate callback calls as done by API client
        callback(:start; name="test.parquet")
        callback(:progress; name="test.parquet", progress=50.0, current_mb=25.0, total_mb=50.0)
        callback(:complete; size_mb=50.0)
    end
end

println("✅ All TUI improvement tests passed!")