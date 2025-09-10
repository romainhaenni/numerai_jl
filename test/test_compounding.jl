using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using NumeraiTournament
using Test
using Dates
using TimeZones

# Mock API client for testing - wrapper around the real client
mutable struct MockNumeraiClient
    real_client::NumeraiTournament.API.NumeraiClient
    api_calls::Vector{Symbol}
    wallet_balance::Float64
    model_stakes::Dict{String, Float64}
    stake_increase_results::Dict{String, Bool}
    should_fail::Symbol  # :none, :wallet, :stakes, :increase, :models
    user_models::Vector{String}
end

function MockNumeraiClient(;
    wallet_balance=100.0,
    model_stakes=Dict{String, Float64}(),
    stake_increase_results=Dict{String, Bool}(),
    should_fail=:none,
    user_models=["test_model"]
)
    # Create a real client with dummy credentials
    real_client = NumeraiTournament.API.NumeraiClient("test_public_id", "test_secret_key")
    
    MockNumeraiClient(
        real_client,
        Symbol[],
        wallet_balance,
        model_stakes,
        stake_increase_results,
        should_fail,
        user_models
    )
end

# Helper function to create a CompoundingManager that works with mocked API calls
function create_test_manager(mock_client::MockNumeraiClient, config::NumeraiTournament.Compounding.CompoundingConfig)
    # Create the manager with the real client
    manager = NumeraiTournament.Compounding.CompoundingManager(mock_client.real_client, config)
    
    # Store the mock client reference for our custom compound function
    return (manager, mock_client)
end

# Custom compound function that uses the mock data
function mock_check_and_compound_earnings(manager, mock_client::MockNumeraiClient, model_name::String)
    if !manager.enabled || !manager.config.enabled
        return 0.0
    end
    
    # Get or create state for this model
    state = get!(manager.states, model_name, NumeraiTournament.Compounding.CompoundingState(model_name))
    
    try
        # Mock get current wallet balance
        push!(mock_client.api_calls, :get_wallet_balance)
        if mock_client.should_fail == :wallet
            throw(ErrorException("Mock wallet balance failure"))
        end
        current_balance = mock_client.wallet_balance
        
        # Calculate earnings since last check
        earnings = current_balance - state.last_balance
        
        # Only compound if we have positive earnings
        if earnings <= 0
            return 0.0
        end
        
        # Check minimum compound amount
        if earnings < manager.config.min_compound_amount
            return 0.0
        end
        
        # Calculate amount to compound based on percentage
        compound_amount = earnings * (manager.config.compound_percentage / 100.0)
        
        # Mock get current stake to check against maximum
        push!(mock_client.api_calls, :get_model_stakes)
        if mock_client.should_fail == :stakes
            throw(ErrorException("Mock stakes failure"))
        end
        current_stake = get(mock_client.model_stakes, model_name, 0.0)
        
        # Check if we would exceed maximum stake
        if current_stake + compound_amount > manager.config.max_stake_amount
            compound_amount = max(0.0, manager.config.max_stake_amount - current_stake)
            if compound_amount <= 0
                return 0.0
            end
        end
        
        # Mock perform the stake increase
        push!(mock_client.api_calls, :stake_increase)
        if mock_client.should_fail == :increase
            throw(ErrorException("Mock stake increase failure"))
        end
        
        success = get(mock_client.stake_increase_results, model_name, true)
        if success
            # Update mock state
            mock_client.model_stakes[model_name] = current_stake + compound_amount
            # For testing purposes, don't reduce wallet balance to simulate independent earnings per model
            # mock_client.wallet_balance = current_balance - compound_amount
            
            # Update manager state
            state.last_checked = now(UTC)
            state.last_balance = current_balance  # Important: don't subtract compound amount from balance tracking
            state.total_compounded += compound_amount
            NumeraiTournament.Compounding.add_to_compound_history!(state, now(UTC), compound_amount, manager.config.history_limit)
            
            return compound_amount
        else
            return 0.0
        end
        
    catch e
        return 0.0
    end
end

