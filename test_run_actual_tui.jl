#!/usr/bin/env julia

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("Starting actual TUI for 5 seconds...")
println("=====================================")
println("This will start the real TUI dashboard and exit after 5 seconds.")
println()

# Load config
config = NumeraiTournament.load_config("config.toml")

# Run TUI in a task so we can kill it after 5 seconds
tui_task = @async begin
    try
        NumeraiTournament.run_tui_v1036(config)
    catch e
        if !(e isa InterruptException)
            println("TUI Error: $e")
        end
    end
end

# Wait 5 seconds
sleep(5)

# Create a dashboard just to set running to false (hacky but works)
dashboard = NumeraiTournament.TUIv1036Dashboard(config)
dashboard.running = false

println("\n\nTUI test completed.")
println("If the TUI started and showed real system values, the dashboard is working.")
println("Check if auto-start pipeline initiated downloads.")