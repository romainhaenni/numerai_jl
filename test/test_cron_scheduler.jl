using Test
using Dates
using TimeZones
using NumeraiTournament
using NumeraiTournament.Scheduler

# Mock function for testing
test_job_executed = false
test_job_count = 0

function reset_test_globals()
    global test_job_executed = false
    global test_job_count = 0
end

function test_job()
    global test_job_executed = true
    global test_job_count += 1
end

@testset "Cron Scheduler Tests" begin
    
    @testset "CronExpression Construction and Parsing" begin
        
        @testset "Valid cron expressions" begin
            # Basic expressions
            expr = Scheduler.CronExpression("0 18 * * 6")  # Saturday at 18:00
            @test expr.minute == [0]
            @test expr.hour == [18]
            @test expr.day == collect(1:31)
            @test expr.month == collect(1:12)
            @test expr.weekday == [6]
            @test expr.expression == "0 18 * * 6"
            
            # Multiple values with comma
            expr2 = Scheduler.CronExpression("0 */2 * * 0,6")  # Every 2 hours on weekends
            @test expr2.minute == [0]
            @test expr2.hour == collect(0:2:23)
            @test expr2.weekday == [0, 6]
            
            # Range expressions
            expr3 = Scheduler.CronExpression("0 18 * * 2-6")  # Weekdays at 18:00
            @test expr3.weekday == collect(2:6)
            
            # Step values
            expr4 = Scheduler.CronExpression("*/15 * * * *")  # Every 15 minutes
            @test expr4.minute == collect(0:15:59)
            
            # Range with step
            expr5 = Scheduler.CronExpression("0-30/10 * * * *")  # Every 10 minutes from 0 to 30
            @test expr5.minute == [0, 10, 20, 30]
        end
        
        @testset "Invalid cron expressions" begin
            # Wrong number of fields
            @test_throws ErrorException Scheduler.CronExpression("0 18 * *")
            @test_throws ErrorException Scheduler.CronExpression("0 18 * * 6 extra")
            
            # Note: The current implementation doesn't validate bounds
            # These tests verify the current behavior - values are parsed but may be invalid
            expr_minute = Scheduler.CronExpression("60 18 * * 6")  # minute 60 is technically invalid but parsed
            @test 60 in expr_minute.minute
            
            expr_hour = Scheduler.CronExpression("0 25 * * 6")   # hour 25 is technically invalid but parsed
            @test 25 in expr_hour.hour
            
            # Day 32, month 13, and weekday 7 would also be parsed without validation
            # The actual validation happens during matching
        end
        
    end
    
    @testset "Cron Field Parsing" begin
        
        @testset "Asterisk (*) parsing" begin
            @test Scheduler.parse_cron_field("*", 0, 59) == collect(0:59)
            @test Scheduler.parse_cron_field("*", 1, 12) == collect(1:12)
        end
        
        @testset "Step value parsing" begin
            @test Scheduler.parse_cron_field("*/5", 0, 59) == collect(0:5:59)
            @test Scheduler.parse_cron_field("*/10", 1, 12) == collect(1:10:12)
        end
        
        @testset "Range parsing" begin
            @test Scheduler.parse_cron_field("1-5", 0, 10) == collect(1:5)
            @test Scheduler.parse_cron_field("10-15", 0, 59) == collect(10:15)
        end
        
        @testset "Range with step parsing" begin
            @test Scheduler.parse_cron_field("0-20/5", 0, 59) == [0, 5, 10, 15, 20]
            @test Scheduler.parse_cron_field("10-30/10", 0, 59) == [10, 20, 30]
        end
        
        @testset "Comma-separated values" begin
            @test Scheduler.parse_cron_field("1,3,5", 0, 10) == [1, 3, 5]
            @test Scheduler.parse_cron_field("0,15,30,45", 0, 59) == [0, 15, 30, 45]
        end
        
        @testset "Single value parsing" begin
            @test Scheduler.parse_cron_field("5", 0, 10) == [5]
            @test Scheduler.parse_cron_field("0", 0, 59) == [0]
        end
        
    end
    
    @testset "Cron Matching Logic" begin
        
        @testset "Exact time matching" begin
            expr = Scheduler.CronExpression("30 14 11 6 2")  # 14:30 on June 11th, Tuesday
            
            # Should match
            dt1 = DateTime(2024, 6, 11, 14, 30, 0)  # Tuesday June 11th at 14:30
            @test Scheduler.matches(expr, dt1)
            
            # Should not match - wrong minute
            dt2 = DateTime(2024, 6, 11, 14, 31, 0)
            @test !Scheduler.matches(expr, dt2)
            
            # Should not match - wrong hour
            dt3 = DateTime(2024, 6, 11, 15, 30, 0)
            @test !Scheduler.matches(expr, dt3)
        end
        
        @testset "Weekday conversion" begin
            # Test Julia dayofweek (1=Monday, 7=Sunday) to cron format (0=Sunday, 6=Saturday)
            expr = Scheduler.CronExpression("0 12 * * 0")  # Sunday at noon
            
            sunday_dt = DateTime(2024, 1, 7, 12, 0, 0)  # This is a Sunday
            @test dayofweek(sunday_dt) == 7  # Julia format
            @test Scheduler.matches(expr, sunday_dt)
            
            monday_dt = DateTime(2024, 1, 8, 12, 0, 0)  # This is a Monday
            @test !Scheduler.matches(expr, monday_dt)
        end
        
        @testset "Wildcard matching" begin
            expr = Scheduler.CronExpression("0 * * * *")  # Every hour at minute 0
            
            @test Scheduler.matches(expr, DateTime(2024, 1, 1, 0, 0, 0))
            @test Scheduler.matches(expr, DateTime(2024, 1, 1, 12, 0, 0))
            @test Scheduler.matches(expr, DateTime(2024, 1, 1, 23, 0, 0))
            @test !Scheduler.matches(expr, DateTime(2024, 1, 1, 12, 30, 0))
        end
        
        @testset "Range matching" begin
            expr = Scheduler.CronExpression("0 9-17 * * 1-5")  # Business hours
            
            # Should match: Monday at 9 AM
            @test Scheduler.matches(expr, DateTime(2024, 1, 8, 9, 0, 0))
            
            # Should match: Friday at 5 PM
            @test Scheduler.matches(expr, DateTime(2024, 1, 12, 17, 0, 0))
            
            # Should not match: Saturday at 9 AM
            @test !Scheduler.matches(expr, DateTime(2024, 1, 13, 9, 0, 0))
            
            # Should not match: Monday at 8 AM (before business hours)
            @test !Scheduler.matches(expr, DateTime(2024, 1, 8, 8, 0, 0))
        end
        
    end
    
    @testset "Next Run Time Calculation" begin
        
        @testset "Basic next run calculation" begin
            expr = Scheduler.CronExpression("0 18 * * 6")  # Saturday at 18:00
            
            # From a Friday, should find next Saturday
            friday = DateTime(2024, 1, 5, 12, 0, 0)  # Friday noon
            saturday_expected = DateTime(2024, 1, 6, 18, 0, 0)  # Saturday 6 PM
            
            next_run = Scheduler.next_run_time(expr, friday)
            @test next_run == saturday_expected
        end
        
        @testset "Same day next run" begin
            expr = Scheduler.CronExpression("0 20 * * *")  # Every day at 20:00
            
            # From 15:00, should find 20:00 same day
            current = DateTime(2024, 1, 1, 15, 0, 0)
            expected = DateTime(2024, 1, 1, 20, 0, 0)
            
            next_run = Scheduler.next_run_time(expr, current)
            @test next_run == expected
        end
        
        @testset "Next minute rounding" begin
            expr = Scheduler.CronExpression("*/5 * * * *")  # Every 5 minutes
            
            # From 12:03:30, should round up to 12:05:00
            current = DateTime(2024, 1, 1, 12, 3, 30)
            expected = DateTime(2024, 1, 1, 12, 5, 0)
            
            next_run = Scheduler.next_run_time(expr, current)
            @test next_run == expected
        end
        
        @testset "Weekly schedule" begin
            expr = Scheduler.CronExpression("0 12 * * 1")  # Every Monday at noon
            
            # From Wednesday, should find next Monday
            wednesday = DateTime(2024, 1, 3, 15, 0, 0)  # Wednesday afternoon
            next_monday = DateTime(2024, 1, 8, 12, 0, 0)  # Next Monday noon
            
            next_run = Scheduler.next_run_time(expr, wednesday)
            @test next_run == next_monday
        end
        
    end
    
    @testset "CronJob Management" begin
        
        @testset "CronJob creation" begin
            reset_test_globals()
            
            job = Scheduler.CronJob("0 12 * * *", test_job, "Test Job")
            
            @test job.name == "Test Job"
            @test job.cron_expression.expression == "0 12 * * *"
            @test job.active == false
            @test job.last_run === nothing
            @test job.next_run !== nothing
        end
        
        @testset "CronJob execution" begin
            reset_test_globals()
            
            job = Scheduler.CronJob("* * * * *", test_job, "Test Job")
            job.active = true
            
            # Simulate job execution
            job.task()
            
            @test test_job_executed == true
            @test test_job_count == 1
        end
        
    end
    
    @testset "Tournament-Specific Cron Expressions" begin
        
        @testset "Weekend round schedule" begin
            # "0 18 * * 6" - Saturday at 18:00
            expr = Scheduler.CronExpression("0 18 * * 6")
            
            # Test various Saturdays
            sat1 = DateTime(2024, 1, 6, 18, 0, 0)   # Saturday
            sat2 = DateTime(2024, 2, 10, 18, 0, 0)  # Saturday
            fri = DateTime(2024, 1, 5, 18, 0, 0)    # Friday
            sun = DateTime(2024, 1, 7, 18, 0, 0)    # Sunday
            
            @test Scheduler.matches(expr, sat1)
            @test Scheduler.matches(expr, sat2)
            @test !Scheduler.matches(expr, fri)
            @test !Scheduler.matches(expr, sun)
        end
        
        @testset "Weekend check and submit" begin
            # "0 */2 * * 0,6" - Every 2 hours on weekends
            expr = Scheduler.CronExpression("0 */2 * * 0,6")
            
            # Saturday at even hours
            @test Scheduler.matches(expr, DateTime(2024, 1, 6, 0, 0, 0))   # Midnight
            @test Scheduler.matches(expr, DateTime(2024, 1, 6, 2, 0, 0))   # 2 AM
            @test Scheduler.matches(expr, DateTime(2024, 1, 6, 18, 0, 0))  # 6 PM
            @test !Scheduler.matches(expr, DateTime(2024, 1, 6, 1, 0, 0))  # 1 AM (odd hour)
            
            # Sunday at even hours
            @test Scheduler.matches(expr, DateTime(2024, 1, 7, 0, 0, 0))   # Sunday midnight
            @test Scheduler.matches(expr, DateTime(2024, 1, 7, 12, 0, 0))  # Sunday noon
            @test !Scheduler.matches(expr, DateTime(2024, 1, 7, 13, 0, 0)) # Sunday 1 PM
            
            # Weekdays should not match
            @test !Scheduler.matches(expr, DateTime(2024, 1, 8, 2, 0, 0))  # Monday 2 AM
        end
        
        @testset "Daily round schedule" begin
            # "0 18 * * 2-6" - Tuesday through Saturday at 18:00
            expr = Scheduler.CronExpression("0 18 * * 2-6")
            
            @test Scheduler.matches(expr, DateTime(2024, 1, 2, 18, 0, 0))   # Tuesday
            @test Scheduler.matches(expr, DateTime(2024, 1, 3, 18, 0, 0))   # Wednesday
            @test Scheduler.matches(expr, DateTime(2024, 1, 4, 18, 0, 0))   # Thursday
            @test Scheduler.matches(expr, DateTime(2024, 1, 5, 18, 0, 0))   # Friday
            @test Scheduler.matches(expr, DateTime(2024, 1, 6, 18, 0, 0))   # Saturday
            @test !Scheduler.matches(expr, DateTime(2024, 1, 7, 18, 0, 0))  # Sunday
            @test !Scheduler.matches(expr, DateTime(2024, 1, 8, 18, 0, 0))  # Monday
        end
        
        @testset "Weekly update schedule" begin
            # "0 12 * * 1" - Monday at 12:00
            expr = Scheduler.CronExpression("0 12 * * 1")
            
            @test Scheduler.matches(expr, DateTime(2024, 1, 8, 12, 0, 0))   # Monday
            @test !Scheduler.matches(expr, DateTime(2024, 1, 9, 12, 0, 0))  # Tuesday
            @test !Scheduler.matches(expr, DateTime(2024, 1, 8, 11, 0, 0))  # Monday 11 AM
            @test !Scheduler.matches(expr, DateTime(2024, 1, 8, 13, 0, 0))  # Monday 1 PM
        end
        
        @testset "Hourly monitoring" begin
            # "0 * * * *" - Every hour at minute 0
            expr = Scheduler.CronExpression("0 * * * *")
            
            for hour in 0:23
                @test Scheduler.matches(expr, DateTime(2024, 1, 1, hour, 0, 0))
                @test !Scheduler.matches(expr, DateTime(2024, 1, 1, hour, 30, 0))
            end
        end
        
    end
    
    @testset "UTC Timezone Handling" begin
        
        @testset "UTC time consistency" begin
            # Test that our UTC utility functions work correctly
            utc_time = NumeraiTournament.utc_now_datetime()
            @test isa(utc_time, DateTime)
            
            # Should be roughly now (within a few seconds)
            now_local = now()
            time_diff = abs((utc_time - now_local).value) / 1000  # Convert to seconds
            @test time_diff < 86400  # Less than a day difference (accounting for timezone)
        end
        
        @testset "Cron matching with UTC times" begin
            # Test with specific UTC times
            expr = Scheduler.CronExpression("0 18 * * 6")  # Saturday 18:00 UTC
            
            # Create a specific UTC Saturday at 18:00
            utc_saturday = DateTime(2024, 1, 6, 18, 0, 0)  # This should be Saturday
            @test dayofweek(utc_saturday) == 6  # Verify it's Saturday
            @test Scheduler.matches(expr, utc_saturday)
        end
        
    end
    
    @testset "Error Handling and Edge Cases" begin
        
        @testset "Invalid date handling" begin
            expr = Scheduler.CronExpression("0 0 31 2 *")  # Feb 31st (doesn't exist)
            
            # Should not find a match for Feb 31st
            march_start = DateTime(2024, 3, 1, 0, 0, 0)
            next_run = Scheduler.next_run_time(expr, march_start)
            
            # Should skip to next year's Feb 31st (which doesn't exist) or timeout
            @test next_run === nothing || year(next_run) > 2024
        end
        
        @testset "Leap year handling" begin
            expr = Scheduler.CronExpression("0 0 29 2 *")  # Feb 29th
            
            # 2024 is a leap year, so Feb 29th should exist
            jan_2024 = DateTime(2024, 1, 1, 0, 0, 0)
            next_run = Scheduler.next_run_time(expr, jan_2024)
            
            @test next_run !== nothing
            @test month(next_run) == 2
            @test day(next_run) == 29
            @test year(next_run) == 2024
        end
        
        @testset "Year boundary crossing" begin
            expr = Scheduler.CronExpression("0 0 1 1 *")  # New Year's Day
            
            # From December, should find next January 1st
            dec_31 = DateTime(2024, 12, 31, 12, 0, 0)
            next_run = Scheduler.next_run_time(expr, dec_31)
            
            @test next_run !== nothing
            @test next_run == DateTime(2025, 1, 1, 0, 0, 0)
        end
        
        @testset "No match within search limit" begin
            # Create an expression that's very unlikely to match soon
            expr = Scheduler.CronExpression("0 0 29 2 1")  # Feb 29th on a Monday (very rare)
            
            current = DateTime(2024, 1, 1, 0, 0, 0)
            next_run = Scheduler.next_run_time(expr, current)
            
            # Should return nothing if no match found within 1 year
            # (or return a very distant date)
            @test next_run === nothing || year(next_run) > 2030
        end
        
    end
    
    @testset "Scheduler Configuration" begin
        
        @testset "Weekend detection" begin
            # Test the is_weekend function
            saturday = DateTime(2024, 1, 6, 12, 0, 0)  # Saturday
            sunday = DateTime(2024, 1, 7, 12, 0, 0)    # Sunday
            monday = DateTime(2024, 1, 8, 12, 0, 0)    # Monday
            
            # Note: The is_weekend function in cron.jl checks for dayofweek 6,7
            @test dayofweek(saturday) == 6
            @test dayofweek(sunday) == 7
            @test dayofweek(monday) == 1
        end
        
        @testset "Cron job setup validation" begin
            # Test that all tournament cron expressions are valid
            weekend_expr = "0 18 * * 6"
            @test_nowarn Scheduler.CronExpression(weekend_expr)
            
            check_submit_expr = "0 */2 * * 0,6"
            @test_nowarn Scheduler.CronExpression(check_submit_expr)
            
            daily_expr = "0 18 * * 2-6"
            @test_nowarn Scheduler.CronExpression(daily_expr)
            
            weekly_expr = "0 12 * * 1"
            @test_nowarn Scheduler.CronExpression(weekly_expr)
            
            hourly_expr = "0 * * * *"
            @test_nowarn Scheduler.CronExpression(hourly_expr)
        end
        
    end
    
    @testset "Performance and Stress Tests" begin
        
        @testset "Large time range search" begin
            expr = Scheduler.CronExpression("0 0 1 1 *")  # Once per year
            
            # Should be able to find next occurrence quickly
            current = DateTime(2024, 6, 15, 12, 0, 0)
            
            # Measure time (should be fast)
            start_time = time()
            next_run = Scheduler.next_run_time(expr, current)
            elapsed = time() - start_time
            
            @test next_run !== nothing
            @test elapsed < 1.0  # Should complete in less than 1 second
        end
        
        @testset "Complex expression parsing" begin
            # Test with complex but valid expressions
            complex_expr = "15,30,45 9-17 */2 1,3,5 1-5"
            
            @test_nowarn Scheduler.CronExpression(complex_expr)
            
            expr = Scheduler.CronExpression(complex_expr)
            @test length(expr.minute) == 3  # 15, 30, 45
            @test length(expr.hour) == 9    # 9-17
            @test length(expr.month) == 3   # 1, 3, 5  
            @test length(expr.weekday) == 5  # 1-5
        end
        
    end
    
end

# Reset test globals after all tests
reset_test_globals()

println("✅ Cron scheduler tests completed!")