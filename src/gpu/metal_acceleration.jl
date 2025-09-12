module MetalAcceleration

using Metal
using LinearAlgebra
using Statistics
using DataFrames
using Random
using Logging
using LoggingExtras
using Printf

# Core GPU functionality
export MetalDevice, GPUArray, cpu, gpu
export has_metal_gpu, get_gpu_info, configure_metal_device
export gpu_memory_info, gpu_memory_status, clear_gpu_cache!, gpu_synchronize

# GPU-accelerated operations
export gpu_matrix_multiply, gpu_vector_add, gpu_element_wise_ops
export gpu_standardize!, gpu_normalize!, gpu_feature_engineering

# ML-specific acceleration
export gpu_compute_correlations
export gpu_feature_selection, gpu_ensemble_predictions

# Benchmarking utilities
export GPUBenchmark, benchmark_gpu_operations, compare_cpu_gpu_performance

# Fallback mechanisms
export with_gpu_fallback, @gpu_fallback

"""
GPU device management and configuration
"""
mutable struct MetalDevice
    device::Union{Nothing, Any}  # Use Any instead of MTLDevice for compatibility
    is_available::Bool
    memory_total::Int64
    memory_free::Int64
    compute_units::Int
    max_threads_per_group::Int
    supports_unified_memory::Bool
end

# Global device instance
const METAL_DEVICE = Ref{Union{Nothing, MetalDevice}}(nothing)

"""
Check if Metal GPU is available on the current system
"""
function has_metal_gpu()::Bool
    try
        return Metal.functional()
    catch
        return false
    end
end

"""
Initialize and configure Metal device
"""
function configure_metal_device()::MetalDevice
    if METAL_DEVICE[] !== nothing
        return METAL_DEVICE[]
    end
    
    if !has_metal_gpu()
        @warn "Metal GPU not available, falling back to CPU operations"
        return MetalDevice(nothing, false, 0, 0, 0, 0, false)
    end
    
    try
        device = Metal.device()
        
        # Get system memory as proxy for unified memory
        # Apple Silicon shares memory between CPU and GPU
        total_memory_gb = Sys.total_memory() / (1024^3)
        
        # Estimate GPU-available memory (typically ~75% of system memory on Apple Silicon)
        gpu_memory_bytes = round(Int, Sys.total_memory() * 0.75)
        
        # Estimate free memory based on current system state
        # This is an approximation since Metal doesn't expose direct memory queries
        free_memory_bytes = round(Int, Sys.free_memory() * 0.75)
        
        # Apple Silicon GPU compute units (typical values)
        # M1: 7-8 cores, M1 Pro: 14-16, M1 Max: 24-32, M2 series similar
        # We'll use a conservative estimate
        compute_units = 16  # Reasonable default for M-series chips
        
        # Maximum threads per threadgroup (typical for Apple Silicon)
        max_threads = 1024
        
        metal_device = MetalDevice(
            device,
            true,
            gpu_memory_bytes,
            free_memory_bytes,
            compute_units,
            max_threads,
            true  # Apple Silicon supports unified memory
        )
        
        METAL_DEVICE[] = metal_device
        @info "Metal GPU configured successfully"
        
        return metal_device
    catch e
        @error "Failed to configure Metal device" exception=e
        return MetalDevice(nothing, false, 0, 0, 0, 0, false)
    end
end

"""
Get GPU device information
"""
function get_gpu_info()::Dict{String, Any}
    device = configure_metal_device()
    
    if !device.is_available
        return Dict("available" => false, "reason" => "Metal GPU not available")
    end
    
    try
        # Get current memory state
        memory_used = device.memory_total - device.memory_free
        memory_gb = device.memory_total / (1024^3)
        
        # Determine GPU model based on compute units
        gpu_name = if device.compute_units <= 8
            "Apple M1 GPU"
        elseif device.compute_units <= 16
            "Apple M1 Pro/M2 GPU"
        elseif device.compute_units <= 32
            "Apple M1 Max/M2 Max GPU"
        else
            "Apple M-series Ultra GPU"
        end
        
        return Dict(
            "available" => true,
            "device_name" => gpu_name,
            "memory_total" => device.memory_total,
            "memory_free" => device.memory_free,
            "memory_used" => memory_used,
            "memory_gb" => memory_gb,
            "compute_units" => device.compute_units,
            "max_threads_per_group" => device.max_threads_per_group,
            "supports_unified_memory" => device.supports_unified_memory
        )
    catch e
        @error "Failed to get GPU info" exception=e
        return Dict("available" => false, "error" => string(e))
    end
