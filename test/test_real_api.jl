#!/usr/bin/env julia

using NumeraiTournament
using NumeraiTournament.API
using Test

println("Testing Numerai API Client with real API endpoints...")
println("=" ^ 60)

# Create a client with dummy credentials for public endpoints
# These are not needed for public endpoints but the client requires them
client = API.NumeraiClient("dummy_public_id", "dummy_secret_key")

# Test 1: Get current round (public endpoint, no auth required)
println("\n1. Testing get_current_round()...")
try
    round_info = API.get_current_round(client)
    println("✅ Successfully retrieved current round: $(round_info.number)")
    println("   Round opens: $(round_info.open_time)")
    println("   Round closes: $(round_info.close_time)")
    println("   Round resolved: $(round_info.resolved)")
catch e
    println("❌ Failed to get current round: $e")
end

# Test 2: Get dataset info (public endpoint)
println("\n2. Testing get_dataset_info()...")
try
    dataset_info = API.get_dataset_info(client)
    println("✅ Successfully retrieved dataset info")
    println("   Version: $(dataset_info.version)")
    println("   Training data: $(dataset_info.train_url)")
    println("   Validation data: $(dataset_info.validation_url)")
    println("   Live data: $(dataset_info.live_url)")
    println("   Features metadata: $(dataset_info.features_url)")
catch e
    println("❌ Failed to get dataset info: $e")
end

# Test 3: Skip live dataset ID as it's deprecated
println("\n3. Skipping get_live_dataset_id() - deprecated field in API")

# Test 4: Validate submission window
println("\n4. Testing validate_submission_window()...")
try
    result = API.validate_submission_window(client)
    if isa(result, Tuple) && length(result) == 2
        is_open, message = result
        println("✅ Submission window check completed")
        println("   Window open: $is_open")
        println("   Message: $message")
    else
        println("✅ Submission window check completed")
        println("   Result: $result")
    end
catch e
    println("❌ Failed to validate submission window: $e")
end

# Test authenticated endpoints only if credentials are available
if haskey(ENV, "NUMERAI_PUBLIC_ID") && haskey(ENV, "NUMERAI_SECRET_KEY")
    println("\n5. Testing authenticated endpoints...")
    
    # Create a client with real credentials
    auth_client = API.NumeraiClient(ENV["NUMERAI_PUBLIC_ID"], ENV["NUMERAI_SECRET_KEY"])
    
    # Test account info
    println("\n   Testing get_account()...")
    try
        account_info = API.get_account(auth_client)
        println("   ✅ Successfully retrieved account info")
        println("      Username: $(get(account_info, "username", "N/A"))")
        println("      Models: $(length(get(account_info, "models", [])))")
    catch e
        println("   ❌ Failed to get account info: $e")
    end
    
    # Test wallet balance
    println("\n   Testing get_wallet_balance()...")
    try
        wallet = API.get_wallet_balance(auth_client)
        println("   ✅ Successfully retrieved wallet balance")
        if wallet !== nothing
            println("      NMR balance: $(get(wallet, "nmr_balance", "N/A"))")
        end
    catch e
        println("   ❌ Failed to get wallet balance: $e")
    end
else
    println("\n⚠️  Skipping authenticated endpoints (no credentials found)")
    println("   Set NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY to test authenticated endpoints")
end

println("\n" * "=" ^ 60)
println("API Client Test Complete!")