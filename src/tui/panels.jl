module Panels

using Term
using Term: Panel, Tables
using Dates
using DataFrames
using ..Charts
using Statistics: mean, std

function create_model_performance_panel(performances::Vector{Dict{Symbol, Any}})::Panel
    if isempty(performances)
        content = "No models running"
    else
        rows = []
        push!(rows, ["Model", "CORR", "MMC", "FNC", "Sharpe", "Status"])
        
        for perf in performances
            status_icon = perf[:is_active] ? "🟢" : "🔴"
            push!(rows, [
                perf[:name],
                round(perf[:corr], digits=4),
                round(perf[:mmc], digits=4),
                round(perf[:fnc], digits=4),
                round(perf[:sharpe], digits=3),
                status_icon
            ])
        end
        
        content = Tables.Table(rows, box=:ROUNDED)
    end
    
    return Panel(
        content,
        title="📊 Model Performance",
        style="blue",
        width=60
    )
end

function create_staking_panel(stake_info::Dict{Symbol, Any})::Panel
    content = """
    Total Staked: $(stake_info[:total_stake]) NMR
    At Risk: $(stake_info[:at_risk]) NMR
    Expected Payout: $(stake_info[:expected_payout]) NMR
    
    Current Round: #$(stake_info[:current_round])
    Submission Status: $(stake_info[:submission_status])
    Time Remaining: $(stake_info[:time_remaining])
    """
    
    return Panel(
        content,
        title="💰 Staking Status",
        style="green",
        width=40
    )
end

function create_predictions_panel(predictions_history::Vector{Float64})::Panel
    if isempty(predictions_history)
        content = "No predictions yet"
    else
        chart = Charts.create_sparkline(predictions_history, width=35, height=6)
        
        stats = """
        Latest: $(round(predictions_history[end], digits=4))
        Mean: $(round(mean(predictions_history), digits=4))
        Std: $(round(std(predictions_history), digits=4))
        """
        
        content = chart * "\n\n" * stats
    end
    
    return Panel(
        content,
        title="📈 Live Predictions",
        style="yellow",
        width=40
    )
end

function create_events_panel(events::Vector{Dict{Symbol, Any}}; max_events::Int=20)::Panel
    if isempty(events)
        content = "No recent events"
    else
        lines = String[]
        
        for event in events[max(1, end-max_events+1):end]
            timestamp = Dates.format(event[:time], "HH:MM:SS")
            
            color = if event[:type] == :error
                "red"
            elseif event[:type] == :warning
                "yellow"
            elseif event[:type] == :success
                "green"
            else
                "white"
            end
            
            icon = if event[:type] == :error
                "❌"
            elseif event[:type] == :warning
                "⚠️"
            elseif event[:type] == :success
                "✅"
            else
                "ℹ️"
            end
            
            push!(lines, "[$timestamp] $icon $(event[:message])")
        end
        
        content = join(reverse(lines), "\n")
    end
    
    return Panel(
        content,
        title="🔔 Recent Events",
        style="cyan",
        width=60,
        height=22
    )
end

function create_system_panel(system_info::Dict{Symbol, Any})::Panel
    cpu_bar = create_progress_bar(system_info[:cpu_usage], 100)
    mem_bar = create_progress_bar(system_info[:memory_used], system_info[:memory_total])
    
    content = """
    CPU Usage: $cpu_bar $(system_info[:cpu_usage])%
    Memory: $mem_bar $(round(system_info[:memory_used], digits=1))/$(system_info[:memory_total]) GB
    
    Active Models: $(system_info[:active_models])/$(system_info[:total_models])
    Threads: $(system_info[:threads])
    Uptime: $(format_uptime(system_info[:uptime]))
    """
    
    return Panel(
        content,
        title="⚙️ System Status",
        style="magenta",
        width=40
    )
end

function create_training_panel(training_info::Dict{Symbol, Any})::Panel
    if !training_info[:is_training]
        content = "No training in progress"
    else
        progress_bar = create_progress_bar(training_info[:progress], 100)
        
        content = """
        Model: $(training_info[:current_model])
        Epoch: $(training_info[:current_epoch])/$(training_info[:total_epochs])
        
        Progress: $progress_bar $(training_info[:progress])%
        
        Loss: $(round(training_info[:loss], digits=6))
        Val Score: $(round(training_info[:val_score], digits=4))
        ETA: $(training_info[:eta])
        """
    end
    
    return Panel(
        content,
        title="🚀 Training Progress",
        style="blue",
        width=40
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
    days = seconds ÷ 86400
    hours = (seconds % 86400) ÷ 3600
    minutes = (seconds % 3600) ÷ 60
    
    if days > 0
        return "$(days)d $(hours)h $(minutes)m"
    elseif hours > 0
        return "$(hours)h $(minutes)m"
    else
        return "$(minutes)m"
    end
end

function create_help_panel()::Panel
    content = """
    Keyboard Controls:
    ─────────────────
    q - Quit
    p - Pause/Resume training
    s - Start training
    r - Refresh data
    n - New model wizard
    h - Toggle help
    ↑/↓ - Navigate models
    Enter - View model details
    
    Commands:
    ─────────────────
    /train [model] - Train specific model
    /submit [model] - Submit predictions
    /stake [amount] - Update stake
    /download - Download latest data
    """
    
    return Panel(
        content,
        title="❓ Help",
        style="white",
        width=40
    )
end

export create_model_performance_panel, create_staking_panel, create_predictions_panel,
       create_events_panel, create_system_panel, create_training_panel, create_help_panel,
       create_progress_bar, format_uptime

end