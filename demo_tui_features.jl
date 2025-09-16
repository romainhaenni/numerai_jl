#!/usr/bin/env julia

# Demo script showcasing the Numerai Tournament TUI features
# This demonstrates all the working functionality of v0.10.32

using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament
using Term

function show_demo_info()
    print("\033[2J\033[H")  # Clear screen

    panel = Panel(
        """
        🚀 [bold cyan]Numerai Tournament TUI v0.10.32 - Feature Demo[/bold cyan]

        [bold yellow]✨ All Features Now Working:[/bold yellow]

        [green]✅ Real-time Progress Bars[/green]
        • Downloads show actual MB transferred
        • Training shows real epochs/iterations
        • Uploads show submission progress
        • Predictions show processing status

        [green]✅ Instant Commands (No Enter Required)[/green]
        • [bold]d[/bold] - Download tournament data
        • [bold]t[/bold] - Train models
        • [bold]p[/bold] - Generate predictions
        • [bold]s[/bold] - Submit to Numerai
        • [bold]r[/bold] - Refresh system info
        • [bold]q[/bold] - Quit application

        [green]✅ Automatic Features[/green]
        • Auto-training after all datasets download
        • Real-time system monitoring (CPU/Memory/Disk)
        • Event log tracks last 30 operations

        [green]✅ Visual Interface[/green]
        • Sticky top panel with system status
        • Sticky bottom panel with event log
        • Clean, responsive layout
        • Updates every 100ms during operations

        [bold magenta]Press any key to start the TUI...[/bold magenta]
        """,
        title="Feature Demo",
        width=80,
        fit=false
    )

    println(panel)
end

function main()
    # Show demo information
    show_demo_info()

    # Wait for user input
    println("\n")
    print("Ready to start? (y/n): ")
    response = readline()

    if lowercase(response) != "y"
        println("Demo cancelled.")
        return
    end

    # Load configuration
    config = NumeraiTournament.load_config("config.toml")

    println("\n📊 Starting Numerai Tournament TUI...")
    println("   All operations connect to REAL Numerai API")
    println("   Progress bars show REAL data transfer")
    println("   Training uses REAL ML models")
    println()
    sleep(2)

    # Run the operational dashboard
    NumeraiTournament.run_operational_dashboard(config)
end

# Run the demo
main()