end

"""
Get current GPU memory information

Returns a dictionary with:
- total: Total GPU memory available (recommended working set)
- used: Currently allocated GPU memory
- free: Available GPU memory
"""
function gpu_memory_info()::Dict{String, Int64}
    if !has_metal_gpu()
        return Dict("total" => 0, "free" => 0, "used" => 0)
    end
    
    try
        device = Metal.current_device()
        
        # Get memory information from Metal device
        total_memory = Int64(device.recommendedMaxWorkingSetSize)
        used_memory = Int64(device.currentAllocatedSize)
        free_memory = max(0, total_memory - used_memory)
        
        return Dict(
            "total" => total_memory,
            "used" => used_memory,
            "free" => free_memory
        )
    catch e
        @error "Failed to get GPU memory info" exception=e
        return Dict("total" => 0, "free" => 0, "used" => 0)
    end
end

"""
Get formatted GPU memory information string

Returns a human-readable string with memory usage information.
"""
function gpu_memory_status()::String
    info = gpu_memory_info()
    
    if info["total"] == 0
        return "GPU memory not available"
    end
    
    # Convert bytes to GB for readability
    total_gb = info["total"] / (1024^3)
    used_gb = info["used"] / (1024^3)
    free_gb = info["free"] / (1024^3)
    usage_percent = (info["used"] / info["total"]) * 100
    
    return @sprintf("GPU Memory: %.2f/%.2f GB used (%.1f%%), %.2f GB free", 
                    used_gb, total_gb, usage_percent, free_gb)
end

"""
Clear GPU memory cache
"""
function clear_gpu_cache!()
    if has_metal_gpu()
        try
            # Use GC to reclaim memory and synchronize GPU operations
            Metal.synchronize()
            GC.gc(true)
            @info "GPU memory cache cleared"
        catch e
            @warn "Failed to clear GPU cache" exception=e
        end
    end
end

"""
Synchronize GPU operations
"""
function gpu_synchronize()
    if has_metal_gpu()
        try
            Metal.synchronize()
        catch e
            @warn "Failed to synchronize GPU" exception=e
        end
    end
end

"""
Convert array to GPU if available, otherwise return original
Automatically converts Float64 to Float32 for Metal compatibility
"""
function gpu(x::AbstractArray{Float64})
    if has_metal_gpu()
        try
            # Convert Float64 to Float32 for Metal compatibility
            x_f32 = Float32.(x)
            return MtlArray(x_f32)
        catch e
            @warn "Failed to transfer Float64 array to GPU, using CPU" exception=e
            return x
        end
    else
        return x
    end
end

function gpu(x::AbstractArray{Float32})
    if has_metal_gpu()
        try
            return MtlArray(x)
        catch e
            @warn "Failed to transfer Float32 array to GPU, using CPU" exception=e
            return x
        end
    else
        return x
    end
end

function gpu(x::AbstractArray{T}) where T
    if has_metal_gpu()
        try
            # For other numeric types, attempt direct conversion
            if T <: Real
                # Try to convert to Float32 for Metal compatibility
                x_f32 = Float32.(x)
                return MtlArray(x_f32)
            else
                # For non-numeric types, attempt direct transfer
                return MtlArray(x)
            end
        catch e
            @warn "Failed to transfer $(T) array to GPU, using CPU" exception=e
            return x
        end
    else
        return x
    end
end

"""
Convert array to CPU
Converts Float32 GPU arrays back to Float64 for consistency with CPU operations
"""
function cpu(x::MtlArray{Float32})
    try
        # Convert back to Float64 for consistency with CPU operations
        cpu_array = Array(x)
        return Float64.(cpu_array)
    catch e
        @warn "Failed to transfer Float32 array from GPU to CPU" exception=e
        return x
    end
end

function cpu(x::MtlArray{T}) where T
    try
        return Array(x)
    catch e
        @warn "Failed to transfer $(T) array from GPU to CPU" exception=e
        return x
    end
end

function cpu(x::AbstractArray)
    return x
end

"""
GPU-accelerated matrix multiplication
"""
function gpu_matrix_multiply(A::AbstractMatrix, B::AbstractMatrix)
    if !has_metal_gpu()
        return A * B
    end
    
    try
        A_gpu = gpu(A)
        B_gpu = gpu(B)
        result_gpu = A_gpu * B_gpu
        return cpu(result_gpu)
    catch e
        @warn "GPU matrix multiplication failed, falling back to CPU" exception=e
        return A * B
    end
