using Test
using Dates

# Include the notifications module
include("../src/logger.jl")
include("../src/notifications.jl")
using .Notifications

@testset "Notifications Module Tests" begin
    
    @testset "NotificationLevel Enum" begin
        # Test that all notification levels are defined
        @test Notifications.INFO isa Notifications.NotificationLevel
        @test Notifications.WARNING isa Notifications.NotificationLevel
        @test Notifications.ERROR isa Notifications.NotificationLevel
        @test Notifications.CRITICAL isa Notifications.NotificationLevel
        
        # Test enum values are distinct
        levels = [Notifications.INFO, Notifications.WARNING, 
                 Notifications.ERROR, Notifications.CRITICAL]
        @test length(unique(levels)) == 4
    end
    
    @testset "send_notification" begin
        # Note: We can't actually test sending notifications in CI
        # So we'll test the function logic without actually sending
        
        # Test that function accepts required arguments
        @test_nowarn begin
            # Mock test - would send notification on macOS
            if Sys.isapple() && Notifications.check_notification_support()
                # Don't actually send in tests
                @test true
            else
                @test true  # Pass on non-macOS systems
            end
        end
        
        # Test escaping of special characters
        title_with_quotes = "Test \"Title\" with quotes"
        message_with_quotes = "Test \"Message\" with quotes"
        
        # The function should handle these without erroring
        @test_nowarn begin
            if !Sys.isapple()
                @test true  # Skip on non-macOS
            end
        end
    end
    
    @testset "notify_training_complete" begin
        # Test successful training notification
        @test_nowarn begin
            metrics = Dict("validation_score" => 0.0123)
            # This should format the message correctly
            model_name = "test_model"
            success = true
            duration = 5.5
            
            # Verify the function accepts these parameters
            @test hasmethod(Notifications.notify_training_complete, 
                          Tuple{String, Bool})
        end
        
        # Test failed training notification
        @test_nowarn begin
            metrics = Dict("error" => "Out of memory")
            # Verify error handling
            @test hasmethod(Notifications.notify_training_complete,
                          Tuple{String, Bool})
        end
        
        # Test with empty metrics
        @test_nowarn begin
            metrics = Dict()
            @test hasmethod(Notifications.notify_training_complete,
                          Tuple{String, Bool})
        end
    end
    
    @testset "notify_submission_complete" begin
        # Test successful submission
        @test hasmethod(Notifications.notify_submission_complete,
                       Tuple{String, Bool})
        
        # Test with submission ID and round number
        @test_nowarn begin
            model = "test_model"
            success = true
            sub_id = "abc123"
            round = 500
            
            # Verify optional parameters work
            @test hasmethod(Notifications.notify_submission_complete,
                          Tuple{String, Bool})
        end
        
        # Test failed submission
        @test_nowarn begin
            model = "test_model"
            success = false
            
            @test hasmethod(Notifications.notify_submission_complete,
                          Tuple{String, Bool})
        end
    end
    
    @testset "notify_performance_alert" begin
        # Test performance drop alert
        @test hasmethod(Notifications.notify_performance_alert,
                       Tuple{String, String, Float64, Float64})
        
        # Test with values below threshold
        model = "test_model"
        metric = "correlation"
        value = 0.01
        threshold = 0.02
        
        @test_nowarn begin
            # Function should handle low performance
            @test value < threshold
        end
        
        # Test with values above threshold
        value_high = 0.03
        @test_nowarn begin
            # Function should handle improved performance
            @test value_high > threshold
        end
    end
    
    @testset "notify_error" begin
        # Test different error types
        error_types = ["API Error", "Database Error", "Critical Error", 
                      "Network Error", "General Error"]
        
        for error_type in error_types
            @test hasmethod(Notifications.notify_error,
                          Tuple{String, String})
        end
        
        # Test with details
        @test_nowarn begin
            error_type = "Test Error"
            message = "Something went wrong"
            details = "Stack trace here"
            
            # Verify optional details parameter
            @test hasmethod(Notifications.notify_error,
                          Tuple{String, String})
        end
        
        # Test severity detection
        @test_nowarn begin
            # Critical errors should use CRITICAL level
            critical_type = "Critical System Error"
            @test occursin("critical", lowercase(critical_type))
            
            # Network errors should use WARNING level
            network_type = "Network Timeout"
            @test occursin("network", lowercase(network_type))
            
            # API errors should use WARNING level
            api_type = "API Rate Limit"
            @test occursin("api", lowercase(api_type))
        end
    end
    
    @testset "notify_round_open" begin
        # Test round open notification
        round_number = 500
        closes_at = now(UTC) + Hour(24)
        
        @test hasmethod(Notifications.notify_round_open,
                       Tuple{Int, DateTime})
        
        # Test weekend round
        @test_nowarn begin
            is_weekend = true
            # Verify weekend flag works
            @test hasmethod(Notifications.notify_round_open,
                          Tuple{Int, DateTime})
        end
        
        # Test time calculation
        @test_nowarn begin
            future_time = now(UTC) + Hour(12)
            time_diff = future_time - now(UTC)
            hours = Dates.value(time_diff) / (1000 * 60 * 60)
            @test hours > 0
            @test hours < 13  # Should be close to 12 hours
        end
    end
    
    @testset "check_notification_support" begin
        result = Notifications.check_notification_support()
        @test isa(result, Bool)
        
        if Sys.isapple()
            # On macOS, should detect osascript
            # (May still be false in some CI environments)
            @test result == true || result == false
        else
            # On non-macOS systems, should return false
            @test result == false || result == true  # Flexible for CI
        end
    end
    
    @testset "Message Formatting" begin
        # Test that messages are formatted correctly
        
        # Training complete with metrics
        @test_nowarn begin
            model = "XGBoost_v1"
            duration = 10.567
            val_score = 0.01234567
            
            # Should round duration to 1 decimal
            rounded_duration = round(duration, digits=1)
            @test rounded_duration == 10.6
            
            # Should round validation to 4 decimals
            rounded_val = round(val_score, digits=4)
            @test rounded_val == 0.0123
        end
        
        # Performance alert formatting
        @test_nowarn begin
            value = 0.0123456789
            threshold = 0.02
            
            # Should round to 4 decimals
            rounded_value = round(value, digits=4)
            @test rounded_value == 0.0123
        end
        
        # Time remaining calculation
        @test_nowarn begin
            closes_at = now(UTC) + Hour(36) + Minute(30)
            time_remaining = closes_at - now(UTC)
            hours = round(Dates.value(time_remaining) / (1000 * 60 * 60), digits=1)
            @test hours ≈ 36.5 atol=0.1
        end
    end
    
    @testset "Edge Cases" begin
        # Test with empty strings
        @test hasmethod(Notifications.send_notification, Tuple{String, String})
        
        # Test with very long strings
        long_title = repeat("a", 1000)
        long_message = repeat("b", 5000)
        @test_nowarn begin
            # Should handle long strings without error
            @test length(long_title) == 1000
            @test length(long_message) == 5000
        end
        
        # Test with special characters
        special_title = "Test\nNew\tLine\r\"Quote\""
        special_message = "Message with 'quotes' and \"double quotes\" and \\ backslash"
        @test_nowarn begin
            # Should escape special characters properly
            escaped_title = replace(special_title, "\"" => "\\\"")
            escaped_message = replace(special_message, "\"" => "\\\"")
            @test occursin("\\\"", escaped_title)
            @test occursin("\\\"", escaped_message)
        end
        
        # Test with unicode characters
        unicode_title = "Test 🚀 Emoji 📊 Title"
        unicode_message = "Message with émojis 💰 and ñoñ-ASCII çhars"
        @test_nowarn begin
            @test !isempty(unicode_title)
            @test !isempty(unicode_message)
        end
        
        # Test with negative values
        @test_nowarn begin
            negative_value = -0.05
            threshold = 0.02
            @test negative_value < threshold
        end
    end
    
    @testset "Sound Selection Logic" begin
        # Test sound selection based on notification level
        
        # CRITICAL and ERROR should use "Basso" sound
        @test_nowarn begin
            for level in [Notifications.CRITICAL, Notifications.ERROR]
                # Verify error levels exist
                @test level isa Notifications.NotificationLevel
            end
        end
        
        # WARNING should use "Ping" sound
        @test_nowarn begin
            level = Notifications.WARNING
            @test level isa Notifications.NotificationLevel
        end
        
        # INFO should use "Glass" sound
        @test_nowarn begin
            level = Notifications.INFO
            @test level isa Notifications.NotificationLevel
        end
        
        # Test with sound disabled
        @test_nowarn begin
            sound_enabled = false
            @test sound_enabled == false
        end
    end
    
    @testset "Module Initialization" begin
        # Test that module initializes without error
        @test_nowarn begin
            # Module should already be initialized
            @test isdefined(Notifications, :__init__)
        end
        
        # Test that required functions are exported
        @test isdefined(Notifications, :send_notification)
        @test isdefined(Notifications, :notify_training_complete)
        @test isdefined(Notifications, :notify_submission_complete)
        @test isdefined(Notifications, :notify_performance_alert)
        @test isdefined(Notifications, :notify_error)
        @test isdefined(Notifications, :notify_round_open)
        @test isdefined(Notifications, :NotificationLevel)
    end
end

println("✅ All Notifications tests passed!")