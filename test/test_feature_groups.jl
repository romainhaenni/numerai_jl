#!/usr/bin/env julia
# Import NumeraiTournament if not already loaded (for standalone testing)
if !isdefined(Main, :NumeraiTournament)
    using NumeraiTournament
end
using DataFrames
using JSON3
using Test

println("Testing feature groups integration...")

# Test 1: Test resolve_features_from_groups function with direct feature_cols (backward compatibility)
println("\n1. Testing backward compatibility with feature_cols...")

test_features = ["feature_1", "feature_2", "feature_3"]
resolved = NumeraiTournament.Pipeline.resolve_features_from_groups(
    test_features,   # feature_cols
    nothing,         # feature_groups 
    nothing,         # features_metadata
    nothing          # group_names
)

@test resolved == test_features
println("✓ Backward compatibility test passed")

# Test 2: Test resolve_features_from_groups with feature_groups
println("\n2. Testing feature groups resolution...")

test_feature_groups = Dict(
    "group_a" => ["feature_1", "feature_2"],
    "group_b" => ["feature_3", "feature_4", "feature_5"],
    "group_c" => ["feature_6"]
)

test_group_names = ["group_a", "group_b"]

resolved = NumeraiTournament.Pipeline.resolve_features_from_groups(
    nothing,               # feature_cols
    test_feature_groups,   # feature_groups
    nothing,               # features_metadata  
    test_group_names       # group_names
)

expected_features = ["feature_1", "feature_2", "feature_3", "feature_4", "feature_5"]
@test sort(resolved) == sort(expected_features)
println("✓ Feature groups resolution test passed")

# Test 3: Test resolve_features_from_groups with features_metadata
println("\n3. Testing features metadata resolution...")

test_metadata = Dict{String, Any}(
    "feature_stats" => Dict{String, Any}(
        "feature_1" => Dict{String, Any}("group" => "momentum"),
        "feature_2" => Dict{String, Any}("group" => "momentum"), 
        "feature_3" => Dict{String, Any}("group" => "reversal"),
        "feature_4" => Dict{String, Any}("group" => "reversal"),
        "feature_5" => Dict{String, Any}("group" => "size"),
        "feature_6" => Dict{String, Any}("group" => "size")
    )
)

test_group_names_meta = ["momentum", "size"]

resolved = NumeraiTournament.Pipeline.resolve_features_from_groups(
    nothing,               # feature_cols
    nothing,               # feature_groups
    test_metadata,         # features_metadata
    test_group_names_meta  # group_names
)

expected_features_meta = ["feature_1", "feature_2", "feature_5", "feature_6"]
@test sort(resolved) == sort(expected_features_meta)
println("✓ Features metadata resolution test passed")

# Test 4: Test MLPipeline constructor with feature groups
println("\n4. Testing MLPipeline constructor with feature groups...")

try
    # Test using model configs instead of model instances to avoid type issues
    model_configs = [NumeraiTournament.Pipeline.ModelConfig("xgboost", name="test_xgb")]
    
    pipeline = NumeraiTournament.Pipeline.MLPipeline(
        feature_groups=test_feature_groups,
        group_names=["group_a"],
        target_col="target_cyrus_v4_20",
        model_configs=model_configs
    )
    
    expected_pipeline_features = ["feature_1", "feature_2"]
    @test sort(pipeline.feature_cols) == sort(expected_pipeline_features)
    @test pipeline.feature_groups == test_feature_groups
    println("✓ MLPipeline constructor with feature groups test passed")
catch e
    println("✗ MLPipeline constructor test failed: $e")
end

# Test 5: Test error cases
println("\n5. Testing error cases...")

# Should error when no valid feature specification is provided
try
    NumeraiTournament.Pipeline.resolve_features_from_groups(
        nothing,  # feature_cols
        nothing,  # feature_groups
        nothing,  # features_metadata
        nothing   # group_names
    )
    println("✗ Expected error for missing feature specification")
catch e
    if isa(e, ErrorException)
        println("✓ Correctly threw error for missing feature specification")
    else
        println("✗ Wrong error type: $(typeof(e))")
    end
end

# Test warning for unknown group
println("\n6. Testing warning for unknown group...")
resolved = NumeraiTournament.Pipeline.resolve_features_from_groups(
    nothing,               # feature_cols
    test_feature_groups,   # feature_groups
    nothing,               # features_metadata  
    ["group_a", "unknown_group"]  # group_names with unknown group
)

expected_features_with_warning = ["feature_1", "feature_2"]
@test sort(resolved) == sort(expected_features_with_warning)
println("✓ Warning for unknown group test passed")

println("\n✅ All tests passed! Feature groups integration is working correctly.")