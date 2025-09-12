#!/usr/bin/env julia

"""
Basic Training Example

This example demonstrates how to:
1. Download tournament data
2. Train a simple XGBoost model
3. Generate predictions
4. Submit to the tournament

Prerequisites:
- Set NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY in .env file
- Have valid Numerai API credentials
"""

using Pkg
Pkg.activate(@__DIR__ * "/..")

using NumeraiTournament
using DataFrames
using CSV

# Initialize the tournament system
function main()
    println("🚀 Starting Numerai Tournament Basic Training Example")
    
    # Load configuration
    config = NumeraiTournament.load_config("config.toml")
    println("✅ Configuration loaded")
    
    # Create API client
    api_client = NumeraiTournament.API.create_client_from_env()
    println("✅ API client created")
    
    # Download training data if needed
    data_dir = get(config, "data_dir", "data")
    train_file = joinpath(data_dir, "train.parquet")
    
    if !isfile(train_file)
        println("📥 Downloading training data...")
        NumeraiTournament.API.download_dataset(api_client, "train", data_dir)
        println("✅ Training data downloaded")
    else
        println("✅ Training data already exists")
    end
    
    # Load training data
    println("📊 Loading training data...")
    train_data = NumeraiTournament.DataLoader.load_training_data(data_dir)
    println("✅ Loaded $(nrow(train_data)) training samples")
    
    # Create and configure ML pipeline
    println("🤖 Creating ML pipeline...")
    pipeline_config = Dict(
        :model_type => "xgboost",
        :model_params => Dict(
            :max_depth => 5,
            :eta => 0.1,
            :subsample => 0.8,
            :colsample_bytree => 0.8,
            :num_round => 100
        ),
        :features => "small",
        :target => "target",
        :neutralization_proportion => 0.5
    )
    
    pipeline = NumeraiTournament.Pipeline.MLPipeline(pipeline_config)
    println("✅ Pipeline created")
    
    # Train the model
    println("🏋️ Training model...")
    start_time = time()
    NumeraiTournament.Pipeline.train!(pipeline, train_data)
    training_time = time() - start_time
    println("✅ Model trained in $(round(training_time/60, digits=1)) minutes")
    
    # Evaluate on validation data
    val_file = joinpath(data_dir, "validation.parquet")
    if isfile(val_file)
        println("📈 Evaluating on validation data...")
        val_data = NumeraiTournament.DataLoader.load_validation_data(data_dir)
        metrics = NumeraiTournament.Pipeline.evaluate(pipeline, val_data)
        
        println("📊 Validation Metrics:")
        println("   Correlation: $(round(metrics[:correlation], digits=4))")
        println("   Sharpe: $(round(metrics[:sharpe], digits=2))")
        println("   Max Drawdown: $(round(metrics[:max_drawdown], digits=4))")
    end
    
    # Generate predictions for live data
    live_file = joinpath(data_dir, "live.parquet")
    if !isfile(live_file)
        println("📥 Downloading live data...")
        NumeraiTournament.API.download_dataset(api_client, "live", data_dir)
    end
    
    println("🔮 Generating predictions...")
    live_data = NumeraiTournament.DataLoader.load_live_data(data_dir)
    predictions = NumeraiTournament.Pipeline.predict(pipeline, live_data)
    println("✅ Generated $(length(predictions)) predictions")
    
    # Save predictions to CSV
    predictions_df = DataFrame(
        id = live_data.id,
        prediction = predictions
    )
    predictions_file = joinpath(data_dir, "predictions.csv")
    CSV.write(predictions_file, predictions_df)
    println("💾 Predictions saved to $predictions_file")
    
    # Optional: Submit predictions (uncomment to enable)
    # println("📤 Submitting predictions...")
    # model_name = get(config, "models", ["default_model"])[1]
    # submission_id = NumeraiTournament.API.submit_predictions(
    #     api_client,
    #     predictions_file,
    #     model_name
    # )
    # println("✅ Predictions submitted! ID: $submission_id")
    
    println("\n🎉 Example completed successfully!")
end

# Run the example
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end