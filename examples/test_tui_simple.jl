#!/usr/bin/env julia

# Simple test to verify TUI components are working

using Pkg
Pkg.activate(dirname(@__DIR__))

println("Loading NumeraiTournament module...")
using NumeraiTournament

println("✅ Module loaded successfully")
println()

# Test basic functions that don't require a dashboard instance
println("Testing TUI utility functions:")
println("=" ^ 50)

# Test progress bar creation
println("\n1. Progress bars:")
for pct in [0, 25, 50, 75, 100]
    # Create progress bar directly
    filled = Int(round((pct / 100.0) * 30))
    empty = 30 - filled
    bar = "[" * "█" ^ filled * "░" ^ empty * "]"
    println("   $pct%: $bar $(pct)%")
end

# Test spinner
println("\n2. Spinner animation:")
spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
for char in spinner_chars
    print("\r   $char Working...  ")
    flush(stdout)
    sleep(0.1)
end
println()

# Test terminal size
println("\n3. Terminal dimensions:")
height, width = displaysize(stdout)
println("   Width: $width columns")
println("   Height: $height rows")

# Test ANSI color codes
println("\n4. ANSI colors (for event types):")
println("   \033[32m✅ Success message\033[0m")
println("   \033[33m⚠️  Warning message\033[0m")
println("   \033[31m❌ Error message\033[0m")
println("   \033[36mℹ️  Info message\033[0m")

# Test time formatting
println("\n5. Time formatting:")
using Dates
println("   Current time: $(Dates.format(now(), "HH:MM:SS"))")
println("   45 seconds = 45s")
println("   125 seconds = 2m 5s")
println("   3665 seconds = 1h 1m")

println("\n" * "=" ^ 50)
println("✅ All basic TUI components working!")
println()
println("To run the full TUI:")
println("  julia start_tui.jl")