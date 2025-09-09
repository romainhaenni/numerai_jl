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

@testset "NumeraiTournament Tests" begin
    
    @testset "Configuration" begin
        config = NumeraiTournament.load_config("config.toml")
        @test config.data_dir == "data"
        @test config.model_dir == "models"
        @test length(config.models) > 0
        @test config.max_workers > 0
    end
    
    @testset "API Client" begin
        client = NumeraiTournament.API.NumeraiClient(
            ENV["NUMERAI_PUBLIC_ID"],
            ENV["NUMERAI_SECRET_KEY"]
        )
        @test client.public_id == ENV["NUMERAI_PUBLIC_ID"]
        @test haskey(client.headers, "x-public-id")
        
        # Test getting current round
        round = NumeraiTournament.API.get_current_round(client)
        @test round.number > 0
        @test round.open_time isa DateTime
    end
    
    @testset "Data Structures" begin
        # Test Round schema
        round = NumeraiTournament.Schemas.Round(
            1090, now(), now() + Day(2), now() + Day(7), true
        )
        @test round.number == 1090
        @test round.is_active == true
        
        # Test ModelPerformance schema
        perf = NumeraiTournament.Schemas.ModelPerformance(
            "model_id", "model_name", 0.05, 0.02, 0.03, 0.01, 1.5, 100.0
        )
        @test perf.corr == 0.05
        @test perf.stake == 100.0
    end
    
    @testset "Dashboard Creation" begin
        config = NumeraiTournament.load_config("config.toml")
        dashboard = NumeraiTournament.Dashboard.TournamentDashboard(config)
        @test dashboard.config == config
        @test dashboard.running == false
        
        # Test adding events
        NumeraiTournament.Dashboard.add_event!(dashboard, :info, "Test event")
        @test length(dashboard.events) > 0
    end
    
    @testset "Scheduler Creation" begin
        config = NumeraiTournament.load_config("config.toml")
        scheduler = NumeraiTournament.Scheduler.TournamentScheduler(config)
        @test scheduler.config == config
        @test scheduler.running == false
        @test scheduler.pipeline === nothing
    end
    
    @testset "Performance Optimization" begin
        perf_info = NumeraiTournament.Performance.optimize_for_m4_max()
        @test perf_info[:threads] > 0
        @test perf_info[:memory_gb] > 0
        @test perf_info[:blas_threads] > 0
    end
    
end

println("\n✅ All tests passed!")