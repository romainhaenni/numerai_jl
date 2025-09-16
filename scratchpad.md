# Numerai Tournament System - Critical TUI Issues to Fix

## 🚨 CURRENT ISSUES (User Reported - September 2025)

### 1. ❌ Auto-start pipeline NOT working
   - Pipeline is not initiated on startup even when configured
   - auto_start_initiated flag set too early and never reset
   - Need to fix logic in tui_production_v047.jl lines 1110-1127

### 2. ❌ Disk space shows 0.0/0.0 GB
   - get_disk_space_info() returning default zeros
   - df command parsing failing silently on macOS
   - Need to fix parsing in utils.jl lines 184-191

### 3. ❌ Keyboard commands not responding
   - Complex input handling with race conditions
   - Only handles ASCII chars, might miss inputs
   - Terminal raw mode issues on some systems
   - Need to fix lines 1056-1142 in tui_production_v047.jl

### 4. ✅ Progress bars ARE implemented correctly
   - Download progress works (lines 280-337)
   - Training progress works (lines 472-505)
   - Upload progress works (lines 590-655)
   - These are actually working!

### 5. ❌ Auto-training after download not triggering
   - Logic exists but depends on download success flag
   - May not be triggered due to other issues
   - Lines 378-401 in tui_production_v047.jl

## Priority Order:
1. Fix disk space monitoring (utils.jl)
2. Fix auto-start pipeline logic
3. Fix keyboard input handling
4. Fix auto-training trigger
5. Test all fixes together

## Note:
The scratchpad was previously incorrect claiming v0.10.48 was production ready. The actual state has multiple critical bugs that need immediate fixing.