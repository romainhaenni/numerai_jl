# GPU Acceleration Benchmark Report
Generated: 2025-09-10T04:55:41.527

## System Information
- GPU Available: true
- Device: Metal GPU
- Total Memory: 0 GB
- Free Memory: 0 GB
- Unified Memory: true

## Performance Summary
- Average Speedup: 0.64x
- Maximum Speedup: 4.62x
- Minimum Speedup: 0.0x
- Total Benchmarks: 8
- Successful GPU Benchmarks: 8

## Detailed Results

| Operation | Data Size | CPU Time (s) | GPU Time (s) | Speedup | Memory (MB) |
|-----------|-----------|--------------|--------------|---------|-------------|
| Standardization | 1000 | 0.0000 | 0.0306 | 0.00x | 0 |
| Normalization | 1000 | 0.0000 | 0.0002 | 0.11x | 0 |
| Matrix Multiplication | 1000 | 0.0014 | 0.0003 | 4.62x | 0 |
| Matrix Transpose | 1000 | 0.0000 | 0.0001 | 0.00x | 0 |
| Feature Engineering (square) | 1000 | 0.0000 | 0.0170 | 0.00x | 0 |
| Feature Engineering (sqrt) | 1000 | 0.0000 | 0.0003 | 0.01x | 0 |
| Feature Engineering (log) | 1000 | 0.0001 | 0.0002 | 0.30x | 0 |
| Correlation Computation | 1000 | 0.0000 | 0.0003 | 0.07x | 0 |

## Performance by Operation Type

### Standardization
- Average Speedup: 0.0x
- Benchmarks: 1

### Normalization
- Average Speedup: 0.11x
- Benchmarks: 1

### Matrix Multiplication
- Average Speedup: 4.62x
- Benchmarks: 1

### Matrix Transpose
- Average Speedup: 0.0x
- Benchmarks: 1

### Feature Engineering (square)
- Average Speedup: 0.0x
- Benchmarks: 1

### Feature Engineering (sqrt)
- Average Speedup: 0.01x
- Benchmarks: 1

### Feature Engineering (log)
- Average Speedup: 0.3x
- Benchmarks: 1

### Correlation Computation
- Average Speedup: 0.07x
- Benchmarks: 1

## Recommendations

✅ **GPU acceleration is beneficial for:**
- Matrix Multiplication (4.62x speedup)

⚠️ **Limited GPU benefit for:**
- Standardization (0.0x speedup)
- Normalization (0.11x speedup)
- Matrix Transpose (0.0x speedup)
- Feature Engineering (square) (0.0x speedup)
- Feature Engineering (sqrt) (0.01x speedup)
- Feature Engineering (log) (0.3x speedup)
- Correlation Computation (0.07x speedup)

## Configuration Suggestions

Based on these benchmarks:
- Enable GPU acceleration for operations with >2x speedup
- Use CPU fallback for operations with <1.5x speedup
- Consider hybrid CPU/GPU approach for mixed workloads

