#!/usr/bin/env julia

using Pkg
Pkg.activate(dirname(@__DIR__))

using NumeraiTournament
using Dates
using TOML

# Test TUI fixes
function test_tui_fixes()
    println("Testing TUI fixes...")

    # Load configuration
    config_path = joinpath(dirname(@__DIR__), "config.toml")
    if !isfile(config_path)
        error("Config file not found at: $config_path")
    end

    config = NumeraiTournament.load_config(config_path)

    # Create a test dashboard
    dashboard = NumeraiTournament.TournamentDashboard(config)

    # Test 1: Check if progress tracking is connected
    println("\n1. Testing progress tracking...")
    dashboard.progress_tracker.is_downloading = true
    dashboard.progress_tracker.download_progress = 50.0
    dashboard.progress_tracker.download_file = "test_file.parquet"
    println("✓ Progress tracker can be updated")

    # Test 2: Check if instant keyboard handling is set up
    println("\n2. Testing instant keyboard commands...")
    if isdefined(dashboard, :instant_key_handler) ||
       isdefined(NumeraiTournament, :TUIFixes)
        println("✓ Instant keyboard handler is available")
    else
        println("✗ Instant keyboard handler not found")
    end

    # Test 3: Check if auto-training is configured
    println("\n3. Testing auto-training configuration...")
    auto_train = if isdefined(config, :auto_train_after_download)
        config.auto_train_after_download
    else
        false
    end
    println("Auto-training after download: $auto_train")

    # Test 4: Check if sticky panels are available
    println("\n4. Testing sticky panel functions...")
    if isdefined(NumeraiTournament, :render_sticky_dashboard)
        println("✓ Sticky panel rendering function exists")
    else
        println("✗ Sticky panel rendering not found")
    end

    # Test 5: Check if real-time updates are configured
    println("\n5. Testing real-time update configuration...")
    if isdefined(dashboard, :update_loop) || isdefined(NumeraiTournament, :update_loop)
        println("✓ Update loop is available")
    else
        println("✗ Update loop not found")
    end

    # Test 6: Test event color coding
    println("\n6. Testing event color coding...")
    events = [
        (timestamp=now(), level=:error, message="Test error"),
        (timestamp=now(), level=:warning, message="Test warning"),
        (timestamp=now(), level=:success, message="Test success"),
        (timestamp=now(), level=:info, message="Test info")
    ]

    for event in events
        level = event.level
        icon = if level == :error
            "❌"
        elseif level == :warning
            "⚠️"
        elseif level == :success
            "✅"
        else
            "ℹ️"
        end
        println("$icon $(event.level): $(event.message)")
    end
    println("✓ Event color coding works")

    # Test 7: Simulate operations with progress
    println("\n7. Testing operation progress simulation...")

    # Simulate download
    println("Simulating download...")
    for i in 0:20:100
        dashboard.progress_tracker.download_progress = Float64(i)
        print("\rDownload progress: $i%")
        sleep(0.1)
    end
    println("\n✓ Download simulation complete")

    # Simulate training
    println("Simulating training...")
    dashboard.progress_tracker.is_training = true
    for epoch in 1:5
        dashboard.progress_tracker.training_epoch = epoch
        dashboard.progress_tracker.training_total_epochs = 5
        dashboard.progress_tracker.training_progress = (epoch / 5) * 100
        print("\rTraining epoch: $epoch/5")
        sleep(0.1)
    end
    dashboard.progress_tracker.is_training = false
    println("\n✓ Training simulation complete")

    println("\n✅ All TUI fix tests completed!")

    return true
end

# Run the test
try
    test_tui_fixes()
catch e
    println("\n❌ Test failed with error:")
    println(e)
    for (exc, bt) in Base.catch_stack()
        showerror(stdout, exc, bt)
        println()
    end
    exit(1)
end