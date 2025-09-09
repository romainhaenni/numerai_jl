using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using NumeraiTournament
using Test
using Dates

# Load environment variables
if isfile(joinpath(@__DIR__, "..", ".env"))
    for line in readlines(joinpath(@__DIR__, "..", ".env"))
        if !startswith(line, "#") && contains(line, "=")
            key, value = split(line, "=", limit=2)
            ENV[strip(key)] = strip(value)
        end
    end
end

@testset "API Client Tests" begin
    # Test client creation
    @testset "Client Creation" begin
        client = NumeraiTournament.API.NumeraiClient(
            ENV["NUMERAI_PUBLIC_ID"],
            ENV["NUMERAI_SECRET_KEY"]
        )
        @test client.public_id == ENV["NUMERAI_PUBLIC_ID"]
        @test client.secret_key == ENV["NUMERAI_SECRET_KEY"]
        @test haskey(client.headers, "x-public-id")
        @test haskey(client.headers, "x-secret-key")
    end
    
    # Test getting current round
    @testset "Get Current Round" begin
        client = NumeraiTournament.API.NumeraiClient(
            ENV["NUMERAI_PUBLIC_ID"],
            ENV["NUMERAI_SECRET_KEY"]
        )
        
        try
            round = NumeraiTournament.API.get_current_round(client)
            @test round.number > 0
            @test round.open_time isa DateTime
            @test round.close_time isa DateTime
            @test round.resolve_time isa DateTime
            println("✅ Current round: #$(round.number)")
            println("   Open: $(round.open_time)")
            println("   Close: $(round.close_time)")
        catch e
            @warn "Failed to get current round" exception=e
        end
    end
    
    # Test getting models for user
    @testset "Get User Models" begin
        client = NumeraiTournament.API.NumeraiClient(
            ENV["NUMERAI_PUBLIC_ID"],
            ENV["NUMERAI_SECRET_KEY"]
        )
        
        try
            models = NumeraiTournament.API.get_models_for_user(client)
            @test models isa Vector{String}
            println("✅ Found $(length(models)) models: $(join(models, ", "))")
            
            # Test getting performance for first model if exists
            if length(models) > 0
                model_name = models[1]
                perf = NumeraiTournament.API.get_model_performance(client, model_name)
                @test perf.model_name == model_name
                println("   Model: $model_name")
                println("   CORR: $(perf.corr)")
                println("   MMC: $(perf.mmc)")
                println("   Stake: $(perf.stake) NMR")
            end
        catch e
            @warn "Failed to get user models" exception=e
        end
    end
    
    # Test dataset info
    @testset "Dataset Info" begin
        client = NumeraiTournament.API.NumeraiClient(
            ENV["NUMERAI_PUBLIC_ID"],
            ENV["NUMERAI_SECRET_KEY"]
        )
        
        dataset_info = NumeraiTournament.API.get_dataset_info(client)
        @test dataset_info.version == "v5.0"
        @test contains(dataset_info.train_url, "train.parquet")
        @test contains(dataset_info.validation_url, "validation.parquet")
        @test contains(dataset_info.live_url, "live.parquet")
        println("✅ Dataset version: $(dataset_info.version)")
    end
end

println("\n🎉 API client tests completed!")