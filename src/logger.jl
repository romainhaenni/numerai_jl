module Logger

using Logging
using LoggingExtras
using Dates
using Term

export init_logger, @log_debug, @log_info, @log_warn, @log_error, @log_critical
export log_model_performance, log_api_call, log_submission, log_training_progress
export set_log_level, get_logger, close_logger

mutable struct NumeraiLogger
    logger::AbstractLogger
    log_file::String
    log_level::LogLevel
    file_handle::Union{IO, Nothing}
    
    function NumeraiLogger(logger::AbstractLogger, log_file::String, log_level::LogLevel, file_handle::Union{IO, Nothing})
        instance = new(logger, log_file, log_level, file_handle)
        # Add finalizer to ensure cleanup when garbage collected
        if !isnothing(file_handle)
            finalizer(instance) do x
                if !isnothing(x.file_handle) && isopen(x.file_handle)
                    try
                        close(x.file_handle)
                    catch
                        # Silently ignore errors during finalization
                    end
                end
            end
        end
        return instance
    end
end

const GLOBAL_LOGGER = Ref{NumeraiLogger}()

const LOG_COLORS = Dict(
    Logging.Debug => :blue,
    Logging.Info => :green,
    Logging.Warn => :yellow,
    Logging.Error => :red
)

function format_log_message(level, message, _module, group, id, file, line; kwargs...)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS.sss")
    level_str = uppercase(string(level))
    color = get(LOG_COLORS, level, :default)
    
    formatted_msg = if !isempty(kwargs)
        pairs = [string(k, "=", v) for (k, v) in kwargs]
        "$message | " * join(pairs, ", ")
    else
        message
    end
    
    return "[$timestamp] [$level_str] $formatted_msg"
end

function init_logger(; 
    log_file::String = "logs/numerai_$(Dates.format(now(), "yyyymmdd_HHMMSS")).log",
    console_level::LogLevel = Logging.Info,
    file_level::LogLevel = Logging.Debug,
    append::Bool = false
)
    # Create logs directory if it doesn't exist
    log_dir = dirname(log_file)
    if !isdir(log_dir) && !isempty(log_dir)
        mkpath(log_dir)
    end
    
    # Create file logger with proper handle management
    file_handle = if append && isfile(log_file)
        open(log_file, "a")
    else
        open(log_file, "w")
    end
    file_logger = SimpleLogger(file_handle, file_level)
    
    # Create console logger with formatting
    console_logger = ConsoleLogger(stdout, console_level)
    
    # Combine loggers
    combined_logger = TeeLogger(console_logger, file_logger)
    
    # Close any existing logger before creating new one
    if isassigned(GLOBAL_LOGGER) && !isnothing(GLOBAL_LOGGER[].file_handle)
        close(GLOBAL_LOGGER[].file_handle)
    end
    
    # Store global logger
    GLOBAL_LOGGER[] = NumeraiLogger(combined_logger, log_file, min(console_level, file_level), file_handle)
    
    # Set as global logger
    global_logger(combined_logger)
    
    @info "Logging initialized" log_file=log_file console_level=console_level file_level=file_level
    
    return combined_logger
end

function set_log_level(level::LogLevel)
    if !isassigned(GLOBAL_LOGGER)
        init_logger()
    end
    GLOBAL_LOGGER[].log_level = level
end

function get_logger()
    if !isassigned(GLOBAL_LOGGER)
        init_logger()
    end
    return GLOBAL_LOGGER[].logger
end

function close_logger()
    """
    Properly close the logger and release file handles to prevent resource leaks.
    Should be called when the logger is no longer needed.
    """
    if isassigned(GLOBAL_LOGGER) && !isnothing(GLOBAL_LOGGER[].file_handle)
        try
            close(GLOBAL_LOGGER[].file_handle)
            GLOBAL_LOGGER[].file_handle = nothing
            @debug "Logger file handle closed successfully"
        catch e
            @warn "Error closing logger file handle" error=string(e)
        end
    end
