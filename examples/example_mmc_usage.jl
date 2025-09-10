#!/usr/bin/env julia

"""
Example script demonstrating MMC (Meta Model Contribution) calculation usage

This script shows how to use the new MMC calculation functionality
that has been added to the Numerai Julia project.
"""

using DataFrames
using Random
using Statistics
using NumeraiTournament

# Set seed for reproducible results
Random.seed!(42)

println("🚀 MMC (Meta Model Contribution) Calculation Demo")
println("=" ^ 50)

# Create synthetic tournament data
println("\n📊 Creating synthetic tournament data...")
n_samples = 1000
n_features = 20
n_eras = 10

# Generate features
X = randn(n_samples, n_features)

# Generate targets with some signal
targets = 0.3 * sum(X[:, 1:5], dims=2)[:, 1] + 0.7 * randn(n_samples)

# Create eras
eras = repeat(1:n_eras, inner=div(n_samples, n_eras))

# Create feature names
feature_names = ["feature_$i" for i in 1:n_features]

# Create DataFrame
df = DataFrame()
for (i, name) in enumerate(feature_names)
    df[!, name] = X[:, i]
end
df[!, "target_cyrus_v4_20"] = targets
df[!, "era"] = eras
df[!, "id"] = 1:n_samples

println("✅ Created dataset with $n_samples samples, $n_features features, $n_eras eras")

# Split data for training and validation
train_mask = df.era .<= 7
val_mask = df.era .> 7

train_df = df[train_mask, :]
val_df = df[val_mask, :]

println("📈 Training set: $(nrow(train_df)) samples")
println("📊 Validation set: $(nrow(val_df)) samples")

# Create and train pipeline
println("\n🤖 Training ensemble models...")
pipeline = NumeraiTournament.Pipeline.MLPipeline(
    feature_cols=feature_names,
    target_col="target_cyrus_v4_20",
    neutralize=false  # Disable neutralization for cleaner MMC demonstration
)

# Train the pipeline
NumeraiTournament.Pipeline.train!(pipeline, train_df, val_df, verbose=false)

println("✅ Training completed!")

# Demonstrate MMC calculation
println("\n📐 Calculating MMC scores...")

# Get standard evaluation metrics
standard_results = NumeraiTournament.Pipeline.evaluate(pipeline, val_df)
println("\n🎯 Standard Evaluation Metrics:")
for (metric, value) in standard_results
    println("   $metric: $(round(value, digits=4))")
end

# Get evaluation with MMC
mmc_results = NumeraiTournament.Pipeline.evaluate_with_mmc(pipeline, val_df)
println("\n🧮 MMC Evaluation Results:")
for (metric, value) in mmc_results
    if metric == :mmc
        println("   MMC scores by model:")
        for (model_name, mmc_score) in value
            println("     $model_name: $(round(mmc_score, digits=6))")
        end
    else
        println("   $metric: $(round(value, digits=4))")
    end
end

# Demonstrate individual model contribution analysis
println("\n🔍 Individual Model Contribution Analysis:")
model_names = [m.name for m in pipeline.ensemble.models]

for model_name in model_names[1:2]  # Analyze first two models
    contribution = NumeraiTournament.Pipeline.calculate_model_contribution(pipeline, val_df, model_name)
    println("\n   Model: $model_name")
    for (metric, value) in contribution
        println("     $metric: $(round(value, digits=6))")
    end
end

# Demonstrate direct MMC calculation with custom stakes
println("\n⚖️ Custom Stake-Weighted MMC Analysis:")

# Get individual model predictions
individual_preds = NumeraiTournament.Pipeline.predict_individual_models(pipeline, val_df)
_, y_val, _ = NumeraiTournament.Pipeline.prepare_data(pipeline, val_df)

# Create custom stakes (e.g., simulate different staking strategies)
n_models = size(individual_preds, 2)
custom_stakes = [0.5, 0.3, 0.15, 0.05]  # Weighted towards first model

if length(custom_stakes) >= n_models
    custom_stakes = custom_stakes[1:n_models]
else
    # Pad with equal weights if needed
    remaining = 1.0 - sum(custom_stakes)
    for i in (length(custom_stakes)+1):n_models
        push!(custom_stakes, remaining / (n_models - length(custom_stakes)))
    end
end

# Create custom meta-model
custom_meta_model = NumeraiTournament.Metrics.create_stake_weighted_ensemble(individual_preds, custom_stakes)

# Calculate MMC for each model against custom meta-model
println("   With custom stakes: $custom_stakes")
for i in 1:n_models
    model_name = pipeline.ensemble.models[i].name
    mmc_score = NumeraiTournament.Metrics.calculate_mmc(individual_preds[:, i], custom_meta_model, y_val)
    println("   $model_name MMC: $(round(mmc_score, digits=6))")
end

# Demonstrate low-level MMC functions
println("\n🔧 Low-level MMC Function Demonstrations:")

# Create simple example data
simple_targets = [1.0, 2.0, 3.0, 4.0, 5.0]
simple_predictions = [1.1, 1.9, 3.2, 3.8, 5.1]  # Noisy but correlated
simple_meta_model = [0.8, 1.8, 2.7, 3.9, 4.9]   # Different but also correlated

# Demonstrate tie-kept ranking
ranks = NumeraiTournament.Metrics.tie_kept_rank(simple_predictions)
println("   Tie-kept ranks: $ranks")

# Demonstrate gaussianization
gauss_preds = NumeraiTournament.Metrics.gaussianize(simple_predictions)
println("   Gaussianized predictions: $(round.(gauss_preds, digits=3))")

# Demonstrate orthogonalization
ortho_preds = NumeraiTournament.Metrics.orthogonalize(simple_predictions, simple_meta_model)
println("   Orthogonalized predictions: $(round.(ortho_preds, digits=3))")

# Calculate final MMC
mmc_simple = NumeraiTournament.Metrics.calculate_mmc(simple_predictions, simple_meta_model, simple_targets)
println("   Final MMC score: $(round(mmc_simple, digits=6))")

println("\n🎉 MMC demonstration completed!")
println("\n📚 Key Takeaways:")
println("   • MMC measures how much a model contributes uniquely to the meta-model")
println("   • Positive MMC indicates the model adds value beyond existing predictions")
println("   • Negative MMC suggests the model may be harmful to the ensemble")
println("   • MMC accounts for both correlation with targets AND orthogonality to meta-model")
println("   • The implementation follows Numerai's official algorithm specification")

println("\n💡 Usage Tips:")
println("   • Use evaluate_with_mmc() for comprehensive pipeline evaluation")
println("   • Use calculate_model_contribution() to analyze individual model value")
println("   • Use custom stakes to simulate different meta-model compositions")
println("   • MMC is most meaningful when calculated on out-of-sample data")