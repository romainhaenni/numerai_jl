#!/usr/bin/env julia

# Test script to verify TUI issues are fixed
using Pkg
Pkg.activate(dirname(@__DIR__))

# Load the main module
using NumeraiTournament

# Create a test configuration
config = Dict(
    :api_public_key => get(ENV, "NUMERAI_PUBLIC_ID", ""),
    :api_secret_key => get(ENV, "NUMERAI_SECRET_KEY", ""),
    :data_dir => "data",
    :model_dir => "models",
    :auto_train_after_download => true,
    :model => Dict(:type => "XGBoost"),
    :model_name => "test_model"
)

println("=" ^ 60)
println("TESTING TUI OPERATIONAL DASHBOARD")
println("=" ^ 60)
println()
println("This will test the following features:")
println("1. Download progress bars")
println("2. Upload progress bars")
println("3. Training progress bars/spinners")
println("4. Prediction progress bars/spinners")
println("5. Auto-training after downloads")
println("6. Instant command execution (no Enter needed)")
println("7. Real-time status updates")
println("8. Sticky top panel with system info")
println("9. Sticky bottom panel with event logs")
println()
println("Press 'd' to start download test")
println("Press 't' to test training")
println("Press 'p' to test predictions")
println("Press 's' to test submission")
println("Press 'q' to quit")
println()
println("Starting dashboard...")
println()

# Run the operational dashboard
NumeraiTournament.run_operational_dashboard(config)