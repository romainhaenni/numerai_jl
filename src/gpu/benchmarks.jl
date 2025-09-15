module GPUBenchmarks

using DataFrames
using Random
using Statistics
using Logging
using LoggingExtras
using Printf
using Dates
using CSV

# Use Metal acceleration module (already loaded by main module)
using ..MetalAcceleration

export run_comprehensive_gpu_benchmark, generate_benchmark_report
export benchmark_data_preprocessing, benchmark_model_operations
export BenchmarkResult, save_benchmark_results, load_benchmark_results

"""
Structure to hold benchmark results
"""
struct BenchmarkResult
    operation::String
    data_size::Int
    cpu_time::Float64
    gpu_time::Float64
    speedup::Float64
    memory_used::Int64
    success::Bool
    error_message::Union{String, Nothing}
    timestamp::String
end

"""
Run comprehensive GPU benchmark suite for Numerai Tournament
"""
function run_comprehensive_gpu_benchmark(; 
    data_sizes::Vector{Int} = [1000, 5000, 10000, 25000, 50000],
    n_features::Int = 310,  # Typical Numerai feature count
    n_runs::Int = 3,
    save_results::Bool = true,
    output_dir::String = "benchmarks"
)::Vector{BenchmarkResult}
    
    @info "Starting comprehensive GPU benchmark suite" data_sizes=data_sizes n_features=n_features n_runs=n_runs
    
    results = BenchmarkResult[]
    
    # Initialize GPU system
    gpu_info = get_gpu_info()
    @info "GPU Information" gpu_info=gpu_info
    
    if save_results && !isdir(output_dir)
        mkdir(output_dir)
    end
    
    for data_size in data_sizes
        @info "Benchmarking data size: $data_size"
        
        # Generate synthetic Numerai-like data
        Random.seed!(42)
        X = randn(Float64, data_size, n_features)
        y = randn(Float64, data_size)
        
        # Add some realistic correlations and noise
        for i in 1:min(50, n_features)  # First 50 features have some signal
            X[:, i] .+= 0.1 * y + 0.05 * randn(data_size)
        end
        
        # Benchmark different operations
        append!(results, benchmark_data_preprocessing(X, y, n_runs))
        append!(results, benchmark_matrix_operations(X, n_runs))
        append!(results, benchmark_feature_engineering(X, n_runs))
        append!(results, benchmark_statistical_operations(X, y, n_runs))
    end
    
    # Generate summary report
    if save_results
        report_path = joinpath(output_dir, "gpu_benchmark_report_$(Dates.format(now(), "yyyymmdd_HHMMSS")).md")
        generate_benchmark_report(results, report_path)
    end
    
    @info "Benchmark suite completed" total_operations=length(results)
    
    return results
end

"""
Benchmark data preprocessing operations
"""
function benchmark_data_preprocessing(X::Matrix{Float64}, y::Vector{Float64}, n_runs::Int)::Vector{BenchmarkResult}
    results = BenchmarkResult[]
    data_size, n_features = size(X)
    timestamp = string(now())
    
    @info "Benchmarking data preprocessing operations" data_size=data_size n_features=n_features
    
    # Standardization benchmark
    cpu_times = Float64[]
    gpu_times = Float64[]
    
    for run in 1:n_runs
        X_test = copy(X)
        cpu_time = @elapsed begin
            for j in 1:size(X_test, 2)
                col = view(X_test, :, j)
                μ = mean(col)
                σ = std(col)
                if σ > 0
                    col .= (col .- μ) ./ σ
                end
            end
        end
        push!(cpu_times, cpu_time)
        
        if has_metal_gpu()
            X_test = copy(X)
            gpu_time = @elapsed gpu_standardize!(X_test)
            push!(gpu_times, gpu_time)
        end
    end
    
    cpu_mean = mean(cpu_times)
    gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
    speedup = cpu_mean / gpu_mean
    
    push!(results, BenchmarkResult(
        "Standardization",
        data_size,
        cpu_mean,
        gpu_mean,
        speedup,
        sizeof(X),
        true,
        nothing,
        timestamp
    ))
    
    # Normalization benchmark
    cpu_times = Float64[]
    gpu_times = Float64[]
    
    for run in 1:n_runs
        X_test = copy(X)
        cpu_time = @elapsed begin
            for j in 1:size(X_test, 2)
                col = view(X_test, :, j)
                min_val = minimum(col)
                max_val = maximum(col)
                if max_val > min_val
                    col .= (col .- min_val) ./ (max_val - min_val)
                end
            end
        end
        push!(cpu_times, cpu_time)
        
        if has_metal_gpu()
            X_test = copy(X)
            gpu_time = @elapsed gpu_normalize!(X_test)
            push!(gpu_times, gpu_time)
        end
    end
    
    cpu_mean = mean(cpu_times)
    gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
    speedup = cpu_mean / gpu_mean
    
    push!(results, BenchmarkResult(
        "Normalization",
        data_size,
        cpu_mean,
        gpu_mean,
        speedup,
        sizeof(X),
        true,
        nothing,
        timestamp
    ))
    
    return results
