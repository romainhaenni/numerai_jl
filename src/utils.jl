"""
Utility module for the NumeraiTournament package.
"""
module Utils

using Dates
using TimeZones
using Printf

export utc_now, utc_now_datetime, is_weekend_round,
       calculate_submission_window_end, is_submission_window_open,
       get_submission_window_info, get_disk_space_info

"""
    utc_now() -> ZonedDateTime

Returns the current time in UTC timezone.
This should be used instead of `now()` to ensure all scheduling 
and timing operations are consistent across different local timezones.
"""
function utc_now()
    return now(tz"UTC")
end

"""
    utc_now_datetime() -> DateTime

Returns the current UTC time as a DateTime object (without timezone info).
Use this when you need a DateTime object instead of ZonedDateTime.
"""
function utc_now_datetime()
    return DateTime(utc_now())
end

"""
    is_weekend_round(open_time::DateTime) -> Bool

Determines if a round is a weekend round based on its opening time.
Weekend rounds open on Saturday at 18:00 UTC.
"""
function is_weekend_round(open_time::DateTime)
    return dayofweek(open_time) == 6  # Saturday = 6
end

"""
    calculate_submission_window_end(open_time::DateTime) -> DateTime

Calculates when the submission window closes based on the round type.
- Weekend rounds: 60 hours after opening (Saturday 18:00 UTC → Monday 06:00 UTC)
- Daily rounds: 30 hours after opening (Tuesday-Friday rounds)
"""
function calculate_submission_window_end(open_time::DateTime)
    if is_weekend_round(open_time)
        # Weekend round: 60 hours (2.5 days)
        return open_time + Hour(60)
    else
        # Daily round: 30 hours
        return open_time + Hour(30)
    end
end

"""
    is_submission_window_open(round_open_time::DateTime, current_time::DateTime = utc_now_datetime()) -> Bool

Checks if the submission window is still open for a given round.
Returns true if submissions are still accepted, false otherwise.
"""
function is_submission_window_open(round_open_time::DateTime, current_time::DateTime = utc_now_datetime())
    window_end = calculate_submission_window_end(round_open_time)
    return current_time <= window_end
end

"""
    get_submission_window_info(round_open_time::DateTime, current_time::DateTime = utc_now_datetime()) -> NamedTuple

Returns detailed information about the submission window for a round.
Returns a named tuple with:
- window_end: When the submission window closes
- is_open: Whether submissions are currently accepted
- time_remaining: Hours remaining until window closes (if open), or hours since closed (if closed)
- round_type: "weekend" or "daily"
"""
function get_submission_window_info(round_open_time::DateTime, current_time::DateTime = utc_now_datetime())
    window_end = calculate_submission_window_end(round_open_time)
    is_open = current_time <= window_end
    time_diff = (window_end - current_time).value / (1000 * 60 * 60)  # Convert to hours
    round_type = is_weekend_round(round_open_time) ? "weekend" : "daily"
    
    return (
        window_end = window_end,
        is_open = is_open,
        time_remaining = time_diff,
        round_type = round_type
    )
end

"""
    get_disk_space_info(path::String = pwd()) -> NamedTuple

Returns disk space information for the given path.
Returns a named tuple with:
- free_gb: Free space in GB
- total_gb: Total space in GB
- used_gb: Used space in GB
- used_pct: Percentage of disk used
"""
function get_disk_space_info(path::String = pwd())
    try
        # Use df command to get disk space info on Unix systems
        if Sys.isunix()
            # Run df command with -k flag for KB output
            cmd = `df -k $path`
            output = read(cmd, String)
            lines = split(output, '\n')

            # Parse the output (second line has the data)
            if length(lines) >= 2
                # The data is usually on the second line
                # Format: filesystem 1024-blocks used available capacity ...
                data_line = lines[2]

                # On some systems, filesystem name might be on a separate line
                if !occursin(r"\d+\s+\d+\s+\d+", data_line) && length(lines) >= 3
                    data_line = lines[3]
                end

                # Split by whitespace and extract numeric columns
                parts = split(data_line)

                # Find the numeric columns (blocks, used, available)
                # They should appear consecutively after the filesystem name
                numeric_indices = Int[]
                for (i, part) in enumerate(parts)
                    # Match pure numeric values (including those starting with -)
                    if occursin(r"^-?\d+$", part)
                        push!(numeric_indices, i)
                    end
                end

                # We need at least 3 numeric values (blocks, used, available)
                if length(numeric_indices) >= 3
                    # The first 3 numeric values are blocks, used, available
                    total_kb = parse(Float64, parts[numeric_indices[1]])
                    used_kb = parse(Float64, parts[numeric_indices[2]])
                    avail_kb = parse(Float64, parts[numeric_indices[3]])

                    total_gb = total_kb / (1024 * 1024)
                    used_gb = used_kb / (1024 * 1024)
                    free_gb = avail_kb / (1024 * 1024)
                    used_pct = total_gb > 0 ? (used_gb / total_gb * 100) : 0.0

                    return (
                        free_gb = free_gb,
                        total_gb = total_gb,
                        used_gb = used_gb,
                        used_pct = used_pct
                    )
                end
            end
        end
    catch e
        # If anything fails, return zeros
        @debug "Failed to get disk space info" error=e
    end

    # Return default values if we couldn't get disk info
    return (
        free_gb = 0.0,
        total_gb = 0.0,
        used_gb = 0.0,
        used_pct = 0.0
    )
end

end # module Utils