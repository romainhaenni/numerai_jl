using Test
using Dates
using TimeZones

# Include the utils module
include("../src/utils.jl")

@testset "Submission Window Tests" begin
    @testset "Weekend Round Detection" begin
        # Saturday at 18:00 UTC (weekend round)
        weekend_open = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday
        @test is_weekend_round(weekend_open) == true
        
        # Tuesday at 18:00 UTC (daily round)
        daily_open = DateTime(2024, 1, 2, 18, 0, 0)    # Tuesday
        @test is_weekend_round(daily_open) == false
        
        # Wednesday at 18:00 UTC (daily round)
        daily_open2 = DateTime(2024, 1, 3, 18, 0, 0)   # Wednesday
        @test is_weekend_round(daily_open2) == false
    end
    
    @testset "Submission Window Calculation" begin
        # Weekend round: Saturday 18:00 -> Monday 06:00 (60 hours)
        weekend_open = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday 18:00
        weekend_close = calculate_submission_window_end(weekend_open)
        expected_weekend_close = DateTime(2024, 1, 9, 6, 0, 0)  # Tuesday 06:00 (60 hours later)
        @test weekend_close == expected_weekend_close
        
        # Daily round: Tuesday 18:00 -> Thursday 00:00 (30 hours)
        daily_open = DateTime(2024, 1, 2, 18, 0, 0)    # Tuesday 18:00
        daily_close = calculate_submission_window_end(daily_open)
        expected_daily_close = DateTime(2024, 1, 4, 0, 0, 0)    # Thursday 00:00 (30 hours later)
        @test daily_close == expected_daily_close
    end
    
    @testset "Submission Window Status" begin
        # Test weekend round
        weekend_open = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday 18:00
        
        # Test within window (1 hour after opening)
        current_time = DateTime(2024, 1, 6, 19, 0, 0)
        @test is_submission_window_open(weekend_open, current_time) == true
        
        # Test at window end (exactly 60 hours later)
        window_end = DateTime(2024, 1, 9, 6, 0, 0)
        @test is_submission_window_open(weekend_open, window_end) == true
        
        # Test after window closes (1 minute after)
        after_window = DateTime(2024, 1, 9, 6, 1, 0)
        @test is_submission_window_open(weekend_open, after_window) == false
        
        # Test daily round
        daily_open = DateTime(2024, 1, 2, 18, 0, 0)    # Tuesday 18:00
        
        # Test within daily window (10 hours after opening)
        current_time_daily = DateTime(2024, 1, 3, 4, 0, 0)
        @test is_submission_window_open(daily_open, current_time_daily) == true
        
        # Test after daily window closes (31 hours after)
        after_daily_window = DateTime(2024, 1, 4, 1, 0, 0)
        @test is_submission_window_open(daily_open, after_daily_window) == false
    end
    
    @testset "Submission Window Info" begin
        # Test weekend round info
        weekend_open = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday 18:00
        current_time = DateTime(2024, 1, 7, 10, 0, 0)  # Sunday 10:00 (16 hours later)
        
        info = get_submission_window_info(weekend_open, current_time)
        
        @test info.round_type == "weekend"
        @test info.is_open == true
        @test info.window_end == DateTime(2024, 1, 9, 6, 0, 0)
        @test info.time_remaining ≈ 44.0  # 60 - 16 = 44 hours remaining
        
        # Test daily round info
        daily_open = DateTime(2024, 1, 2, 18, 0, 0)    # Tuesday 18:00
        current_time_daily = DateTime(2024, 1, 3, 6, 0, 0)  # Wednesday 6:00 (12 hours later)
        
        info_daily = get_submission_window_info(daily_open, current_time_daily)
        
        @test info_daily.round_type == "daily"
        @test info_daily.is_open == true
        @test info_daily.window_end == DateTime(2024, 1, 4, 0, 0, 0)
        @test info_daily.time_remaining ≈ 18.0  # 30 - 12 = 18 hours remaining
        
        # Test closed window (negative time remaining)
        closed_time = DateTime(2024, 1, 10, 0, 0, 0)  # Wednesday after weekend window
        info_closed = get_submission_window_info(weekend_open, closed_time)
        
        @test info_closed.round_type == "weekend"
        @test info_closed.is_open == false
        @test info_closed.time_remaining < 0  # Should be negative
    end
    
    @testset "Edge Cases" begin
        # Test exactly at opening time
        weekend_open = DateTime(2024, 1, 6, 18, 0, 0)
        @test is_submission_window_open(weekend_open, weekend_open) == true
        
        # Test one second before opening (hypothetical)
        before_open = DateTime(2024, 1, 6, 17, 59, 59)
        # Note: This is testing the logic, not a real scenario since rounds don't open before their open time
        window_end = calculate_submission_window_end(weekend_open)
        @test before_open < window_end
        
        # Test boundary conditions for day of week
        sunday_round = DateTime(2024, 1, 7, 18, 0, 0)  # Sunday (not typical but testing)
        @test is_weekend_round(sunday_round) == false   # Only Saturday is weekend round
        
        friday_round = DateTime(2024, 1, 5, 18, 0, 0)   # Friday
        @test is_weekend_round(friday_round) == false   # Friday is daily round
    end
end

println("Running submission window validation tests...")