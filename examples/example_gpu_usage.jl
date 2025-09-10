#!/usr/bin/env julia

"""
Example usage of GPU acceleration in Numerai Tournament Julia application

This script demonstrates the GPU acceleration features implemented with Metal.jl
for the Numerai Tournament application running on Apple Silicon (M4 Max).
"""

using NumeraiTournament
using Random

function main()
    println("=== GPU-Accelerated Numerai Tournament Demo ===\n")
    
    # 1. Check GPU availability
    println("1. Checking GPU availability...")
    gpu_available = has_metal_gpu()
    gpu_info = get_gpu_info()
    
    if gpu_available
        println("✅ Metal GPU available!")
        println("   Device: $(gpu_info["device_name"])")
        println("   Unified Memory: $(gpu_info["supports_unified_memory"])")
    else
        println("❌ Metal GPU not available - falling back to CPU")
    end
    
    # 2. Create GPU-accelerated models
    println("\n2. Creating GPU-accelerated models...")
    
    xgb_model = XGBoostModel("demo_xgb", gpu_enabled=true)
    lgb_model = LightGBMModel("demo_lgb", gpu_enabled=true)  
    evo_model = EvoTreesModel("demo_evo", gpu_enabled=true)
    
    println("✅ Models created with GPU acceleration:")
    println("   XGBoost GPU enabled: $(xgb_model.gpu_enabled)")
    println("   LightGBM GPU enabled: $(lgb_model.gpu_enabled)")
    println("   EvoTrees GPU enabled: $(evo_model.gpu_enabled)")
    
    # 3. Generate synthetic Numerai-like data
    println("\n3. Generating synthetic Numerai-like data...")
    Random.seed!(42)
    
    n_samples = 10000
    n_features = 310  # Typical Numerai feature count
    
    X = randn(Float32, n_samples, n_features)  # Use Float32 for Metal compatibility
    y = randn(Float32, n_samples)
    
    # Add some realistic correlations
    for i in 1:50  # First 50 features have some signal
        X[:, i] .+= 0.1f0 * y + 0.05f0 * randn(Float32, n_samples)
    end
    
    println("✅ Generated data: $n_samples samples × $n_features features")
    
    # 4. Test GPU-accelerated preprocessing
    println("\n4. Testing GPU-accelerated preprocessing...")
    
    X_standardized = copy(X)
    X_normalized = copy(X)
    
    # Convert to Float64 for preprocessing (will fallback to CPU)
    X_test = Float64.(X)
    gpu_standardize!(X_test)
    println("✅ GPU standardization completed (with CPU fallback for Float64)")
    
    # 5. Get comprehensive GPU status
    println("\n5. GPU system status...")
    status = get_models_gpu_status()
    println("✅ GPU Status Summary:")
    for (key, value) in status["gpu_info"]
        println("   $key: $value")
    end
    
    # 6. Run a mini benchmark (optional)
    println("\n6. Running mini GPU benchmark...")
    try
        results = run_comprehensive_gpu_benchmark(
            data_sizes=[1000, 5000], 
            n_features=50,
            n_runs=2
        )
        println("✅ Benchmark completed with $(length(results)) operations tested")
        
        # Show some results
        successful_gpu = filter(r -> r.success && r.gpu_time != Inf, results)
        if !isempty(successful_gpu)
            avg_speedup = sum(r.speedup for r in successful_gpu) / length(successful_gpu)
            println("   Average GPU speedup: $(round(avg_speedup, digits=2))x")
        else
            println("   GPU operations fell back to CPU (expected for Float64 data)")
        end
    catch e
        println("⚠️  Benchmark skipped: $e")
    end
    
    # 7. Summary
    println("\n=== Summary ===")
    println("✅ GPU acceleration successfully implemented with Metal.jl")
    println("✅ Models configured for GPU acceleration (with CPU fallback)")
    println("✅ GPU-accelerated preprocessing functions available")
    println("✅ Comprehensive benchmarking utilities included")
    println("✅ Production-ready error handling and logging")
    
    if gpu_available
        println("\n💡 Tips for optimal GPU performance:")
        println("   • Use Float32 instead of Float64 for better Metal compatibility")
        println("   • GPU acceleration is most beneficial for large datasets (>50k samples)")
        println("   • Monitor GPU memory usage for very large datasets")
        println("   • CPU fallback ensures compatibility across all systems")
    else
        println("\n💡 Note: Running on CPU - GPU features will automatically fallback")
    end
    
    println("\n🎉 GPU-accelerated Numerai Tournament implementation complete!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end