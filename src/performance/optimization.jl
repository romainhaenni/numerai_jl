module Performance

using LinearAlgebra
using Distributed
using ThreadsX
using Statistics
using CSV
using DataFrames
using Parquet

function optimize_for_m4_max()
    # Set optimal number of threads for M4 Max (16 performance cores)
    num_threads = min(16, Sys.CPU_THREADS)
    BLAS.set_num_threads(num_threads)
    
    # Configure Julia threading
    if Threads.nthreads() < num_threads
        @warn "Julia started with $(Threads.nthreads()) threads. For optimal performance, restart with: julia -t $num_threads"
    end
    
    # Set memory optimizations
    GC.enable(true)
    
    # Configure garbage collection for 48GB unified memory
    # Less aggressive GC for systems with ample memory
    if Sys.total_memory() > 32 * 1024^3  # More than 32GB
        GC.gc(false)  # Minor collection
    end
    
    return Dict(
        :threads => Threads.nthreads(),
        :blas_threads => BLAS.get_num_threads(),
        :memory_gb => round(Sys.total_memory() / 1024^3, digits=1),
        :cpu_cores => Sys.CPU_THREADS
    )
end

function parallel_map(f::Function, data::AbstractArray; 
                     batch_size::Union{Nothing, Int}=nothing)
    n = length(data)
    
    if batch_size === nothing
        # Auto-determine batch size based on data size and threads
        batch_size = max(1, n ÷ (Threads.nthreads() * 4))
    end
    
    if n < batch_size * 2
        # Small dataset, use regular map
        return map(f, data)
    else
        # Large dataset, use ThreadsX for parallel processing
        return ThreadsX.map(f, data)
    end
end

function chunked_processing(f::Function, data::AbstractArray; 
                          chunk_size::Int=10000,
                          progress::Bool=false)
    n = length(data)
    n_chunks = ceil(Int, n / chunk_size)
    results = []
    
    for i in 1:n_chunks
        start_idx = (i - 1) * chunk_size + 1
        end_idx = min(i * chunk_size, n)
        chunk = data[start_idx:end_idx]
        
        if progress
            print("\rProcessing chunk $i/$n_chunks...")
        end
        
        chunk_result = f(chunk)
        push!(results, chunk_result)
    end
    
    if progress
        println(" Done!")
    end
    
    return vcat(results...)
end

function memory_efficient_load(file_path::String; 
                              max_memory_gb::Float64=8.0,
                              chunk_size::Int=100000)
    file_size_gb = filesize(file_path) / 1024^3
    
    if file_size_gb > max_memory_gb
        @warn "File size ($file_size_gb GB) exceeds memory limit ($max_memory_gb GB). Using chunked loading."
        
        # Determine file type
        ext = lowercase(splitext(file_path)[2])
        
        if ext == ".csv"
            # Chunked CSV loading
            return load_csv_chunked(file_path, chunk_size)
        elseif ext == ".parquet"
            # Chunked Parquet loading
            return load_parquet_chunked(file_path, chunk_size)
        else
            @warn "Unsupported file type for chunked loading: $ext"
            return nothing
        end
    else
        # Regular loading for files that fit in memory
        return file_path
    end
end

function load_csv_chunked(file_path::String, chunk_size::Int)
    # Count total rows first for proper chunking
    total_rows = countlines(file_path) - 1  # Subtract header row
    
    chunks = DataFrame[]
    offset = 0
    
    while offset < total_rows
        # Read a chunk starting from offset
        df_chunk = CSV.read(
            file_path, 
            DataFrame; 
            skipto=offset + 2,  # +2 because skipto is 1-indexed and we skip header
            limit=min(chunk_size, total_rows - offset),
            copycols=true
        )
        
        push!(chunks, df_chunk)
        offset += chunk_size
        
        # Process chunks periodically to reduce memory
        if length(chunks) >= 10
            combined = vcat(chunks...)
            chunks = [combined]
            GC.gc()  # Force garbage collection to free memory
        end
    end
    
    # Combine all remaining chunks
    return isempty(chunks) ? DataFrame() : vcat(chunks...)
end

function load_parquet_chunked(file_path::String, chunk_size::Int)
    # Open parquet file
    pf = Parquet.File(file_path)
    
    chunks = DataFrame[]
    row_groups = Parquet.nrowgroups(pf)
    
    for i in 1:row_groups
        # Read one row group at a time
        df_chunk = DataFrame(Parquet.read(pf, i))
        push!(chunks, df_chunk)
        
        # Process chunk immediately if needed
        if length(chunks) > 5  # Combine every 5 row groups
            combined = vcat(chunks...)
            chunks = [combined]
        end
    end
    
    # Combine all chunks
    return vcat(chunks...)
end

function benchmark_function(f::Function, args...; 
                          warmup::Int=1, 
                          runs::Int=10)
    # Warmup runs
    for _ in 1:warmup
        f(args...)
    end
    
    # Benchmark runs
    times = Float64[]
    for _ in 1:runs
        t = @elapsed f(args...)
        push!(times, t)
    end
    
    return Dict(
        :mean => mean(times),
        :median => median(times),
        :min => minimum(times),
        :max => maximum(times),
        :std => std(times)
    )
end

function optimize_data_layout(X::Matrix{Float64})
    # Ensure column-major layout for Julia (optimal for BLAS operations)
    if !isa(X, Matrix{Float64})
        X = Matrix{Float64}(X)
    end
    
    # Pre-allocate for common operations
    n_samples, n_features = size(X)
    
    # Check if transposing would be beneficial
    # (more features than samples suggests row operations)
    if n_features > n_samples * 2
        @info "Consider transposing data for better cache performance"
    end
    
    return X
end

function parallel_ensemble_predict(models::Vector, X::Matrix{Float64})
    n_models = length(models)
    n_samples = size(X, 1)
    
    # Pre-allocate results matrix
    predictions = Matrix{Float64}(undef, n_samples, n_models)
    
    # Parallel prediction across models
    ThreadsX.foreach(enumerate(models)) do (i, model)
        predictions[:, i] = predict(model, X)
    end
    
    return predictions
end

function get_system_info()::Dict{Symbol, Any}
    return Dict(
        :julia_version => VERSION,
        :threads => Threads.nthreads(),
        :cpu_cores => Sys.CPU_THREADS,
        :cpu_name => Sys.cpu_info()[1].model,
        :memory_gb => round(Sys.total_memory() / 1024^3, digits=1),
        :free_memory_gb => round(Sys.free_memory() / 1024^3, digits=1),
        :platform => Sys.KERNEL,
        :word_size => Sys.WORD_SIZE,
        :blas_vendor => BLAS.vendor(),
        :blas_threads => BLAS.get_num_threads()
    )
end

export optimize_for_m4_max, parallel_map, chunked_processing,
       memory_efficient_load, benchmark_function, optimize_data_layout,
       parallel_ensemble_predict, get_system_info

end