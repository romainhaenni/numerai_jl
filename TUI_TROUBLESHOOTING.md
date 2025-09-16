# TUI Dashboard Troubleshooting Guide

## Current Status: PRODUCTION READY ✅

The TUI dashboard (v0.10.36) has been comprehensively tested and verified to be fully functional.

## Verified Working Components

All components have been tested and confirmed working:

1. **System Monitoring** ✅
   - Real CPU usage from `Sys.loadavg()`
   - Real memory from `Sys.total_memory()` and `Sys.free_memory()`
   - Real disk space from `df` command via `Utils.get_disk_space_info()`

2. **Auto-Start Pipeline** ✅
   - Configuration properly loaded from config.toml
   - `auto_start_pipeline = true` correctly set
   - Auto-start conditions met when TUI runs

3. **Keyboard Commands** ✅
   - Command channel properly initialized
   - Raw terminal mode enabled for instant response
   - Single-key commands (d/t/p/s/r/q) handled without Enter

4. **Progress Bars** ✅
   - Download progress with real MB tracking
   - Training progress with epoch/iteration tracking
   - Upload progress with file tracking
   - Prediction progress with batch tracking

5. **API Client** ✅
   - Successfully initialized with credentials from config.toml
   - Ready for real tournament operations

## Running the TUI

### Basic Start
```bash
julia start_tui.jl
```

### With Multiple Threads (Recommended)
```bash
julia -t auto start_tui.jl
```

### What Happens on Startup

1. **Initialization**
   - Loads configuration from config.toml
   - Creates dashboard with real system values
   - Initializes API client if credentials valid

2. **Auto-Start (if enabled)**
   - Checks `auto_start_pipeline` setting
   - Automatically begins download pipeline
   - Shows progress bars for each operation

3. **Keyboard Input**
   - Sets terminal to raw mode
   - Listens for single-key commands
   - No Enter key required

4. **Main Loop**
   - Updates system info every second
   - Renders dashboard with real values
   - Processes keyboard commands instantly

## Common Issues and Solutions

### Issue: TUI doesn't start
**Solution:** Check Julia installation and dependencies
```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

### Issue: No auto-start happening
**Solution:** Verify config.toml settings
```bash
julia --project=. -e "using NumeraiTournament; c=NumeraiTournament.load_config(); println(\"auto_start_pipeline: \", c.auto_start_pipeline)"
```

### Issue: Keyboard commands not working
**Solution:** Ensure terminal supports raw mode. Try different terminal emulator.

### Issue: System values showing 0.0
**Solution:** This should not happen. Run verification:
```bash
julia --project=. test_and_fix_tui.jl
```

## Verification Tests

Run these tests to verify your installation:

### 1. Component Test
```bash
julia --project=. test_and_fix_tui.jl
```
This verifies all components are working.

### 2. Mini TUI Test
```bash
julia --project=. test_mini_tui.jl
```
This tests dashboard creation and state.

### 3. System Monitoring Test
```bash
julia --project=. -e "using NumeraiTournament; d=NumeraiTournament.Utils.get_disk_space_info(); println(\"Disk: \", d.free_gb, \" GB free\")"
```

## Expected Behavior

When you run `julia start_tui.jl`, you should see:

1. **Initial Messages**
   - "Welcome to Numerai TUI v0.10.37" (version label is incorrect but functionality is v0.10.36)
   - "Press keys for instant commands (no Enter needed)"
   - "System monitoring with REAL CPU/Memory/Disk values"

2. **Auto-Start (if enabled)**
   - "Auto-starting pipeline: initiating downloads..."
   - Progress bars showing download progress

3. **Real-Time Updates**
   - System stats updating every second
   - Event log showing operations
   - Progress bars animating during operations

## Configuration

Ensure your `config.toml` has these settings for auto-start:

```toml
auto_submit = true
auto_train_after_download = true
auto_start_pipeline = true
```

## Support

If issues persist after verification:
1. Check terminal compatibility
2. Verify Julia version (1.10+)
3. Review error messages in terminal
4. Check API credentials are valid

The TUI has been thoroughly tested and verified working. Most issues are configuration or environment related.