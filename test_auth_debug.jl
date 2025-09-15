#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using HTTP
using JSON3

# Load .env file
env_file = ".env"
if isfile(env_file)
    lines = readlines(env_file)
    for line in lines
        line = strip(line)
        if !isempty(line) && !startswith(line, "#") && occursin("=", line)
            key, val = split(line, "=", limit=2)
            key = strip(key)
            val = strip(val)
            ENV[key] = val
        end
    end
end

public_id = get(ENV, "NUMERAI_PUBLIC_ID", "")
secret_key = get(ENV, "NUMERAI_SECRET_KEY", "")

println("Public ID: $public_id")
println("Secret Key: $secret_key")
println()

# Test with authorization header instead of x-public-id/x-secret-key
println("Testing with Authorization header...")

# Create auth token - Numerai uses public_id:secret_key format
auth_token = "$public_id:$secret_key"

query = """
{
    account {
        username
        models {
            name
        }
    }
}
"""

url = "https://api-tournament.numer.ai/graphql"

# Test 1: Using x-public-id and x-secret-key headers (current implementation)
println("\nTest 1: Using x-public-id and x-secret-key headers")
try
    response = HTTP.post(
        url,
        [
            "Content-Type" => "application/json",
            "x-public-id" => public_id,
            "x-secret-key" => secret_key
        ],
        JSON3.write(Dict("query" => query));
        verbose=2  # Show detailed request/response
    )

    data = JSON3.read(String(response.body))
    println("Response: ", JSON3.write(data, 2))
catch e
    println("Error: $e")
end

# Test 2: Using Authorization header with Bearer token
println("\nTest 2: Using Authorization Bearer header")
try
    response = HTTP.post(
        url,
        [
            "Content-Type" => "application/json",
            "Authorization" => "Bearer $public_id$secret_key"
        ],
        JSON3.write(Dict("query" => query))
    )

    data = JSON3.read(String(response.body))
    println("Response: ", JSON3.write(data, 2))
catch e
    println("Error: $e")
end

# Test 3: Using Authorization header with Token format
println("\nTest 3: Using Authorization Token header")
try
    response = HTTP.post(
        url,
        [
            "Content-Type" => "application/json",
            "Authorization" => "Token $public_id$secret_key"
        ],
        JSON3.write(Dict("query" => query))
    )

    data = JSON3.read(String(response.body))
    println("Response: ", JSON3.write(data, 2))
catch e
    println("Error: $e")
end

# Test 4: Using combined auth in a single header
println("\nTest 4: Using x-numer-auth header")
try
    response = HTTP.post(
        url,
        [
            "Content-Type" => "application/json",
            "x-numer-auth" => "$public_id$secret_key"
        ],
        JSON3.write(Dict("query" => query))
    )

    data = JSON3.read(String(response.body))
    println("Response: ", JSON3.write(data, 2))
catch e
    println("Error: $e")
end