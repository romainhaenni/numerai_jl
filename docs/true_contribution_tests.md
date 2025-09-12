# True Contribution Tests Documentation

## Overview

The `test/test_true_contribution.jl` file provides comprehensive testing for the True Contribution (TC) calculation functionality in the NumeraiTournament.jl package. These tests ensure the robustness, numerical stability, and correctness of the TC metric implementation.

## Test Coverage

### 1. Basic TC Calculation Tests
- **Perfect correlation**: Tests TC when predictions perfectly match returns
- **Perfect anti-correlation**: Tests TC with anti-correlated predictions
- **Zero correlation**: Tests behavior with uncorrelated/constant predictions
- **Identical to meta-model**: Tests when predictions equal the meta-model

### 2. Edge Cases and Error Conditions
- **Single element vectors**: Ensures proper handling of minimal data
- **Empty vectors**: Tests graceful handling of empty inputs
- **Mismatched vector lengths**: Validates argument error handling
- **Constant predictions**: Tests behavior with no prediction variance
- **Constant returns/meta-model**: Tests edge cases with constant inputs
- **NaN/Infinite values**: Validates robustness with invalid numeric inputs

### 3. Numerical Stability Tests
- **Very large values**: Tests with extreme magnitude inputs (1e10 scale)
- **Very small values**: Tests with tiny magnitude inputs (1e-10 scale)  
- **Mixed scales**: Tests with inputs spanning multiple orders of magnitude
- **High precision requirements**: Tests numerical stability with subtle differences

### 4. Correlation Method Tests
Since the current implementation uses correlation-based TC calculation:
- **Correlation method consistency**: Validates internal calculation steps
- **Zero variance handling**: Tests proper handling when orthogonalized returns have no variance
- **Manual vs automatic calculation**: Compares step-by-step manual calculation with function output

### 5. Real-world Data Distribution Tests
- **Tournament-like simulation**: Tests with era-based structure mimicking Numerai tournaments
- **Realistic correlation ranges**: Tests with low signal-to-noise ratios typical in finance
- **Skewed distributions**: Tests with non-normal, skewed data distributions
- **Heavy-tailed distributions**: Tests with distributions having extreme outliers

### 6. Batch TC Calculation Tests
- **Batch vs individual consistency**: Ensures batch calculation matches individual calculations
- **Edge cases in batches**: Tests batch processing with various edge case scenarios
- **Dimension mismatch errors**: Validates proper error handling for mismatched dimensions

### 7. Feature Neutralized TC Tests
- **Basic neutralization effect**: Tests TC calculation after feature neutralization
- **Dimension validation**: Tests proper error handling for dimension mismatches
- **Empty features**: Tests behavior when no features are provided for neutralization

### 8. Performance and Scalability Tests
- **Large dataset performance**: Tests TC calculation on datasets with 50,000 samples
- **Memory efficiency**: Validates that calculations don't create excessive temporary arrays
- **Time complexity**: Ensures reasonable execution time for large datasets

### 9. Comparison with MMC Tests
- **Conceptual differences**: Tests scenarios where TC and MMC should differ
- **Identical targets/returns**: Tests behavior when target values equal return values
- **Validation of distinct metrics**: Ensures TC and MMC measure different aspects

### 10. Regression Tests
- **NaN result handling**: Tests fixes for cases that previously returned NaN
- **Numerical stability fixes**: Tests improvements to tie-kept ranking and gaussianization
- **Edge case fixes**: Tests solutions for various edge cases discovered during development

### 11. Documentation Examples
- **Basic usage examples**: Tests simple examples that could appear in documentation
- **Multi-model comparisons**: Tests realistic scenarios with multiple model predictions

## Key Implementation Details Tested

### True Contribution Algorithm Steps
The tests validate each step of the TC calculation:

1. **Rank and Gaussianize Predictions**: 
   - Uses `tie_kept_rank()` to handle tied values properly
   - Applies `gaussianize()` to convert to standard normal distribution

2. **Orthogonalize Returns**: 
   - Uses `orthogonalize()` to remove meta-model component from returns
   - Handles cases where meta-model has zero variance

3. **Correlation Calculation**:
   - Computes correlation between gaussianized predictions and orthogonalized returns
   - Returns 0.0 when orthogonalized returns have zero variance
   - Handles NaN results gracefully

### Error Conditions Tested
- **Dimension mismatches**: All functions validate input dimensions match
- **Invalid inputs**: NaN and infinite values are handled gracefully  
- **Zero variance scenarios**: Functions handle constant inputs appropriately
- **Empty inputs**: Edge cases with empty vectors are managed correctly

### Numerical Robustness
- **Extreme values**: Tests with values spanning from 1e-10 to 1e10
- **Precision requirements**: Validates calculations work with subtle numeric differences
- **Memory efficiency**: Ensures large datasets don't cause memory issues
- **Performance**: Validates reasonable execution time on large datasets

## Test Statistics
- **Total tests**: 92 test cases
- **Coverage areas**: 11 major test categories
- **Edge cases**: Extensive coverage of boundary conditions
- **Performance tests**: Validates scalability to 50,000+ samples
- **Integration tests**: Ensures compatibility with existing codebase

## Usage in Development
These tests serve as:
- **Regression testing**: Prevents introduction of bugs during development
- **Documentation**: Provides examples of expected behavior
- **Validation**: Ensures mathematical correctness of TC calculations
- **Performance monitoring**: Catches performance regressions

The comprehensive test suite ensures the TC implementation is production-ready and mathematically sound for use in the Numerai tournament environment.