end

"""
Benchmark matrix operations
"""
function benchmark_matrix_operations(X::Matrix{Float64}, n_runs::Int)::Vector{BenchmarkResult}
    results = BenchmarkResult[]
    data_size, n_features = size(X)
    timestamp = string(now())
    
    @info "Benchmarking matrix operations" data_size=data_size n_features=n_features
    
    # Create test matrices
    A = randn(Float64, n_features, n_features)
    B = randn(Float64, n_features, min(100, n_features))
    
    # Matrix multiplication benchmark
    cpu_times = Float64[]
    gpu_times = Float64[]
    
    for run in 1:n_runs
        cpu_time = @elapsed result_cpu = X * A
        push!(cpu_times, cpu_time)
        
        if has_metal_gpu()
            gpu_time = @elapsed result_gpu = gpu_matrix_multiply(X, A)
            push!(gpu_times, gpu_time)
        end
    end
    
    cpu_mean = mean(cpu_times)
    gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
    speedup = cpu_mean / gpu_mean
    
    push!(results, BenchmarkResult(
        "Matrix Multiplication",
        data_size,
        cpu_mean,
        gpu_mean,
        speedup,
        sizeof(X) + sizeof(A),
        true,
        nothing,
        timestamp
    ))
    
    # Transpose operation
    cpu_times = Float64[]
    gpu_times = Float64[]
    
    for run in 1:n_runs
        cpu_time = @elapsed result_cpu = transpose(X)
        push!(cpu_times, cpu_time)
        
        if has_metal_gpu()
            gpu_time = @elapsed begin
                X_gpu = gpu(X)
                result_gpu = cpu(transpose(X_gpu))
            end
            push!(gpu_times, gpu_time)
        end
    end
    
    cpu_mean = mean(cpu_times)
    gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
    speedup = cpu_mean / gpu_mean
    
    push!(results, BenchmarkResult(
        "Matrix Transpose",
        data_size,
        cpu_mean,
        gpu_mean,
        speedup,
        sizeof(X),
        true,
        nothing,
        timestamp
    ))
    
    return results
end

"""
Benchmark feature engineering operations
"""
function benchmark_feature_engineering(X::Matrix{Float64}, n_runs::Int)::Vector{BenchmarkResult}
    results = BenchmarkResult[]
    data_size, n_features = size(X)
    timestamp = string(now())
    
    @info "Benchmarking feature engineering operations" data_size=data_size n_features=n_features
    
    operations = [:square, :sqrt, :log]
    
    for operation in operations
        cpu_times = Float64[]
        gpu_times = Float64[]
        
        for run in 1:n_runs
            # CPU benchmark
            cpu_time = @elapsed begin
                if operation == :square
                    result_cpu = X .^ 2
                elseif operation == :sqrt
                    result_cpu = sqrt.(abs.(X))
                elseif operation == :log
                    result_cpu = log.(abs.(X) .+ 1e-8)
                end
            end
            push!(cpu_times, cpu_time)
            
            # GPU benchmark
            if has_metal_gpu()
                gpu_time = @elapsed result_gpu = gpu_feature_engineering(X, [operation])
                push!(gpu_times, gpu_time)
            end
        end
        
        cpu_mean = mean(cpu_times)
        gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
        speedup = cpu_mean / gpu_mean
        
        push!(results, BenchmarkResult(
            "Feature Engineering ($operation)",
            data_size,
            cpu_mean,
            gpu_mean,
            speedup,
            sizeof(X) * 2,  # Original + transformed features
            true,
            nothing,
            timestamp
        ))
    end
    
    return results
end

