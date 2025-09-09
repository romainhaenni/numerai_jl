# Numerai Tournament System - Implementation Priority List (Sept 9, 2025)

## Project Status: NEEDS CRITICAL FIXES 🔴

### Priority 1: CRITICAL BUGS (Blocking Functionality) 🔴

1. **Missing API Functions** - Dashboard calls undefined functions
   - **File**: `/Users/romain/src/Numerai/numerai_jl/src/tui/dashboard.jl` lines 342, 374
   - **Issue**: Calls `API.get_model_stakes()` and `API.get_latest_submission()` but these functions don't exist in `/Users/romain/src/Numerai/numerai_jl/src/api/client.jl`
   - **Impact**: Dashboard crashes when trying to display stake information
   - **Priority**: CRITICAL - Blocking TUI functionality

2. **ModelConfig Type Not Defined** - Type used but never declared
   - **File**: `/Users/romain/src/Numerai/numerai_jl/src/tui/dashboard.jl` lines 497, 506
   - **Issue**: Code creates `Pipeline.ModelConfig()` objects but this type doesn't exist
   - **Impact**: Model creation wizard fails
   - **Priority**: CRITICAL - Blocking model creation

3. **MLPipeline Field Mismatch** - Code accesses wrong field names
   - **File**: `/Users/romain/src/Numerai/numerai_jl/src/tui/dashboard.jl` lines 526-527
   - **Issue**: Accesses `pipeline.model_configs` but MLPipeline struct only has `models` field
   - **Impact**: Training progress tracking fails
   - **Priority**: CRITICAL - Blocking training interface

### Priority 2: MAJOR ISSUES (Degraded Functionality) 🟡

4. **Scheduler Using Timer Instead of Cron** - Poor scheduling implementation
   - **File**: `/Users/romain/src/Numerai/numerai_jl/src/scheduler/cron.jl` lines 56-84
   - **Issue**: Uses simple Timer objects instead of proper cron scheduling
   - **Impact**: Inefficient resource usage, not true cron-based automation
   - **Priority**: MAJOR - Degrades automation quality

5. **Training Simulation Using Fake Values** - Dashboard shows fake metrics
   - **File**: `/Users/romain/src/Numerai/numerai_jl/src/tui/dashboard.jl` lines 538, 562-563
   - **Issue**: Uses `rand()` for validation scores and performance metrics instead of real ML results
   - **Impact**: Misleading performance information, not connected to actual training
   - **Priority**: MAJOR - Dashboard not showing real data

6. **Missing Test Coverage for Critical Functions** - Untested API functions
   - **Issue**: Missing functions like `get_model_stakes`, `get_latest_submission` have no tests
   - **Impact**: No validation of API integration, potential runtime failures
   - **Priority**: MAJOR - Quality assurance gaps

### Priority 3: MINOR IMPROVEMENTS (Polish) 🟢

7. **Error Handling Improvements** - Better user feedback needed
   - **Issue**: Some error cases could provide more helpful messages
   - **Impact**: Poor user experience during failures
   - **Priority**: MINOR - Quality of life improvement

8. **Memory Optimization Opportunities** - Potential performance gains
   - **Issue**: Some operations could be more memory efficient
   - **Impact**: Slower performance on large datasets
   - **Priority**: MINOR - Performance optimization

9. **Documentation Gaps** - Some functions lack docstrings
   - **Issue**: Internal functions need better documentation
   - **Impact**: Maintenance difficulty
   - **Priority**: MINOR - Code maintainability

## Implementation Requirements

### Immediate Action Items (Must Fix):
1. **Add missing API functions**: Implement `get_model_stakes()` and `get_latest_submission()` in API client
2. **Define ModelConfig type**: Create proper struct definition for model configuration
3. **Fix field access**: Either rename `models` to `model_configs` in MLPipeline or update dashboard code
4. **Connect real training**: Replace fake random values with actual ML pipeline results

### Secondary Fixes:
5. **Implement proper cron scheduling**: Replace Timer-based system with real cron functionality
6. **Add comprehensive tests**: Cover all API functions and error cases
7. **Improve error handling**: Better user-facing error messages

### Current Test Status:
- Tests pass but don't cover critical missing functionality
- Missing functions are not tested (because they don't exist)
- Integration between TUI and ML pipeline not properly tested

## Assessment Summary

**Reality Check**: The scratchpad claiming "100% complete" and "all tests passing" is **incorrect**. The codebase has critical bugs that prevent core functionality from working. The TUI dashboard contains multiple calls to undefined functions and uses fake data instead of real ML results.

**Confidence Level**: LOW - System not production ready due to blocking bugs
**Immediate Priority**: Fix the 3 critical bugs before any other work