end

"""
GPU-accelerated vector addition
"""
function gpu_vector_add(a::AbstractVector, b::AbstractVector)
    if !has_metal_gpu()
        return a .+ b
    end
    
    try
        a_gpu = gpu(a)
        b_gpu = gpu(b)
        result_gpu = a_gpu .+ b_gpu
        return cpu(result_gpu)
    catch e
        @warn "GPU vector addition failed, falling back to CPU" exception=e
        return a .+ b
    end
end

"""
GPU-accelerated element-wise operations
"""
function gpu_element_wise_ops(x::AbstractArray, operation::Function)
    if !has_metal_gpu()
        return operation.(x)
    end
    
    try
        x_gpu = gpu(x)
        result_gpu = operation.(x_gpu)
        return cpu(result_gpu)
    catch e
        @warn "GPU element-wise operation failed, falling back to CPU" exception=e
        return operation.(x)
    end
end

"""
GPU-accelerated standardization (z-score normalization)
"""
function gpu_standardize!(X::AbstractMatrix{Float64})
    if !has_metal_gpu()
        # CPU fallback
        for j in 1:size(X, 2)
            col = view(X, :, j)
            μ = mean(col)
            σ = std(col)
            if σ > 0
                col .= (col .- μ) ./ σ
            end
        end
        return X
    end
    
    try
        # Convert to Float32 for GPU operations
        X_f32 = Float32.(X)
        X_gpu = gpu(X_f32)
        
        # Batch compute mean and std for all columns at once
        # This is much more efficient on GPU than column-by-column processing
        μ = mean(X_gpu, dims=1)  # Row vector of means
        σ = std(X_gpu, dims=1, corrected=true)  # Row vector of stds
        
        # Create a mask for columns with non-zero std (non-constant columns)
        # Only standardize columns where std > threshold
        threshold = Float32(1e-10)
        
        # Handle standardization using vectorized operations to avoid scalar indexing
        # For constant columns, we want to preserve original values, not standardize them
        σ_cpu = cpu(σ)  # Move to CPU for safer operations
        μ_cpu = cpu(μ)
        X_cpu_orig = cpu(X_gpu)  # Original values for constant columns
        
        # Create masks for constant vs variable columns
        is_constant = σ_cpu .<= threshold
        is_variable = .!is_constant
        
        # For variable columns: standardize normally
        # For constant columns: keep original values
        σ_safe_cpu = similar(σ_cpu)
        σ_safe_cpu .= ifelse.(is_variable, σ_cpu, one(eltype(σ_cpu)))
        
        # Transfer back to GPU
        σ_safe = gpu(σ_safe_cpu)
        μ_safe = gpu(μ_cpu)
        is_constant_gpu = gpu(Float32.(is_constant))  # Convert to Float32 for GPU
        
        # Perform vectorized standardization only for variable columns
        X_standardized = (X_gpu .- μ_safe) ./ σ_safe
        
        # Preserve original values for constant columns
        X_gpu = X_standardized .* (1.0f0 .- is_constant_gpu) .+ X_gpu .* is_constant_gpu
        
        # Convert back to Float64 and copy to original array
        X .= Float64.(cpu(X_gpu))
        return X
    catch e
        @warn "GPU standardization failed, falling back to CPU" exception=e
        # CPU fallback
        for j in 1:size(X, 2)
            col = view(X, :, j)
            μ = mean(col)
            σ = std(col)
            if σ > 0
                col .= (col .- μ) ./ σ
            end
        end
        return X
    end
end

