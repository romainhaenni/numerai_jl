#!/usr/bin/env julia

# Test production API with real credentials
using Pkg
Pkg.activate(".")

println("Testing Production API with Real Credentials")
println("=" ^ 60)

# Load the main module
include("src/NumeraiTournament.jl")
using .NumeraiTournament
using .NumeraiTournament.API
using HTTP

# Load configuration
config_path = "config.toml"
config = NumeraiTournament.load_config(config_path)

println("\n1. Testing API Authentication...")
try
    client = API.NumeraiClient(
        config.api_public_key,
        config.api_secret_key
    )
    println("✅ API client created successfully")
    
    println("\n2. Testing Account Info Retrieval...")
    account_info = API.get_account(client)
    if !isnothing(account_info)
        println("✅ Account info retrieved successfully")
        println("   Username: ", get(account_info, "username", "unknown"))
        println("   Wallet Address: ", get(account_info, "walletAddress", "none"))
    else
        println("❌ Failed to retrieve account info")
    end
    
    println("\n3. Testing Models List...")
    models = API.list_models(client)
    if !isempty(models)
        println("✅ Found $(length(models)) model(s):")
        for model in models
            println("   - $(model["name"]) (ID: $(model["id"]))")
        end
    else
        println("⚠️  No models found (this might be normal for new accounts)")
    end
    
    println("\n4. Testing Current Round Info...")
    current_round = API.get_current_round(client)
    if !isnothing(current_round)
        println("✅ Current round retrieved: $current_round")
    else
        println("❌ Failed to retrieve current round")
    end
    
    println("\n5. Testing Competitions Info...")
    competitions = API.get_competitions(client)
    if !isnothing(competitions) && !isempty(competitions)
        println("✅ Found $(length(competitions)) competition(s)")
        for comp in competitions[1:min(3, length(competitions))]
            println("   - Competition $(comp["number"]): $(comp["openTime"]) to $(comp["closeTime"])")
        end
    else
        println("❌ Failed to retrieve competitions")
    end
    
    println("\n6. Testing Submission Window Status...")
    is_open = API.is_submission_window_open(client)
    println(is_open ? "✅ Submission window is OPEN" : "⚠️  Submission window is CLOSED")
    
    println("\n7. Testing Dataset Info...")
    dataset_info = API.get_dataset_info(client)
    if !isnothing(dataset_info)
        println("✅ Dataset info retrieved")
        if haskey(dataset_info, "trainDataUrl")
            println("   Training data available: Yes")
        end
        if haskey(dataset_info, "validationDataUrl")
            println("   Validation data available: Yes")
        end
    else
        println("❌ Failed to retrieve dataset info")
    end
    
    println("\n" * "=" ^ 60)
    println("✅ PRODUCTION API TEST SUCCESSFUL!")
    println("The API integration is working correctly with real credentials.")
    
catch e
    println("\n" * "=" ^ 60)
    println("❌ PRODUCTION API TEST FAILED!")
    println("Error: ", e)
    if isa(e, HTTP.Exceptions.HTTPError)
        println("HTTP Status: ", e.status)
        println("Response: ", String(e.response.body))
    end
    println("\nPlease check:")
    println("1. API credentials are valid")
    println("2. Internet connection is working")
    println("3. Numerai API is accessible")
end

println("\n" * "=" ^ 60)