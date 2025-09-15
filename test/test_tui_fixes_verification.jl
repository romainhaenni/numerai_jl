using Test

# Load the NumeraiTournament module
include("../src/NumeraiTournament.jl")
using .NumeraiTournament

@testset "TUI Fixes Verification" begin
    # Create a test configuration
    config = NumeraiTournament.TournamentConfig(
        "test_public_id",
        "test_secret_key",
        ["test_model"],
        "test_data",
        "test_models",
        false,  # auto_submit
        0.0,    # stake_amount
        4,      # max_workers
        8,      # tournament_id
        true,   # auto_train_after_download - NEW FIELD
        "medium",  # feature_set
        false,  # compounding_enabled
        1.0,    # min_compound_amount
        100.0,  # compound_percentage
        10000.0, # max_stake_amount
        Dict{String, Any}(),  # tui_config
        0.1,    # sample_pct
        "target",  # target_col
        false,  # enable_neutralization
        0.5,    # neutralization_proportion
        false,  # enable_dynamic_sharpe
        20,     # sharpe_history_rounds
        10      # sharpe_min_data_points
    )

    @testset "Configuration has auto_train_after_download" begin
        @test hasfield(typeof(config), :auto_train_after_download)
        @test config.auto_train_after_download == true
    end

    @testset "TUIFixes module functions exist" begin
        # Check that the module and functions are accessible
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :handle_direct_command)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :read_key_improved)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :handle_post_download_training)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :ensure_realtime_updates!)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :apply_tui_fixes!)
    end

    @testset "Progress callback functions exist" begin
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :create_download_callback)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :create_upload_callback)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :create_training_callback)
        @test isdefined(NumeraiTournament.Dashboard.TUIFixes, :create_prediction_callback)
    end

    @testset "Dashboard functions for operations exist" begin
        @test isdefined(NumeraiTournament.Dashboard, :download_tournament_data)
        @test isdefined(NumeraiTournament.Dashboard, :start_training)
        @test isdefined(NumeraiTournament.Dashboard, :submit_predictions_to_numerai)
        @test isdefined(NumeraiTournament.Dashboard, :update_model_performances!)
    end

    @testset "Sticky panel rendering functions exist" begin
        @test isdefined(NumeraiTournament.Dashboard, :render_sticky_dashboard)
        @test isdefined(NumeraiTournament.Dashboard, :render_top_sticky_panel)
        @test isdefined(NumeraiTournament.Dashboard, :render_bottom_sticky_panel)
        @test isdefined(NumeraiTournament.Dashboard, :render_middle_content)
    end

    @testset "System info update function exists" begin
        @test isdefined(NumeraiTournament.Dashboard, :update_system_info!)
    end

    @testset "Apply TUI fixes returns status dictionary" begin
        # Create a mock dashboard for testing
        api_client = NumeraiTournament.API.NumeraiClient("test", "test")
        # Use the correct constructor that takes only config
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)

        # Apply TUI fixes and check return value
        fixes_status = NumeraiTournament.Dashboard.TUIFixes.apply_tui_fixes!(dashboard)

        @test isa(fixes_status, Dict{Symbol, Bool})
        @test haskey(fixes_status, :instant_commands)
        @test haskey(fixes_status, :progress_bars)
        @test haskey(fixes_status, :auto_training)
        @test haskey(fixes_status, :sticky_panels)
        @test haskey(fixes_status, :realtime_updates)

        # All fixes should report as working
        @test all(values(fixes_status))
    end
end

println("✅ All TUI fixes verification tests passed!")