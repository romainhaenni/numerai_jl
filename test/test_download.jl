# Import NumeraiTournament if not already loaded (for standalone testing)
if !isdefined(Main, :NumeraiTournament)
    using NumeraiTournament
end

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

# Test downloading features.json (smallest file)
data_dir = joinpath(@__DIR__, "..", "data")
mkpath(data_dir)

try
    println("📥 Downloading features.json...")
    features_path = joinpath(data_dir, "features.json")
    NumeraiTournament.API.download_dataset(client, "features", features_path, show_progress=false)
    
    if isfile(features_path)
        size_mb = filesize(features_path) / 1024 / 1024
        println("✅ Downloaded features.json ($(round(size_mb, digits=2)) MB)")
    end
catch e
    println("❌ Failed to download: $e")
end

# Test getting current round
try
    round_info = NumeraiTournament.API.get_current_round(client)
    println("✅ Current round: #$(round_info.number)")
    println("   Open: $(round_info.open_time)")
    println("   Close: $(round_info.close_time)")
catch e
    println("❌ Failed to get round info: $e")
end