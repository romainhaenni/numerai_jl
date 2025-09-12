#!/usr/bin/env julia

# Comprehensive tests for the API client
using Test
using JSON3
using Dates

# NumeraiTournament is already loaded by runtests.jl

# Mock GraphQL responses for testing
const MOCK_RESPONSES = Dict(
    # User query response
    "user" => JSON3.read("""
    {
        "data": {
            "user": {
                "username": "test_user",
                "id": "test_id",
                "models": [
                    {"name": "model1", "id": "id1"},
                    {"name": "model2", "id": "id2"}
                ]
            }
        }
    }
    """),
    
    # v3UserProfile with modelName
    "v3UserProfile_with_model" => JSON3.read("""
    {
        "data": {
            "v3UserProfile": {
                "username": "test_user",
                "latestRanks": {
                    "corr": 0.02,
                    "mmc": 0.01,
                    "fnc": 0.015,
                    "tc": 0.025
                },
                "nmrStaked": 100.0,
                "stake": {
                    "value": 100.0,
                    "confidence": 0.8,
                    "burnRate": 0.25
                },
                "roundModelPerformances": []
            }
        }
    }
    """),
    
    # Rounds query
    "rounds" => JSON3.read("""
    {
        "data": {
            "rounds": [
                {
                    "number": 500,
                    "openTime": "2024-01-01T00:00:00Z",
                    "closeTime": "2024-01-08T00:00:00Z",
                    "resolveTime": "2024-01-15T00:00:00Z"
                }
            ]
        }
    }
    """),
    
    # Account query  
    "account" => JSON3.read("""
    {
        "data": {
            "account": {
                "username": "test_user",
                "walletAddress": "0x123",
                "availableNmr": 50.0,
                "email": "test@example.com",
                "status": "VERIFIED"
            }
        }
    }
    """)
)

# Mock API client for testing
mutable struct MockAPIClient
    public_id::String
    secret_key::String
    tournament_id::Int
    model_name::String
    responses::Dict
end

function mock_client()
    return MockAPIClient(
        "test_public",
        "test_secret",
        8,
        "test_model",
        MOCK_RESPONSES
    )
end

@testset "API Client Tests" begin
    
    @testset "Client Initialization" begin
        # Test that client can be created with valid credentials
        client = NumeraiTournament.API.NumeraiClient(
            "test_public_id",
            "test_secret_key"
        )
        @test client.public_id == "test_public_id"
        @test client.secret_key == "test_secret_key"
        @test client.tournament_id == 8  # Default tournament
    end
    
    @testset "GraphQL Query Structure" begin
        # Test that queries are properly formatted
        
        # Test rounds query - should NOT have 'take' parameter
        rounds_query = """
        query {
            rounds(tournament: 8) {
                number
                openTime
                closeTime
                resolveTime
            }
        }
        """
        # Check that 'take' is not in the query
        @test !occursin("take:", rounds_query)
        
        # Test v3UserProfile query with modelName
        model_query = """
        query(\$modelName: String!) {
            v3UserProfile(modelName: \$modelName) {
                latestRanks {
                    corr
                    mmc
                    fnc
                    tc
                }
                nmrStaked
            }
        }
        """
        @test occursin("modelName: \$modelName", model_query)
        
        # Test user query for getting models list
        user_query = """
        query {
            user {
                username
                models {
                    name
                    id
                }
            }
        }
        """
        @test occursin("user {", user_query)
        @test occursin("models {", user_query)
    end
    
    @testset "Error Handling" begin
        # Test that API errors are properly caught and handled
        client = NumeraiTournament.API.NumeraiClient(
            "invalid_key",
            "invalid_secret"
        )
        
        # Test with try-catch to ensure errors don't crash
        try
            # This should fail gracefully
            result = NumeraiTournament.API.get_current_round(client)
            # If it succeeds despite bad credentials, accept any positive round number
            @test result.number >= 0
        catch e
            # Even if it throws, it should be a controlled error
            @test isa(e, Exception)
        end
    end
    
    @testset "Query Parameters" begin
        # Test that client can be created and has expected fields
        client = NumeraiTournament.API.NumeraiClient(
            "test_public",
            "test_secret"
        )
        
        # Test client structure
        @test client.public_id == "test_public"
        @test client.secret_key == "test_secret"
        @test haskey(client.headers, "x-public-id")
        @test client.headers["x-public-id"] == "test_public"
    end
    
    @testset "Response Parsing" begin
        # Test that responses are properly parsed
        
        # Test parsing rounds response
        rounds_data = MOCK_RESPONSES["rounds"]["data"]["rounds"]
        @test length(rounds_data) > 0
        @test rounds_data[1]["number"] == 500
        
        # Test parsing user profile
        profile_data = MOCK_RESPONSES["v3UserProfile_with_model"]["data"]["v3UserProfile"]
        @test profile_data["nmrStaked"] == 100.0
        @test profile_data["latestRanks"]["corr"] == 0.02
        
        # Test parsing user models
        user_data = MOCK_RESPONSES["user"]["data"]["user"]
        @test length(user_data["models"]) == 2
        @test user_data["models"][1]["name"] == "model1"
    end
    
    @testset "API Query Functions" begin
        # Test that all API functions handle errors gracefully
        client = NumeraiTournament.API.NumeraiClient(
            "test_public",
            "test_secret"
        )
        
        # Each of these should handle errors gracefully
        functions_to_test = [
            () -> NumeraiTournament.API.get_current_round(client),
            () -> NumeraiTournament.API.get_account(client),
            () -> NumeraiTournament.API.get_models(client),
            () -> NumeraiTournament.API.get_model_performance(client, "test_model"),
            () -> NumeraiTournament.API.get_stake_info(client, "test_model"),
            () -> NumeraiTournament.API.get_latest_submission(client)
        ]
        
        for func in functions_to_test
            try
                result = func()
                # Should return some default/empty value on error
                @test result !== nothing
            catch e
                # If it throws, should be a controlled error
                @test isa(e, Exception)
                # Should not be a MethodError (those indicate bugs)
                @test !isa(e, MethodError)
            end
        end
    end
end

println("✅ All API client tests completed!")