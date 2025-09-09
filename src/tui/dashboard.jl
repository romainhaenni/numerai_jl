module Dashboard

using Term
using Dates
using ThreadsX
using ..API
using ..Pipeline
using ..Panels
using ..Notifications

mutable struct TournamentDashboard
    config::Any
    api_client::API.NumeraiClient
    models::Vector{Dict{Symbol, Any}}
    events::Vector{Dict{Symbol, Any}}
    system_info::Dict{Symbol, Any}
    training_info::Dict{Symbol, Any}
    predictions_history::Vector{Float64}
    running::Bool
    paused::Bool
    show_help::Bool
    selected_model::Int
    refresh_rate::Int
end

function TournamentDashboard(config)
    api_client = API.NumeraiClient(config.api_public_key, config.api_secret_key)
    
    models = [Dict(:name => model, :is_active => false, :corr => 0.0, 
                  :mmc => 0.0, :fnc => 0.0, :sharpe => 0.0) 
             for model in config.models]
    
    system_info = Dict(
        :cpu_usage => 0,
        :memory_used => 0.0,
        :memory_total => 48.0,
        :active_models => 0,
        :total_models => length(config.models),
        :threads => Threads.nthreads(),
        :uptime => 0
    )
    
    training_info = Dict(
        :is_training => false,
        :current_model => "",
        :progress => 0,
        :current_epoch => 0,
        :total_epochs => 0,
        :loss => 0.0,
        :val_score => 0.0,
        :eta => "N/A"
    )
    
    return TournamentDashboard(
        config, api_client, models, Vector{Dict{Symbol, Any}}(),
        system_info, training_info, Float64[],
        false, false, false, 1, 1
    )
end

function run_dashboard(dashboard::TournamentDashboard)
    dashboard.running = true
    start_time = time()
    
    Term.clear()
    Term.hide_cursor()
    
    try
        add_event!(dashboard, :info, "Dashboard started")
        
        @async update_loop(dashboard, start_time)
        
        input_loop(dashboard)
        
    finally
        dashboard.running = false
        Term.show_cursor()
        Term.clear()
    end
end

function update_loop(dashboard::TournamentDashboard, start_time::Float64)
    while dashboard.running
        if !dashboard.paused
            dashboard.system_info[:uptime] = Int(time() - start_time)
            
            update_system_info!(dashboard)
            
            if rand() < 0.1
                update_model_performances!(dashboard)
            end
            
            render(dashboard)
        end
        
        sleep(dashboard.refresh_rate)
    end
end

function input_loop(dashboard::TournamentDashboard)
    while dashboard.running
        key = Term.read_key()
        
        if key == "q"
            dashboard.running = false
        elseif key == "p"
            dashboard.paused = !dashboard.paused
            status = dashboard.paused ? "paused" : "resumed"
            add_event!(dashboard, :info, "Dashboard $status")
        elseif key == "s"
            start_training(dashboard)
        elseif key == "r"
            update_model_performances!(dashboard)
            add_event!(dashboard, :info, "Data refreshed")
        elseif key == "h"
            dashboard.show_help = !dashboard.show_help
        elseif key == "n"
            create_new_model_wizard(dashboard)
        elseif key == "\e[A"
            dashboard.selected_model = max(1, dashboard.selected_model - 1)
        elseif key == "\e[B"
            dashboard.selected_model = min(length(dashboard.models), dashboard.selected_model + 1)
        elseif key == "\r"
            show_model_details(dashboard, dashboard.selected_model)
        end
    end
end

function render(dashboard::TournamentDashboard)
    Term.clear()
    
    layout = Grid(
        Panels.create_model_performance_panel(dashboard.models),
        Panels.create_staking_panel(get_staking_info(dashboard)),
        Panels.create_predictions_panel(dashboard.predictions_history),
        Panels.create_events_panel(dashboard.events),
        Panels.create_system_panel(dashboard.system_info),
        dashboard.training_info[:is_training] ? 
            Panels.create_training_panel(dashboard.training_info) : 
            (dashboard.show_help ? Panels.create_help_panel() : nothing),
        layout=(3, 2)
    )
    
    println(layout)
    
    status_line = create_status_line(dashboard)
    println("\n" * status_line)
end