"""
GPU-accelerated min-max normalization
"""
function gpu_normalize!(X::AbstractMatrix{Float64})
    if !has_metal_gpu()
        # CPU fallback
        for j in 1:size(X, 2)
            col = view(X, :, j)
            min_val = minimum(col)
            max_val = maximum(col)
            if max_val > min_val
                col .= (col .- min_val) ./ (max_val - min_val)
            end
        end
        return X
    end
    
    try
        # Convert to Float32 for GPU operations
        X_f32 = Float32.(X)
        X_gpu = gpu(X_f32)
        
        # Batch compute min and max for all columns at once
        # This is much more efficient on GPU than column-by-column processing
        min_vals = minimum(X_gpu, dims=1)  # Row vector of minimums
        max_vals = maximum(X_gpu, dims=1)  # Row vector of maximums
        
        # Compute range for each column
        range_vals = max_vals .- min_vals
        
        # Create a mask for columns with non-zero range (non-constant columns)
        # Only normalize columns where range > threshold
        threshold = Float32(1e-10)
        
        # Handle normalization using vectorized operations to avoid scalar indexing
        # For constant columns, we want to preserve original values, not normalize them
        range_cpu = cpu(range_vals)  # Move to CPU for safer operations
        min_cpu = cpu(min_vals)
        
        # Create masks for constant vs variable columns
        is_constant = range_cpu .<= threshold
        is_variable = .!is_constant
        
        # For variable columns: normalize normally
        # For constant columns: keep original values
        range_safe_cpu = similar(range_cpu)
        range_safe_cpu .= ifelse.(is_variable, range_cpu, one(eltype(range_cpu)))
        
        # Transfer back to GPU
        range_safe = gpu(range_safe_cpu)
        min_safe = gpu(min_cpu)
        is_constant_gpu = gpu(Float32.(is_constant))  # Convert to Float32 for GPU
        
        # Perform vectorized normalization only for variable columns
        X_normalized = (X_gpu .- min_safe) ./ range_safe
        
        # Preserve original values for constant columns
        X_gpu = X_normalized .* (1.0f0 .- is_constant_gpu) .+ X_gpu .* is_constant_gpu
        
        # Convert back to Float64 and copy to original array
        X .= Float64.(cpu(X_gpu))
        return X
    catch e
        @warn "GPU normalization failed, falling back to CPU" exception=e
        # CPU fallback
        for j in 1:size(X, 2)
            col = view(X, :, j)
            min_val = minimum(col)
            max_val = maximum(col)
            if max_val > min_val
                col .= (col .- min_val) ./ (max_val - min_val)
            end
        end
        return X
    end
end

"""
GPU-accelerated feature engineering operations
"""
function gpu_feature_engineering(X::AbstractMatrix{Float64}, operations::Vector{Symbol})
    result_matrices = Vector{Matrix{Float64}}()
    push!(result_matrices, copy(X))  # Original features
    
    for op in operations
        if op == :square
            if has_metal_gpu()
                try
                    X_f32 = Float32.(X)
                    X_gpu = gpu(X_f32)
                    X_squared = Float64.(cpu(X_gpu .^ 2))
                    push!(result_matrices, X_squared)
                    continue
                catch e
                    @warn "GPU square operation failed, using CPU" exception=e
                end
            end
            # CPU fallback
            push!(result_matrices, X .^ 2)
            
        elseif op == :sqrt
            if has_metal_gpu()
                try
                    X_f32 = Float32.(abs.(X))  # Ensure non-negative values
                    X_gpu = gpu(X_f32)
                    X_sqrt = Float64.(cpu(sqrt.(X_gpu)))
                    push!(result_matrices, X_sqrt)
                    continue
                catch e
                    @warn "GPU sqrt operation failed, using CPU" exception=e
                end
            end
            # CPU fallback
            push!(result_matrices, sqrt.(abs.(X)))
            
        elseif op == :log
            if has_metal_gpu()
                try
                    X_f32 = Float32.(abs.(X) .+ 1e-8)  # Avoid log(0)
                    X_gpu = gpu(X_f32)
                    X_log = Float64.(cpu(log.(X_gpu)))
                    push!(result_matrices, X_log)
                    continue
                catch e
                    @warn "GPU log operation failed, using CPU" exception=e
                end
            end
            # CPU fallback
            push!(result_matrices, log.(abs.(X) .+ 1e-8))
        end
    end
    
    return hcat(result_matrices...)
end

