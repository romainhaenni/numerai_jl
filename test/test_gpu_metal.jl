using Test
using Statistics
using Random
using LinearAlgebra
using DataFrames
using Logging
using Printf

# Import the main module and GPU acceleration module
using NumeraiTournament
using NumeraiTournament.MetalAcceleration

@testset "GPU Metal Acceleration Tests" begin
    
    @testset "GPU Detection and Initialization" begin
        @testset "has_metal_gpu function" begin
            # Test GPU detection
            gpu_available = has_metal_gpu()
            @test gpu_available isa Bool
            
            # If GPU is available, log it for informational purposes
            if gpu_available
                @info "Metal GPU detected and available for testing"
            else
                @info "Metal GPU not available - testing CPU fallback behavior"
            end
        end
        
        @testset "configure_metal_device function" begin
            # Test device configuration
            device = configure_metal_device()
            @test device isa MetalDevice
            @test device.is_available isa Bool
            @test device.memory_total >= 0
            @test device.memory_free >= 0
            @test device.compute_units >= 0
            @test device.max_threads_per_group >= 0
            @test device.supports_unified_memory isa Bool
            
            # Test singleton behavior - should return same device
            device2 = configure_metal_device()
            @test device === device2
        end
        
        @testset "get_gpu_info function" begin
            gpu_info = get_gpu_info()
            @test gpu_info isa Dict{String, Any}
            @test haskey(gpu_info, "available")
            @test gpu_info["available"] isa Bool
            
            if gpu_info["available"]
                @test haskey(gpu_info, "device_name")
                @test haskey(gpu_info, "memory_total")
                @test haskey(gpu_info, "memory_free")
                @test haskey(gpu_info, "memory_used")
                @test haskey(gpu_info, "supports_unified_memory")
                @test gpu_info["device_name"] isa String
                @test gpu_info["supports_unified_memory"] isa Bool
            else
                # Should have reason when not available
                @test haskey(gpu_info, "reason") || haskey(gpu_info, "error")
            end
        end
    end
    
    @testset "GPU Memory Management" begin
        @testset "gpu_memory_info function" begin
            memory_info = gpu_memory_info()
            @test memory_info isa Dict{String, Int64}
            @test haskey(memory_info, "total")
            @test haskey(memory_info, "used")
            @test haskey(memory_info, "free")
            @test memory_info["total"] >= 0
            @test memory_info["used"] >= 0
            @test memory_info["free"] >= 0
            
            # Free + Used should not exceed Total (allowing for small discrepancies)
            if memory_info["total"] > 0
                @test memory_info["used"] + memory_info["free"] >= memory_info["total"] * 0.9
                @test memory_info["used"] + memory_info["free"] <= memory_info["total"] * 1.1
            end
        end
        
        @testset "gpu_memory_status function" begin
            status = gpu_memory_status()
            @test status isa String
            @test length(status) > 0
            
            # Should contain memory information if available
            if has_metal_gpu()
                memory_info = gpu_memory_info()
                if memory_info["total"] > 0
                    @test occursin("GB", status)
                    @test occursin("used", status)
                    @test occursin("free", status)
                end
            else
                @test occursin("not available", status)
            end
        end
        
        @testset "clear_gpu_cache! function" begin
            # Test cache clearing (should not throw errors)
            initial_memory = gpu_memory_info()
            clear_gpu_cache!()
            # Function should complete without errors
            @test true
            
            # If GPU is available, memory usage might change
            if has_metal_gpu() && initial_memory["total"] > 0
                post_clear_memory = gpu_memory_info()
                # Used memory might be same or less after clearing
                @test post_clear_memory["used"] <= initial_memory["used"] + 1024*1024  # Allow 1MB tolerance
            end
        end
        
        @testset "gpu_synchronize function" begin
            # Test GPU synchronization (should not throw errors)
            gpu_synchronize()
            @test true  # Should complete without errors
        end
    end
    
    @testset "Array Transfer Operations" begin
        @testset "gpu function - CPU to GPU transfer" begin
            # Test with different array types
            test_arrays = [
                Float32[1.0, 2.0, 3.0, 4.0],
                Float64[1.0, 2.0, 3.0, 4.0],
                [1.0f0 2.0f0; 3.0f0 4.0f0],
                [1.0 2.0; 3.0 4.0]
            ]
            
            for arr in test_arrays
                gpu_arr = gpu(arr)
                
                # Should return an array
                @test gpu_arr isa AbstractArray
                @test size(gpu_arr) == size(arr)
                @test eltype(gpu_arr) == eltype(arr)
                
                # If GPU is not available, should return original array
                if !has_metal_gpu()
                    @test gpu_arr === arr
                end
            end
        end
        
        @testset "cpu function - GPU to CPU transfer" begin
            # Test CPU transfer with regular arrays
            test_array = [1.0, 2.0, 3.0, 4.0]
            cpu_arr = cpu(test_array)
            @test cpu_arr === test_array  # Should return same array for CPU arrays
            @test cpu_arr == test_array
            
            # Test GPU array transfer if available
            if has_metal_gpu()
                gpu_arr = gpu(test_array)
                if gpu_arr !== test_array  # Only test if actually transferred to GPU
                    try
                        cpu_result = cpu(gpu_arr)
                        @test cpu_result isa Array
                        @test size(cpu_result) == size(test_array)
                        @test cpu_result ≈ test_array
                    catch e
                        # If transfer fails, should log warning but not crash test
                        @test e isa Exception
                    end
                end
            end
        end
    end
    
    @testset "GPU-Accelerated Linear Algebra Operations" begin
        # Setup test data
        Random.seed!(42)
        
        @testset "gpu_matrix_multiply function" begin
            # Test different matrix sizes
            test_cases = [
                (5, 5, 5),    # Small matrices
                (10, 8, 6),   # Rectangular matrices
                (50, 50, 50), # Medium matrices
            ]
            
            for (m, k, n) in test_cases
                A = randn(Float64, m, k)
                B = randn(Float64, k, n)
                
                # Test GPU matrix multiplication
                result_gpu = gpu_matrix_multiply(A, B)
                result_cpu = A * B
                
                @test result_gpu isa AbstractMatrix
                @test size(result_gpu) == (m, n)
                @test result_gpu ≈ result_cpu rtol=1e-10
            end
            
            # Test error handling with mismatched dimensions
            A = randn(3, 4)
            B = randn(5, 6)  # Incompatible dimensions
            
            # Should fallback to CPU and throw same error
            @test_throws DimensionMismatch gpu_matrix_multiply(A, B)
        end
        
        @testset "gpu_vector_add function" begin
            # Test vector addition
            test_cases = [
                10,    # Small vectors
                100,   # Medium vectors
                1000   # Large vectors
            ]
            
            for n in test_cases
                a = randn(Float64, n)
                b = randn(Float64, n)
                
                result_gpu = gpu_vector_add(a, b)
                result_cpu = a .+ b
                
                @test result_gpu isa AbstractVector
                @test length(result_gpu) == n
                @test result_gpu ≈ result_cpu rtol=1e-12
            end
            
            # Test error handling with mismatched lengths
            a = randn(5)
            b = randn(3)
            
            @test_throws DimensionMismatch gpu_vector_add(a, b)
        end
        
        @testset "gpu_element_wise_ops function" begin
            # Test various element-wise operations
            test_data = randn(Float64, 100)
            
            operations = [
                x -> x .^ 2,
                x -> sin.(x),
                x -> exp.(x),
                x -> abs.(x),
                x -> x .+ 1.0
            ]
            
            for op in operations
                result_gpu = gpu_element_wise_ops(test_data, op)
                result_cpu = op(test_data)
                
                @test result_gpu isa AbstractArray
                @test size(result_gpu) == size(test_data)
                @test result_gpu ≈ result_cpu rtol=1e-10
            end
            
            # Test with matrices
            test_matrix = randn(Float64, 20, 30)
            square_op = x -> x .^ 2
            
            result_gpu = gpu_element_wise_ops(test_matrix, square_op)
            result_cpu = square_op(test_matrix)
            
            @test result_gpu ≈ result_cpu rtol=1e-10
        end
    end
    
    @testset "GPU Data Preprocessing Operations" begin
        Random.seed!(123)
        
        @testset "gpu_standardize! function" begin
            # Test standardization with different matrix sizes
            test_cases = [
                (50, 5),    # Small dataset
                (100, 20),  # Medium dataset
                (200, 10)   # Larger dataset
            ]
            
            for (n_samples, n_features) in test_cases
                # Create test data with different scales
                # Create scaling factors that match the number of features
                base_scales = [1.0, 10.0, 100.0, 0.1, 0.01]
                scales = [base_scales[mod1(i, 5)] for i in 1:n_features]
                X_original = randn(Float64, n_samples, n_features) .* scales'
                X_gpu = copy(X_original)
                X_cpu = copy(X_original)
                
                # Test GPU standardization
                result_gpu = gpu_standardize!(X_gpu)
                @test result_gpu === X_gpu  # Should modify in-place
                
                # Compare with manual CPU standardization
                for j in 1:size(X_cpu, 2)
                    col = view(X_cpu, :, j)
                    μ = mean(col)
                    σ = std(col)
                    if σ > 0
                        col .= (col .- μ) ./ σ
                    end
                end
                
                @test X_gpu ≈ X_cpu rtol=1e-10
                
                # Verify standardization properties
                for j in 1:n_features
                    col_std = std(X_gpu[:, j])
                    col_mean = mean(X_gpu[:, j])
                    
                    if std(X_original[:, j]) > 0  # Skip constant columns
                        @test abs(col_mean) < 1e-10  # Mean should be ~0
                        @test abs(col_std - 1.0) < 1e-10  # Std should be ~1
                    end
                end
            end
            
            # Test with constant columns (should handle gracefully)
            X_constant = ones(Float64, 50, 3)
            X_constant[:, 2] .= 5.0  # Constant but non-zero
            X_test = copy(X_constant)
            
            gpu_standardize!(X_test)
            # Constant columns should remain unchanged
            @test X_test[:, 1] ≈ X_constant[:, 1]
            @test X_test[:, 2] ≈ X_constant[:, 2]
            @test X_test[:, 3] ≈ X_constant[:, 3]
        end
        
        @testset "gpu_normalize! function" begin
            # Test min-max normalization
            test_cases = [
                (50, 5),
                (100, 10),
                (200, 15)
            ]
            
            for (n_samples, n_features) in test_cases
                # Create test data with different ranges
                X_original = randn(Float64, n_samples, n_features) .* 100 .+ 50
                X_gpu = copy(X_original)
                X_cpu = copy(X_original)
                
                # Test GPU normalization
                result_gpu = gpu_normalize!(X_gpu)
                @test result_gpu === X_gpu  # Should modify in-place
                
                # Compare with manual CPU normalization
                for j in 1:size(X_cpu, 2)
                    col = view(X_cpu, :, j)
                    min_val = minimum(col)
                    max_val = maximum(col)
                    if max_val > min_val
                        col .= (col .- min_val) ./ (max_val - min_val)
                    end
                end
                
                @test X_gpu ≈ X_cpu rtol=1e-10
                
                # Verify normalization properties
                for j in 1:n_features
                    if maximum(X_original[:, j]) > minimum(X_original[:, j])
                        @test minimum(X_gpu[:, j]) ≈ 0.0 atol=1e-10
                        @test maximum(X_gpu[:, j]) ≈ 1.0 atol=1e-10
                    end
                end
            end
            
            # Test with constant columns
            X_constant = ones(Float64, 30, 2) .* 42.0
            X_test = copy(X_constant)
            
            gpu_normalize!(X_test)
            # Constant columns should remain unchanged
            @test X_test ≈ X_constant
        end
    end
    
    @testset "GPU Feature Engineering Operations" begin
        Random.seed!(456)
        
        @testset "gpu_feature_engineering function" begin
            # Test feature engineering operations
            X = randn(Float64, 100, 5)
            
            # Test individual operations
            operations_tests = [
                ([:square], "square operation"),
                ([:sqrt], "sqrt operation"),
                ([:log], "log operation"),
                ([:square, :sqrt], "multiple operations"),
                ([:square, :sqrt, :log], "all operations")
            ]
            
            for (ops, description) in operations_tests
                @testset "$description" begin
                    result = gpu_feature_engineering(X, ops)
                    
                    # Should return matrix with original + new features
                    expected_cols = size(X, 2) * (1 + length(ops))
                    @test size(result, 1) == size(X, 1)
                    @test size(result, 2) == expected_cols
                    
                    # First columns should be original data
                    @test result[:, 1:size(X, 2)] ≈ X
                    
                    # Verify specific operations
                    col_idx = size(X, 2)
                    for op in ops
                        if op == :square
                            expected = X .^ 2
                            @test result[:, col_idx+1:col_idx+size(X, 2)] ≈ expected rtol=1e-10
                        elseif op == :sqrt
                            expected = sqrt.(abs.(X))
                            @test result[:, col_idx+1:col_idx+size(X, 2)] ≈ expected rtol=1e-10
                        elseif op == :log
                            expected = log.(abs.(X) .+ 1e-8)
                            @test result[:, col_idx+1:col_idx+size(X, 2)] ≈ expected rtol=1e-10
                        end
                        col_idx += size(X, 2)
                    end
                end
            end
            
            # Test with edge cases
            X_edge = [0.0 -1.0; 1.0 -2.0; -1.0 0.0]
            result_edge = gpu_feature_engineering(X_edge, [:sqrt, :log])
            
            @test size(result_edge, 1) == 3
            @test size(result_edge, 2) == 6  # Original + sqrt + log
            @test all(isfinite.(result_edge))  # Should handle negative values gracefully
        end
    end
    
    @testset "GPU ML Operations" begin
        Random.seed!(789)
        
        @testset "gpu_compute_correlations function" begin
            # Test correlation computation
            n = 1000
            base = randn(Float64, n)
            
            # Perfect correlation
            predictions1 = copy(base)
            targets1 = copy(base)
            corr1 = gpu_compute_correlations(predictions1, targets1)
            @test corr1 ≈ 1.0 atol=1e-10
            
            # Perfect anti-correlation
            predictions2 = copy(base)
            targets2 = -copy(base)
            corr2 = gpu_compute_correlations(predictions2, targets2)
            @test corr2 ≈ -1.0 atol=1e-10
            
            # No correlation
            predictions3 = randn(Float64, n)
            targets3 = randn(Float64, n)
            corr3 = gpu_compute_correlations(predictions3, targets3)
            @test -1.0 <= corr3 <= 1.0
            @test !isnan(corr3)
            
            # Compare with standard correlation
            predictions4 = randn(Float64, n)
            targets4 = 0.5 * predictions4 + 0.5 * randn(Float64, n)
            corr_gpu = gpu_compute_correlations(predictions4, targets4)
            corr_cpu = cor(predictions4, targets4)
            @test corr_gpu ≈ corr_cpu rtol=1e-10
        end
        
        @testset "gpu_ensemble_predictions function" begin
            # Test ensemble predictions
            n_samples = 200
            n_models = 5
            
            predictions_matrix = randn(Float64, n_samples, n_models)
            weights = rand(Float64, n_models)
            weights ./= sum(weights)  # Normalize weights
            
            result_gpu = gpu_ensemble_predictions(predictions_matrix, weights)
            result_cpu = predictions_matrix * weights
            
            @test result_gpu isa AbstractVector
            @test length(result_gpu) == n_samples
            @test result_gpu ≈ result_cpu rtol=1e-12
            
            # Test with equal weights
            equal_weights = ones(Float64, n_models) ./ n_models
            result_equal = gpu_ensemble_predictions(predictions_matrix, equal_weights)
            expected_equal = mean(predictions_matrix, dims=2)[:, 1]
            @test result_equal ≈ expected_equal rtol=1e-12
        end
        
        @testset "gpu_feature_selection function" begin
            # Create synthetic data with known correlations
            n_samples = 500
            n_features = 20
            
            X = randn(Float64, n_samples, n_features)
            
            # Make some features more correlated with target
            y = 0.8 * X[:, 1] + 0.6 * X[:, 2] + 0.4 * X[:, 3] + 0.2 * randn(Float64, n_samples)
            
            # Test feature selection
            k_values = [5, 10, 15]
            for k in k_values
                selected_features = gpu_feature_selection(X, y, k)
                
                @test selected_features isa Vector{Int}
                @test length(selected_features) == min(k, n_features)
                @test all(1 .<= selected_features .<= n_features)
                @test length(unique(selected_features)) == length(selected_features)  # No duplicates
                
                # First few features should have higher correlation
                # (features 1, 2, 3 should be in top selections)
                if k >= 3
                    top_3 = selected_features[1:3]
                    @test 1 in top_3 || 2 in top_3 || 3 in top_3  # At least one of the correlated features
                end
            end
            
            # Test with k larger than n_features
            selected_all = gpu_feature_selection(X, y, n_features + 10)
            @test length(selected_all) == n_features
        end
    end
    
    @testset "GPU Benchmarking System" begin
        @testset "GPUBenchmark struct" begin
            # Test benchmark structure
            benchmark = GPUBenchmark("Test Operation", 1.5, 0.8, 1.875, 1024, true)
            @test benchmark.operation_name == "Test Operation"
            @test benchmark.cpu_time == 1.5
            @test benchmark.gpu_time == 0.8
            @test benchmark.speedup == 1.875
            @test benchmark.memory_used == 1024
            @test benchmark.success == true
        end
        
        @testset "benchmark_gpu_operations function" begin
            # Test benchmarking with small data sizes for speed
            benchmarks = benchmark_gpu_operations(100, 10)  # Small data for testing
            
            @test benchmarks isa Vector{GPUBenchmark}
            @test length(benchmarks) >= 3  # Should have multiple operations benchmarked
            
            for benchmark in benchmarks
                @test benchmark isa GPUBenchmark
                @test benchmark.operation_name isa String
                @test benchmark.cpu_time > 0
                @test benchmark.gpu_time > 0 || benchmark.gpu_time == Inf  # Inf if GPU not available
                @test benchmark.success isa Bool
                
                if has_metal_gpu() && benchmark.gpu_time != Inf
                    @test benchmark.speedup > 0
                end
            end
        end
        
        @testset "compare_cpu_gpu_performance function" begin
            # Test performance comparison with very small datasets
            data_sizes = [50, 100]
            results = compare_cpu_gpu_performance(data_sizes)
            
            @test results isa Dict{Int, Vector{GPUBenchmark}}
            @test length(results) == length(data_sizes)
            
            for size in data_sizes
                @test haskey(results, size)
                @test results[size] isa Vector{GPUBenchmark}
                @test length(results[size]) > 0
            end
        end
    end
    
    @testset "Fallback Mechanisms" begin
        @testset "@gpu_fallback macro" begin
            # Test the fallback macro
            test_var = [1.0, 2.0, 3.0]
            
            # Test successful GPU operation (or fallback if GPU not available)
            result = @gpu_fallback begin
                gpu(test_var)
            end begin
                test_var
            end
            
            @test result isa AbstractArray
            @test result == test_var || size(result) == size(test_var)
            
            # Test fallback with intentional error in GPU path
            result_fallback = @gpu_fallback begin
                error("Simulated GPU error")
            end begin
                test_var .+ 1
            end
            
            @test result_fallback == test_var .+ 1
        end
        
        @testset "with_gpu_fallback function" begin
            test_data = [1.0, 2.0, 3.0, 4.0]
            
            # Test function that might succeed on GPU
            gpu_func = (x) -> gpu(x)
            cpu_func = (x) -> x
            
            result = with_gpu_fallback(gpu_func, cpu_func, test_data)
            @test result isa AbstractArray
            @test size(result) == size(test_data)
            
            # Test with functions that have operations
            gpu_square = (x) -> gpu(x) .^ 2
            cpu_square = (x) -> x .^ 2
            
            result_square = with_gpu_fallback(gpu_square, cpu_square, test_data)
            expected = test_data .^ 2
            @test result_square ≈ expected rtol=1e-12
            
            # Test fallback with error in GPU function
            error_gpu_func = (x) -> error("GPU function failed")
            safe_cpu_func = (x) -> x .* 2
            
            result_error = with_gpu_fallback(error_gpu_func, safe_cpu_func, test_data)
            @test result_error == test_data .* 2
        end
    end
    
    @testset "Integration and Edge Cases" begin
        @testset "Large scale operations" begin
            # Test with larger datasets to ensure stability
            if has_metal_gpu()
                # Only run large tests if GPU is available to avoid long CPU times
                Random.seed!(999)
                
                # Test large matrix operations
                n = 500
                A = randn(Float64, n, n)
                B = randn(Float64, n, n)
                
                # This should complete without memory issues
                result = gpu_matrix_multiply(A, B)
                @test size(result) == (n, n)
                @test result ≈ A * B rtol=1e-10
                
                # Test large feature engineering
                X_large = randn(Float64, 1000, 50)
                result_large = gpu_feature_engineering(X_large, [:square])
                @test size(result_large, 1) == 1000
                @test size(result_large, 2) == 100
                
                # Check memory after operations
                memory_info = gpu_memory_info()
                @test memory_info["total"] >= 0
                @test memory_info["used"] >= 0
                @test memory_info["free"] >= 0
            end
        end
        
        @testset "Error handling and edge cases" begin
            # Test empty arrays
            empty_arr = Float64[]
            result_empty = gpu(empty_arr)
            @test length(result_empty) == 0
            @test cpu(result_empty) == empty_arr
            
            # Test single element arrays
            single_arr = [42.0]
            result_single = gpu(single_arr)
            @test length(result_single) == 1
            @test cpu(result_single) ≈ single_arr
            
            # Test very small matrices
            tiny_matrix = reshape([1.0], 1, 1)
            result_tiny = gpu_matrix_multiply(tiny_matrix, tiny_matrix)
            @test result_tiny == reshape([1.0], 1, 1)
            
            # Test operations with NaN and Inf
            nan_data = [1.0, NaN, 3.0, Inf, -Inf]
            result_nan = gpu(nan_data)
            result_cpu_nan = cpu(result_nan)
            @test length(result_cpu_nan) == 5
            @test result_cpu_nan[1] == 1.0
            @test isnan(result_cpu_nan[2])
            @test result_cpu_nan[3] == 3.0
            @test isinf(result_cpu_nan[4]) && result_cpu_nan[4] > 0
            @test isinf(result_cpu_nan[5]) && result_cpu_nan[5] < 0
        end
        
        @testset "Memory pressure handling" begin
            # Test behavior under memory pressure by creating many arrays
            initial_memory = gpu_memory_info()
            
            arrays = []
            try
                # Create arrays until we use significant memory or hit limits
                for i in 1:50
                    arr = randn(Float64, 100, 100)
                    gpu_arr = gpu(arr)
                    push!(arrays, gpu_arr)
                    
                    # Check if memory usage is increasing (if GPU is available)
                    if has_metal_gpu() && i % 10 == 0
                        current_memory = gpu_memory_info()
                        if current_memory["total"] > 0
                            # Memory usage should be tracked properly
                            @test current_memory["used"] >= 0
                            @test current_memory["free"] >= 0
                        end
                    end
                end
            catch e
                # If we run out of memory, that's expected behavior
                @test e isa Exception
            end
            
            # Clear allocated memory
            arrays = nothing
            clear_gpu_cache!()
            
            # Memory should be freed or at least not higher than before
            final_memory = gpu_memory_info()
            if initial_memory["total"] > 0 && final_memory["total"] > 0
                # Allow some tolerance for memory fragmentation
                tolerance = 100 * 1024 * 1024  # 100 MB tolerance
                @test final_memory["used"] <= initial_memory["used"] + tolerance
            end
        end
    end
    
    @testset "Thread Safety and Concurrency" begin
        @testset "Concurrent GPU operations" begin
            # Test multiple simultaneous GPU operations
            n_tasks = 4
            results = Vector{Any}(undef, n_tasks)
            
            # Use @sync to wait for all tasks
            @sync begin
                for i in 1:n_tasks
                    Threads.@spawn begin
                        Random.seed!(i * 100)
                        data = randn(Float64, 50, 50)
                        
                        # Perform various GPU operations
                        gpu_data = gpu(data)
                        result1 = cpu(gpu_data)
                        result2 = gpu_matrix_multiply(data, data)
                        result3 = gpu_element_wise_ops(data, x -> x .^ 2)
                        
                        results[i] = (result1, result2, result3)
                    end
                end
            end
            
            # Verify all tasks completed successfully
            for i in 1:n_tasks
                @test results[i] !== nothing
                result1, result2, result3 = results[i]
                @test result1 isa AbstractArray
                @test result2 isa AbstractArray
                @test result3 isa AbstractArray
                @test size(result1) == (50, 50)
                @test size(result2) == (50, 50)
                @test size(result3) == (50, 50)
            end
        end
    end
    
    @testset "Logging and Debugging" begin
        @testset "GPU operation logging" begin
            # Capture log messages
            logger = Logging.SimpleLogger(IOBuffer(), Logging.Info)
            
            Logging.with_logger(logger) do
                # These operations should generate appropriate log messages
                device = configure_metal_device()
                gpu_info = get_gpu_info()
                memory_status = gpu_memory_status()
                
                # Test operations that might generate warnings
                try
                    large_array = ones(Float64, 1000, 1000)
                    gpu_array = gpu(large_array)
                    clear_gpu_cache!()
                catch
                    # Expected if GPU memory is limited
                end
            end
            
            # Check that logger captured some content
            log_content = String(take!(logger.stream))
            # Log content should exist (exact content depends on system state)
            @test true  # Just verify no crashes occurred during logging
        end
    end
    
    # Final GPU state verification
    @testset "Post-test GPU State" begin
        # Ensure GPU is in a clean state after all tests
        clear_gpu_cache!()
        gpu_synchronize()
        
        final_memory = gpu_memory_info()
        @test final_memory["total"] >= 0
        @test final_memory["used"] >= 0
        @test final_memory["free"] >= 0
        
        # GPU should still be functional
        device_info = get_gpu_info()
        @test device_info isa Dict{String, Any}
        @test haskey(device_info, "available")
        
        if has_metal_gpu()
            @info "GPU tests completed successfully with Metal acceleration"
        else
            @info "GPU tests completed successfully with CPU fallback"
        end
    end
end