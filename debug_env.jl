println("Before loading .env:")
println("PUBLIC_ID: ", get(ENV, "NUMERAI_PUBLIC_ID", "NOT SET"))
println("SECRET_KEY: ", get(ENV, "NUMERAI_SECRET_KEY", "NOT SET"))

env_file = joinpath(@__DIR__, ".env")
println("\nReading .env from: ", env_file)

for line in readlines(env_file)
    if !startswith(line, "#") && contains(line, "=")
        key, value = split(line, "=", limit=2)
        ENV[strip(key)] = strip(value)
        println("Set ", strip(key), " = ", strip(value)[1:min(10,length(strip(value)))], "...")
    end
end

println("\nAfter loading .env:")
println("PUBLIC_ID: ", ENV["NUMERAI_PUBLIC_ID"])
println("SECRET_KEY: ", ENV["NUMERAI_SECRET_KEY"][1:10], "...")

# Now test the API
using NumeraiTournament
client = NumeraiTournament.API.NumeraiClient(
    ENV["NUMERAI_PUBLIC_ID"],
    ENV["NUMERAI_SECRET_KEY"]
)
println("\nTesting API connection...")
try
    round = NumeraiTournament.API.get_current_round(client)
    println("✓ API connection successful! Current round: ", round.number)
catch e
    println("✗ API connection failed: ", e)
end