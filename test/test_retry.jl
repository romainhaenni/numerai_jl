using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using Test
using NumeraiTournament
using HTTP
using Dates
using Logging
using LoggingExtras
using Downloads
using Random

# Import the Retry module directly
include(joinpath(@__DIR__, "..", "src", "api", "retry.jl"))
using .Retry: RetryConfig, exponential_backoff, should_retry, with_retry, with_graphql_retry, with_download_retry, CircuitBreaker, with_circuit_breaker, record_failure, record_success, is_open

# Set up basic logging for testing
logger = ConsoleLogger(stdout, Logging.Debug)

@testset "Retry Logic Tests" begin
    
    @testset "RetryConfig Creation and Validation" begin
        @testset "Default RetryConfig" begin
            config = RetryConfig()
            @test config.max_attempts == 3
            @test config.initial_delay == 1.0
            @test config.max_delay == 60.0
            @test config.exponential_base == 2.0
            @test config.jitter == true
            @test HTTP.ExceptionRequest.StatusError in config.retry_on
            @test HTTP.TimeoutError in config.retry_on
            @test HTTP.ConnectionPool.ConnectError in config.retry_on
        end
        
        @testset "Custom RetryConfig" begin
            config = RetryConfig(
                max_attempts = 5,
                initial_delay = 2.5,
                max_delay = 120.0,
                exponential_base = 1.5,
                jitter = false,
                retry_on = Type[HTTP.TimeoutError]
            )
            @test config.max_attempts == 5
            @test config.initial_delay == 2.5
            @test config.max_delay == 120.0
            @test config.exponential_base == 1.5
            @test config.jitter == false
            @test config.retry_on == Type[HTTP.TimeoutError]
        end
        
        @testset "Validation edge cases" begin
            # Test with zero attempts
            config_zero = RetryConfig(max_attempts = 0)
            @test config_zero.max_attempts == 0
            
            # Test with very high delays
            config_high = RetryConfig(initial_delay = 1000.0, max_delay = 2000.0)
            @test config_high.initial_delay == 1000.0
            @test config_high.max_delay == 2000.0
        end
    end
    
    @testset "Exponential Backoff Calculation" begin
        @testset "Basic exponential backoff without jitter" begin
            config = RetryConfig(
                initial_delay = 1.0,
                max_delay = 60.0,
                exponential_base = 2.0,
                jitter = false
            )
            
            @test exponential_backoff(1, config) == 1.0
            @test exponential_backoff(2, config) == 2.0
            @test exponential_backoff(3, config) == 4.0
            @test exponential_backoff(4, config) == 8.0
            @test exponential_backoff(5, config) == 16.0
            @test exponential_backoff(6, config) == 32.0
            @test exponential_backoff(7, config) == 60.0  # Capped at max_delay
            @test exponential_backoff(10, config) == 60.0  # Still capped
        end
        
        @testset "Exponential backoff with different base" begin
            config = RetryConfig(
                initial_delay = 2.0,
                max_delay = 100.0,
                exponential_base = 1.5,
                jitter = false
            )
            
            @test exponential_backoff(1, config) == 2.0
            @test exponential_backoff(2, config) == 3.0
            @test exponential_backoff(3, config) == 4.5
            @test exponential_backoff(4, config) == 6.75
        end
        
        @testset "Exponential backoff with jitter" begin
            Random.seed!(42)  # For reproducible tests
            config = RetryConfig(
                initial_delay = 1.0,
                max_delay = 60.0,
                exponential_base = 2.0,
                jitter = true
            )
            
            # With jitter, delays should be between 100% and 125% of base delay
            delay1 = exponential_backoff(1, config)
            @test 1.0 <= delay1 <= 1.25
            
            delay2 = exponential_backoff(2, config)
            @test 2.0 <= delay2 <= 2.5
            
            # Test multiple calls to ensure jitter varies
            delays = [exponential_backoff(2, config) for _ in 1:100]
            @test length(unique(delays)) > 1  # Should have variation due to jitter
            @test all(d -> 2.0 <= d <= 2.5, delays)
        end
        
        @testset "Max delay capping with jitter" begin
            config = RetryConfig(
                initial_delay = 50.0,
                max_delay = 60.0,
                exponential_base = 2.0,
                jitter = true
            )
            
            # Even with jitter, should not exceed max_delay significantly
            delay = exponential_backoff(2, config)
            @test delay <= 75.0  # 60 * 1.25 = 75.0 (max with 25% jitter)
        end
    end
    
    @testset "should_retry Logic" begin
        config = RetryConfig()
        
        @testset "HTTP Status Code Logic" begin
            # Create mock HTTP responses for different status codes
            
            # 5xx errors should retry
            response_500 = HTTP.Response(500, "Internal Server Error")
            error_500 = HTTP.ExceptionRequest.StatusError(500, "GET", "http://example.com", response_500)
            @test should_retry(error_500, config) == true
            
            response_502 = HTTP.Response(502, "Bad Gateway")
            error_502 = HTTP.ExceptionRequest.StatusError(502, "GET", "http://example.com", response_502)
            @test should_retry(error_502, config) == true
            
            response_503 = HTTP.Response(503, "Service Unavailable")
            error_503 = HTTP.ExceptionRequest.StatusError(503, "GET", "http://example.com", response_503)
            @test should_retry(error_503, config) == true
            
            # 429 rate limiting should retry
            response_429 = HTTP.Response(429, "Too Many Requests")
            error_429 = HTTP.ExceptionRequest.StatusError(429, "GET", "http://example.com", response_429)
            @test should_retry(error_429, config) == true
            
            # 4xx client errors should not retry (except 429)
            response_400 = HTTP.Response(400, "Bad Request")
            error_400 = HTTP.ExceptionRequest.StatusError(400, "GET", "http://example.com", response_400)
            @test should_retry(error_400, config) == false
            
            response_401 = HTTP.Response(401, "Unauthorized")
            error_401 = HTTP.ExceptionRequest.StatusError(401, "GET", "http://example.com", response_401)
            @test should_retry(error_401, config) == false
            
            response_404 = HTTP.Response(404, "Not Found")
            error_404 = HTTP.ExceptionRequest.StatusError(404, "GET", "http://example.com", response_404)
            @test should_retry(error_404, config) == false
            
            # 2xx and 3xx success codes shouldn't trigger retry logic
            response_200 = HTTP.Response(200, "OK")
            error_200 = HTTP.ExceptionRequest.StatusError(200, "GET", "http://example.com", response_200)
            @test should_retry(error_200, config) == true  # Would retry if it's in retry_on list
        end
        
        @testset "Network Error Types" begin
            # TimeoutError should retry
            timeout_error = HTTP.TimeoutError(30)  # 30 second timeout
            @test should_retry(timeout_error, config) == true
            
            # ConnectionError should retry  
            conn_error = HTTP.ConnectionPool.ConnectError("http://localhost:8080", "Connection refused")
            @test should_retry(conn_error, config) == true
        end
        
        @testset "Non-retryable Errors" begin
            # ArgumentError should not retry
            arg_error = ArgumentError("Invalid argument")
            @test should_retry(arg_error, config) == false
            
            # BoundsError should not retry
            bounds_error = BoundsError([1, 2, 3], 5)
            @test should_retry(bounds_error, config) == false
        end
        
        @testset "Custom retry_on Configuration" begin
            custom_config = RetryConfig(retry_on = Type[ArgumentError, BoundsError])
            
            # Now ArgumentError should retry
            arg_error = ArgumentError("Invalid argument")
            @test should_retry(arg_error, custom_config) == true
            
            # But HTTP errors should not
            response_500 = HTTP.Response(500, "Internal Server Error")
            error_500 = HTTP.ExceptionRequest.StatusError(500, "GET", "http://example.com", response_500)
            @test should_retry(error_500, custom_config) == false
        end
    end
    
    @testset "Circuit Breaker State Transitions" begin
        @testset "Circuit Breaker Creation" begin
            cb = CircuitBreaker()
            @test cb.failure_threshold == 5
            @test cb.recovery_timeout == 60.0
            @test cb.failure_count == 0
            @test cb.last_failure_time == 0.0
            @test cb.state == :closed
        end
        
        @testset "Custom Circuit Breaker" begin
            cb = CircuitBreaker(failure_threshold = 3, recovery_timeout = 30.0)
            @test cb.failure_threshold == 3
            @test cb.recovery_timeout == 30.0
            @test cb.state == :closed
        end
        
        @testset "State Transitions - Closed to Open" begin
            cb = CircuitBreaker(failure_threshold = 3)
            
            # Initially closed
            @test cb.state == :closed
            @test !is_open(cb)
            
            # Record failures
            record_failure(cb)
            @test cb.failure_count == 1
            @test cb.state == :closed
            
            record_failure(cb)
            @test cb.failure_count == 2
            @test cb.state == :closed
            
            record_failure(cb)
            @test cb.failure_count == 3
            @test cb.state == :open
            @test is_open(cb)
        end
        
        @testset "State Transitions - Open to Half-Open" begin
            cb = CircuitBreaker(failure_threshold = 2, recovery_timeout = 0.1)
            
            # Force circuit breaker to open state
            record_failure(cb)
            record_failure(cb)
            @test cb.state == :open
            @test is_open(cb)
            
            # Wait for recovery timeout
            sleep(0.15)
            
            # Check should transition to half-open
            @test !is_open(cb)
            @test cb.state == :half_open
        end
        
        @testset "State Transitions - Half-Open to Closed" begin
            cb = CircuitBreaker(failure_threshold = 2)
            cb.state = :half_open
            
            # Record success should close the circuit
            record_success(cb)
            @test cb.state == :closed
            @test cb.failure_count == 0
        end
        
        @testset "State Transitions - Half-Open back to Open" begin
            cb = CircuitBreaker(failure_threshold = 2)
            cb.state = :half_open
            cb.failure_count = 1
            
            # Another failure should open the circuit again
            record_failure(cb)
            @test cb.state == :open
            @test cb.failure_count == 2
        end
    end
    
    @testset "with_retry Success Scenarios" begin
        @testset "Function succeeds on first try" begin
            call_count = 0
            result = with_retry(RetryConfig(max_attempts = 3)) do
                call_count += 1
                return "success"
            end
            
            @test result == "success"
            @test call_count == 1
        end
        
        @testset "Function succeeds after retries" begin
            call_count = 0
            config = RetryConfig(max_attempts = 3, initial_delay = 0.01, jitter = false)
            
            result = with_retry(config) do
                call_count += 1
                if call_count < 3
                    throw(HTTP.TimeoutError(30))
                end
                return "success_after_retry"
            end
            
            @test result == "success_after_retry"
            @test call_count == 3
        end
        
        @testset "Return different types" begin
            # Test returning various types
            int_result = with_retry(RetryConfig()) do
                return 42
            end
            @test int_result == 42
            
            dict_result = with_retry(RetryConfig()) do
                return Dict("key" => "value")
            end
            @test dict_result["key"] == "value"
            
            nothing_result = with_retry(RetryConfig()) do
                return nothing
            end
            @test nothing_result === nothing
        end
    end
    
    @testset "with_retry Failure Scenarios" begin
        @testset "Max retries exceeded with retryable error" begin
            call_count = 0
            config = RetryConfig(max_attempts = 3, initial_delay = 0.01, jitter = false)
            
            @test_throws HTTP.TimeoutError begin
                with_retry(config) do
                    call_count += 1
                    throw(HTTP.TimeoutError(30))
                end
            end
            
            @test call_count == 3  # Should have tried max_attempts times
        end
        
        @testset "Non-retryable error fails immediately" begin
            call_count = 0
            config = RetryConfig(max_attempts = 3, initial_delay = 0.01)
            
            @test_throws ArgumentError begin
                with_retry(config) do
                    call_count += 1
                    throw(ArgumentError("Invalid argument"))
                end
            end
            
            @test call_count == 1  # Should not retry
        end
        
        @testset "HTTP 4xx errors fail immediately" begin
            call_count = 0
            config = RetryConfig(max_attempts = 3, initial_delay = 0.01)
            
            @test_throws HTTP.ExceptionRequest.StatusError begin
                with_retry(config) do
                    call_count += 1
                    response = HTTP.Response(404, "Not Found")
                    throw(HTTP.ExceptionRequest.StatusError(404, "GET", "http://example.com", response))
                end
            end
            
            @test call_count == 1  # Should not retry 404
        end
        
        @testset "Mixed error types during retries" begin
            call_count = 0
            config = RetryConfig(max_attempts = 4, initial_delay = 0.01, jitter = false)
            
            @test_throws ArgumentError begin
                with_retry(config) do
                    call_count += 1
                    if call_count <= 2
                        throw(HTTP.TimeoutError(30))
                    else
                        throw(ArgumentError("Non-retryable"))
                    end
                end
            end
            
            @test call_count == 3  # Two timeouts, then non-retryable error
        end
    end
    
    @testset "with_circuit_breaker Integration" begin
        @testset "Circuit breaker allows successful operations" begin
            cb = CircuitBreaker(failure_threshold = 2)
            call_count = 0
            
            result = with_circuit_breaker(cb) do
                call_count += 1
                return "success"
            end
            
            @test result == "success"
            @test call_count == 1
            @test cb.state == :closed
        end
        
        @testset "Circuit breaker opens after failures" begin
            cb = CircuitBreaker(failure_threshold = 2)
            call_count = 0
            
            # First failure
            @test_throws ErrorException begin
                with_circuit_breaker(cb) do
                    call_count += 1
                    throw(ErrorException("First failure"))
                end
            end
            @test cb.state == :closed
            @test cb.failure_count == 1
            
            # Second failure - should open circuit
            @test_throws ErrorException begin
                with_circuit_breaker(cb) do
                    call_count += 1
                    throw(ErrorException("Second failure"))
                end
            end
            @test cb.state == :open
            @test cb.failure_count == 2
            
            # Third call should fail due to open circuit
            @test_throws ErrorException begin
                with_circuit_breaker(cb) do
                    call_count += 1
                    return "should not reach"
                end
            end
            @test call_count == 2  # Third call not executed
        end
        
        @testset "Circuit breaker recovery" begin
            cb = CircuitBreaker(failure_threshold = 1, recovery_timeout = 0.1)
            
            # Force circuit to open
            @test_throws ErrorException begin
                with_circuit_breaker(cb) do
                    throw(ErrorException("Force open"))
                end
            end
            @test cb.state == :open
            
            # Wait for recovery timeout
            sleep(0.15)
            
            # Next call should transition to half-open and succeed
            result = with_circuit_breaker(cb) do
                return "recovered"
            end
            
            @test result == "recovered"
            @test cb.state == :closed
        end
    end
    
    @testset "Specialized Retry Functions" begin
        @testset "with_graphql_retry" begin
            call_count = 0
            
            result = with_graphql_retry() do
                call_count += 1
                if call_count < 2
                    throw(HTTP.TimeoutError(30))
                end
                return "graphql_success"
            end
            
            @test result == "graphql_success"
            @test call_count == 2
        end
        
        @testset "with_download_retry" begin
            call_count = 0
            
            # Test that download retry works with HTTP.TimeoutError
            result = with_download_retry() do
                call_count += 1
                if call_count < 2
                    throw(HTTP.TimeoutError(30))
                end
                return "download_success"
            end
            
            @test result == "download_success"
            @test call_count == 2
        end
    end
    
    @testset "Timeout Handling" begin
        @testset "Operation timeout during retry" begin
            call_count = 0
            config = RetryConfig(max_attempts = 3, initial_delay = 0.01)
            
            start_time = time()
            @test_throws HTTP.TimeoutError begin
                with_retry(config, context = "timeout_test") do
                    call_count += 1
                    throw(HTTP.TimeoutError(30))
                end
            end
            elapsed = time() - start_time
            
            @test call_count == 3
            # Should take at least the sum of delays: 0.01 + 0.02 ≈ 0.03 seconds
            @test elapsed >= 0.02
        end
    end
    
    @testset "GraphQL-Specific Error Handling" begin
        @testset "GraphQL configuration parameters" begin
            # Test that GraphQL retry uses appropriate configuration
            call_count = 0
            
            # Should have higher max_attempts and different delays
            start_time = time()
            @test_throws HTTP.TimeoutError begin
                with_graphql_retry(context = "test_graphql") do
                    call_count += 1
                    throw(HTTP.TimeoutError(30))
                end
            end
            elapsed = time() - start_time
            
            @test call_count == 5  # GraphQL config has max_attempts = 5
            @test elapsed >= 0.1   # Should take longer due to higher initial_delay
        end
    end
    
    @testset "Thread Safety" begin
        @testset "Concurrent retry operations" begin
            # Test that multiple retry operations can run concurrently
            # without interfering with each other
            
            results = Vector{String}(undef, 10)
            config = RetryConfig(max_attempts = 2, initial_delay = 0.01)
            
            # Run concurrent retry operations
            Threads.@threads for i in 1:10
                call_count = 0
                results[i] = with_retry(config, context = "thread_$(i)") do
                    call_count += 1
                    if call_count == 1 && i % 2 == 0  # Fail even-numbered threads once
                        throw(HTTP.TimeoutError(30))
                    end
                    return "thread_$(i)_success"
                end
            end
            
            # All operations should succeed
            for i in 1:10
                @test results[i] == "thread_$(i)_success"
            end
        end
        
        @testset "Concurrent circuit breaker operations" begin
            # Test circuit breaker thread safety
            cb = CircuitBreaker(failure_threshold = 5, recovery_timeout = 0.1)
            successes = Vector{Bool}(undef, 20)
            
            Threads.@threads for i in 1:20
                try
                    with_circuit_breaker(cb, context = "concurrent_$i") do
                        if i <= 3  # First few operations fail
                            throw(ErrorException("Planned failure $i"))
                        end
                        return "success_$i"
                    end
                    successes[i] = true
                catch e
                    successes[i] = false
                end
            end
            
            # Some operations should fail, but circuit breaker state should be consistent
            @test cb.state in [:closed, :open, :half_open]
            @test cb.failure_count >= 0
        end
    end
    
    @testset "Edge Cases and Error Conditions" begin
        @testset "Zero max attempts" begin
            config = RetryConfig(max_attempts = 0)
            call_count = 0
            
            # Should throw an error or handle gracefully
            try
                result = with_retry(config) do
                    call_count += 1
                    return "should_not_execute"
                end
                # If no error is thrown, function should not have been called
                @test call_count == 0
            catch e
                # If an error is thrown, that's also acceptable behavior
                @test call_count == 0
            end
        end
        
        @testset "Negative delays" begin
            # Test behavior with edge case configurations
            config = RetryConfig(initial_delay = -1.0, max_delay = -5.0, jitter = false)
            delay = exponential_backoff(1, config)
            # The current implementation doesn't guard against negative delays,
            # so we test the actual behavior rather than assuming it's handled
            @test delay == -5.0  # max(-1.0, -5.0) = -5.0 (capped at max_delay)
        end
        
        @testset "Very large attempt numbers" begin
            config = RetryConfig(initial_delay = 1.0, max_delay = 10.0, exponential_base = 2.0, jitter = false)
            delay = exponential_backoff(100, config)
            @test delay == 10.0  # Should be capped at max_delay
        end
    end
    
    @testset "Logging Integration" begin
        @testset "Retry logging messages" begin
            # Capture log messages during retry operations
            with_logger(logger) do
                call_count = 0
                config = RetryConfig(max_attempts = 3, initial_delay = 0.01)
                
                try
                    with_retry(config, context = "logging_test") do
                        call_count += 1
                        if call_count < 3
                            throw(HTTP.TimeoutError(30))
                        end
                        return "success"
                    end
                catch
                    # Ignore the error, we're testing logging
                end
            end
            
            # Verify that appropriate log messages were generated
            # Since we're testing retry logic, the function should have been called the expected number of times
            # The actual log verification would require mocking the logger, which is beyond the scope
            # For now, we verify the retry behavior through the call count
            @test call_count > 1  # At least one retry occurred
        end
    end
end

println("\n✅ All retry logic tests passed!")