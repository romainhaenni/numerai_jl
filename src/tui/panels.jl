module Panels

using Term
using Term: Panel
import Term.Tables as TermTables
using Dates
using DataFrames
using ..Charts
using Statistics: mean, std

function create_model_performance_panel(model::Dict{Symbol, Any}, config=nothing)::Panel
    status_icon = model[:is_active] ? "🟢 Active" : "🔴 Inactive"
    
    content = """
    Model: $(model[:name])
    Status: $status_icon
    
    Performance Metrics:
    ─────────────────────
    CORR:   $(round(model[:corr], digits=4))
    MMC:    $(round(model[:mmc], digits=4))
    FNC:    $(round(model[:fnc], digits=4))
    TC:     $(round(get(model, :tc, 0.0), digits=4))
    Sharpe: $(round(get(model, :sharpe, 0.0), digits=3))
    """
    
    # Get panel width from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "model_panel_width")
        config.tui_config["panels"]["model_panel_width"]
    else
        40  # default fallback, smaller for single model
    end
    
    return Panel(
        content,
        title="📊 Model Performance",
        style="blue",
        width=panel_width
    )
end

function create_staking_panel(stake_info::Dict{Symbol, Any}, config=nothing)::Panel
    content = """
    Total Staked: $(stake_info[:total_stake]) NMR
    At Risk: $(stake_info[:at_risk]) NMR
    Expected Payout: $(stake_info[:expected_payout]) NMR
    
    Current Round: #$(stake_info[:current_round])
    Submission Status: $(stake_info[:submission_status])
    Time Remaining: $(stake_info[:time_remaining])
    """
    
    # Get panel width from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "staking_panel_width")
        config.tui_config["panels"]["staking_panel_width"]
    else
        40  # default fallback
    end
    
    return Panel(
        content,
        title="💰 Staking Status",
        style="green",
        width=panel_width
    )
end

function create_predictions_panel(predictions_history::Vector{Float64}, config=nothing)::Panel
    if isempty(predictions_history)
        content = "No predictions yet"
    else
        # Get chart dimensions from config
        chart_width = if config !== nothing && haskey(config.tui_config, "charts") && haskey(config.tui_config["charts"], "sparkline_width")
            config.tui_config["charts"]["sparkline_width"]
        else
            35  # default fallback
        end
        chart_height = if config !== nothing && haskey(config.tui_config, "charts") && haskey(config.tui_config["charts"], "sparkline_height")
            config.tui_config["charts"]["sparkline_height"]
        else
            6  # default fallback
        end
        
        chart = Charts.create_sparkline(predictions_history, width=chart_width, height=chart_height)
        
        stats = """
        Latest: $(round(predictions_history[end], digits=4))
        Mean: $(round(mean(predictions_history), digits=4))
        Std: $(round(std(predictions_history), digits=4))
        """
        
        content = chart * "\n\n" * stats
    end
    
    # Get panel width from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "predictions_panel_width")
        config.tui_config["panels"]["predictions_panel_width"]
    else
        40  # default fallback
    end
    
    return Panel(
        content,
        title="📈 Live Predictions",
        style="yellow",
        width=panel_width
    )
end

function create_events_panel(events::Vector{Dict{Symbol, Any}}, config=nothing; max_events::Union{Int,Nothing}=nothing)::Panel
    if isempty(events)
        content = "No recent events"
    else
        lines = String[]
        
        # Get max events from config if not provided
        if max_events === nothing
            max_events = if config !== nothing && haskey(config.tui_config, "limits") && haskey(config.tui_config["limits"], "max_events_display")
                config.tui_config["limits"]["max_events_display"]
            else
                20  # default fallback
            end
        end
        
        for event in events[max(1, end-max_events+1):end]
            timestamp = Dates.format(event[:time], "HH:MM:SS")
            
            # Enhanced color coding based on severity (if available) or type
            color = if haskey(event, :severity)
                # Use severity-based colors for enhanced error events
                severity = event[:severity]
                if severity == :CRITICAL
                    "bold red"
                elseif severity == :HIGH
                    "red"
                elseif severity == :MEDIUM
                    "yellow"
                elseif severity == :LOW
                    "cyan"
                else
                    "white"
                end
            else
                # Fallback to type-based colors for standard events
                if event[:type] == :error
                    "red"
                elseif event[:type] == :warning
                    "yellow"
                elseif event[:type] == :success
                    "green"
                else
                    "white"
                end
            end
            
            # Enhanced icon logic - if event has severity info, it already includes severity icon
            icon = if haskey(event, :severity)
                ""  # Severity icon already included in message
            else
                # Standard icons for non-categorized events
                if event[:type] == :error
                    "❌"
                elseif event[:type] == :warning
                    "⚠️"
                elseif event[:type] == :success
                    "✅"
                else
                    "ℹ️"
                end
            end
            
            # Add category info for enhanced errors
            category_info = if haskey(event, :category)
                category_name = string(event[:category])
                category_display = replace(category_name, "_" => " ")
                " [$(category_display)]"
            else
                ""
            end
            
            # Format line with Term styling
            line = if haskey(event, :severity)
                "[$timestamp]$category_info $(event[:message])"
            else
                "[$timestamp] $icon $(event[:message])"
            end
            
            # Apply color styling - Term.highlight doesn't support color, just use plain text
            # or apply color using Term's markup syntax
            styled_line = line  # For now, just use plain text
            push!(lines, styled_line)
        end
        
        content = join(reverse(lines), "\n")
    end
    
    # Dynamic panel title based on recent error types
    error_count = count(e -> e[:type] == :error, events)
    warning_count = count(e -> e[:type] == :warning, events)
    
    title_suffix = if error_count > 0
        " ($(error_count) errors)"
    elseif warning_count > 0
        " ($(warning_count) warnings)"
    else
        ""
    end
    
    # Get panel dimensions from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "events_panel_width")
        config.tui_config["panels"]["events_panel_width"]
    else
        60  # default fallback
    end
    panel_height = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "events_panel_height")
        config.tui_config["panels"]["events_panel_height"]
    else
        22  # default fallback
    end
    
    return Panel(
        content,
        title="🔔 Recent Events$title_suffix",
        style="cyan",
        width=panel_width,
        height=panel_height
    )
