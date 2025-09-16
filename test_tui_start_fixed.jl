#!/usr/bin/env julia

# Test that TUI can now start without scoping errors

using Pkg
Pkg.activate(@__DIR__)

# Load the main module
using NumeraiTournament

println("Testing TUI Start After Scoping Fix")
println("="^50)

# Load config
config = NumeraiTournament.load_config("config.toml")

println("\nConfiguration loaded:")
println("  API credentials present: $(!isempty(config.api_public_key) && !isempty(config.api_secret_key))")
println("  Auto-start enabled: $(config.auto_start_pipeline)")

println("\nAttempting to start TUI...")
println("(Will run for 3 seconds then exit)")

# Start TUI in a task so we can stop it after a few seconds
tui_task = @async begin
    NumeraiTournament.run_tui_v1043(config)
end

# Let it run for 3 seconds
sleep(3)

# Check if any errors occurred
if istaskdone(tui_task)
    if istaskfailed(tui_task)
        println("\n❌ TUI failed to start!")
        println("Error: $(tui_task.exception)")
    else
        println("\n✅ TUI started and ran successfully!")
    end
else
    println("\n✅ TUI is running! (would continue if not stopped)")
end

println("\nTest complete!")
println("="^50)