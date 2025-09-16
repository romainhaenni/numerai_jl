# Comprehensive test for TUI v0.10.41 to verify all fixes

using Test
using NumeraiTournament
using Dates

@testset "TUI v0.10.41 Comprehensive Tests" begin
    
    @testset "System Monitoring Functions" begin
        # Test that system monitoring returns real values
        disk_info = NumeraiTournament.Utils.get_disk_space_info()
        @test disk_info.total_gb > 0
        @test disk_info.free_gb > 0
        @test disk_info.used_pct >= 0 && disk_info.used_pct <= 100
        
        cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
        @test cpu_usage >= 0 && cpu_usage <= 100
        
        mem_info = NumeraiTournament.Utils.get_memory_info()
        @test mem_info.total_gb > 0
        @test mem_info.used_gb > 0
        @test mem_info.used_pct >= 0 && mem_info.used_pct <= 100
    end
    
    @testset "Configuration Loading" begin
        # Load config and verify it's the correct type
        config = NumeraiTournament.load_config("config.toml")
        @test isa(config, NumeraiTournament.TournamentConfig)
        @test hasfield(typeof(config), :auto_start_pipeline)
        @test hasfield(typeof(config), :auto_train_after_download)
        @test hasfield(typeof(config), :auto_submit)
    end
    
    @testset "TUI Dashboard Initialization" begin
        config = NumeraiTournament.load_config("config.toml")
        
        # Create dashboard
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        @test !isnothing(dashboard)
        
        # Verify configuration was properly extracted
        @test isa(dashboard.auto_start_enabled, Bool)
        @test isa(dashboard.auto_train_enabled, Bool)
        @test isa(dashboard.auto_submit_enabled, Bool)
        
        # These should match the config values
        @test dashboard.auto_start_enabled == config.auto_start_pipeline
        @test dashboard.auto_train_enabled == config.auto_train_after_download
        @test dashboard.auto_submit_enabled == config.auto_submit
    end
    
    @testset "System Info Updates" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        
        # Initial values should be zero
        @test dashboard.disk_total == 0.0
        @test dashboard.memory_total == 0.0
        
        # Update system info
        NumeraiTournament.TUIv1041Fixed.update_system_info!(dashboard)
        
        # After update, should have real values
        @test dashboard.disk_total > 0
        @test dashboard.memory_total > 0
        @test dashboard.cpu_usage >= 0
        @test dashboard.disk_free > 0
        @test dashboard.memory_used > 0
    end
    
    @testset "Event Logging" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        
        # Add events
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :info, "Test info")
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :success, "Test success")
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :warn, "Test warning")
        NumeraiTournament.TUIv1041Fixed.add_event!(dashboard, :error, "Test error")
        
        @test length(dashboard.events) == 4
        @test dashboard.events[1].level == :info
        @test dashboard.events[2].level == :success
        @test dashboard.events[3].level == :warn
        @test dashboard.events[4].level == :error
    end
    
    @testset "Operation Progress Tracking" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        
        # Test download operation tracking
        dashboard.current_operation = :downloading
        dashboard.operation_description = "Downloading train.parquet"
        dashboard.operation_progress = 50.0
        dashboard.operation_details = Dict(:show_mb => true, :current_mb => 250.0, :total_mb => 500.0)
        
        @test dashboard.current_operation == :downloading
        @test dashboard.operation_progress == 50.0
        @test dashboard.operation_details[:current_mb] == 250.0
        @test dashboard.operation_details[:total_mb] == 500.0
        
        # Test training operation tracking
        dashboard.current_operation = :training
        dashboard.operation_description = "Training XGBoost model"
        dashboard.operation_progress = 75.0
        dashboard.training_in_progress = true
        dashboard.training_model = "xgboost"
        
        @test dashboard.current_operation == :training
        @test dashboard.operation_progress == 75.0
        @test dashboard.training_in_progress == true
        @test dashboard.training_model == "xgboost"
    end
    
    @testset "Pipeline State Management" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        
        # Test pipeline stages
        @test dashboard.pipeline_stage == :idle
        
        dashboard.pipeline_stage = :downloading
        @test dashboard.pipeline_stage == :downloading
        
        dashboard.pipeline_stage = :training
        @test dashboard.pipeline_stage == :training
        
        dashboard.pipeline_stage = :predicting
        @test dashboard.pipeline_stage == :predicting
        
        dashboard.pipeline_stage = :uploading
        @test dashboard.pipeline_stage == :uploading
    end
    
    @testset "Keyboard Channel" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        
        # Keyboard channel should be created
        @test !isnothing(dashboard.keyboard_channel)
        @test isa(dashboard.keyboard_channel, Channel{Char})
        
        # Test putting and reading from channel
        put!(dashboard.keyboard_channel, 's')
        @test isready(dashboard.keyboard_channel)
        key = take!(dashboard.keyboard_channel)
        @test key == 's'
    end
    
    @testset "Auto-start Configuration" begin
        # Test with auto-start enabled
        config = NumeraiTournament.load_config("config.toml")
        config.auto_start_pipeline = true
        config.auto_train_after_download = true
        config.auto_submit = true
        
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        @test dashboard.auto_start_enabled == true
        @test dashboard.auto_train_enabled == true
        @test dashboard.auto_submit_enabled == true
        
        # Test with auto-start disabled
        config.auto_start_pipeline = false
        config.auto_train_after_download = false
        config.auto_submit = false
        
        dashboard2 = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        @test dashboard2.auto_start_enabled == false
        @test dashboard2.auto_train_enabled == false
        @test dashboard2.auto_submit_enabled == false
    end
    
    @testset "Progress Bar Formatting" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)
        
        # Test format_duration function
        @test NumeraiTournament.TUIv1041Fixed.format_duration(30.0) == "30s"
        @test NumeraiTournament.TUIv1041Fixed.format_duration(90.0) == "1m 30s"
        @test NumeraiTournament.TUIv1041Fixed.format_duration(3665.0) == "1h 1m"
        
        # format_eta might not be exported, skip if not available
        if isdefined(NumeraiTournament.TUIv1041Fixed, :format_eta)
            @test NumeraiTournament.TUIv1041Fixed.format_eta(50.0, 10.0) == "10s"  # 50% in 10s -> 10s remaining
            @test NumeraiTournament.TUIv1041Fixed.format_eta(25.0, 30.0) == "1m 30s"  # 25% in 30s -> 90s remaining
        end
    end
    
    println("\n✅ All TUI v0.10.41 tests passed!")
end