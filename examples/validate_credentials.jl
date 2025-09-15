#!/usr/bin/env julia

"""
    Validate Numerai API Credentials
    
    This script helps validate and configure your Numerai API credentials.
    
    Usage:
        julia examples/validate_credentials.jl
        
    To get valid credentials:
    1. Go to https://numer.ai/account
    2. Navigate to the API section
    3. Generate a new API key pair
    4. Copy the Public ID and Secret Key
"""

using Pkg
cd(@__DIR__)
cd("..")
Pkg.activate(".")

using HTTP
using JSON3
using DotEnv

# Load environment variables
env_file = joinpath(@__DIR__, "..", ".env")
if isfile(env_file)
    DotEnv.load!(env_file)
    println("✓ Found .env file at: $env_file")
else
    println("✗ No .env file found at: $env_file")
end

# Check for credentials
public_id = get(ENV, "NUMERAI_PUBLIC_ID", "")
secret_key = get(ENV, "NUMERAI_SECRET_KEY", "")

println("\n" * "="^60)
println("NUMERAI API CREDENTIAL VALIDATOR")
println("="^60)

# Validate credential format
function validate_credential_format(public_id, secret_key)
    issues = String[]
    
    # Check if credentials exist
    if isempty(public_id)
        push!(issues, "✗ NUMERAI_PUBLIC_ID is not set")
    else
        println("✓ NUMERAI_PUBLIC_ID is set ($(length(public_id)) characters)")
        
        # Check for invalid credentials
        if length(public_id) != 32
            push!(issues, "⚠ NUMERAI_PUBLIC_ID should be 32 characters (found $(length(public_id)))")
        end
    end
    
    if isempty(secret_key)
        push!(issues, "✗ NUMERAI_SECRET_KEY is not set")
    else
        println("✓ NUMERAI_SECRET_KEY is set ($(length(secret_key)) characters)")
        
        # Check for invalid credentials
        if length(secret_key) != 64
            push!(issues, "⚠ NUMERAI_SECRET_KEY should be 64 characters (found $(length(secret_key)))")
        end
    end
    
    return issues
end

# Test API connection
function test_api_connection(public_id, secret_key)
    println("\n" * "-"^60)
    println("Testing API Connection...")
    println("-"^60)
    
    # Use the same tournament API endpoint as the main application
    url = "https://api-tournament.numer.ai/graphql"
    
    # Test public API (no auth required)
    query_public = """
    {
        rounds(tournament: 8, take: 1) {
            number
            openTime
            closeTime
        }
    }
    """
    
    try
        response = HTTP.post(
            url,
            ["Content-Type" => "application/json"],
            JSON3.write(Dict("query" => query_public))
        )
        
        if response.status == 200
            println("✓ Public API connection successful")
            data = JSON3.read(String(response.body))
            if haskey(data, :data) && haskey(data.data, :rounds) && !isempty(data.data.rounds)
                round = data.data.rounds[1]
                println("  Current round: $(round.number)")
            end
        else
            println("✗ Public API connection failed (status: $(response.status))")
        end
    catch e
        println("✗ Public API connection failed: $e")
    end
    
    # Test authenticated API
    if !isempty(public_id) && !isempty(secret_key)
        query_auth = """
        {
            account {
                username
                email
                models {
                    name
                    id
                }
            }
        }
        """
        
        println("\nTesting authenticated API...")
        
        try
            response = HTTP.post(
                url,
                [
                    "Content-Type" => "application/json",
                    "x-public-id" => public_id,
                    "x-secret-key" => secret_key
                ],
                JSON3.write(Dict("query" => query_auth))
            )
            
            if response.status == 200
                data = JSON3.read(String(response.body))
                
                if haskey(data, :errors) && !isempty(data.errors)
                    error_msg = data.errors[1].message
                    if occursin("not_authenticated", lowercase(error_msg)) || occursin("not authenticated", lowercase(error_msg))
                        println("✗ Authentication failed: Invalid credentials")
                        println("  The provided API keys are not valid")
                        println("\n  To fix this:")
                        println("  1. Go to https://numer.ai/account")
                        println("  2. Navigate to the 'Compute' or 'API' section")
                        println("  3. Create a new API key")
                        println("  4. Copy both the Public ID and Secret Key")
                        println("  5. Update your .env file with the new credentials")
                        return false
                    else
                        println("✗ API error: $error_msg")
                        return false
                    end
                elseif haskey(data, :data) && haskey(data.data, :account) && !isnothing(data.data.account)
                    account = data.data.account
                    println("✓ Authentication successful!")
                    println("  Username: $(account.username)")
                    if haskey(account, :email) && !isnothing(account.email)
                        println("  Email: $(account.email)")
                    end
                    if haskey(account, :models) && !isempty(account.models)
                        println("  Models: $(length(account.models)) model(s) found")
                        for model in account.models
                            println("    - $(model.name)")
                        end
                    end
                    return true
                else
                    println("✗ Unexpected API response structure")
                    println("  Response: $(data)")
                    return false
                end
            else
                println("✗ API request failed (status: $(response.status))")
                return false
            end
        catch e
            println("✗ API connection failed: $e")
            return false
        end
    else
        println("\n⚠ Skipping authenticated API test (credentials not set)")
        return false
    end
end

# Main validation
println("\nValidating credential format...")
issues = validate_credential_format(public_id, secret_key)

if !isempty(issues)
    println("\n" * "!"^60)
    println("CREDENTIAL ISSUES FOUND:")
    println("!"^60)
    for issue in issues
        println(issue)
    end
end

# Test API if credentials look valid
if isempty(issues) || (length(issues) <= 2 && all(i -> occursin("⚠", i), issues))
    authenticated = test_api_connection(public_id, secret_key)
else
    println("\n⚠ Skipping API test due to credential format issues")
    authenticated = false
end

# Provide instructions
if !authenticated
    println("\n" * "="^60)
    println("HOW TO FIX AUTHENTICATION:")
    println("="^60)
    println()
    println("1. Get your Numerai API credentials:")
    println("   • Go to https://numer.ai")
    println("   • Log in to your account")
    println("   • Go to Account → Compute (or API section)")
    println("   • Generate a new API key")
    println("   • Copy both the Public ID and Secret Key")
    println()
    println("2. Update your .env file:")
    println("   • Open .env in your editor")
    println("   • Replace the example credentials with your real ones:")
    println()
    println("   NUMERAI_PUBLIC_ID=your_real_public_id_here")
    println("   NUMERAI_SECRET_KEY=your_real_secret_key_here")
    println()
    println("3. Run this script again to validate")
    println()
    println("Note: Real Numerai credentials are:")
    println("  • Public ID: 32 characters (alphanumeric)")
    println("  • Secret Key: 64 characters (alphanumeric)")
else
    println("\n" * "="^60)
    println("SUCCESS! Your credentials are valid and working!")
    println("="^60)
    println("\nYou can now use the Numerai Tournament System.")
    println("Try running:")
    println("  julia -t 16 ./numerai")
end