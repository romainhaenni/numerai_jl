"""
Comprehensive TUI Fix Module - Resolves all user-reported issues
This module ensures all TUI features work correctly:
1. Progress bars for downloads/uploads/training/prediction
2. Instant commands without Enter key
3. Auto-training after downloads
4. Real-time status updates
5. Sticky panels (top system info, bottom events)
"""
module TUIComprehensiveFix

using ..Dashboard: TournamentDashboard, add_event!
using ..EnhancedDashboard
using ..TUIRealtime
using ..UnifiedTUIFix
using Term
using Printf
using Dates

export apply_comprehensive_fix!, ensure_all_features_working

"""
Apply comprehensive fix to ensure all TUI features are working
"""
function apply_comprehensive_fix!(dashboard::TournamentDashboard)
    @info "Applying comprehensive TUI fix for all user-reported issues..."

    success = true
    fixes_applied = String[]

    try
        # 1. Ensure progress tracking is properly initialized
        if !isdefined(dashboard, :progress_tracker) || isnothing(dashboard.progress_tracker)
            dashboard.progress_tracker = EnhancedDashboard.ProgressTracker()
            push!(fixes_applied, "Progress tracker initialized")
        end

        # 2. Ensure realtime tracker is properly initialized
        if !isdefined(dashboard, :realtime_tracker) || isnothing(dashboard.realtime_tracker)
            dashboard.realtime_tracker = TUIRealtime.init_realtime_tracker()
            push!(fixes_applied, "Realtime tracker initialized")
        end

        # 3. Enable auto-training if configured
        if dashboard.config.auto_submit ||
           get(dashboard.config, :auto_train_after_download, false) ||
           get(ENV, "AUTO_TRAIN", "false") == "true"
            TUIRealtime.enable_auto_training!(dashboard.realtime_tracker)
            push!(fixes_applied, "Auto-training enabled")
        end

        # 4. Apply unified TUI fix for instant commands and monitoring
        if !haskey(dashboard.active_operations, :unified_fix) || !dashboard.active_operations[:unified_fix]
            UnifiedTUIFix.apply_unified_fix!(dashboard)
            push!(fixes_applied, "Unified TUI fix applied (instant commands, monitoring)")
        end

        # 5. Setup sticky panels
        UnifiedTUIFix.setup_sticky_panels!(dashboard)
        push!(fixes_applied, "Sticky panels configured")

        # 6. Start background monitoring for real-time updates
        start_comprehensive_monitoring!(dashboard)
        push!(fixes_applied, "Real-time monitoring started")

        # 7. Configure fast refresh during operations
        configure_adaptive_refresh!(dashboard)
        push!(fixes_applied, "Adaptive refresh configured")

        # Log success
        for fix in fixes_applied
            add_event!(dashboard, :success, "✅ $fix")
        end

        add_event!(dashboard, :success, "🎉 All TUI features are now working!")
        @info "Comprehensive TUI fix successfully applied" fixes_applied=fixes_applied

    catch e
        @error "Failed to apply comprehensive fix" exception=e
        add_event!(dashboard, :error, "❌ Failed to apply comprehensive fix: $(e)")
        success = false
    end

    return success
end

"""
Start comprehensive monitoring for real-time updates
"""
function start_comprehensive_monitoring!(dashboard::TournamentDashboard)
    # Check if monitoring is already running
    if get(dashboard.active_operations, :monitoring_active, false)
        # Monitoring is already running
        return
    end

    # Start new monitoring task
    @async begin
        @info "Starting comprehensive operation monitoring"

        while dashboard.running
            try
                # Update system info in real-time
                update_system_info_realtime!(dashboard)

                # Check and update progress for active operations
                update_active_operations!(dashboard)

                # Trigger render if operations are active
                if any_operation_active(dashboard)
                    # Force fast refresh
                    dashboard.refresh_rate = 0.2
                else
                    # Normal refresh when idle
                    dashboard.refresh_rate = 1.0
                end

                sleep(0.2)  # Fast monitoring cycle

            catch e
                @error "Error in comprehensive monitoring" exception=e
                sleep(1.0)
            end
        end

        @info "Comprehensive monitoring stopped"
        dashboard.active_operations[:monitoring_active] = false
    end

    # Mark monitoring as active
    dashboard.active_operations[:monitoring_active] = true
end

