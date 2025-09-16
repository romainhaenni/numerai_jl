"""
Utility module for the NumeraiTournament package.
"""
module Utils

using Dates
using TimeZones
using Printf

export utc_now, utc_now_datetime, is_weekend_round,
       calculate_submission_window_end, is_submission_window_open,
       get_submission_window_info, get_disk_space_info,
       get_cpu_usage, get_memory_info

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
    @debug "Getting disk space info for path: $path"
    try
        # Use df command to get disk space info on Unix systems
        if Sys.isunix()
            # Run df command with -k flag for KB output
            cmd = `df -k $path`
            output = read(cmd, String)
            @debug "df command output: $output"
            lines = split(output, '\n')

            # Parse the output - handle different df output formats
            if length(lines) >= 2
                # Parse the data line (skip header)
                # macOS format: Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted
                # Linux format: Filesystem 1K-blocks Used Available Use% Mounted
                data_line = strip(lines[2])
                parts = split(data_line)

                # The 2nd, 3rd, and 4th columns should be: total, used, available (in KB)
                if length(parts) >= 4
                    try
                        # Direct parsing of columns 2, 3, 4
                        total_kb = parse(Float64, parts[2])
                        used_kb = parse(Float64, parts[3])
                        avail_kb = parse(Float64, parts[4])

                        # Sanity check: values should be reasonable (> 1000 KB)
                        if total_kb > 1000 && used_kb >= 0 && avail_kb >= 0
                            # Convert from KB to GB
                            total_gb = total_kb / (1024 * 1024)
                            used_gb = used_kb / (1024 * 1024)
                            free_gb = avail_kb / (1024 * 1024)
                            used_pct = total_gb > 0 ? (used_gb / total_gb * 100) : 0.0

                            result = (
                                free_gb = free_gb,
                                total_gb = total_gb,
                                used_gb = used_gb,
                                used_pct = used_pct
                            )
                            @debug "Successfully parsed disk space info" result
                            return result
                        else
                            @debug "Disk values seem invalid" total=total_kb used=used_kb avail=avail_kb
                        end
                    catch e
                        @debug "Failed to parse df columns directly" error=e columns=parts[2:min(4,length(parts))]
                    end
                end

                # Fallback: search for numeric values if direct parsing failed
                numeric_vals = Float64[]
                for part in parts
                    if !occursin("%", part) && !occursin("/", part)
                        try
                            num = parse(Float64, part)
                            if num > 1000  # Must be KB values
                                push!(numeric_vals, num)
                            end
                        catch
                            continue
                        end
                    end
                end

                if length(numeric_vals) >= 3
                    total_gb = numeric_vals[1] / (1024 * 1024)
                    used_gb = numeric_vals[2] / (1024 * 1024)
                    free_gb = numeric_vals[3] / (1024 * 1024)
                    used_pct = total_gb > 0 ? (used_gb / total_gb * 100) : 0.0

                    return (
                        free_gb = free_gb,
                        total_gb = total_gb,
                        used_gb = used_gb,
                        used_pct = used_pct
                    )
                else
                    @debug "Could not find enough numeric values in df output" found=length(numeric_vals) parts=parts
                end
            end
        end
    catch e
        # If anything fails, log the error but don't warn repeatedly
        @debug "Failed to get disk space info" error=e path=path
    end

    # Return default values if we couldn't get disk info
    @debug "Returning default disk space values"
    return (
        free_gb = 0.0,
        total_gb = 0.0,
        used_gb = 0.0,
        used_pct = 0.0
    )
end

"""
    get_cpu_usage() -> Float64

Returns the current CPU usage percentage.
Uses system commands to get actual CPU utilization on Unix systems.
"""
function get_cpu_usage()
    try
        if Sys.isunix()
            # Use top command to get CPU usage on macOS/Unix
            if Sys.isapple()
                # macOS specific: use top with -l 1 for one sample
                cmd = `top -l 1 -n 0`
                output = read(cmd, String)

                # Look for CPU usage line: "CPU usage: x.x% user, y.y% sys, z.z% idle"
                for line in split(output, '\n')
                    if occursin("CPU usage", line)
                        # Extract idle percentage
                        idle_match = match(r"(\d+\.?\d*)% idle", line)
                        if !isnothing(idle_match)
                            idle_pct = parse(Float64, idle_match.captures[1])
                            return 100.0 - idle_pct
                        end

                        # Alternative: extract user and sys percentages
                        user_match = match(r"(\d+\.?\d*)% user", line)
                        sys_match = match(r"(\d+\.?\d*)% sys", line)
                        if !isnothing(user_match) && !isnothing(sys_match)
                            user_pct = parse(Float64, user_match.captures[1])
                            sys_pct = parse(Float64, sys_match.captures[1])
                            return user_pct + sys_pct
                        end
                    end
                end
            else
                # Linux: use /proc/stat for more reliable CPU usage
                if isfile("/proc/stat")
                    # Read two samples 100ms apart to calculate usage
                    function read_cpu_stats()
                        content = read("/proc/stat", String)
                        line = split(content, '\n')[1]  # First line has overall CPU stats
                        parts = split(line)
                        # Format: cpu user nice system idle iowait irq softirq steal guest guest_nice
                        return [parse(Int, x) for x in parts[2:end] if !isempty(x)]
                    end

                    stats1 = read_cpu_stats()
                    sleep(0.1)  # 100ms delay
                    stats2 = read_cpu_stats()

                    if length(stats1) >= 4 && length(stats2) >= 4
                        # Calculate differences
                        diff = stats2 .- stats1
                        total_diff = sum(diff)
                        idle_diff = diff[4]  # idle is 4th field

                        if total_diff > 0
                            cpu_usage = (1.0 - idle_diff / total_diff) * 100.0
                            return max(0.0, min(100.0, cpu_usage))
                        end
                    end
                end
            end
        end
    catch e
        @debug "Failed to get CPU usage" error=e
    end

    # Fallback: return a reasonable default
    return 0.0