"""
Benchmark statistical operations
"""
function benchmark_statistical_operations(X::Matrix{Float64}, y::Vector{Float64}, n_runs::Int)::Vector{BenchmarkResult}
    results = BenchmarkResult[]
    data_size, n_features = size(X)
    timestamp = string(now())
    
    @info "Benchmarking statistical operations" data_size=data_size n_features=n_features
    
    # Correlation computation benchmark
    cpu_times = Float64[]
    gpu_times = Float64[]
    
    # Use first feature for correlation test
    feature = X[:, 1]
    
    for run in 1:n_runs
        cpu_time = @elapsed correlation_cpu = cor(feature, y)
        push!(cpu_times, cpu_time)
        
        if has_metal_gpu()
            gpu_time = @elapsed correlation_gpu = gpu_compute_correlations(feature, y)
            push!(gpu_times, gpu_time)
        end
    end
    
    cpu_mean = mean(cpu_times)
    gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
    speedup = cpu_mean / gpu_mean
    
    push!(results, BenchmarkResult(
        "Correlation Computation",
        data_size,
        cpu_mean,
        gpu_mean,
        speedup,
        sizeof(feature) + sizeof(y),
        true,
        nothing,
        timestamp
    ))
    
    # Feature selection benchmark (smaller subset for performance)
    if n_features >= 100 && data_size <= 10000  # Only for reasonable sizes
        k_features = min(50, n_features ÷ 2)
        cpu_times = Float64[]
        gpu_times = Float64[]
        
        for run in 1:n_runs
            cpu_time = @elapsed begin
                correlations = Vector{Float64}(undef, n_features)
                for i in 1:n_features
                    correlations[i] = abs(cor(X[:, i], y))
                end
                top_indices = sortperm(correlations, rev=true)[1:k_features]
            end
            push!(cpu_times, cpu_time)
            
            if has_metal_gpu()
                gpu_time = @elapsed top_indices_gpu = gpu_feature_selection(X, y, k_features)
                push!(gpu_times, gpu_time)
            end
        end
        
        cpu_mean = mean(cpu_times)
        gpu_mean = has_metal_gpu() ? mean(gpu_times) : Inf
        speedup = cpu_mean / gpu_mean
        
        push!(results, BenchmarkResult(
            "Feature Selection (k=$k_features)",
            data_size,
            cpu_mean,
            gpu_mean,
            speedup,
            sizeof(X) + sizeof(y),
            true,
            nothing,
            timestamp
        ))
    end
    
    return results
end