"""
GPU-accelerated correlation computation
"""
function gpu_compute_correlations(predictions::AbstractVector{Float64}, targets::AbstractVector{Float64})
    if !has_metal_gpu()
        return cor(predictions, targets)
    end
    
    try
        # Convert to Float32 for GPU operations
        pred_f32 = Float32.(predictions)
        targ_f32 = Float32.(targets)
        pred_gpu = gpu(pred_f32)
        targ_gpu = gpu(targ_f32)
        
        # Compute correlation manually on GPU using the formula:
        # cor(x,y) = cov(x,y) / (std(x) * std(y))
        # where cov(x,y) = E[(x - μx)(y - μy)]
        
        n = Float32(length(predictions))
        
        # Compute means
        mean_pred = sum(pred_gpu) / n
        mean_targ = sum(targ_gpu) / n
        
        # Center the variables
        pred_centered = pred_gpu .- mean_pred
        targ_centered = targ_gpu .- mean_targ
        
        # Compute covariance
        covariance = sum(pred_centered .* targ_centered) / (n - 1)
        
        # Compute standard deviations
        var_pred = sum(pred_centered .^ 2) / (n - 1)
        var_targ = sum(targ_centered .^ 2) / (n - 1)
        
        std_pred = sqrt(var_pred)
        std_targ = sqrt(var_targ)
        
        # Compute correlation
        correlation = covariance / (std_pred * std_targ)
        
        return Float64(correlation)
    catch e
        @warn "GPU correlation computation failed, falling back to CPU" exception=e
        return cor(predictions, targets)
    end
end

"""
GPU-accelerated ensemble predictions
"""
function gpu_ensemble_predictions(predictions_matrix::AbstractMatrix{Float64}, weights::AbstractVector{Float64})
    if !has_metal_gpu()
        return predictions_matrix * weights
    end
    
    try
        # Convert to Float32 for GPU operations
        pred_f32 = Float32.(predictions_matrix)
        weights_f32 = Float32.(weights)
        pred_gpu = gpu(pred_f32)
        weights_gpu = gpu(weights_f32)
        
        ensemble_pred = pred_gpu * weights_gpu
        return Float64.(cpu(ensemble_pred))
    catch e
        @warn "GPU ensemble prediction failed, falling back to CPU" exception=e
        return predictions_matrix * weights
    end
end

"""
Benchmarking structure for GPU operations
"""
struct GPUBenchmark
    operation_name::String
    cpu_time::Float64
    gpu_time::Float64
    speedup::Float64
    memory_used::Int64
    success::Bool
end

"""
Benchmark GPU operations against CPU
"""
function benchmark_gpu_operations(data_size::Int=10000, num_features::Int=100)::Vector{GPUBenchmark}
    @info "Starting GPU benchmark" data_size=data_size num_features=num_features
    
    # Generate test data
    Random.seed!(42)
    X = randn(Float64, data_size, num_features)
    y = randn(Float64, data_size)
    
    benchmarks = GPUBenchmark[]
    
    # Matrix multiplication benchmark
    A = randn(Float64, num_features, num_features)
    
    # CPU timing
    cpu_time = @elapsed begin
        for _ in 1:10
            result_cpu = X * A
        end
    end
    
    # GPU timing
    gpu_time = if has_metal_gpu()
        @elapsed begin
            for _ in 1:10
                result_gpu = gpu_matrix_multiply(X, A)
            end
        end
    else
        Inf
    end
    
    speedup = cpu_time / gpu_time
    push!(benchmarks, GPUBenchmark("Matrix Multiplication", cpu_time, gpu_time, speedup, 0, true))
    
    # Standardization benchmark
    X_test = copy(X)
    cpu_time = @elapsed begin
        X_cpu = copy(X_test)
        gpu_standardize!(X_cpu)  # This will use CPU fallback
    end
    
    gpu_time = if has_metal_gpu()
        @elapsed begin
            X_gpu_test = copy(X_test)
            gpu_standardize!(X_gpu_test)
        end
    else
        Inf
    end
    
    speedup = cpu_time / gpu_time
    push!(benchmarks, GPUBenchmark("Standardization", cpu_time, gpu_time, speedup, 0, true))
    
    # Feature engineering benchmark
    cpu_time = @elapsed begin
        result_cpu = gpu_feature_engineering(X, [:square, :sqrt])  # Will fallback to CPU
    end
    
    gpu_time = if has_metal_gpu()
        @elapsed begin
            result_gpu = gpu_feature_engineering(X, [:square, :sqrt])
        end
    else
        Inf
    end
    
    speedup = cpu_time / gpu_time
    push!(benchmarks, GPUBenchmark("Feature Engineering", cpu_time, gpu_time, speedup, 0, true))
    
    return benchmarks
end

