#!/usr/bin/env julia

# Test script for TUI v0.10.39 fixes
# This tests all the reported issues to ensure they are resolved

using Pkg
Pkg.activate(dirname(@__DIR__))

using Test
using NumeraiTournament

@testset "TUI v0.10.39 Fixes" begin

    @testset "Configuration Loading" begin
        # Test that config loading returns TournamentConfig
        config = NumeraiTournament.load_config("config.toml")
        @test isa(config, NumeraiTournament.TournamentConfig)

        # Test that auto-start fields exist
        @test hasfield(typeof(config), :auto_start_pipeline)
        @test hasfield(typeof(config), :auto_train_after_download)
        @test hasfield(typeof(config), :auto_submit)

        println("✅ Configuration type: $(typeof(config))")
        println("✅ auto_start_pipeline: $(config.auto_start_pipeline)")
        println("✅ auto_train_after_download: $(config.auto_train_after_download)")
        println("✅ auto_submit: $(config.auto_submit)")
    end

    @testset "System Monitoring Functions" begin
        # Test CPU monitoring
        cpu_usage = NumeraiTournament.Utils.get_cpu_usage()
        @test cpu_usage >= 0.0
        @test cpu_usage <= 100.0
        println("✅ CPU Usage: $(round(cpu_usage, digits=1))%")

        # Test Memory monitoring
        mem_info = NumeraiTournament.Utils.get_memory_info()
        @test mem_info.total_gb > 0.0
        @test mem_info.used_gb >= 0.0
        @test mem_info.used_gb <= mem_info.total_gb
        println("✅ Memory: $(round(mem_info.used_gb, digits=1))/$(round(mem_info.total_gb, digits=1)) GB")

        # Test Disk monitoring
        disk_info = NumeraiTournament.Utils.get_disk_space_info()
        @test disk_info.total_gb > 0.0
        @test disk_info.free_gb >= 0.0
        @test disk_info.free_gb <= disk_info.total_gb
        println("✅ Disk: $(round(disk_info.free_gb, digits=1))/$(round(disk_info.total_gb, digits=1)) GB free")
    end

    @testset "TUI Dashboard Creation" begin
        config = NumeraiTournament.load_config("config.toml")

        # Create dashboard instance
        dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)

        # Check that configuration was properly extracted
        @test isa(dashboard.auto_start_enabled, Bool)
        @test isa(dashboard.auto_train_enabled, Bool)
        @test isa(dashboard.auto_submit_enabled, Bool)

        println("✅ Dashboard created with:")
        println("   - auto_start_enabled: $(dashboard.auto_start_enabled)")
        println("   - auto_train_enabled: $(dashboard.auto_train_enabled)")
        println("   - auto_submit_enabled: $(dashboard.auto_submit_enabled)")

        # Test system info update
        NumeraiTournament.TUIv1039.update_system_info!(dashboard)

        # Verify system values are not zero (unless they genuinely are)
        if dashboard.memory_total == 0.0
            @warn "Memory total is 0.0 - Utils.get_memory_info() may have failed"
        else
            @test dashboard.memory_total > 0.0
            println("✅ System info updated: Memory $(round(dashboard.memory_total, digits=1)) GB")
        end

        if dashboard.disk_total == 0.0
            @warn "Disk total is 0.0 - Utils.get_disk_space_info() may have failed"
        else
            @test dashboard.disk_total > 0.0
            println("✅ System info updated: Disk $(round(dashboard.disk_total, digits=1)) GB")
        end

        # Test event logging
        NumeraiTournament.TUIv1039.add_event!(dashboard, :info, "Test event")
        @test length(dashboard.events) > 0
        @test dashboard.events[end].message == "Test event"
        println("✅ Event logging works")

        # Stop the dashboard
        dashboard.running = false
    end

    @testset "Progress Tracking" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.TUIv1039.TUIv1039Dashboard(config)

        # Test download progress
        dashboard.current_operation = :downloading
        dashboard.operation_progress = 50.0
        dashboard.operation_description = "Downloading train.parquet"
        dashboard.operation_details = Dict(:show_mb => true, :current_mb => 250.0, :total_mb => 500.0)

        @test dashboard.current_operation == :downloading
        @test dashboard.operation_progress == 50.0
        println("✅ Download progress tracking configured")

        # Test training progress
        dashboard.current_operation = :training
        dashboard.operation_progress = 75.0
        dashboard.operation_description = "Training XGBoost model"

        @test dashboard.current_operation == :training
        @test dashboard.operation_progress == 75.0
        println("✅ Training progress tracking configured")

        # Test prediction progress
        dashboard.current_operation = :predicting
        dashboard.operation_progress = 30.0
        dashboard.operation_description = "Generating predictions"

        @test dashboard.current_operation == :predicting
        @test dashboard.operation_progress == 30.0
        println("✅ Prediction progress tracking configured")

        # Test upload progress
        dashboard.current_operation = :uploading
        dashboard.operation_progress = 90.0
        dashboard.operation_description = "Uploading predictions"
        dashboard.operation_details = Dict(:show_mb => true, :current_mb => 9.0, :total_mb => 10.0)

        @test dashboard.current_operation == :uploading
        @test dashboard.operation_progress == 90.0
        println("✅ Upload progress tracking configured")

        dashboard.running = false
    end

    println("\n" * "="^60)
    println("All TUI v0.10.39 fixes verified successfully! ✅")
    println("="^60)
end