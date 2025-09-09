# Numerai Tournament System - Implementation Scratchpad

## Project Overview
Building a production-ready Julia application for Numerai tournament participation with:
- Pure Julia ML implementation optimized for M4 Max (16 cores, 48GB memory)
- TUI dashboard for real-time monitoring
- Automated tournament participation with scheduled downloads/submissions
- Multi-model ensemble with gradient boosting
- macOS notifications
- Progress tracking for all operations

## Implementation Plan

### Phase 1: Core Infrastructure ✅
1. Project setup with dependencies (Project.toml) ✅
2. Configuration management (config.toml) ✅
3. Environment variables (.env) ✅

### Phase 2: API Client Module
1. GraphQL client for Numerai API
2. Authentication with API credentials
3. Data download functionality
4. Submission upload functionality
5. Model performance queries

### Phase 3: ML Pipeline
1. Data loading and preprocessing
2. Feature engineering
3. Feature neutralization implementation
4. Model training (XGBoost, LightGBM)
5. Ensemble management
6. Prediction generation

### Phase 4: TUI Dashboard
1. Main dashboard layout with panels
2. Model performance panel
3. Staking status panel
4. Live predictions visualization
5. Event log panel
6. System status bar
7. Interactive controls

### Phase 5: Automation
1. Scheduler for automated tasks
2. Round detection and participation
3. Download scheduling
4. Training and prediction automation
5. Submission automation

### Phase 6: Notifications
1. macOS notification integration
2. Event-based notifications
3. Success/error alerts

### Phase 7: Testing & Optimization
1. Unit tests for all modules
2. Integration tests
3. Performance optimization for M4 Max
4. Memory management
5. Parallel processing optimization

## Current Status
- Starting implementation of API client module
- Need to implement GraphQL queries for Numerai API
- Focus on modular, testable design

## Technical Notes
- Using HTTP.jl for API communication
- Term.jl for TUI dashboard
- XGBoost.jl and LightGBM.jl for models
- ThreadsX.jl for parallel processing
- Cron.jl for scheduling

## TODOs
- [ ] Implement GraphQL client
- [ ] Create data download functionality
- [ ] Build ML pipeline
- [ ] Design TUI layout
- [ ] Set up scheduler
- [ ] Add macOS notifications
- [ ] Write comprehensive tests
