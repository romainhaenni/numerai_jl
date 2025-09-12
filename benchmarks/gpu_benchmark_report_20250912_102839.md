# GPU Acceleration Benchmark Report
Generated: 2025-09-12T10:28:39.508

## System Information
- GPU Available: true
- Device: Apple M1 Pro/M2 GPU
- Total Memory: 36 GB
- Free Memory: 1 GB
- Unified Memory: true

## Performance Summary
- Average Speedup: 0.1x
- Maximum Speedup: 1.18x
- Minimum Speedup: 0.0x
- Total Benchmarks: 43
- Successful GPU Benchmarks: 43

## Detailed Results

| Operation | Data Size | CPU Time (s) | GPU Time (s) | Speedup | Memory (MB) |
|-----------|-----------|--------------|--------------|---------|-------------|
| Standardization | 1000 | 0.0001 | 0.4959 | 0.00x | 2 |
| Normalization | 1000 | 0.0003 | 0.4180 | 0.00x | 2 |
| Matrix Multiplication | 1000 | 0.0012 | 0.0137 | 0.09x | 3 |
| Matrix Transpose | 1000 | 0.0000 | 0.0003 | 0.00x | 2 |
| Feature Engineering (square) | 1000 | 0.0012 | 0.0482 | 0.03x | 4 |
| Feature Engineering (sqrt) | 1000 | 0.0002 | 0.0542 | 0.00x | 4 |
| Feature Engineering (log) | 1000 | 0.0027 | 0.0356 | 0.08x | 4 |
| Correlation Computation | 1000 | 0.0000 | 0.3309 | 0.00x | 0 |
| Feature Selection (k=50) | 1000 | 0.0002 | 0.4750 | 0.00x | 2 |
| Standardization | 5000 | 0.0007 | 0.3733 | 0.00x | 11 |
| Normalization | 5000 | 0.0015 | 0.3960 | 0.00x | 11 |
| Matrix Multiplication | 5000 | 0.0078 | 0.0206 | 0.38x | 12 |
| Matrix Transpose | 5000 | 0.0000 | 0.0013 | 0.00x | 11 |
| Feature Engineering (square) | 5000 | 0.0010 | 0.0116 | 0.08x | 23 |
| Feature Engineering (sqrt) | 5000 | 0.0009 | 0.0917 | 0.01x | 23 |
| Feature Engineering (log) | 5000 | 0.0059 | 0.0355 | 0.17x | 23 |
| Correlation Computation | 5000 | 0.0000 | 0.2281 | 0.00x | 0 |
| Feature Selection (k=50) | 5000 | 0.0014 | 0.2426 | 0.01x | 11 |
| Standardization | 10000 | 0.0014 | 0.3826 | 0.00x | 23 |
| Normalization | 10000 | 0.0029 | 0.3668 | 0.01x | 23 |
| Matrix Multiplication | 10000 | 0.0134 | 0.0414 | 0.32x | 24 |
| Matrix Transpose | 10000 | 0.0000 | 0.0511 | 0.00x | 23 |
| Feature Engineering (square) | 10000 | 0.0017 | 0.0128 | 0.13x | 47 |
| Feature Engineering (sqrt) | 10000 | 0.0031 | 0.0517 | 0.06x | 47 |
| Feature Engineering (log) | 10000 | 0.0117 | 0.0962 | 0.12x | 47 |
| Correlation Computation | 10000 | 0.0000 | 0.2282 | 0.00x | 0 |
| Feature Selection (k=50) | 10000 | 0.0058 | 0.2098 | 0.03x | 23 |
| Standardization | 25000 | 0.0053 | 0.3975 | 0.01x | 59 |
| Normalization | 25000 | 0.0076 | 0.4290 | 0.02x | 59 |
| Matrix Multiplication | 25000 | 0.0254 | 0.0398 | 0.64x | 59 |
| Matrix Transpose | 25000 | 0.0000 | 0.0077 | 0.00x | 59 |
| Feature Engineering (square) | 25000 | 0.0049 | 0.0854 | 0.06x | 118 |
| Feature Engineering (sqrt) | 25000 | 0.0115 | 0.1203 | 0.10x | 118 |
| Feature Engineering (log) | 25000 | 0.0790 | 0.0667 | 1.18x | 118 |
| Correlation Computation | 25000 | 0.0000 | 0.2349 | 0.00x | 0 |
| Standardization | 50000 | 0.0117 | 0.4268 | 0.03x | 118 |
| Normalization | 50000 | 0.0147 | 0.4600 | 0.03x | 118 |
| Matrix Multiplication | 50000 | 0.0386 | 0.1156 | 0.33x | 118 |
| Matrix Transpose | 50000 | 0.0000 | 0.0126 | 0.00x | 118 |
| Feature Engineering (square) | 50000 | 0.0094 | 0.1189 | 0.08x | 236 |
| Feature Engineering (sqrt) | 50000 | 0.0182 | 0.2021 | 0.09x | 236 |
| Feature Engineering (log) | 50000 | 0.0588 | 0.1497 | 0.39x | 236 |
| Correlation Computation | 50000 | 0.0000 | 0.2776 | 0.00x | 0 |

## Performance by Operation Type

### Standardization
- Average Speedup: 0.01x
- Benchmarks: 5

### Normalization
- Average Speedup: 0.01x
- Benchmarks: 5

### Matrix Multiplication
- Average Speedup: 0.35x
- Benchmarks: 5

### Matrix Transpose
- Average Speedup: 0.0x
- Benchmarks: 5

### Feature Engineering (square)
- Average Speedup: 0.08x
- Benchmarks: 5

### Feature Engineering (sqrt)
- Average Speedup: 0.05x
- Benchmarks: 5

### Feature Engineering (log)
- Average Speedup: 0.39x
- Benchmarks: 5

### Correlation Computation
- Average Speedup: 0.0x
- Benchmarks: 5

### Feature Selection (k=50)
- Average Speedup: 0.01x
- Benchmarks: 3

## Recommendations

⚠️ **Limited GPU benefit for:**
- Standardization (0.01x speedup)
- Normalization (0.01x speedup)
- Matrix Multiplication (0.35x speedup)
- Matrix Transpose (0.0x speedup)
- Feature Engineering (square) (0.08x speedup)
- Feature Engineering (sqrt) (0.05x speedup)
- Feature Engineering (log) (0.39x speedup)
- Correlation Computation (0.0x speedup)
- Feature Selection (k=50) (0.01x speedup)

## Configuration Suggestions

Based on these benchmarks:
- Enable GPU acceleration for operations with >2x speedup
- Use CPU fallback for operations with <1.5x speedup
- Consider hybrid CPU/GPU approach for mixed workloads

