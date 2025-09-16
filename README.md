# Numerai Tournament System - Julia Implementation

A production-ready Julia application for automated participation in the Numerai tournament, optimized for M4 Max Mac Studio with comprehensive ML models and advanced TUI dashboard.

## ✅ Current Status

**PRODUCTION READY (v0.10.31)** - All systems operational with working API authentication and full tournament functionality. TUI dashboard now has ALL features working properly.

## 🚀 Key Features

### Machine Learning Pipeline
- **9 Model Types** - XGBoost, LightGBM, CatBoost, EvoTrees, Neural Networks (MLP, ResNet), Linear Models (Ridge, Lasso, ElasticNet)
- **Multi-Target Support** - Both V4 (single) and V5 (multi-target) predictions
- **Ensemble Management** - Weighted predictions combining multiple models
- **Feature Engineering** - Neutralization, interaction constraints, feature groups
- **Hyperparameter Optimization** - Bayesian, grid, and random search strategies

### Advanced TUI Dashboard (v0.10.31 - All Features Working)
- **Real Progress Bars** - Live progress tracking for downloads, training, predictions, and uploads
- **Instant Commands** - Single-key commands work without Enter key (d/t/p/s/r/q)
- **Auto-Training** - Automatically starts training after all datasets are downloaded
- **Real-Time Monitoring** - System info updates every second with actual CPU/memory/disk metrics
- **Sticky Panels** - Fixed top panel for system status, fixed bottom panel for event logs
- **Visual Progress Tracking** - Progress bars with MB/percentage indicators

### System Features
- **Automated Tournament Participation** - Scheduled data downloads, training, and submissions
- **GPU Acceleration** - Apple Metal support for M-series chips with automatic CPU fallback
- **macOS Notifications** - Native alerts for important events
- **M4 Max Optimization** - Leverages all 16 CPU cores and 48GB unified memory
- **Thread-Safe Architecture** - Concurrent operations with proper resource management

## Installation

### Prerequisites

- Julia 1.10 or higher
- macOS (optimized for Apple Silicon)
- Numerai API credentials

### Setup

1. Clone the repository:
```bash
git clone https://github.com/romainhaenni/numerai_jl.git
cd numerai_jl
```

2. Install Julia dependencies:
```bash
julia -e "using Pkg; Pkg.activate(\".\"); Pkg.instantiate()"
```

3. Configure your API credentials in `.env`:
```bash
NUMERAI_PUBLIC_ID=your_public_id_here
NUMERAI_SECRET_KEY=your_secret_key_here
```

To get valid API credentials:
- Go to https://numer.ai/account
- Navigate to the API/Compute section
- Generate a new API key pair
- Copy both the Public ID (32 chars) and Secret Key (64 chars)

Validate your credentials:
```bash
julia --project=. examples/validate_credentials.jl
```

4. Configure tournament settings in `config.toml`:
```toml
models = ["your_model_name"]
data_dir = "data"
model_dir = "models"
auto_submit = false
stake_amount = 0.0
max_workers = 16
```

## Usage

### Interactive Dashboard
```bash
# Start with default number of threads
julia start_tui.jl

# Recommended: Start with multiple threads for better performance
julia -t auto start_tui.jl

# Or specify exact number of threads (e.g., 16 for M4 Max)
julia -t 16 start_tui.jl
```

### Headless Mode (for automation)
```bash
julia start_tui.jl --headless
```

### Command-Line Operations

#### Download Tournament Data
```bash
julia start_tui.jl --download
```

#### Train Models
```bash
julia start_tui.jl --train
```

#### Submit Predictions
```bash
julia start_tui.jl --submit
```

#### View Model Performance
```bash
julia start_tui.jl --performance
```

### TUI Dashboard Controls

#### Keyboard Shortcuts
- `q` - Quit application
- `p` - Pause/Resume training
- `s` - Start training pipeline
- `h` - Show help menu
- `n` - Launch model creation wizard
- `/` - Enter command mode
- `ESC` - Cancel current operation

#### Available Commands
- `/new` - Create new model with wizard
- `/train` - Start training pipeline
- `/submit` - Submit predictions to Numerai
- `/stake <amount>` - Set stake amount for model
- `/download` - Download latest tournament data
- `/refresh` - Refresh model performances
- `/diag` - Run system diagnostics
- `/network` - Test network connectivity
- `/help` - Show available commands

## Architecture

### Core Modules

