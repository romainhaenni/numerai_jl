#!/usr/bin/env julia
"""
Example demonstrating True Contribution (TC) calculation in the Numerai Julia project.

TC (True Contribution) measures how much a model's predictions directly contribute 
to the fund's returns after accounting for the meta-model.
"""

using Pkg
Pkg.activate(".")

using NumeraiTournament
using NumeraiTournament.Metrics
using NumeraiTournament.Pipeline
using DataFrames
using Random
using Statistics

function create_example_data(n_samples=1000, n_features=20, n_models=4)
    """Create synthetic data for demonstration"""
    println("Creating synthetic data...")
    
    Random.seed!(42)
    
    # Create features
    X = randn(n_samples, n_features)
    
    # Create target with some correlation to features
    y = 0.3 * sum(X[:, 1:5], dims=2)[:, 1] + 0.7 * randn(n_samples)
    
    # Create eras (sequential groups)
    eras = repeat(1:div(n_samples, 20), inner=20)
    # Ensure eras vector has exactly n_samples elements
    if length(eras) > n_samples
        eras = eras[1:n_samples]
    elseif length(eras) < n_samples
        eras = vcat(eras, fill(eras[end], n_samples - length(eras)))
    end
    
    # Create DataFrame
    feature_names = ["feature_$i" for i in 1:n_features]
    df = DataFrame()
    for (i, name) in enumerate(feature_names)
        df[!, name] = X[:, i]
    end
    df[!, "target_cyrus_v4_20"] = y
    df[!, "era"] = eras
    df[!, "id"] = 1:n_samples
    
    return df, feature_names
end

function demonstrate_basic_tc()
    """Demonstrate basic TC calculation with synthetic data"""
    println("=== Basic TC Calculation Demo ===\n")
    
    # Create synthetic predictions and returns
    n_samples = 500
    Random.seed!(123)
    
    # Base signal that all models somewhat follow
    base_signal = randn(n_samples)
    
    # Create returns (targets)
    returns = 0.8 * base_signal + 0.2 * randn(n_samples)
    
    # Create meta-model predictions
    meta_model = 0.6 * base_signal + 0.4 * randn(n_samples)
    
    # Create individual model predictions with varying correlation to base signal
    model_1_preds = 0.7 * base_signal + 0.3 * randn(n_samples)
    model_2_preds = 0.5 * base_signal + 0.5 * randn(n_samples)
    model_3_preds = 0.9 * base_signal + 0.1 * randn(n_samples)
    
    # Calculate TC for each model
    tc_1 = Metrics.calculate_tc(model_1_preds, meta_model, returns)
    tc_2 = Metrics.calculate_tc(model_2_preds, meta_model, returns)
    tc_3 = Metrics.calculate_tc(model_3_preds, meta_model, returns)
    
    println("Individual TC scores:")
    println("  Model 1 TC: $(round(tc_1, digits=4))")
    println("  Model 2 TC: $(round(tc_2, digits=4))")
    println("  Model 3 TC: $(round(tc_3, digits=4))")
    
    # Calculate MMC for comparison
    mmc_1 = Metrics.calculate_mmc(model_1_preds, meta_model, returns)
    mmc_2 = Metrics.calculate_mmc(model_2_preds, meta_model, returns)
    mmc_3 = Metrics.calculate_mmc(model_3_preds, meta_model, returns)
    
    println("\nComparison with MMC:")
    println("  Model 1 - TC: $(round(tc_1, digits=4)), MMC: $(round(mmc_1, digits=4))")
    println("  Model 2 - TC: $(round(tc_2, digits=4)), MMC: $(round(mmc_2, digits=4))")
    println("  Model 3 - TC: $(round(tc_3, digits=4)), MMC: $(round(mmc_3, digits=4))")
    
    # Batch calculation
    predictions_matrix = hcat(model_1_preds, model_2_preds, model_3_preds)
    tc_batch = Metrics.calculate_tc_batch(predictions_matrix, meta_model, returns)
    
    println("\nBatch TC calculation:")
    for (i, tc) in enumerate(tc_batch)
        println("  Model $i TC: $(round(tc, digits=4))")
    end
    
    println()
