using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using NumeraiTournament

# Load environment variables
if isfile(joinpath(@__DIR__, "..", ".env"))
    for line in readlines(joinpath(@__DIR__, "..", ".env"))
        if !startswith(line, "#") && contains(line, "=")
            key, value = split(line, "=", limit=2)
            ENV[strip(key)] = strip(value)
        end
    end
end

# Test dashboard initialization
config = NumeraiTournament.load_config("config.toml")
println("✅ Config loaded")

try
    dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
    println("✅ Dashboard created")
    
    # Test adding events
    NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Test info event")
    NumeraiTournament.Dashboard.add_event!(dashboard, :success, "Test success event")
    NumeraiTournament.Dashboard.add_event!(dashboard, :warning, "Test warning event")
    NumeraiTournament.Dashboard.add_event!(dashboard, :error, "Test error event")
    
    println("✅ Events added")
    
    # Test updating model performance
    NumeraiTournament.Dashboard.update_model_performance!(dashboard, "test_model", 0.05, 0.02, 0.03, 100.0)
    println("✅ Model performance updated")
    
    println("\n📊 Dashboard ready. Press Ctrl+C to exit.")
    println("Run './numerai' for the full TUI experience")
    
catch e
    println("❌ Dashboard error: $e")
end