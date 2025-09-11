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

client = NumeraiTournament.API.NumeraiClient(
    ENV["NUMERAI_PUBLIC_ID"],
    ENV["NUMERAI_SECRET_KEY"]
)

println("Testing API connection...")

# Test getting current round
try
    round = NumeraiTournament.API.get_current_round(client)
    println("✅ Current round: #$(round.number)")
catch e
    println("❌ Failed to get current round: $e")
end

# Test getting models
try
    models = NumeraiTournament.API.get_models_for_user(client)
    println("✅ Found $(length(models)) models: $(join(models, ", "))")
    
    # Update config file with actual models
    if length(models) > 0
        config = """
        api_public_key = "$(ENV["NUMERAI_PUBLIC_ID"])"
        api_secret_key = "$(ENV["NUMERAI_SECRET_KEY"])"
        models = ["$(join(models, "\", \""))"]
        data_dir = "data"
        model_dir = "models"
        auto_submit = false
        stake_amount = 0.0
        max_workers = $(Sys.CPU_THREADS)
        """
        
        write(joinpath(@__DIR__, "..", "config.toml"), config)
        println("✅ Updated config.toml with models")
    end
    
catch e
    println("❌ Failed to get models: $e")
end