end

# Convenience macros
macro log_debug(msg, kwargs...)
    quote
        @debug $(esc(msg)) $(map(esc, kwargs)...)
    end
end

macro log_info(msg, kwargs...)
    quote
        @info $(esc(msg)) $(map(esc, kwargs)...)
    end
end

macro log_warn(msg, kwargs...)
    quote
        @warn $(esc(msg)) $(map(esc, kwargs)...)
    end
end

macro log_error(msg, kwargs...)
    quote
        @error $(esc(msg)) $(map(esc, kwargs)...)
    end
end

macro log_critical(msg, kwargs...)
    quote
        @error "[CRITICAL] " * $(esc(msg)) $(map(esc, kwargs)...)
    end
end

# Specialized logging functions for tournament operations

function log_model_performance(model_name::String, metrics::Dict)
    @info "Model performance update" model=model_name corr=get(metrics, :corr, NaN) mmc=get(metrics, :mmc, NaN) tc=get(metrics, :tc, NaN) sharpe=get(metrics, :sharpe, NaN)
end

function log_api_call(endpoint::String, method::String, status::Int; duration::Float64=0.0)
    if status >= 200 && status < 300
        @debug "API call successful" endpoint=endpoint method=method status=status duration_ms=round(duration*1000, digits=2)
    elseif status >= 400 && status < 500
        @warn "API client error" endpoint=endpoint method=method status=status duration_ms=round(duration*1000, digits=2)
    elseif status >= 500
        @error "API server error" endpoint=endpoint method=method status=status duration_ms=round(duration*1000, digits=2)
    else
        @info "API call completed" endpoint=endpoint method=method status=status duration_ms=round(duration*1000, digits=2)
    end
end

function log_submission(model_name::String, round::Int, success::Bool; error_msg::String="")
    if success
        @info "Submission successful" model=model_name round=round
    else
        @error "Submission failed" model=model_name round=round error=error_msg
    end
end

function log_training_progress(model_name::String, epoch::Int, total_epochs::Int; 
                              metrics::Dict=Dict(), eta_seconds::Float64=0.0)
    progress_pct = round(100 * epoch / total_epochs, digits=1)
    eta_str = if eta_seconds > 0
        mins, secs = divrem(Int(round(eta_seconds)), 60)
        "$(mins)m $(secs)s"
    else
        "unknown"
    end
    
    @info "Training progress" model=model_name epoch=epoch total=total_epochs progress_pct=progress_pct eta=eta_str metrics...
end

# Log rotation functionality
function rotate_logs(; max_size_mb::Float64=100.0, max_files::Int=10)
    if !isassigned(GLOBAL_LOGGER)
        return
    end
    
    log_file = GLOBAL_LOGGER[].log_file
    if !isfile(log_file)
        return
    end
    
    file_size_mb = filesize(log_file) / (1024 * 1024)
    if file_size_mb > max_size_mb
        # Close current log file properly
        if !isnothing(GLOBAL_LOGGER[].file_handle)
            close(GLOBAL_LOGGER[].file_handle)
        end
        
        # Rotate files
        base_name = splitext(log_file)[1]
        ext = splitext(log_file)[2]
        
        # Remove oldest file if at max
        oldest_file = "$(base_name).$(max_files)$(ext)"
        if isfile(oldest_file)
            rm(oldest_file)
        end
        
        # Shift existing files
        for i in (max_files-1):-1:1
            old_file = "$(base_name).$(i)$(ext)"
            new_file = "$(base_name).$(i+1)$(ext)"
            if isfile(old_file)
                mv(old_file, new_file)
            end
        end
        
        # Move current to .1
        mv(log_file, "$(base_name).1$(ext)")
        
        # Reinitialize logger
        init_logger(log_file=log_file, append=false)
        @info "Log rotation completed" old_size_mb=round(file_size_mb, digits=2)
    end
end

end # module