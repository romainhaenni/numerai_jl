module Retry

using HTTP
using Logging
using LoggingExtras
using Downloads

export with_retry, RetryConfig, exponential_backoff

struct RetryConfig
    max_attempts::Int
    initial_delay::Float64  # seconds
    max_delay::Float64      # seconds
    exponential_base::Float64
    jitter::Bool
    retry_on::Vector{Type}
end

function RetryConfig(;
    max_attempts::Int = 3,
    initial_delay::Float64 = 1.0,
    max_delay::Float64 = 60.0,
    exponential_base::Float64 = 2.0,
    jitter::Bool = true,
    retry_on::Vector{Type} = Type[HTTP.ExceptionRequest.StatusError, HTTP.TimeoutError, HTTP.ConnectionPool.ConnectError]
)
    RetryConfig(max_attempts, initial_delay, max_delay, exponential_base, jitter, retry_on)
end

function exponential_backoff(attempt::Int, config::RetryConfig)
    delay = min(config.initial_delay * config.exponential_base^(attempt - 1), config.max_delay)
    if config.jitter
        # Add random jitter between 0% and 25% of the delay
        delay *= (1.0 + rand() * 0.25)
    end
    return delay
end

function should_retry(error, config::RetryConfig)
    # Check if error type is in retry list
    for retry_type in config.retry_on
        if isa(error, retry_type)
            # Special handling for HTTP status errors
            if isa(error, HTTP.ExceptionRequest.StatusError)
                status = error.response.status
                # Retry on server errors (5xx) and rate limiting (429)
                if status >= 500 || status == 429
                    return true
                end
                # Don't retry client errors (4xx) except rate limiting
                if status >= 400 && status < 500 && status != 429
                    return false
                end
            end
            return true
        end
    end
    return false
end

function with_retry(f::Function, config::RetryConfig = RetryConfig(); context::String = "operation")
    last_error = nothing
    
    for attempt in 1:config.max_attempts
        try
            @debug "Attempting $context" attempt=attempt max_attempts=config.max_attempts
            result = f()
            if attempt > 1
                @info "Successfully completed after retry" context=context attempts=attempt
            end
            return result
        catch e
            last_error = e
            
            if !should_retry(e, config)
                @error "Non-retryable error encountered" context=context error=string(e)
                rethrow(e)
            end
            
            if attempt == config.max_attempts
                @error "Max retry attempts exceeded" context=context attempts=attempt error=string(e)
                rethrow(e)
            end
            
            delay = exponential_backoff(attempt, config)
            @warn "Retrying after error" context=context attempt=attempt delay_seconds=round(delay, digits=2) error=string(e)
            sleep(delay)
        end
    end
    
    # This should never be reached, but just in case
    if last_error !== nothing
        rethrow(last_error)
    end
end

# Convenience function for GraphQL retries with specific configuration
function with_graphql_retry(f::Function; context::String = "GraphQL query")
    config = RetryConfig(
        max_attempts = 5,
        initial_delay = 2.0,
        max_delay = 30.0,
        exponential_base = 1.5,
        jitter = true
    )
    return with_retry(f, config; context = context)
end

# Convenience function for file download retries
function with_download_retry(f::Function; context::String = "file download")
    config = RetryConfig(
        max_attempts = 3,
        initial_delay = 5.0,
        max_delay = 60.0,
        exponential_base = 2.0,
        jitter = true,
        retry_on = Type[Downloads.RequestError, HTTP.TimeoutError, InterruptException]
    )
    return with_retry(f, config; context = context)
end

# Circuit breaker pattern for API calls
mutable struct CircuitBreaker
    failure_threshold::Int
    recovery_timeout::Float64  # seconds
    failure_count::Int
    last_failure_time::Float64
    state::Symbol  # :closed, :open, :half_open
end

function CircuitBreaker(;
    failure_threshold::Int = 5,
    recovery_timeout::Float64 = 60.0
)
    CircuitBreaker(failure_threshold, recovery_timeout, 0, 0.0, :closed)
end

function is_open(cb::CircuitBreaker)
    if cb.state == :open
        # Check if we should transition to half-open
        if time() - cb.last_failure_time > cb.recovery_timeout
            cb.state = :half_open
            @info "Circuit breaker transitioning to half-open"
            return false
        end
        return true
    end
    return false
end

function record_success(cb::CircuitBreaker)
    if cb.state == :half_open
        cb.state = :closed
        cb.failure_count = 0
        @info "Circuit breaker closed after successful recovery"
    end
end

function record_failure(cb::CircuitBreaker)
    cb.failure_count += 1
    cb.last_failure_time = time()
    
    if cb.failure_count >= cb.failure_threshold
        cb.state = :open
        @warn "Circuit breaker opened" failures=cb.failure_count threshold=cb.failure_threshold
    end
end

function with_circuit_breaker(f::Function, cb::CircuitBreaker; context::String = "operation")
    if is_open(cb)
        error("Circuit breaker is open for $context. Service unavailable.")
    end
    
    try
        result = f()
        record_success(cb)
        return result
    catch e
        record_failure(cb)
        rethrow(e)
    end
end

export CircuitBreaker, with_circuit_breaker, with_graphql_retry, with_download_retry

end # module