- **API Client** (`src/api/client.jl`) - GraphQL API integration
- **ML Pipeline** (`src/ml/`) - Model training and prediction
- **TUI Dashboard** (`src/tui/`) - Terminal user interface
- **Scheduler** (`src/scheduler/`) - Automated tournament participation
- **Notifications** (`src/notifications.jl`) - macOS alerts
- **Performance** (`src/performance/`) - M4 Max optimizations

### Data Flow

1. **Data Download** - Fetches latest tournament data (train, validation, live) with automatic format detection
2. **Feature Engineering** - Preprocessing, neutralization, interaction constraints, feature groups
3. **Model Training** - Multiple algorithms with hyperparameter optimization and callbacks
4. **Ensemble Creation** - Combines predictions from multiple models with weighted averaging
5. **Prediction Generation** - Creates submissions for live data with validation checks
6. **Submission Upload** - Automatically uploads to Numerai with retry logic

## Testing

Run ALL tests:
```bash
# Recommended: Run full test suite with proper project environment
julia --project=. -e "using Pkg; Pkg.test()"

# Alternative: Direct test runner
julia --project=. test/runtests.jl
```

Run specific tests:
```bash
julia --project=. test/test_api.jl               # Test API connectivity
julia --project=. test/test_tui.jl               # Test TUI components
julia --project=. test/test_gpu_metal.jl         # Test GPU acceleration
julia --project=. test/test_e2e_comprehensive.jl # Comprehensive end-to-end tests
julia --project=. test/test_multi_target.jl      # Test multi-target support
```

Run tests with coverage:
```bash
julia --project=. -e "using Pkg; Pkg.test(coverage=true)"
```

## Performance Optimization

### Automatic Optimizations
The system automatically optimizes for M4 Max:
- Configures BLAS for optimal thread usage
- Manages memory allocation for large datasets
- Parallel processing with ThreadsX.jl
- Efficient data loading with Parquet.jl
- GPU acceleration with Metal.jl for neural networks
- Smart caching for frequently accessed data

### Performance Tips
- Use `feature_set = "small"` for faster iteration during development
- Enable GPU with `use_gpu = true` in neural network models
- Adjust `batch_size` based on available memory
- Use ensemble of smaller models for better generalization

For best performance, run Julia with multiple threads:
```bash
julia -t 16 start_tui.jl
```

## Tournament Schedule

The scheduler automatically handles:
- **Weekend Rounds** - Saturday 18:00 UTC
- **Daily Rounds** - Tuesday-Friday 18:00 UTC
- **Weekly Retraining** - Monday 12:00 UTC
- **Hourly Monitoring** - Performance tracking and alerts

## Troubleshooting

### Common Issues

1. **API Authentication Failed**
   - Verify credentials in `.env`
   - Check API key permissions on numer.ai

2. **Download Errors**
   - Ensure stable internet connection
   - Check available disk space

3. **Memory Issues**
   - Reduce `sample_pct` in training
   - Lower `max_workers` in config

4. **TUI Display Issues**
   - Ensure terminal supports Unicode
   - Try different terminal emulator

## Development

### Project Structure
```
numerai_jl/
├── src/                    # Source code
│   ├── api/               # GraphQL API client with retry logic
│   ├── ml/                # ML pipeline
│   │   ├── models.jl      # Model implementations
│   │   ├── neural_networks.jl  # MLP and ResNet
│   │   ├── ensemble.jl    # Ensemble management
│   │   ├── hyperopt.jl    # Hyperparameter optimization
│   │   └── metrics.jl     # Performance metrics
│   ├── tui/               # Terminal UI dashboard
│   │   ├── dashboard.jl   # Main dashboard logic
│   │   ├── grid.jl        # 6-column grid system
│   │   ├── panels.jl      # UI panels
│   │   └── dashboard_commands.jl  # Command handlers
│   ├── gpu/               # GPU acceleration
│   ├── data/              # Data processing
│   └── scheduler/         # Automation & scheduling
├── test/                  # Comprehensive test suite
├── examples/              # Example scripts
├── data/                  # Tournament data
├── models/                # Trained models
├── config.toml            # Configuration
└── start_tui.jl           # TUI starter script
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Numerai for providing the tournament platform
- Julia ML community for excellent packages
- Term.jl for TUI capabilities

## Support

For issues or questions:
- Open an issue on GitHub
- Check Numerai forums for tournament-specific questions
- Review documentation in `spec/` directory