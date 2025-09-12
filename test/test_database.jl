using Test
# Import NumeraiTournament if not already loaded (for standalone testing)
if !isdefined(Main, :NumeraiTournament)
    using NumeraiTournament
end
using DataFrames
using Dates

@testset "Database Tests" begin
    # Create temporary database for testing
    temp_db_path = tempname() * ".db"
    
    # Initialize database
    db_conn = NumeraiTournament.Database.init_database(db_path=temp_db_path)
    
    @testset "Model Performance" begin
        # Save performance data
        perf_data = Dict(
            :model_name => "test_model",
            :round_number => 500,
            :correlation => 0.025,
            :mmc => 0.015,
            :tc => 0.02,
            :fnc => 0.018,
            :sharpe => 0.85,
            :payout => 1.5,
            :stake_value => 100.0,
            :rank => 250,
            :percentile => 25.0
        )
        
        NumeraiTournament.Database.save_model_performance(db_conn, perf_data)
        
        # Retrieve performance data
        result = NumeraiTournament.Database.get_model_performance(db_conn, "test_model")
        @test nrow(result) == 1
        @test result[1, :model_name] == "test_model"
        @test result[1, :round_number] == 500
        @test result[1, :correlation] ≈ 0.025
        
        # Get latest performance
        latest = NumeraiTournament.Database.get_latest_performance(db_conn, "test_model")
        @test latest !== nothing
        @test latest.round_number == 500
    end
    
    @testset "Submissions" begin
        # Save submission
        sub_data = Dict(
            :model_name => "test_model",
            :round_number => 500,
            :submission_id => "sub123",
            :filename => "predictions.csv",
            :status => "submitted",
            :validation_correlation => 0.024,
            :validation_sharpe => 0.82
        )
        
        NumeraiTournament.Database.save_submission(db_conn, sub_data)
        
        # Retrieve submissions
        result = NumeraiTournament.Database.get_submissions(db_conn, "test_model")
        @test nrow(result) == 1
        @test result[1, :submission_id] == "sub123"
        
        # Get latest submission
        latest = NumeraiTournament.Database.get_latest_submission(db_conn, "test_model")
        @test latest !== nothing
        @test latest.round_number == 500
    end
    
    @testset "Round Data" begin
        # Save round data
        round_data = Dict(
            :round_number => 500,
            :open_time => now(),
            :close_time => now() + Hour(48),
            :resolve_time => now() + Day(7),
            :round_type => "daily",
            :dataset_url => "https://example.com/data",
            :features_url => "https://example.com/features"
        )
        
        NumeraiTournament.Database.save_round_data(db_conn, round_data)
        
        # Retrieve round data
        result = NumeraiTournament.Database.get_round_data(db_conn, 500)
        @test result !== nothing
        @test result.round_type == "daily"
    end
    
    @testset "Stake History" begin
        # Save stake history
        stake_data = Dict(
            :model_name => "test_model",
            :round_number => 500,
            :action => "increase",
            :amount => 10.0,
            :balance_before => 100.0,
            :balance_after => 110.0,
            :transaction_hash => "0xabc123"
        )
        
        NumeraiTournament.Database.save_stake_history(db_conn, stake_data)
        
        # Retrieve stake history
        result = NumeraiTournament.Database.get_stake_history(db_conn, "test_model")
        @test nrow(result) == 1
        @test result[1, :action] == "increase"
        @test result[1, :amount] == 10.0
    end
    
    @testset "Training Runs" begin
        # Save training run
        train_data = Dict(
            :model_name => "test_model",
            :model_type => "XGBoost",
            :round_number => 500,
            :training_time_seconds => 120.5,
            :validation_score => 0.025,
            :test_score => 0.023,
            :feature_importance => Dict("feature1" => 0.15, "feature2" => 0.10),
            :hyperparameters => Dict("max_depth" => 5, "learning_rate" => 0.01),
            :dataset_version => "v5",
            :num_features => 1050,
            :num_samples => 500000
        )
        
        NumeraiTournament.Database.save_training_run(db_conn, train_data)
        
        # Retrieve training runs
        result = NumeraiTournament.Database.get_training_runs(db_conn, "test_model")
        @test nrow(result) == 1
        @test result[1, :model_type] == "XGBoost"
        @test result[1, :validation_score] ≈ 0.025
    end
    
    @testset "Performance Summary" begin
        # Add more performance data
        for round in 501:505
            perf_data = Dict(
                :model_name => "test_model",
                :round_number => round,
                :correlation => 0.02 + rand() * 0.01,
                :mmc => 0.01 + rand() * 0.01,
                :payout => rand() * 2
            )
            NumeraiTournament.Database.save_model_performance(db_conn, perf_data)
        end
        
        # Get performance summary
        summary = NumeraiTournament.Database.get_performance_summary(db_conn, "test_model")
        @test summary !== nothing
        @test summary.total_rounds == 6  # 500 + 501-505
        @test summary.avg_corr > 0
    end
    
    @testset "Model List" begin
        # Add another model
        perf_data = Dict(
            :model_name => "test_model_2",
            :round_number => 500,
            :correlation => 0.03
        )
        NumeraiTournament.Database.save_model_performance(db_conn, perf_data)
        
        # Get all models
        models = NumeraiTournament.Database.get_all_models(db_conn)
        @test length(models) == 2
        @test "test_model" in models
        @test "test_model_2" in models
    end
    
    # Close database
    NumeraiTournament.Database.close_database(db_conn)
    
    # Clean up
    rm(temp_db_path)
    
    @test !isfile(temp_db_path)
end

println("✅ All database tests passed!")