end

function create_system_panel(system_info::Dict{Symbol, Any}, network_status::Union{Nothing, Dict{Symbol, Any}}=nothing, config=nothing)::Panel
    cpu_bar = create_progress_bar(system_info[:cpu_usage], 100)
    mem_bar = create_progress_bar(system_info[:memory_used], system_info[:memory_total])
    
    # Network status display
    network_info = if network_status !== nothing
        connection_icon = network_status[:is_connected] ? "🟢" : "🔴"
        connection_status = network_status[:is_connected] ? "Connected" : "Disconnected"
        
        latency_display = if network_status[:is_connected] && network_status[:api_latency] > 0
            " ($(round(network_status[:api_latency], digits=0))ms)"
        else
            ""
        end
        
        failure_info = if network_status[:consecutive_failures] > 0
            " - $(network_status[:consecutive_failures]) failures"
        else
            ""
        end
        
        "Network: $connection_icon $connection_status$latency_display$failure_info"
    else
        "Network: ❓ Unknown"
    end
    
    content = """
    CPU Usage: $cpu_bar $(system_info[:cpu_usage])%
    Memory: $mem_bar $(round(system_info[:memory_used], digits=1))/$(system_info[:memory_total]) GB
    
    Model Status: $(system_info[:model_active] ? "🟢 Active" : "🔴 Inactive")
    Threads: $(system_info[:threads])
    Uptime: $(format_uptime(system_info[:uptime]))
    
    $network_info
    """
    
    # Get panel width from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "system_panel_width")
        config.tui_config["panels"]["system_panel_width"]
    else
        40  # default fallback
    end
    
    return Panel(
        content,
        title="⚙️ System Status",
        style="magenta",
        width=panel_width
    )
end

function create_training_panel(training_info::Dict{Symbol, Any}, config=nothing)::Panel
    if !training_info[:is_training]
        content = "No training in progress"
    else
        # Get progress bar width from config
        progress_width = if config !== nothing && haskey(config.tui_config, "training") && haskey(config.tui_config["training"], "progress_bar_width")
            config.tui_config["training"]["progress_bar_width"]
        else
            20  # default fallback
        end
        
        progress_bar = create_progress_bar(training_info[:progress], 100, width=progress_width)
        
        content = """
        Model: $(get(training_info, :model_name, "unknown"))
        Epoch: $(training_info[:current_epoch])/$(training_info[:total_epochs])
        
        Progress: $progress_bar $(training_info[:progress])%
        
        Loss: $(round(training_info[:loss], digits=6))
        Val Score: $(round(training_info[:val_score], digits=4))
        ETA: $(training_info[:eta])
        """
    end
    
    # Get panel width from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "training_panel_width")
        config.tui_config["panels"]["training_panel_width"]
    else
        40  # default fallback
    end
    
    return Panel(
        content,
        title="🚀 Training Progress",
        style="blue",
        width=panel_width
    )
end

function create_progress_bar(current::Number, total::Number; width::Int=20)::String
    if total == 0
        return "─" ^ width
    end
    
    percentage = current / total
    filled = Int(round(percentage * width))
    
    bar = "█" ^ filled * "░" ^ (width - filled)
    
    return bar
end

function format_uptime(seconds::Int)::String
    # Handle negative values gracefully
    if seconds < 0
        return "0s"
    end
    
    days = div(seconds, 86400)
    hours = div(seconds % 86400, 3600)
    minutes = div(seconds % 3600, 60)
    
    if days > 0
        return "$(days)d $(hours)h $(minutes)m"
    elseif hours > 0
        return "$(hours)h $(minutes)m"
    else
        return "$(minutes)m"
    end
end

function create_help_panel(config=nothing)::Panel
    content = """
    Keyboard Controls:
    ─────────────────
    q - Quit
    p - Pause/Resume training
    s - Start training
    r - Refresh data
    h - Toggle help
    Enter - View model details
    
    Commands:
    ─────────────────
    /train - Train current model
    /submit - Submit predictions
    /stake [amount] - Update stake
    /download - Download latest data
    """
    
    # Get panel width from config
    panel_width = if config !== nothing && haskey(config.tui_config, "panels") && haskey(config.tui_config["panels"], "help_panel_width")
        config.tui_config["panels"]["help_panel_width"]
    else
        40  # default fallback
    end
    
    return Panel(
        content,
        title="❓ Help",
        style="white",
        width=panel_width
    )
end

export create_model_performance_panel, create_staking_panel, create_predictions_panel,
       create_events_panel, create_system_panel, create_training_panel, create_help_panel,
       create_progress_bar, format_uptime

end