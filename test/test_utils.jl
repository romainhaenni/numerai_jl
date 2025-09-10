using Test
using Dates
using TimeZones

# Include the utils module for direct testing
include("../src/utils.jl")

@testset "Utils Module Tests" begin
    
    @testset "UTC Time Functions" begin
        @testset "utc_now()" begin
            # Test that utc_now returns a ZonedDateTime
            current_utc = utc_now()
            @test current_utc isa ZonedDateTime
            @test timezone(current_utc) == tz"UTC"
            
            # Test that consecutive calls are reasonably close (within 1 second)
            time1 = utc_now()
            time2 = utc_now()
            time_diff = (time2 - time1).value / 1000  # Convert to seconds
            @test time_diff < 1.0
            
            # Test that the time is approximately correct (within reasonable bounds)
            expected_year = year(now())
            @test year(current_utc) == expected_year
        end
        
        @testset "utc_now_datetime()" begin
            # Test that utc_now_datetime returns a DateTime
            current_dt = utc_now_datetime()
            @test current_dt isa DateTime
            
            # Test that it's consistent with utc_now()
            zdt = utc_now()
            dt = utc_now_datetime()
            time_diff = abs((DateTime(zdt) - dt).value) / 1000  # Convert to seconds
            @test time_diff < 1.0  # Should be within 1 second
            
            # Test multiple calls are sequential
            dt1 = utc_now_datetime()
            sleep(0.001)  # Small delay
            dt2 = utc_now_datetime()
            @test dt2 >= dt1
        end
    end
    
    @testset "Weekend Round Detection" begin
        @testset "is_weekend_round() - Basic Cases" begin
            # Test Saturday (day 6) - should be weekend round
            saturday_morning = DateTime(2024, 1, 6, 10, 0, 0)  # Saturday 10:00
            saturday_evening = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday 18:00 (typical open time)
            saturday_night = DateTime(2024, 1, 6, 23, 0, 0)    # Saturday 23:00
            @test is_weekend_round(saturday_morning) == true
            @test is_weekend_round(saturday_evening) == true
            @test is_weekend_round(saturday_night) == true
            
            # Test all other days - should NOT be weekend rounds
            days = [
                (DateTime(2024, 1, 1, 18, 0, 0), "Monday"),    # Monday
                (DateTime(2024, 1, 2, 18, 0, 0), "Tuesday"),   # Tuesday
                (DateTime(2024, 1, 3, 18, 0, 0), "Wednesday"), # Wednesday
                (DateTime(2024, 1, 4, 18, 0, 0), "Thursday"),  # Thursday
                (DateTime(2024, 1, 5, 18, 0, 0), "Friday"),    # Friday
                (DateTime(2024, 1, 7, 18, 0, 0), "Sunday")     # Sunday
            ]
            
            for (date, day_name) in days
                @test is_weekend_round(date) == false
            end
        end
        
        @testset "is_weekend_round() - Edge Cases" begin
            # Test different times on Saturday
            times = [
                DateTime(2024, 6, 1, 0, 0, 0),   # Saturday midnight
                DateTime(2024, 6, 1, 6, 0, 0),   # Saturday early morning
                DateTime(2024, 6, 1, 12, 0, 0),  # Saturday noon
                DateTime(2024, 6, 1, 18, 0, 0),  # Saturday evening
                DateTime(2024, 6, 1, 23, 59, 59) # Saturday last second
            ]
            
            for time in times
                @test dayofweek(time) == 6  # Verify it's Saturday
                @test is_weekend_round(time) == true
            end
        end
    end
    
    @testset "Submission Window End Calculation" begin
        @testset "calculate_submission_window_end() - Weekend Rounds" begin
            # Standard weekend round: Saturday 18:00 -> Monday 06:00 (60 hours)
            weekend_opens = [
                DateTime(2024, 1, 6, 18, 0, 0),   # Saturday 18:00
                DateTime(2024, 1, 13, 18, 0, 0),  # Another Saturday 18:00
                DateTime(2024, 6, 1, 18, 0, 0),   # Saturday in June
                DateTime(2024, 12, 7, 18, 0, 0),  # Saturday in December
            ]
            
            for open_time in weekend_opens
                @test is_weekend_round(open_time) == true  # Verify it's actually a weekend round
                close_time = calculate_submission_window_end(open_time)
                hours_diff = (close_time - open_time).value / (1000 * 60 * 60)
                @test hours_diff == 60.0  # Exactly 60 hours
                
                # Verify the closing day is Tuesday (day 2) 
                # Saturday 18:00 + 60 hours = Tuesday 06:00
                @test dayofweek(close_time) == 2  # Tuesday
            end
            
            # Test specific expected outcomes
            saturday_6pm = DateTime(2024, 1, 6, 18, 0, 0)   # Saturday 18:00
            expected_close = DateTime(2024, 1, 9, 6, 0, 0)   # Tuesday 06:00 (60 hours later)
            actual_close = calculate_submission_window_end(saturday_6pm)
            @test actual_close == expected_close
        end
        
        @testset "calculate_submission_window_end() - Daily Rounds" begin
            # Daily rounds: 30 hours after opening
            daily_rounds = [
                (DateTime(2024, 1, 1, 18, 0, 0), "Monday"),     # Monday 18:00 -> Wednesday 00:00
                (DateTime(2024, 1, 2, 18, 0, 0), "Tuesday"),    # Tuesday 18:00 -> Thursday 00:00
                (DateTime(2024, 1, 3, 18, 0, 0), "Wednesday"),  # Wednesday 18:00 -> Friday 00:00
                (DateTime(2024, 1, 4, 18, 0, 0), "Thursday"),   # Thursday 18:00 -> Saturday 00:00
                (DateTime(2024, 1, 5, 18, 0, 0), "Friday"),     # Friday 18:00 -> Sunday 00:00
                (DateTime(2024, 1, 7, 18, 0, 0), "Sunday")      # Sunday 18:00 -> Tuesday 00:00
            ]
            
            for (open_time, day_name) in daily_rounds
                @test is_weekend_round(open_time) == false  # Verify it's NOT a weekend round
                close_time = calculate_submission_window_end(open_time)
                hours_diff = (close_time - open_time).value / (1000 * 60 * 60)
                @test hours_diff == 30.0
            end
            
            # Test specific expected outcomes
            tuesday_6pm = DateTime(2024, 1, 2, 18, 0, 0)    # Tuesday 18:00
            expected_close = DateTime(2024, 1, 4, 0, 0, 0)   # Thursday 00:00
            actual_close = calculate_submission_window_end(tuesday_6pm)
            @test actual_close == expected_close
        end
    end
    
    @testset "Submission Window Status Check" begin
        @testset "is_submission_window_open() - Weekend Rounds" begin
            weekend_open = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday 18:00
            window_end = DateTime(2024, 1, 9, 6, 0, 0)     # Monday 06:00
            
            # Test times when window should be open
            open_times = [
                weekend_open,                                    # Exactly at opening
                DateTime(2024, 1, 6, 18, 0, 1),                # 1 second after
                DateTime(2024, 1, 6, 22, 0, 0),                # 4 hours after (Saturday night)
                DateTime(2024, 1, 7, 12, 0, 0),                # Sunday noon
                DateTime(2024, 1, 8, 18, 0, 0),                # Monday 18:00 (same time next day)
                DateTime(2024, 1, 9, 5, 59, 59),               # 1 second before close
                window_end                                       # Exactly at close time
            ]
            
            for test_time in open_times
                @test is_submission_window_open(weekend_open, test_time) == true
            end
            
            # Test times when window should be closed
            closed_times = [
                DateTime(2024, 1, 9, 6, 0, 1),                # 1 second after closing
                DateTime(2024, 1, 9, 12, 0, 0),               # Monday noon (after close)
                DateTime(2024, 1, 10, 6, 0, 0),               # Tuesday 06:00
            ]
            
            for test_time in closed_times
                @test is_submission_window_open(weekend_open, test_time) == false
            end
        end
        
        @testset "is_submission_window_open() - Daily Rounds" begin
            daily_open = DateTime(2024, 1, 2, 18, 0, 0)    # Tuesday 18:00
            window_end = DateTime(2024, 1, 4, 0, 0, 0)     # Thursday 00:00
            
            # Test times when window should be open
            open_times = [
                daily_open,                                    # Exactly at opening
                DateTime(2024, 1, 2, 22, 0, 0),              # Tuesday 22:00
                DateTime(2024, 1, 3, 12, 0, 0),              # Wednesday noon
                DateTime(2024, 1, 3, 23, 59, 59),            # Wednesday 23:59:59
                window_end                                     # Exactly at close time
            ]
            
            for test_time in open_times
                @test is_submission_window_open(daily_open, test_time) == true
            end
            
            # Test times when window should be closed
            closed_times = [
                DateTime(2024, 1, 4, 0, 0, 1),               # 1 second after closing
                DateTime(2024, 1, 4, 12, 0, 0),              # Thursday noon
                DateTime(2024, 1, 5, 0, 0, 0),               # Friday midnight
            ]
            
            for test_time in closed_times
                @test is_submission_window_open(daily_open, test_time) == false
            end
        end
    end
    
    @testset "Submission Window Info" begin
        @testset "get_submission_window_info() - Weekend Rounds" begin
            weekend_open = DateTime(2024, 1, 6, 18, 0, 0)   # Saturday 18:00
            
            # Test at different times during the window
            test_cases = [
                (DateTime(2024, 1, 6, 20, 0, 0), 58.0, true),   # 2 hours after opening
                (DateTime(2024, 1, 7, 18, 0, 0), 36.0, true),   # 24 hours after opening
                (DateTime(2024, 1, 8, 18, 0, 0), 12.0, true),   # 48 hours after opening
                (DateTime(2024, 1, 9, 6, 0, 0), 0.0, true),     # Exactly at closing
                (DateTime(2024, 1, 9, 8, 0, 0), -2.0, false),   # 2 hours after closing
                (DateTime(2024, 1, 10, 6, 0, 0), -24.0, false), # 24 hours after closing
            ]
            
            for (current_time, expected_remaining, expected_open) in test_cases
                info = get_submission_window_info(weekend_open, current_time)
                
                @test info.round_type == "weekend"
                @test info.is_open == expected_open
                @test info.window_end == DateTime(2024, 1, 9, 6, 0, 0)
                @test info.time_remaining ≈ expected_remaining atol=0.1
                
                # Check that the named tuple has all expected fields
                @test haskey(info, :window_end)
                @test haskey(info, :is_open)
                @test haskey(info, :time_remaining)
                @test haskey(info, :round_type)
            end
        end
        
        @testset "get_submission_window_info() - Daily Rounds" begin
            daily_open = DateTime(2024, 1, 2, 18, 0, 0)     # Tuesday 18:00
            
            test_cases = [
                (DateTime(2024, 1, 2, 20, 0, 0), 28.0, true),   # 2 hours after opening
                (DateTime(2024, 1, 3, 6, 0, 0), 18.0, true),    # 12 hours after opening
                (DateTime(2024, 1, 3, 18, 0, 0), 6.0, true),    # 24 hours after opening
                (DateTime(2024, 1, 4, 0, 0, 0), 0.0, true),     # Exactly at closing
                (DateTime(2024, 1, 4, 2, 0, 0), -2.0, false),   # 2 hours after closing
                (DateTime(2024, 1, 5, 0, 0, 0), -24.0, false),  # 24 hours after closing
            ]
            
            for (current_time, expected_remaining, expected_open) in test_cases
                info = get_submission_window_info(daily_open, current_time)
                
                @test info.round_type == "daily"
                @test info.is_open == expected_open
                @test info.window_end == DateTime(2024, 1, 4, 0, 0, 0)
                @test info.time_remaining ≈ expected_remaining atol=0.1
            end
        end
    end
    
    @testset "Integration and Cross-Function Validation" begin
        @testset "Consistency Between Functions" begin
            # Test that all functions are consistent with each other
            test_times = [
                DateTime(2024, 1, 6, 18, 0, 0),   # Saturday (weekend)
                DateTime(2024, 1, 2, 18, 0, 0),   # Tuesday (daily)
                DateTime(2024, 1, 5, 18, 0, 0),   # Friday (daily)
            ]
            
            for open_time in test_times
                is_weekend = is_weekend_round(open_time)
                window_end = calculate_submission_window_end(open_time)
                
                # Test at opening time
                @test is_submission_window_open(open_time, open_time) == true
                
                # Test 1 second before closing
                before_close = window_end - Millisecond(1000)
                @test is_submission_window_open(open_time, before_close) == true
                
                # Test exactly at closing
                @test is_submission_window_open(open_time, window_end) == true
                
                # Test 1 second after closing
                after_close = window_end + Millisecond(1000)
                @test is_submission_window_open(open_time, after_close) == false
                
                # Test info function consistency
                info_open = get_submission_window_info(open_time, open_time)
                info_closed = get_submission_window_info(open_time, after_close)
                
                @test info_open.is_open == true
                @test info_closed.is_open == false
                @test info_open.window_end == window_end
                @test info_closed.window_end == window_end
                
                expected_type = is_weekend ? "weekend" : "daily"
                @test info_open.round_type == expected_type
                @test info_closed.round_type == expected_type
            end
        end
    end
end

println("Running comprehensive Utils module tests...")
println("All tests completed successfully!")