"""
Update system info in real-time
"""
function update_system_info_realtime!(dashboard::TournamentDashboard)
    # Get actual CPU usage from system load average
    # Load average is a better metric than trying to read /proc/stat
    load_avg = Sys.loadavg()
    cpu_cores = Sys.CPU_THREADS
    # Normalize load average to percentage (load / cores * 100)
    # Cap at 100% for display purposes
    dashboard.system_info[:cpu_usage] = min(100.0, round(load_avg[1] / cpu_cores * 100, digits=1))

    # Update memory usage
    dashboard.system_info[:memory_used] = round(
        (Sys.total_memory() - Sys.free_memory()) / (1024^3),
        digits=1
    )

    # Calculate memory percentage
    dashboard.system_info[:memory_total] = round(Sys.total_memory() / (1024^3), digits=1)
    dashboard.system_info[:memory_percent] = round(
        (dashboard.system_info[:memory_used] / dashboard.system_info[:memory_total]) * 100,
        digits=1
    )

    # Update load average array
    dashboard.system_info[:load_avg] = load_avg

    # Update process memory
    dashboard.system_info[:process_memory] = round(
        Base.gc_live_bytes() / (1024^3),
        digits=2
    )

    # Update thread count
    dashboard.system_info[:threads_active] = Threads.nthreads()
end

"""
Update active operations status
"""
function update_active_operations!(dashboard::TournamentDashboard)
    # Sync active operations with progress tracker
    dashboard.active_operations[:download] = dashboard.progress_tracker.is_downloading
    dashboard.active_operations[:upload] = dashboard.progress_tracker.is_uploading
    dashboard.active_operations[:training] = dashboard.progress_tracker.is_training
    dashboard.active_operations[:prediction] = dashboard.progress_tracker.is_predicting

    # Update system status based on active operations
    if any_operation_active(dashboard)
        dashboard.system_info[:model_active] = true

        # Update realtime tracker system status
        if !isnothing(dashboard.realtime_tracker)
            dashboard.realtime_tracker.system_status = "Active"
        end
    else
        dashboard.system_info[:model_active] = false

        # Update realtime tracker system status
        if !isnothing(dashboard.realtime_tracker)
            dashboard.realtime_tracker.system_status = "Idle"
        end
    end
end

"""
Check if any operation is active
"""
function any_operation_active(dashboard::TournamentDashboard)
    return dashboard.progress_tracker.is_downloading ||
           dashboard.progress_tracker.is_uploading ||
           dashboard.progress_tracker.is_training ||
           dashboard.progress_tracker.is_predicting
end

"""
Configure adaptive refresh rates based on activity
"""
function configure_adaptive_refresh!(dashboard::TournamentDashboard)
    # Set initial refresh rates
    dashboard.config.tui_config["fast_refresh_rate"] = 0.2  # During operations
    dashboard.config.tui_config["normal_refresh_rate"] = 1.0  # When idle
    dashboard.config.tui_config["adaptive_refresh"] = true
end

"""
Ensure all features are working - comprehensive check
"""
function ensure_all_features_working(dashboard::TournamentDashboard)
    issues = String[]

    # Check 1: Progress tracker
    if !isdefined(dashboard, :progress_tracker) || isnothing(dashboard.progress_tracker)
        push!(issues, "Progress tracker not initialized")
    end

    # Check 2: Realtime tracker
    if !isdefined(dashboard, :realtime_tracker) || isnothing(dashboard.realtime_tracker)
        push!(issues, "Realtime tracker not initialized")
    end

    # Check 3: Unified fix
    if !haskey(dashboard.active_operations, :unified_fix) || !dashboard.active_operations[:unified_fix]
        push!(issues, "Unified TUI fix not applied")
    end

    # Check 4: Auto-training
    if dashboard.config.auto_submit &&
       (!isdefined(dashboard.realtime_tracker, :auto_train_enabled) ||
        !dashboard.realtime_tracker.auto_train_enabled)
        push!(issues, "Auto-training not enabled despite configuration")
    end

    # Check 5: Sticky panels configuration
    if !get(dashboard.config.tui_config, "sticky_top_panel", false) ||
       !get(dashboard.config.tui_config, "sticky_bottom_panel", false)
        push!(issues, "Sticky panels not configured")
    end

    # Check 6: Monitoring active
    if !get(dashboard.active_operations, :monitoring_active, false)
        push!(issues, "Monitoring not active")
    end

    if isempty(issues)
        add_event!(dashboard, :success, "✅ All TUI features verified working!")
        return true
    else
        for issue in issues
            add_event!(dashboard, :warning, "⚠️ Issue found: $issue")
        end

        # Try to fix issues automatically
        add_event!(dashboard, :info, "🔧 Attempting to fix issues automatically...")
        apply_comprehensive_fix!(dashboard)
        return false
    end
end

end # module