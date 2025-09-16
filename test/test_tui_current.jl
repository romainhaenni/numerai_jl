#!/usr/bin/env julia

# Test script to verify current TUI implementation
using Pkg
Pkg.activate(@__DIR__)

println("Loading NumeraiTournament module...")
using NumeraiTournament

# Create test config
config = Dict(
    :api_public_key => "",
    :api_secret_key => "",
    :models => ["test_model"],
    :auto_train_after_download => true,
    :data_dir => "data",
    :model_dir => "models"
)

println("Creating TUI dashboard...")
# Test if the module and function exist
if isdefined(NumeraiTournament, :run_tui_v1034)
    println("✅ run_tui_v1034 function found")

    # Check if TUIv1034Fix module is loaded
    if isdefined(NumeraiTournament, :TUIv1034Fix)
        println("✅ TUIv1034Fix module loaded")
    else
        println("❌ TUIv1034Fix module NOT loaded")
    end
else
    println("❌ run_tui_v1034 function NOT found")
end

# List all exported functions that contain 'tui' or 'TUI'
println("\nAvailable TUI functions:")
for name in names(NumeraiTournament, all=false)
    str = string(name)
    if occursin("tui", lowercase(str)) || occursin("dashboard", lowercase(str))
        println("  - $name")
    end
end

println("\nTrying to test TUI components...")
# Try to access the dashboard module directly
try
    # Check what TUI implementations are available
    tui_path = joinpath(dirname(pathof(NumeraiTournament)), "tui")
    println("\nTUI modules found in $tui_path:")
    for file in readdir(tui_path)
        if endswith(file, ".jl")
            println("  - $file")
        end
    end
catch e
    println("Error checking TUI modules: $e")
end