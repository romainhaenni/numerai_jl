module Compounding

using Dates
using TimeZones
using ..API

# Compounding configuration structure
mutable struct CompoundingConfig
    enabled::Bool
    min_compound_amount::Float64  # Minimum NMR to compound
    compound_percentage::Float64  # Percentage of earnings to compound (0-100)
    max_stake_amount::Float64     # Maximum stake limit per model
    models::Vector{String}         # Models to apply compounding to
end

function CompoundingConfig(;
    enabled::Bool = false,
    min_compound_amount::Float64 = 1.0,
    compound_percentage::Float64 = 100.0,
    max_stake_amount::Float64 = 10000.0,
    models::Vector{String} = String[]
)
    CompoundingConfig(enabled, min_compound_amount, compound_percentage, max_stake_amount, models)
end

# Track compounding state for each model
mutable struct CompoundingState
    model_name::String
    last_checked::DateTime
    last_balance::Float64
    total_compounded::Float64
    compound_history::Vector{Tuple{DateTime, Float64}}
end

function CompoundingState(model_name::String)
    CompoundingState(
        model_name,
        now(UTC),
        0.0,
        0.0,
        Tuple{DateTime, Float64}[]
    )
end

# Main compounding manager
mutable struct CompoundingManager
    api_client::API.NumeraiClient
    config::CompoundingConfig
    states::Dict{String, CompoundingState}
    last_run::DateTime
    enabled::Bool
end

function CompoundingManager(api_client::API.NumeraiClient, config::CompoundingConfig)
    CompoundingManager(
        api_client,
        config,
        Dict{String, CompoundingState}(),
        now(UTC),
        config.enabled
    )
end

"""
Check and process earnings for a specific model.
Returns the amount compounded (0 if none).
"""
function check_and_compound_earnings(manager::CompoundingManager, model_name::String)
    if !manager.enabled || !manager.config.enabled
        return 0.0
    end
    
    # Get or create state for this model
    state = get!(manager.states, model_name, CompoundingState(model_name))
    
    try
        # Get current wallet balance
        wallet_info = API.get_wallet_balance(manager.api_client)
        current_balance = get(wallet_info, :nmr_balance, 0.0)
        
        # Calculate earnings since last check
        earnings = current_balance - state.last_balance
        
        # Only compound if we have positive earnings
        if earnings <= 0
            @debug "No earnings to compound for model $model_name" earnings=earnings
            return 0.0
        end
        
        # Check minimum compound amount
        if earnings < manager.config.min_compound_amount
            @info "Earnings below minimum compound threshold" model=model_name earnings=earnings threshold=manager.config.min_compound_amount
            return 0.0
        end
        
        # Calculate amount to compound based on percentage
        compound_amount = earnings * (manager.config.compound_percentage / 100.0)
        
        # Get current stake to check against maximum
        stake_info = API.get_model_stakes(manager.api_client, model_name)
        current_stake = get(stake_info, :total_stake, 0.0)
        
        # Check if we would exceed maximum stake
        if current_stake + compound_amount > manager.config.max_stake_amount
            compound_amount = max(0.0, manager.config.max_stake_amount - current_stake)
            if compound_amount <= 0
                @info "Model at maximum stake limit" model=model_name current_stake=current_stake max_stake=manager.config.max_stake_amount
                return 0.0
            end
        end
        
        # Perform the stake increase
        @info "Compounding earnings into stake" model=model_name amount=compound_amount
        result = API.stake_increase(manager.api_client, model_name, compound_amount)
        
        if !isnothing(result)
            # Update state
            state.last_checked = now(UTC)
            state.last_balance = current_balance - compound_amount
            state.total_compounded += compound_amount
            push!(state.compound_history, (now(UTC), compound_amount))
            
            @info "Successfully compounded earnings" model=model_name amount=compound_amount total_compounded=state.total_compounded
            return compound_amount
        else
            @error "Failed to compound earnings" model=model_name amount=compound_amount
            return 0.0
        end
        
    catch e
        @error "Error checking earnings for compounding" model=model_name error=e
        return 0.0
    end
end

"""
Process compounding for all configured models.
Returns total amount compounded across all models.
"""
function process_all_compounding(manager::CompoundingManager)
    if !manager.enabled || !manager.config.enabled
        return 0.0
    end
    
    total_compounded = 0.0
    
    # Get list of models to process
    models_to_process = if isempty(manager.config.models)
        # If no specific models configured, get all user models
        try
            user_models = API.get_models_for_user(manager.api_client)
            [model[:name] for model in user_models]
        catch e
            @error "Failed to get user models for compounding" error=e
            String[]
        end
    else
        manager.config.models
    end
    
    # Process each model
    for model_name in models_to_process
        amount = check_and_compound_earnings(manager, model_name)
        total_compounded += amount
    end
    
    manager.last_run = now(UTC)
    
    return total_compounded
end

"""
Check if compounding should run based on timing.
Compounding should run after payouts are processed (typically Wednesdays).
"""
function should_run_compounding(manager::CompoundingManager)
    if !manager.enabled || !manager.config.enabled
        return false
    end
    
    current_time = now(UTC)
    current_day = dayofweek(current_time)
    
    # Run on Wednesdays after 14:00 UTC (after payouts are processed)
    if current_day == 3  # Wednesday
        if hour(current_time) >= 14
            # Check if we haven't run today already
            if Date(manager.last_run) < Date(current_time)
                return true
            end
        end
    end
    
    # Also allow manual triggering if it's been more than 7 days
    if current_time - manager.last_run > Day(7)
        return true
    end
    
    return false
end

"""
Get compounding statistics for a model.
"""
function get_compounding_stats(manager::CompoundingManager, model_name::String)
    state = get(manager.states, model_name, nothing)
    
    if isnothing(state)
        return Dict(
            :total_compounded => 0.0,
            :last_checked => nothing,
            :compound_count => 0,
            :history => []
        )
    end
    
    return Dict(
        :total_compounded => state.total_compounded,
        :last_checked => state.last_checked,
        :compound_count => length(state.compound_history),
        :history => state.compound_history
    )
end

"""
Enable or disable compounding.
"""
function set_compounding_enabled(manager::CompoundingManager, enabled::Bool)
    manager.enabled = enabled
    manager.config.enabled = enabled
    @info "Compounding $(enabled ? "enabled" : "disabled")"
end

"""
Update compounding configuration.
"""
function update_compounding_config(manager::CompoundingManager;
    min_compound_amount::Union{Float64, Nothing} = nothing,
    compound_percentage::Union{Float64, Nothing} = nothing,
    max_stake_amount::Union{Float64, Nothing} = nothing,
    models::Union{Vector{String}, Nothing} = nothing
)
    if !isnothing(min_compound_amount)
        manager.config.min_compound_amount = min_compound_amount
    end
    
    if !isnothing(compound_percentage)
        manager.config.compound_percentage = clamp(compound_percentage, 0.0, 100.0)
    end
    
    if !isnothing(max_stake_amount)
        manager.config.max_stake_amount = max_stake_amount
    end
    
    if !isnothing(models)
        manager.config.models = models
    end
    
    @info "Compounding configuration updated" config=manager.config
end

export CompoundingConfig, CompoundingManager, CompoundingState,
       check_and_compound_earnings, process_all_compounding,
       should_run_compounding, get_compounding_stats,
       set_compounding_enabled, update_compounding_config

end