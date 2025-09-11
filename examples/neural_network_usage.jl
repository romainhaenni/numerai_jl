#!/usr/bin/env julia

"""
Neural Network Integration Example for Numerai Tournament

This example demonstrates how to use the newly integrated neural network models
alongside traditional ML models in the Numerai Tournament system.
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using NumeraiTournament
using DataFrames
using Random

# Set seed for reproducibility
Random.seed!(42)

println("🧠 Neural Network Integration Example")
println("====================================")

# Example 1: Creating individual neural network models
println("\n1. Creating Neural Network Models")
println("----------------------------------")

# Create an MLP model
mlp = NumeraiTournament.MLPModel("my_mlp",
    hidden_layers=[128, 64, 32],
    dropout_rate=0.3,
    learning_rate=0.001,
    epochs=50,
    gpu_enabled=false  # Disable for demo
)
println("✓ Created MLP model: $(mlp.name)")

# Create a ResNet model
resnet = NumeraiTournament.ResNetModel("my_resnet", 
    hidden_layers=[128, 128, 64],
    dropout_rate=0.1,
    epochs=75,
    gpu_enabled=false
)
println("✓ Created ResNet model: $(resnet.name)")

# TabNet model - REMOVED (implementation was incomplete)
# The TabNet model has been removed from the codebase as it was a simplified
# placeholder implementation. Full TabNet would require 3-4 weeks of development.
# tabnet = NumeraiTournament.TabNetModel("my_tabnet",
#     n_d=32,
#     n_a=32,
#     n_steps=3,
#     epochs=100,
#     gpu_enabled=false
# )
# println("✓ Created TabNet model: $(tabnet.name)")

# Example 2: Using ModelConfig to create models
println("\n2. Creating Models via ModelConfig")
println("-----------------------------------")

model_configs = [
    # Traditional ML models
    NumeraiTournament.Pipeline.ModelConfig("xgboost", 
        Dict(:max_depth=>6, :learning_rate=>0.01, :num_rounds=>100), 
        name="xgb_config"),
    
    # Neural network models
    NumeraiTournament.Pipeline.ModelConfig("mlp", 
        Dict(:hidden_layers=>[64, 32], :epochs=>25, :gpu_enabled=>false), 
        name="mlp_config"),
    NumeraiTournament.Pipeline.ModelConfig("resnet", 
        Dict(:hidden_layers=>[64, 64], :epochs=>30, :gpu_enabled=>false), 
        name="resnet_config"),
]

models = NumeraiTournament.Pipeline.create_models_from_configs(model_configs)
println("✓ Created $(length(models)) models from configs")
for model in models
    model_type = typeof(model)
    println("  - $(model.name): $model_type")
end

# Example 3: Creating a pipeline with mixed models
println("\n3. Creating Mixed Model Pipeline")
println("---------------------------------")

# Define feature columns (in real usage, these would match your data)
feature_cols = ["feature_$(i)" for i in 1:20]

# Create pipeline with default models (includes neural networks)
pipeline = NumeraiTournament.Pipeline.MLPipeline(
    feature_cols=feature_cols,
    target_col="target_cyrus_v4_20"
)

println("✓ Created pipeline with $(length(pipeline.models)) models:")
for (i, model) in enumerate(pipeline.models)
    model_type = typeof(model)
    neural_network = model isa NumeraiTournament.NeuralNetworkModel ? "🧠" : "🌳"
    println("  $i. $neural_network $(model.name): $model_type")
end

# Example 4: Creating a custom pipeline with specific neural network configs
println("\n4. Custom Pipeline with Neural Network Configs")
println("-----------------------------------------------")

custom_configs = [
    # Lightweight ensemble for quick testing
    NumeraiTournament.Pipeline.ModelConfig("xgboost", 
        Dict(:max_depth=>4, :learning_rate=>0.05, :num_rounds=>50), 
        name="xgb_light"),
    NumeraiTournament.Pipeline.ModelConfig("mlp", 
        Dict(:hidden_layers=>[32, 16], :epochs=>20, :gpu_enabled=>false), 
        name="mlp_light"),
    NumeraiTournament.Pipeline.ModelConfig("tabnet", 
        Dict(:n_d=>16, :n_a=>16, :n_steps=>2, :epochs=>25, :gpu_enabled=>false), 
        name="tabnet_light"),
]

custom_pipeline = NumeraiTournament.Pipeline.MLPipeline(
    feature_cols=feature_cols,
    target_col="target_cyrus_v4_20",
    model_configs=custom_configs,
    ensemble_type=:weighted
)

println("✓ Created custom pipeline with $(length(custom_pipeline.models)) models:")
for (i, model) in enumerate(custom_pipeline.models)
    model_type = typeof(model)
    neural_network = model isa NumeraiTournament.NeuralNetworkModel ? "🧠" : "🌳"
    println("  $i. $neural_network $(model.name): $model_type")
end

# Example 5: Ensemble with mixed models
println("\n5. Creating Mixed Model Ensemble")
println("---------------------------------")

mixed_models = [
    NumeraiTournament.XGBoostModel("ensemble_xgb", max_depth=5, num_rounds=50),
    NumeraiTournament.MLPModel("ensemble_mlp", 
        hidden_layers=[32, 16], epochs=15, gpu_enabled=false),
    NumeraiTournament.ResNetModel("ensemble_resnet", 
        hidden_layers=[32, 32], epochs=20, gpu_enabled=false)
]

ensemble = NumeraiTournament.Ensemble.ModelEnsemble(mixed_models, name="mixed_ensemble")
println("✓ Created ensemble with $(length(ensemble.models)) models:")
for (i, model) in enumerate(ensemble.models)
    weight = ensemble.weights[i]
    model_type = typeof(model)
    neural_network = model isa NumeraiTournament.NeuralNetworkModel ? "🧠" : "🌳"
    println("  $i. $neural_network $(model.name) (weight: $(round(weight, digits=3))): $model_type")
end

println("\n✅ Neural Network Integration Examples Complete!")
println("\nKey Features:")
println("• 🧠 Two neural network model types: MLP, ResNet (TabNet was removed)")
println("• 🔧 Full ModelConfig integration for flexible configuration") 
println("• 🤖 Seamless ensemble integration with traditional ML models")
println("• ⚡ GPU acceleration support (Metal on macOS, CUDA on Linux)")
println("• 🎯 Specialized loss functions for Numerai (correlation-based)")
println("• 📊 Compatible with existing pipeline, evaluation, and submission systems")

println("\nNext Steps:")
println("• Use config_neural_example.toml as a template for your configuration")
println("• Neural networks work with all existing pipeline functions (train!, predict, evaluate)")
println("• Models automatically handle feature standardization and GPU acceleration")
println("• Compatible with MMC, TC, and other Numerai-specific metrics")