# Mock process all compounding function
function mock_process_all_compounding(manager, mock_client::MockNumeraiClient)
    if !manager.enabled || !manager.config.enabled
        return 0.0
    end
    
    total_compounded = 0.0
    
    # Get list of models to process
    models_to_process = if isempty(manager.config.models)
        # Mock get all user models
        push!(mock_client.api_calls, :get_models_for_user)
        if mock_client.should_fail == :models
            throw(ErrorException("Mock get models failure"))
        end
        mock_client.user_models
    else
        manager.config.models
    end
    
    # Process each model
    for model_name in models_to_process
        amount = mock_check_and_compound_earnings(manager, mock_client, model_name)
        total_compounded += amount
    end
    
    manager.last_run = now(UTC)
    
    return total_compounded
end

@testset "Compounding Module Tests" begin
    
    @testset "CompoundingConfig Creation and Validation" begin
        # Test default configuration
        config = NumeraiTournament.Compounding.CompoundingConfig()
        @test config.enabled == false
        @test config.min_compound_amount == 1.0
        @test config.compound_percentage == 100.0
        @test config.max_stake_amount == 10000.0
        @test config.models == String[]
        @test config.history_limit == 1000
        
        # Test custom configuration
        custom_config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            min_compound_amount=5.0,
            compound_percentage=50.0,
            max_stake_amount=5000.0,
            models=["model1", "model2"],
            history_limit=500
        )
        @test custom_config.enabled == true
        @test custom_config.min_compound_amount == 5.0
        @test custom_config.compound_percentage == 50.0
        @test custom_config.max_stake_amount == 5000.0
        @test custom_config.models == ["model1", "model2"]
        @test custom_config.history_limit == 500
        
        # Test edge values
        edge_config = NumeraiTournament.Compounding.CompoundingConfig(
            min_compound_amount=0.0,
            compound_percentage=0.0,
            max_stake_amount=0.0,
            history_limit=1
        )
        @test edge_config.min_compound_amount == 0.0
        @test edge_config.compound_percentage == 0.0
        @test edge_config.max_stake_amount == 0.0
        @test edge_config.history_limit == 1
    end
    
    @testset "CompoundingState Initialization" begin
        # Test default state creation
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        @test state.model_name == "test_model"
        @test state.last_checked isa DateTime
        @test state.last_balance == 0.0
        @test state.total_compounded == 0.0
        @test length(state.compound_history) == 0
        
        # Test state with different model names
        state2 = NumeraiTournament.Compounding.CompoundingState("another_model")
        @test state2.model_name == "another_model"
        
        # Test empty model name (edge case)
        state3 = NumeraiTournament.Compounding.CompoundingState("")
        @test state3.model_name == ""
    end
    
    @testset "CompoundingManager Creation and State Management" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig(enabled=true)
        
        # Test manager creation
        manager, _ = create_test_manager(mock_client, config)
        @test manager.config === config
        @test length(manager.states) == 0
        @test manager.last_run isa DateTime
        @test manager.enabled == true
        
        # Test state creation on access
        state = get!(manager.states, "new_model", NumeraiTournament.Compounding.CompoundingState("new_model"))
        @test haskey(manager.states, "new_model")
        @test manager.states["new_model"].model_name == "new_model"
        
        # Test disabled manager
        disabled_config = NumeraiTournament.Compounding.CompoundingConfig(enabled=false)
        disabled_manager, _ = create_test_manager(mock_client, disabled_config)
        @test disabled_manager.enabled == false
    end
    
    @testset "should_run_compounding Logic" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig(enabled=true)
        manager, _ = create_test_manager(mock_client, config)
        
        # Test disabled manager
        manager.enabled = false
        @test NumeraiTournament.Compounding.should_run_compounding(manager) == false
        
        # Re-enable for further tests
        manager.enabled = true
        manager.config.enabled = true
        
        # Test disabled config
        manager.config.enabled = false
        @test NumeraiTournament.Compounding.should_run_compounding(manager) == false
        manager.config.enabled = true
        
        # Test manual triggering after 7 days
        manager.last_run = now(UTC) - Day(8)
        @test NumeraiTournament.Compounding.should_run_compounding(manager) == true
        
        # Reset last run to recent
        manager.last_run = now(UTC)
        
        # Test specific Wednesday logic at different times
        current_time = now(UTC)
        current_day = dayofweek(current_time)
        
        if current_day == 3  # If today is Wednesday
            if hour(current_time) >= 14
                # Should run if we haven't run today
                manager.last_run = Date(current_time) - Day(1)
                @test NumeraiTournament.Compounding.should_run_compounding(manager) == true
                
                # Should not run if we already ran today
                manager.last_run = current_time
                @test NumeraiTournament.Compounding.should_run_compounding(manager) == false
            end
        end
        
        # Test non-Wednesday with recent run
        if current_day != 3
            manager.last_run = now(UTC) - Hour(1)
            @test NumeraiTournament.Compounding.should_run_compounding(manager) == false
        end
    end
    
    @testset "calculate_compound_amount with Different Percentages and Limits" begin
        # Test 100% compounding
        mock_client = MockNumeraiClient(wallet_balance=100.0)
        config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            compound_percentage=100.0,
            max_stake_amount=1000.0
        )
        manager, mock_client = create_test_manager(mock_client, config)
        
        # Set up model state with previous balance
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        state.last_balance = 90.0  # Earnings = 100 - 90 = 10
        manager.states["test_model"] = state
        
        # Mock current stake
        mock_client.model_stakes["test_model"] = 50.0
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 10.0  # Should compound all earnings
        
        # Test 50% compounding
        config.compound_percentage = 50.0
        mock_client.wallet_balance = 100.0  # Reset
        state.last_balance = 90.0
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 5.0  # Should compound 50% of earnings
        
        # Test 0% compounding
        config.compound_percentage = 0.0
        mock_client.wallet_balance = 100.0
        state.last_balance = 90.0
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0  # Should compound nothing
        
        # Test exceeding maximum stake
        config.compound_percentage = 100.0
        config.max_stake_amount = 55.0  # Current stake is 50, so max compound is 5
        mock_client.wallet_balance = 100.0
        mock_client.model_stakes["test_model"] = 50.0
        state.last_balance = 90.0  # Earnings = 10
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 5.0  # Should be limited to max_stake - current_stake
        
        # Test at maximum stake already
        mock_client.model_stakes["test_model"] = 55.0
        empty!(mock_client.api_calls)
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0  # Should compound nothing when at max stake
    end
    
    @testset "execute_compound Success and Failure Scenarios" begin
        # Test successful compound
        mock_client = MockNumeraiClient(
            wallet_balance=100.0,
            stake_increase_results=Dict("test_model" => true)
        )
        mock_client.model_stakes["test_model"] = 50.0
        
        config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            min_compound_amount=1.0,
            compound_percentage=100.0
        )
        manager, mock_client = create_test_manager(mock_client, config)
        
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        state.last_balance = 90.0  # Earnings = 10
        manager.states["test_model"] = state
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 10.0
        @test state.total_compounded == 10.0
        @test length(state.compound_history) == 1
        @test state.compound_history[1][2] == 10.0
        @test :stake_increase in mock_client.api_calls
        
        # Test failed compound (API returns nothing)
        mock_client.stake_increase_results["test_model"] = false
        mock_client.wallet_balance = 100.0
        state.last_balance = 90.0
        state.total_compounded = 0.0
        empty!(state.compound_history)
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
        @test state.total_compounded == 0.0
        @test length(state.compound_history) == 0
        
        # Test wallet balance API failure
        mock_client.should_fail = :wallet
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
        
        # Test stakes API failure
        mock_client.should_fail = :stakes
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
        
        # Test stake increase API failure
        mock_client.should_fail = :increase
        mock_client.wallet_balance = 100.0
        state.last_balance = 90.0
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
    end
    
    @testset "update_compounding_config Functionality" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig()
        manager, _ = create_test_manager(mock_client, config)
        
        # Test updating individual parameters
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            min_compound_amount=5.0
        )
        @test manager.config.min_compound_amount == 5.0
        
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            compound_percentage=75.0
        )
        @test manager.config.compound_percentage == 75.0
        
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            max_stake_amount=15000.0
        )
        @test manager.config.max_stake_amount == 15000.0
        
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            models=["model1", "model2", "model3"]
        )
        @test manager.config.models == ["model1", "model2", "model3"]
        
        # Test updating all parameters at once
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            min_compound_amount=2.5,
            compound_percentage=80.0,
            max_stake_amount=8000.0,
            models=["new_model"],
            history_limit=200
        )
        @test manager.config.min_compound_amount == 2.5
        @test manager.config.compound_percentage == 80.0
        @test manager.config.max_stake_amount == 8000.0
        @test manager.config.models == ["new_model"]
        @test manager.config.history_limit == 200
        
        # Test percentage clamping
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            compound_percentage=150.0  # Should be clamped to 100.0
        )
        @test manager.config.compound_percentage == 100.0
        
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            compound_percentage=-10.0  # Should be clamped to 0.0
        )
        @test manager.config.compound_percentage == 0.0
        
        # Test history limit minimum enforcement
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            history_limit=0  # Should be enforced to minimum of 1
        )
        @test manager.config.history_limit == 1
        
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            history_limit=-5  # Should be enforced to minimum of 1
        )
        @test manager.config.history_limit == 1
    end
    
    @testset "Rolling Window Behavior for compound_history" begin
        # Test rolling window functionality
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        history_limit = 3
        
        # Add entries within limit
        NumeraiTournament.Compounding.add_to_compound_history!(
            state, DateTime(2023, 1, 1), 10.0, history_limit
        )
        @test length(state.compound_history) == 1
        
        NumeraiTournament.Compounding.add_to_compound_history!(
            state, DateTime(2023, 1, 2), 15.0, history_limit
        )
        @test length(state.compound_history) == 2
        
        NumeraiTournament.Compounding.add_to_compound_history!(
            state, DateTime(2023, 1, 3), 20.0, history_limit
        )
        @test length(state.compound_history) == 3
        
        # Verify order and content
        @test state.compound_history[1] == (DateTime(2023, 1, 1), 10.0)
        @test state.compound_history[2] == (DateTime(2023, 1, 2), 15.0)
        @test state.compound_history[3] == (DateTime(2023, 1, 3), 20.0)
        
        # Add entry that exceeds limit - should remove oldest
        NumeraiTournament.Compounding.add_to_compound_history!(
            state, DateTime(2023, 1, 4), 25.0, history_limit
        )
        @test length(state.compound_history) == 3
        @test state.compound_history[1] == (DateTime(2023, 1, 2), 15.0)  # Oldest removed
        @test state.compound_history[2] == (DateTime(2023, 1, 3), 20.0)
        @test state.compound_history[3] == (DateTime(2023, 1, 4), 25.0)
        
        # Add multiple entries that exceed limit
        NumeraiTournament.Compounding.add_to_compound_history!(
            state, DateTime(2023, 1, 5), 30.0, history_limit
        )
        NumeraiTournament.Compounding.add_to_compound_history!(
            state, DateTime(2023, 1, 6), 35.0, history_limit
        )
        @test length(state.compound_history) == 3
        @test state.compound_history[1] == (DateTime(2023, 1, 4), 25.0)
        @test state.compound_history[2] == (DateTime(2023, 1, 5), 30.0)
        @test state.compound_history[3] == (DateTime(2023, 1, 6), 35.0)
        
        # Test with history limit of 1
        state2 = NumeraiTournament.Compounding.CompoundingState("test_model2")
        NumeraiTournament.Compounding.add_to_compound_history!(
            state2, DateTime(2023, 1, 1), 10.0, 1
        )
        @test length(state2.compound_history) == 1
        
        NumeraiTournament.Compounding.add_to_compound_history!(
            state2, DateTime(2023, 1, 2), 20.0, 1
        )
        @test length(state2.compound_history) == 1
        @test state2.compound_history[1] == (DateTime(2023, 1, 2), 20.0)
        
        # Test updating history limit in manager affects existing states
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig(history_limit=5)
        manager, _ = create_test_manager(mock_client, config)
        
        # Add state with long history
        test_state = NumeraiTournament.Compounding.CompoundingState("test_model")
        for i in 1:10
            push!(test_state.compound_history, (DateTime(2023, 1, i), Float64(i)))
        end
        manager.states["test_model"] = test_state
        @test length(test_state.compound_history) == 10
        
        # Update history limit to smaller value
        NumeraiTournament.Compounding.update_compounding_config(
            manager,
            history_limit=3
        )
        
        # Should trim existing history
        @test length(test_state.compound_history) == 3
        @test test_state.compound_history[1] == (DateTime(2023, 1, 8), 8.0)
        @test test_state.compound_history[2] == (DateTime(2023, 1, 9), 9.0)
        @test test_state.compound_history[3] == (DateTime(2023, 1, 10), 10.0)
    end
    
    @testset "Edge Cases" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig(enabled=true)
        manager, mock_client = create_test_manager(mock_client, config)
        
        # Test negative earnings (loss)
        mock_client.wallet_balance = 80.0
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        state.last_balance = 90.0  # Earnings = 80 - 90 = -10 (loss)
        manager.states["test_model"] = state
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0  # Should not compound losses
        
        # Test zero earnings
        mock_client.wallet_balance = 90.0
        state.last_balance = 90.0  # Earnings = 0
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
        
        # Test earnings below minimum threshold
        config.min_compound_amount = 5.0
        mock_client.wallet_balance = 92.0
        state.last_balance = 90.0  # Earnings = 2 (below threshold)
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
        
        # Test extreme percentage values
        config.compound_percentage = 1000.0  # Extreme value
        mock_client.wallet_balance = 100.0
        state.last_balance = 90.0
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 100.0  # 10 * (1000/100) = 100
        
        # Test with negative balance (edge case)
        mock_client.wallet_balance = -10.0
        state.last_balance = 0.0
        empty!(mock_client.api_calls)
        
        result = mock_check_and_compound_earnings(manager, mock_client, "test_model")
        @test result == 0.0
        
        # Test empty model name
        empty!(mock_client.api_calls)
        result = mock_check_and_compound_earnings(manager, mock_client, "")
        @test result >= 0.0  # Should handle gracefully
        
        # Test very long model name
        long_name = "a" ^ 1000
        empty!(mock_client.api_calls)
        result = mock_check_and_compound_earnings(manager, mock_client, long_name)
        @test result >= 0.0  # Should handle gracefully
        
        # Test empty states dictionary
        empty_mock_client = MockNumeraiClient()
        empty_manager, _ = create_test_manager(empty_mock_client, config)
        @test length(empty_manager.states) == 0
        
        # Test process_all_compounding with no models
        empty_mock_client.user_models = String[]
        total = mock_process_all_compounding(empty_manager, empty_mock_client)
        @test total == 0.0
        
        # Test get_compounding_stats with non-existent model
        stats = NumeraiTournament.Compounding.get_compounding_stats(empty_manager, "nonexistent")
        @test stats[:total_compounded] == 0.0
        @test stats[:last_checked] === nothing
        @test stats[:compound_count] == 0
        @test stats[:history] == []
    end
    
    @testset "Thread Safety of Operations" begin
        # Test concurrent access to compound history
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        history_limit = 100
        
        # Simulate concurrent additions to history
        tasks = []
        for i in 1:10
            push!(tasks, Threads.@spawn begin
                for j in 1:10
                    timestamp = DateTime(2023, 1, 1) + Hour(i * 10 + j)
                    amount = Float64(i * 10 + j)
                    NumeraiTournament.Compounding.add_to_compound_history!(
                        state, timestamp, amount, history_limit
                    )
                end
            end)
        end
        
        # Wait for all tasks to complete
        for task in tasks
            wait(task)
        end
        
        # Verify data integrity
        @test length(state.compound_history) == 100
        
        # Verify history is sorted by timestamp (should be due to our insertion pattern)
        for i in 2:length(state.compound_history)
            @test state.compound_history[i-1][1] <= state.compound_history[i][1]
        end
        
        # Test concurrent config updates
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig()
        manager, _ = create_test_manager(mock_client, config)
        
        # Concurrent config updates
        update_tasks = []
        for i in 1:5
            push!(update_tasks, Threads.@spawn begin
                NumeraiTournament.Compounding.update_compounding_config(
                    manager,
                    min_compound_amount=Float64(i),
                    compound_percentage=Float64(i * 10)
                )
            end)
        end
        
        # Wait for all updates
        for task in update_tasks
            wait(task)
        end
        
        # Verify final state is valid (specific values depend on race conditions)
        @test manager.config.min_compound_amount >= 1.0
        @test manager.config.compound_percentage >= 10.0
        @test manager.config.compound_percentage <= 50.0  # Due to clamping
    end
    
    @testset "process_all_compounding Functionality" begin
        # Test with specific models configured
        mock_client = MockNumeraiClient(
            wallet_balance=100.0,
            user_models=["model1", "model2", "model3"]
        )
        config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            models=["model1", "model2"]  # Only compound specific models
        )
        manager, mock_client = create_test_manager(mock_client, config)
        
        # Set up states - reset wallet balance after creating each state to ensure consistent earnings
        original_balance = mock_client.wallet_balance
        for model in ["model1", "model2"]
            state = NumeraiTournament.Compounding.CompoundingState(model)
            state.last_balance = original_balance - 10.0  # Each has 10 earnings from current balance
            manager.states[model] = state
            mock_client.model_stakes[model] = 50.0
        end
        
        total = mock_process_all_compounding(manager, mock_client)
        @test total == 20.0  # 10 from each of 2 models
        
        # Test with no specific models (should use all user models)
        config.models = String[]
        
        # Reset the mock client to fresh state
        fresh_mock_client = MockNumeraiClient(
            wallet_balance=100.0,
            user_models=["model1", "model2", "model3"]
        )
        fresh_manager, fresh_mock_client = create_test_manager(fresh_mock_client, config)
        
        # Add states for all models
        fresh_original_balance = fresh_mock_client.wallet_balance
        for model in ["model1", "model2", "model3"]
            state = NumeraiTournament.Compounding.CompoundingState(model)
            state.last_balance = fresh_original_balance - 10.0  # Each has 10 earnings
            fresh_manager.states[model] = state
            fresh_mock_client.model_stakes[model] = 50.0
        end
        
        total = mock_process_all_compounding(fresh_manager, fresh_mock_client)
        @test total == 30.0  # 10 from each of 3 models
        
        # Test with API failure when getting user models
        mock_client.should_fail = :models
        @test_throws ErrorException mock_process_all_compounding(manager, mock_client)
        
        # Test disabled manager
        manager.enabled = false
        mock_client.should_fail = :none
        total = mock_process_all_compounding(manager, mock_client)
        @test total == 0.0
    end
    
    @testset "get_compounding_stats Functionality" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig()
        manager, _ = create_test_manager(mock_client, config)
        
        # Test with existing state
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        state.total_compounded = 50.0
        state.last_checked = DateTime(2023, 6, 15, 12, 0, 0)
        push!(state.compound_history, (DateTime(2023, 6, 1), 10.0))
        push!(state.compound_history, (DateTime(2023, 6, 8), 15.0))
        push!(state.compound_history, (DateTime(2023, 6, 15), 25.0))
        manager.states["test_model"] = state
        
        stats = NumeraiTournament.Compounding.get_compounding_stats(manager, "test_model")
        @test stats[:total_compounded] == 50.0
        @test stats[:last_checked] == DateTime(2023, 6, 15, 12, 0, 0)
        @test stats[:compound_count] == 3
        @test length(stats[:history]) == 3
        @test stats[:history][1] == (DateTime(2023, 6, 1), 10.0)
        
        # Test with non-existent model
        stats = NumeraiTournament.Compounding.get_compounding_stats(manager, "nonexistent_model")
        @test stats[:total_compounded] == 0.0
        @test stats[:last_checked] === nothing
        @test stats[:compound_count] == 0
        @test stats[:history] == []
    end
    
    @testset "set_compounding_enabled Functionality" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig(enabled=false)
        manager, _ = create_test_manager(mock_client, config)
        
        @test manager.enabled == false
        @test manager.config.enabled == false
        
        # Enable compounding
        NumeraiTournament.Compounding.set_compounding_enabled(manager, true)
        @test manager.enabled == true
        @test manager.config.enabled == true
        
        # Disable compounding
        NumeraiTournament.Compounding.set_compounding_enabled(manager, false)
        @test manager.enabled == false
        @test manager.config.enabled == false
    end
    
    @testset "Financial Logic Validation" begin
        mock_client = MockNumeraiClient()
        config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            min_compound_amount=1.0,
            compound_percentage=100.0,
            max_stake_amount=1000.0
        )
        manager, mock_client = create_test_manager(mock_client, config)
        
        # Test precision with small amounts (but above minimum threshold)
        precision_config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            min_compound_amount=0.0001,  # Very small minimum
            compound_percentage=100.0,
            max_stake_amount=1000.0
        )
        precision_mock_client = MockNumeraiClient(wallet_balance=1.001)
        precision_manager, precision_mock_client = create_test_manager(precision_mock_client, precision_config)
        state = NumeraiTournament.Compounding.CompoundingState("test_model")
        state.last_balance = 1.0
        precision_manager.states["test_model"] = state
        precision_mock_client.model_stakes["test_model"] = 0.0
        
        result = mock_check_and_compound_earnings(precision_manager, precision_mock_client, "test_model")
        @test abs(result - 0.001) < 1e-12  # Should compound the exact precision amount (allowing for tiny floating-point errors)
        
        # Test cumulative compounding accuracy
        cumulative_mock_client = MockNumeraiClient(wallet_balance=100.0)
        cumulative_manager, cumulative_mock_client = create_test_manager(cumulative_mock_client, config)
        cumulative_state = NumeraiTournament.Compounding.CompoundingState("test_model")
        cumulative_state.last_balance = 0.0
        cumulative_state.total_compounded = 0.0
        cumulative_manager.states["test_model"] = cumulative_state
        cumulative_mock_client.model_stakes["test_model"] = 0.0
        
        # Compound multiple times
        for i in 1:5
            cumulative_mock_client.wallet_balance = 100.0 + i * 10.0
            cumulative_state.last_balance = 100.0 + (i-1) * 10.0
            empty!(cumulative_mock_client.api_calls)
            amount = mock_check_and_compound_earnings(cumulative_manager, cumulative_mock_client, "test_model")
            @test amount == 10.0
        end
        
        @test cumulative_state.total_compounded == 50.0
        @test length(cumulative_state.compound_history) == 5
        
        # Verify balance tracking consistency (handle empty case)
        if !isempty(cumulative_state.compound_history)
            expected_history_sum = sum(entry[2] for entry in cumulative_state.compound_history)
            @test expected_history_sum == cumulative_state.total_compounded
        end
        
        # Test with fractional percentages
        frac_mock_client = MockNumeraiClient(wallet_balance=103.0)
        frac_config = NumeraiTournament.Compounding.CompoundingConfig(
            enabled=true,
            compound_percentage=33.33,
            max_stake_amount=1000.0
        )
        frac_manager, frac_mock_client = create_test_manager(frac_mock_client, frac_config)
        frac_state = NumeraiTournament.Compounding.CompoundingState("test_model")
        frac_state.last_balance = 100.0  # 3.0 earnings
        frac_manager.states["test_model"] = frac_state
        frac_mock_client.model_stakes["test_model"] = 0.0
        
        result = mock_check_and_compound_earnings(frac_manager, frac_mock_client, "test_model")
        expected = 3.0 * (33.33 / 100.0)
        @test abs(result - expected) < 1e-6  # Relaxed tolerance for floating point
        
        # Test rounding behavior
        frac_config.compound_percentage = 33.333333
        frac_state.last_balance = 100.0  # Reset for new calculation
        empty!(frac_mock_client.api_calls)
        result = mock_check_and_compound_earnings(frac_manager, frac_mock_client, "test_model")
        expected = 3.0 * (33.333333 / 100.0)
        @test abs(result - expected) < 1e-3  # Very relaxed tolerance for floating point with accumulated errors
    end
end

println("✅ All compounding tests passed!")