end

"""
    get_memory_info() -> NamedTuple

Returns memory usage information.
Returns a named tuple with:
- used_gb: Used memory in GB
- total_gb: Total memory in GB
- available_gb: Available memory in GB
- used_pct: Percentage of memory used
"""
function get_memory_info()
    try
        if Sys.isunix()
            if Sys.isapple()
                # macOS: use vm_stat for memory information
                cmd = `vm_stat`
                output = read(cmd, String)

                # Parse vm_stat output
                page_size = 4096  # 4KB pages on macOS
                total_pages = 0
                free_pages = 0
                inactive_pages = 0
                wired_pages = 0
                active_pages = 0

                for line in split(output, '\n')
                    if occursin("Pages free:", line)
                        match_result = match(r"Pages free:\s+(\d+)", line)
                        if !isnothing(match_result)
                            free_pages = parse(Int, match_result.captures[1])
                        end
                    elseif occursin("Pages active:", line)
                        match_result = match(r"Pages active:\s+(\d+)", line)
                        if !isnothing(match_result)
                            active_pages = parse(Int, match_result.captures[1])
                        end
                    elseif occursin("Pages inactive:", line)
                        match_result = match(r"Pages inactive:\s+(\d+)", line)
                        if !isnothing(match_result)
                            inactive_pages = parse(Int, match_result.captures[1])
                        end
                    elseif occursin("Pages wired down:", line)
                        match_result = match(r"Pages wired down:\s+(\d+)", line)
                        if !isnothing(match_result)
                            wired_pages = parse(Int, match_result.captures[1])
                        end
                    end
                end

                # Calculate memory usage
                used_pages = active_pages + wired_pages
                total_pages = free_pages + active_pages + inactive_pages + wired_pages
                available_pages = free_pages + inactive_pages

                if total_pages > 0
                    total_gb = (total_pages * page_size) / (1024^3)
                    used_gb = (used_pages * page_size) / (1024^3)
                    available_gb = (available_pages * page_size) / (1024^3)
                    used_pct = (used_gb / total_gb) * 100.0

                    return (
                        used_gb = used_gb,
                        total_gb = total_gb,
                        available_gb = available_gb,
                        used_pct = used_pct
                    )
                end
            else
                # Linux: use /proc/meminfo
                if isfile("/proc/meminfo")
                    content = read("/proc/meminfo", String)

                    mem_total_kb = 0
                    mem_available_kb = 0

                    for line in split(content, '\n')
                        if startswith(line, "MemTotal:")
                            match_result = match(r"MemTotal:\s+(\d+)", line)
                            if !isnothing(match_result)
                                mem_total_kb = parse(Int, match_result.captures[1])
                            end
                        elseif startswith(line, "MemAvailable:")
                            match_result = match(r"MemAvailable:\s+(\d+)", line)
                            if !isnothing(match_result)
                                mem_available_kb = parse(Int, match_result.captures[1])
                            end
                        end
                    end

                    if mem_total_kb > 0
                        total_gb = mem_total_kb / (1024^2)
                        available_gb = mem_available_kb / (1024^2)
                        used_gb = total_gb - available_gb
                        used_pct = (used_gb / total_gb) * 100.0

                        return (
                            used_gb = used_gb,
                            total_gb = total_gb,
                            available_gb = available_gb,
                            used_pct = used_pct
                        )
                    end
                end
            end
        end
    catch e
        @debug "Failed to get memory info" error=e
    end

    # Fallback: return default values
    return (
        used_gb = 0.0,
        total_gb = 0.0,
        available_gb = 0.0,
        used_pct = 0.0
    )
end

end # module Utils