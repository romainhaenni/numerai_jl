# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

### Setup and Dependencies
```bash
# Activate project and install dependencies
julia --project=. -e "using Pkg; Pkg.instantiate()"

# Precompile packages for faster startup
julia --project=. -e "using Pkg; Pkg.precompile()"

# Update all packages
julia --project=. -e "using Pkg; Pkg.update()"
```

### Running Tests
```bash
# Run all tests with correct project environment
julia --project=. -e "using Pkg; Pkg.test()"

# Run tests directly (faster for development)
julia --project=. test/runtests.jl

# Run individual test files standalone
julia --project=. test/test_api.jl
julia --project=. test/test_production_ready.jl
julia --project=. test/test_gpu_metal.jl

# Run tests with coverage
julia --project=. -e "using Pkg; Pkg.test(coverage=true)"

# Note: CondaPkg initialization on first run is normal - creates Python dependencies for CatBoost
```

### Main Application
```bash
# Run TUI dashboard (recommended: use multiple threads)
julia -t 16 ./numerai

# Run in headless mode for automation
./numerai --headless

# Train models
./numerai --train

# Submit predictions
./numerai --submit

# Download tournament data
./numerai --download
```

## High-Level Architecture

### Module Hierarchy and Dependencies
The codebase follows a layered architecture with clear separation of concerns:

1. **Core Infrastructure Layer** (`src/`)
   - `NumeraiTournament.jl`: Main module that orchestrates all components
   - `logger.jl`: Centralized logging with thread-safe operations
   - `utils.jl`: Shared utility functions
   - Module loading order is critical - base modules must load before dependent ones

2. **API Integration Layer** (`src/api/`)
   - `client.jl`: GraphQL API client with retry logic, handles all Numerai API interactions
   - `retry.jl`: Exponential backoff retry mechanism for API resilience
   - `schemas.jl`: Type definitions for API responses
   - Uses environment variables NUMERAI_PUBLIC_ID and NUMERAI_SECRET_KEY for authentication

3. **Machine Learning Pipeline** (`src/ml/`)
   - `pipeline.jl`: Orchestrates the entire ML workflow, supports both single and multi-target predictions
   - `models.jl`: Base model interface and implementations (XGBoost, LightGBM, EvoTrees, CatBoost)
   - `neural_networks.jl`: Neural network models (MLP, ResNet) using Flux.jl
   - `linear_models.jl`: Linear models (Ridge, Lasso, ElasticNet)
   - `ensemble.jl`: Model ensemble management with weighted predictions
   - `metrics.jl`: Performance metrics including TC (True Contribution) and MMC calculations
   - `hyperopt.jl`: Hyperparameter optimization with Bayesian, grid, and random search
   - `dataloader.jl`: Feature groups and data loading with interaction constraints support
   - `neutralization.jl`: Feature neutralization for reducing exposure

4. **Data Processing Layer** (`src/data/`)
   - `preprocessor.jl`: Data preprocessing, normalization, and memory-efficient operations
   - `database.jl`: SQLite-based persistence for predictions and model metadata

5. **GPU Acceleration** (`src/gpu/`)
   - `metal_acceleration.jl`: Apple Metal GPU support for M-series chips
   - `benchmarks.jl`: GPU performance benchmarking utilities
   - Automatic fallback to CPU when GPU unavailable

6. **User Interface** (`src/tui/`)
   - `dashboard.jl`: Main TUI dashboard with real-time monitoring
   - `panels.jl`: Individual dashboard panels (models, performance, events)
   - `charts.jl`: Data visualization components
   - `dashboard_commands.jl`: Command handling for interactive mode
   - All UI parameters configurable via `config.toml`

7. **Automation** (`src/scheduler/`)
   - `cron.jl`: Tournament scheduling with automatic data download, training, and submission
   - Handles weekend and daily rounds with proper UTC timing

### Key Design Patterns

1. **Multi-Target Support**: The pipeline can handle both single target (V4) and multi-target (V5) predictions
   - Automatic detection based on input configuration
   - Backward compatible with existing single-target code
   - Neural networks support multi-target natively

2. **Feature Groups**: Models support feature interaction constraints
   - XGBoost uses JSON format
   - LightGBM uses Vector{Vector{Int}} format
   - Configured via features.json metadata

3. **Memory Management**: 
   - In-place DataFrame operations to reduce allocations
   - Safe matrix allocation with memory checking
   - Thread-safe parallel processing with locks

4. **Abstract Type Hierarchy**:
   - All models inherit from `NumeraiModel` abstract type
   - Consistent interface: `train!`, `predict`, `feature_importance`, `save_model`, `load_model!`

## Configuration

### Required Environment Variables
```bash
NUMERAI_PUBLIC_ID=your_public_id
NUMERAI_SECRET_KEY=your_secret_key
```

### Main Configuration File (`config.toml`)
- Tournament settings (tournament_id: 8 for Classic, 11 for Signals)
- Model configurations and training parameters
- TUI display settings (refresh rates, panel sizes, chart dimensions)
- Automation settings (auto_submit, stake_amount)
- System resources (max_workers, notification settings)

### Feature Configuration
- Feature groups defined in `data/features.json`
- Supports small/medium/all feature sets
- Interaction constraints for tree-based models

## Critical Implementation Details

### Test Suite Status
- Integration tests have failures: 97 passed, 10 failed, 24 errored
- API logging MethodError needs resolution before production
- Test files organized in `test/` directory
- Example scripts in `examples/` directory

### Known Limitations
1. **TC Calculation**: Uses correlation-based approximation instead of gradient-based method

### Performance Optimizations
- Configured for M4 Max with 16 CPU cores
- Metal GPU acceleration for neural networks
- Parallel processing with ThreadsX.jl
- BLAS thread optimization for linear algebra

## Development Workflow

### Adding New Models
1. Create model struct inheriting from `NumeraiModel` in `src/ml/models.jl`
2. Implement required interface methods: `train!`, `predict`, `feature_importance`
3. Add to model factory in `create_model` function
4. Update exports in main module

### Modifying Pipeline
1. Changes to `MLPipeline` struct require updates to constructor
2. Maintain backward compatibility for single-target workflows
3. Update `prepare_data` and prediction functions accordingly

### API Changes
1. GraphQL queries/mutations defined in `src/api/client.jl`
2. Retry logic configured in `src/api/retry.jl`
3. Schema updates go in `src/api/schemas.jl`

## Tournament Schedule
- Weekend rounds: Saturday 18:00 UTC
- Daily rounds: Tuesday-Friday 18:00 UTC
- Retraining: Monday 12:00 UTC
- All times handled in UTC with automatic timezone conversion