"""
Generate comprehensive benchmark report
"""
function generate_benchmark_report(results::Vector{BenchmarkResult}, output_path::String)
    @info "Generating benchmark report" output_path=output_path
    
    open(output_path, "w") do f
        println(f, "# GPU Acceleration Benchmark Report")
        println(f, "Generated: $(now())")
        println(f, "")
        
        # System information
        gpu_info = get_gpu_info()
        memory_info = gpu_memory_info()
        
        println(f, "## System Information")
        println(f, "- GPU Available: $(gpu_info["available"])")
        if gpu_info["available"]
            println(f, "- Device: $(gpu_info["device_name"])")
            println(f, "- Total Memory: $(gpu_info["memory_total"] ÷ (1024^3)) GB")
            println(f, "- Free Memory: $(gpu_info["memory_free"] ÷ (1024^3)) GB")
            println(f, "- Unified Memory: $(gpu_info["supports_unified_memory"])")
        end
        println(f, "")
        
        # Summary statistics
        successful_results = filter(r -> r.success && r.gpu_time != Inf, results)
        
        if !isempty(successful_results)
            avg_speedup = mean([r.speedup for r in successful_results])
            max_speedup = maximum([r.speedup for r in successful_results])
            min_speedup = minimum([r.speedup for r in successful_results])
            
            println(f, "## Performance Summary")
            println(f, "- Average Speedup: $(round(avg_speedup, digits=2))x")
            println(f, "- Maximum Speedup: $(round(max_speedup, digits=2))x")
            println(f, "- Minimum Speedup: $(round(min_speedup, digits=2))x")
            println(f, "- Total Benchmarks: $(length(results))")
            println(f, "- Successful GPU Benchmarks: $(length(successful_results))")
            println(f, "")
        end
        
        # Detailed results table
        println(f, "## Detailed Results")
        println(f, "")
        println(f, "| Operation | Data Size | CPU Time (s) | GPU Time (s) | Speedup | Memory (MB) |")
        println(f, "|-----------|-----------|--------------|--------------|---------|-------------|")
        
        for result in results
            memory_mb = result.memory_used ÷ (1024^2)
            cpu_time_str = @sprintf("%.4f", result.cpu_time)
            gpu_time_str = result.gpu_time == Inf ? "N/A" : @sprintf("%.4f", result.gpu_time)
            speedup_str = result.gpu_time == Inf ? "N/A" : @sprintf("%.2f", result.speedup)
            
            println(f, "| $(result.operation) | $(result.data_size) | $(cpu_time_str) | $(gpu_time_str) | $(speedup_str)x | $(memory_mb) |")
        end
        
        println(f, "")
        
        # Performance by operation type
        operations = unique([r.operation for r in results])
        
        println(f, "## Performance by Operation Type")
        println(f, "")
        
        for operation in operations
            op_results = filter(r -> r.operation == operation && r.success && r.gpu_time != Inf, results)
            if !isempty(op_results)
                avg_speedup = mean([r.speedup for r in op_results])
                println(f, "### $operation")
                println(f, "- Average Speedup: $(round(avg_speedup, digits=2))x")
                println(f, "- Benchmarks: $(length(op_results))")
                println(f, "")
            end
        end
        
        # Recommendations
        println(f, "## Recommendations")
        println(f, "")
        
        if gpu_info["available"]
            best_operations = filter(r -> r.success && r.speedup > 1.5, successful_results)
            if !isempty(best_operations)
                println(f, "✅ **GPU acceleration is beneficial for:**")
                for op in unique([r.operation for r in best_operations])
                    avg_speedup = mean([r.speedup for r in filter(r -> r.operation == op, best_operations)])
                    println(f, "- $op ($(round(avg_speedup, digits=2))x speedup)")
                end
                println(f, "")
            end
            
            poor_operations = filter(r -> r.success && r.speedup < 1.2, successful_results)
            if !isempty(poor_operations)
                println(f, "⚠️ **Limited GPU benefit for:**")
                for op in unique([r.operation for r in poor_operations])
                    avg_speedup = mean([r.speedup for r in filter(r -> r.operation == op, poor_operations)])
                    println(f, "- $op ($(round(avg_speedup, digits=2))x speedup)")
                end
                println(f, "")
            end
        else
            println(f, "❌ GPU acceleration not available on this system.")
            println(f, "")
        end
        
        println(f, "## Configuration Suggestions")
        println(f, "")
        println(f, "Based on these benchmarks:")
        println(f, "- Enable GPU acceleration for operations with >2x speedup")
        println(f, "- Use CPU fallback for operations with <1.5x speedup")
        println(f, "- Consider hybrid CPU/GPU approach for mixed workloads")
        println(f, "")
    end
    
    @info "Benchmark report generated" path=output_path
end

"""
Save benchmark results to file
"""
function save_benchmark_results(results::Vector{BenchmarkResult}, filepath::String)
    @info "Saving benchmark results" filepath=filepath
    
    # Convert to DataFrame for easy saving
    df = DataFrame(
        operation = [r.operation for r in results],
        data_size = [r.data_size for r in results],
        cpu_time = [r.cpu_time for r in results],
        gpu_time = [r.gpu_time for r in results],
        speedup = [r.speedup for r in results],
        memory_used = [r.memory_used for r in results],
        success = [r.success for r in results],
        error_message = [r.error_message for r in results],
        timestamp = [r.timestamp for r in results]
    )
    
    CSV.write(filepath, df)
    @info "Results saved successfully"
end

"""
Load benchmark results from file
"""
function load_benchmark_results(filepath::String)::Vector{BenchmarkResult}
    @info "Loading benchmark results" filepath=filepath
    
    df = CSV.read(filepath, DataFrame)
    
    results = BenchmarkResult[]
    for row in eachrow(df)
        push!(results, BenchmarkResult(
            row.operation,
            row.data_size,
            row.cpu_time,
            row.gpu_time,
            row.speedup,
            row.memory_used,
            row.success,
            ismissing(row.error_message) ? nothing : row.error_message,
            row.timestamp
        ))
    end
    
    @info "Results loaded successfully" count=length(results)
    return results
end

end  # module GPUBenchmarks