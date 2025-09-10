# Numerai Tournament System - Bug Fixes and Missing Implementations

## HIGH PRIORITY ISSUES TO FIX:

### 1. **CRITICAL - Missing BSON Dependency**
   - BSON package used in neural networks but not in Project.toml
   - Prevents compilation and tests from running
   - Add: BSON = "fbb218c0-5317-5bc6-957e-2ee96dd4b1f0"

### 2. **V5 Dataset Feature Set Limitation**
   - Hardcoded to only use 'medium' feature set
   - File: src/ml/dataloader.jl:250
   - Need to add configuration for small/medium/large feature sets

### 3. **API Tournament ID Hardcoding**
   - Tournament 8 hardcoded throughout API client
   - No support for Signals tournament (ID 11)
   - Need abstraction for multi-tournament support

## MEDIUM PRIORITY IMPROVEMENTS:

### 4. **TUI Error Handling**
   - Silent API failures don't inform users
   - Need proper error categorization and user feedback

### 5. **Test Coverage Gaps**
   - Missing tests for: Logger, Utils, GPU Metal, Notifications, Performance modules
   - Need dedicated test files for these modules

### 6. **Feature Groups Not Integrated**
   - Feature groups parsing exists but not used in workflow
   - File: src/ml/dataloader.jl:152-164

### 7. **Multi-Target Support Missing**
   - V5 dataset has multiple targets but only primary used
   - Need multi-target training capability

### 8. **Notification System Limited**
   - Only macOS support, no Linux/Windows
   - No throttling or rich formatting

## LOW PRIORITY ENHANCEMENTS:

### 9. **Configuration Management**
   - Many hardcoded values in TUI (refresh intervals, limits)
   - Should be user-configurable

### 10. **Missing API Features**
   - Leaderboard access
   - Historical performance trends
   - Webhook management