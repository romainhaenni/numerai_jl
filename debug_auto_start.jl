#!/usr/bin/env julia

# Debug script to test auto-start pipeline functionality
using Pkg
Pkg.activate(@__DIR__)

using NumeraiTournament

println("="^60)
println("DEBUG: Auto-start Pipeline Investigation")
println("="^60)

# Load configuration
config = NumeraiTournament.load_config("config.toml")
println("\n1. Configuration Status:")
println("   auto_start_pipeline: $(config.auto_start_pipeline)")
println("   auto_train_after_download: $(config.auto_train_after_download)")
println("   api_public_key: $(config.api_public_key[1:8])...")
println("   api_secret_key: $(config.api_secret_key[1:8])...")

# Test API client creation
println("\n2. Testing API Client Creation:")
try
    api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)
    println("   ✅ API client created successfully")

    # Test a simple API call
    println("\n3. Testing API Connectivity:")
    try
        # Make a simple GraphQL query to test authentication
        query = """
        {
            account {
                username
                id
            }
        }
        """
        response = NumeraiTournament.API.graphql_query(api_client, query)
        println("   ✅ API call successful")
        println("   Username: $(response.data.account.username)")
    catch e
        println("   ❌ API call failed: $e")
    end

catch e
    println("   ❌ API client creation failed: $e")
end

# Test dashboard creation
println("\n4. Testing Dashboard Creation:")
try
    api_client = NumeraiTournament.API.NumeraiClient(config.api_public_key, config.api_secret_key)
    dashboard = NumeraiTournament.TUIProductionV047.create_dashboard(config, api_client)

    println("   ✅ Dashboard created successfully")
    println("   auto_start_enabled: $(dashboard.auto_start_enabled)")
    println("   auto_start_delay: $(dashboard.auto_start_delay)")
    println("   auto_train_enabled: $(dashboard.auto_train_enabled)")

    # Check if auto-start would trigger
    if dashboard.auto_start_enabled && !dashboard.auto_start_initiated
        println("   ✅ Auto-start conditions met - pipeline should start")
    else
        println("   ⚠️  Auto-start conditions NOT met:")
        println("      auto_start_enabled: $(dashboard.auto_start_enabled)")
        println("      auto_start_initiated: $(dashboard.auto_start_initiated)")
    end

    # Simulate what happens during auto-start
    println("\n5. Simulating Auto-start Logic:")
    if dashboard.auto_start_enabled && !dashboard.auto_start_initiated
        dashboard.auto_start_initiated = true
        println("   Step 1: auto_start_initiated set to true")
        println("   Step 2: Would wait $(dashboard.auto_start_delay) seconds")
        println("   Step 3: Would check dashboard.running && !dashboard.pipeline_active")
        println("          dashboard.running: $(dashboard.running)")
        println("          dashboard.pipeline_active: $(dashboard.pipeline_active)")
        println("   Step 4: Would call start_pipeline(dashboard)")

        # Test the start_pipeline function
        println("\n6. Testing start_pipeline Function:")
        try
            # We'll just check if the function can be called without errors
            # but won't actually run the full pipeline
            println("   Function exists: $(hasmethod(NumeraiTournament.TUIProductionV047.start_pipeline, (typeof(dashboard),)))")
        catch e
            println("   ❌ Error accessing start_pipeline: $e")
        end
    else
        println("   ❌ Auto-start logic would not trigger")
    end

catch e
    println("   ❌ Dashboard creation failed: $e")
    println("   Error type: $(typeof(e))")
    if isa(e, MethodError)
        println("   Available methods: $(methods(e.f))")
    end
end

println("\n" * "="^60)
println("DEBUG COMPLETE")
println("="^60)