end

function demonstrate_pipeline_tc()
    """Demonstrate TC calculation within ML pipeline"""
    println("=== Pipeline TC Calculation Demo ===\n")
    
    # Create data
    df, feature_names = create_example_data(800, 15, 3)
    
    # Split data
    train_df = df[1:600, :]
    val_df = df[601:end, :]
    
    println("Training ML pipeline...")
    
    # Create pipeline with fewer models for faster demo
    pipeline = Pipeline.MLPipeline(
        feature_cols=feature_names,
        target_col="target_cyrus_v4_20",
        neutralize=false  # Disable for simpler demo
    )
    
    # Train with reduced models for speed
    pipeline.models = pipeline.models[1:2]  # Use only first 2 models
    
    # Train pipeline
    Pipeline.train!(pipeline, train_df, val_df, verbose=false)
    
    println("Calculating ensemble metrics...")
    
    # Calculate TC scores for the ensemble
    tc_scores = Pipeline.calculate_ensemble_tc(pipeline, val_df)
    
    println("Individual model TC scores:")
    for (model_name, tc_score) in tc_scores
        println("  $model_name: $(round(tc_score, digits=4))")
    end
    
    # Enhanced evaluation with both MMC and TC
    results = Pipeline.evaluate_with_mmc(pipeline, val_df, metrics=[:corr, :mmc, :tc])
    
    println("\nEnsemble performance:")
    println("  Correlation: $(round(results[:corr], digits=4))")
    println("  Ensemble MMC: $(round(results[:ensemble_mmc], digits=4))")
    println("  Ensemble TC: $(round(results[:ensemble_tc], digits=4))")
    
    # Individual model contribution analysis
    model_name = pipeline.ensemble.models[1].name
    contribution = Pipeline.calculate_model_contribution(pipeline, val_df, model_name)
    
    println("\nDetailed contribution analysis for $model_name:")
    println("  Correlation: $(round(contribution[:correlation], digits=4))")
    println("  MMC: $(round(contribution[:mmc], digits=4))")
    println("  TC: $(round(contribution[:tc], digits=4))")
    println("  Contribution to ensemble: $(round(contribution[:contribution_to_ensemble], digits=4))")
    
    println()
end

function explain_tc_vs_mmc()
    """Explain the difference between TC and MMC"""
    println("=== Understanding TC vs MMC ===\n")
    
    println("Meta Model Contribution (MMC):")
    println("  • Measures how much a model contributes to the meta-model performance")
    println("  • Orthogonalizes model predictions against the meta-model")
    println("  • Calculates covariance with centered targets")
    println("  • Shows if model adds unique predictive power to the ensemble")
    println()
    
    println("True Contribution (TC):")
    println("  • Measures how much a model contributes to actual returns")
    println("  • Orthogonalizes returns against the meta-model")
    println("  • Calculates correlation between gaussianized predictions and orthogonalized returns")
    println("  • Shows if model contributes to returns beyond what meta-model captures")
    println()
    
    println("Key Differences:")
    println("  • MMC focuses on meta-model improvement")
    println("  • TC focuses on actual return contribution")
    println("  • TC uses returns orthogonalized against meta-model")
    println("  • Both are valuable for different aspects of model evaluation")
    println()
end

function main()
    """Main demonstration function"""
    println("🚀 True Contribution (TC) Calculation Demo")
    println("=" ^ 50)
    println()
    
    explain_tc_vs_mmc()
    demonstrate_basic_tc()
    demonstrate_pipeline_tc()
    
    println("✅ Demo completed successfully!")
    println("TC calculation is now integrated into the Numerai Julia project.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end