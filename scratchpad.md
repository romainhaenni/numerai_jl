# Numerai Tournament System - TUI Fix Plan (v0.10.27)

## 🚨 CRITICAL TUI ISSUES TO FIX

### User-Reported Issues (All Currently BROKEN):
1. ❌ **Progress bars don't show** when downloading/uploading/training/predicting
2. ❌ **Commands require Enter key** - should execute instantly without Enter
3. ❌ **No auto-training** after downloads complete
4. ❌ **Status not updating** - system info and events are static
5. ❌ **No sticky panels** - top system info and bottom events should be sticky

### Root Causes Identified:
1. **Disconnected Progress System**: API callbacks not connected to TUI updates
2. **Raw TTY Mode Not Working**: Terminal input still line-buffered
3. **Multiple Conflicting Renderers**: 5 different render systems interfering
4. **Auto-Training Logic Disconnected**: Download completion doesn't trigger training
5. **ANSI Positioning Conflicts**: Multiple screen clears destroy sticky panels

## 📋 Implementation Plan

### Phase 1: Consolidate Progress Tracking
- [ ] Create single ProgressState struct in dashboard.jl
- [ ] Remove duplicate trackers from enhanced_dashboard.jl and tui_realtime.jl
- [ ] Connect API progress callbacks to single tracker
- [ ] Implement progress bars for download/upload/training/prediction

### Phase 2: Fix Raw TTY Mode
- [ ] Implement proper terminal state management
- [ ] Add non-blocking key reading with timeout
- [ ] Handle Ctrl+C and cleanup on exit
- [ ] Test instant command execution

### Phase 3: Unify Rendering System
- [ ] Use single render function in dashboard.jl
- [ ] Remove competing render functions from other modules
- [ ] Implement proper sticky panels with ANSI positioning
- [ ] Fix screen flickering from multiple clears

### Phase 4: Connect Auto-Training
- [ ] Link download completion events to training trigger
- [ ] Check config.auto_train_after_download flag
- [ ] Start training automatically when all data downloaded
- [ ] Show notification when auto-training starts

### Phase 5: Real-Time Updates
- [ ] Create single update loop in main dashboard
- [ ] Update system info every second
- [ ] Refresh events as they occur
- [ ] Show live progress for all operations

## 🔧 Files to Modify

1. **src/tui/dashboard.jl** - Main consolidation point
2. **src/tui/dashboard_commands.jl** - Add progress callbacks
3. **src/api/client.jl** - Ensure callbacks are called
4. **Remove/Deprecate**: unified_tui_fix.jl, tui_comprehensive_fix.jl, tui_realtime.jl (keep minimal)

## ✅ Success Criteria
- Progress bars visible and updating for all operations
- Single keypress executes commands (no Enter needed)
- Training starts automatically after download completes
- System info updates every second
- Events panel shows last 30 events with scrolling
- Top and bottom panels stay in fixed positions