"""
Compare CPU vs GPU performance for various operations
"""
function compare_cpu_gpu_performance(data_sizes::Vector{Int}=[1000, 5000, 10000, 50000])
    results = Dict{Int, Vector{GPUBenchmark}}()
    
    for size in data_sizes
        @info "Benchmarking data size: $size"
        results[size] = benchmark_gpu_operations(size)
    end
    
    # Print results
    println("\n=== GPU Performance Benchmark Results ===")
    println("Data Size | Operation | CPU Time | GPU Time | Speedup")
    println("-" ^ 60)
    
    for size in data_sizes
        benchmarks = results[size]
        for benchmark in benchmarks
            println("$(lpad(size, 8)) | $(rpad(benchmark.operation_name, 20)) | $(rpad(round(benchmark.cpu_time, digits=4), 8)) | $(rpad(round(benchmark.gpu_time, digits=4), 8)) | $(round(benchmark.speedup, digits=2))x")
        end
    end
    
    return results
end

"""
Macro for automatic CPU fallback on GPU operation failure
Handles Float64 to Float32 conversion automatically
"""
macro gpu_fallback(gpu_expr, cpu_expr)
    quote
        if has_metal_gpu()
            try
                # The GPU expression should handle Float32 conversion internally
                $(esc(gpu_expr))
            catch e
                @warn "GPU operation failed, falling back to CPU" exception=e
                $(esc(cpu_expr))
            end
        else
            $(esc(cpu_expr))
        end
    end
end

"""
Execute function with automatic GPU fallback
Ensures proper Float64 to Float32 conversion for Metal compatibility
"""
function with_gpu_fallback(gpu_func::Function, cpu_func::Function, args...)
    if has_metal_gpu()
        try
            # Convert Float64 arrays to Float32 for Metal compatibility
            converted_args = map(args) do arg
                if isa(arg, AbstractArray{Float64})
                    Float32.(arg)
                elseif isa(arg, Float64)
                    Float32(arg)
                else
                    arg
                end
            end
            result = gpu_func(converted_args...)
            # Convert result back to Float64 if needed
            if isa(result, AbstractArray{Float32})
                return Float64.(result)
            elseif isa(result, Float32)
                return Float64(result)
            else
                return result
            end
        catch e
            @warn "GPU operation failed, falling back to CPU" exception=e
            return cpu_func(args...)
        end
    else
        return cpu_func(args...)
    end
end

"""
GPU-accelerated feature selection based on correlation
"""
function gpu_feature_selection(X::AbstractMatrix{Float64}, y::AbstractVector{Float64}, 
                             k::Int=100)::Vector{Int}
    n_features = size(X, 2)
    correlations = Vector{Float64}(undef, n_features)
    
    @info "Computing feature correlations" n_features=n_features
    
    if has_metal_gpu()
        try
            # Convert to Float32 for GPU operations
            X_f32 = Float32.(X)
            y_f32 = Float32.(y)
            X_gpu = gpu(X_f32)
            y_gpu = gpu(y_f32)
            
            # Standardize for correlation computation
            X_mean = mean(X_gpu, dims=1)
            X_std = std(X_gpu, dims=1, corrected=true)
            # Avoid scalar indexing by using vectorized operations
            X_std_safe = X_std .+ Float32(1e-10)  # Add small constant to avoid division by zero
            X_standardized = (X_gpu .- X_mean) ./ X_std_safe
            
            y_mean = mean(y_gpu)
            y_std = std(y_gpu, corrected=true)
            y_std_safe = max(y_std, Float32(1e-10))
            y_standardized = (y_gpu .- y_mean) ./ y_std_safe
            
            # Compute correlations for all features at once using matrix multiplication
            # correlation = (X'y) / n for standardized variables
            n = Float32(size(X, 1))
            correlations_gpu = abs.(vec(X_standardized' * y_standardized) ./ n)
            
            # Copy back to CPU
            correlations .= Float64.(cpu(correlations_gpu))
        catch e
            @warn "GPU feature selection failed, falling back to CPU" exception=e
            for i in 1:n_features
                correlations[i] = abs(cor(X[:, i], y))
            end
        end
    else
        for i in 1:n_features
            correlations[i] = abs(cor(X[:, i], y))
        end
    end
    
    # Return indices of top k features
    top_indices = sortperm(correlations, rev=true)[1:min(k, n_features)]
    return top_indices
end

"""
Initialize Metal acceleration system
"""
function __init__()
    @info "Initializing Metal acceleration system"
    
    if has_metal_gpu()
        device = configure_metal_device()
        if device.is_available
            @info "Metal GPU acceleration ready" device_info=get_gpu_info()
        else
            @info "Metal GPU not available, CPU fallback will be used"
        end
    else
        @info "Metal not functional on this system, CPU fallback will be used"
    end
end

end  # module MetalAcceleration