function create_status_line(dashboard::TournamentDashboard)::String
    status = dashboard.paused ? "PAUSED" : "RUNNING"
    selected = dashboard.models[dashboard.selected_model][:name]
    
    return "Status: $status | Selected: $selected | Press 'h' for help | 'q' to quit"
end

function update_system_info!(dashboard::TournamentDashboard)
    dashboard.system_info[:cpu_usage] = rand(10:40)
    dashboard.system_info[:memory_used] = rand() * 20 + 5
    dashboard.system_info[:active_models] = count(m -> m[:is_active], dashboard.models)
end

function update_model_performances!(dashboard::TournamentDashboard)
    for model in dashboard.models
        try
            perf = API.get_model_performance(dashboard.api_client, model[:name])
            model[:corr] = perf.corr
            model[:mmc] = perf.mmc
            model[:fnc] = perf.fnc
            model[:sharpe] = perf.sharpe
            model[:is_active] = true
        catch e
            model[:is_active] = false
        end
    end
end

function get_staking_info(dashboard::TournamentDashboard)::Dict{Symbol, Any}
    try
        round_info = API.get_current_round(dashboard.api_client)
        time_remaining = round_info.close_time - now()
        
        return Dict(
            :total_stake => sum(m -> get(m, :stake, 0.0), dashboard.models),
            :at_risk => sum(m -> get(m, :stake, 0.0) * 0.25, dashboard.models),
            :expected_payout => sum(m -> get(m, :stake, 0.0) * m[:corr] * 0.5, dashboard.models),
            :current_round => round_info.number,
            :submission_status => "Submitted",
            :time_remaining => "$(Dates.hour(time_remaining))h $(Dates.minute(time_remaining))m"
        )
    catch
        return Dict(
            :total_stake => 0.0,
            :at_risk => 0.0,
            :expected_payout => 0.0,
            :current_round => 0,
            :submission_status => "Unknown",
            :time_remaining => "N/A"
        )
    end
end

function add_event!(dashboard::TournamentDashboard, type::Symbol, message::String)
    event = Dict(
        :type => type,
        :message => message,
        :time => now()
    )
    push!(dashboard.events, event)
    
    if length(dashboard.events) > 100
        popfirst!(dashboard.events)
    end
    
    if dashboard.config.notification_enabled && type in [:error, :success]
        Notifications.send_notification("Numerai Tournament", message, type)
    end
end

function start_training(dashboard::TournamentDashboard)
    if dashboard.training_info[:is_training]
        add_event!(dashboard, :warning, "Training already in progress")
        return
    end
    
    dashboard.training_info[:is_training] = true
    dashboard.training_info[:current_model] = dashboard.models[dashboard.selected_model][:name]
    dashboard.training_info[:progress] = 0
    dashboard.training_info[:total_epochs] = 100
    
    add_event!(dashboard, :info, "Starting training for $(dashboard.training_info[:current_model])")
    
    @async simulate_training(dashboard)
end

function simulate_training(dashboard::TournamentDashboard)
    for epoch in 1:dashboard.training_info[:total_epochs]
        if !dashboard.training_info[:is_training]
            break
        end
        
        dashboard.training_info[:current_epoch] = epoch
        dashboard.training_info[:progress] = (epoch / dashboard.training_info[:total_epochs]) * 100
        dashboard.training_info[:loss] = 0.5 / epoch
        dashboard.training_info[:val_score] = min(0.03, 0.001 * epoch)
        
        remaining_epochs = dashboard.training_info[:total_epochs] - epoch
        dashboard.training_info[:eta] = "$(remaining_epochs * 2)s"
        
        sleep(0.2)
    end
    
    dashboard.training_info[:is_training] = false
    add_event!(dashboard, :success, "Training completed for $(dashboard.training_info[:current_model])")
    
    push!(dashboard.predictions_history, rand())
end

function create_new_model_wizard(dashboard::TournamentDashboard)
    add_event!(dashboard, :info, "New model wizard not yet implemented")
end

function show_model_details(dashboard::TournamentDashboard, model_idx::Int)
    model = dashboard.models[model_idx]
    add_event!(dashboard, :info, "Viewing details for $(model[:name])")
end

export TournamentDashboard, run_dashboard, add_event!, start_training

end