# Numerai Tournament System - Julia Implementation

A production-ready Julia application for automated participation in the Numerai tournament, optimized for M4 Max Mac Studio.

## Features

- **Pure Julia ML Implementation** - XGBoost and LightGBM models with ensemble management
- **TUI Dashboard** - Real-time monitoring with performance metrics, model status, and event logs
- **Automated Tournament Participation** - Scheduled data downloads, training, and submissions
- **Feature Neutralization** - Built-in feature neutralization for improved consistency
- **macOS Notifications** - Native alerts for important events
- **M4 Max Optimization** - Leverages all 16 CPU cores and 48GB unified memory

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
./numerai
```

### Headless Mode (for automation)
```bash
./numerai --headless
```

### Command-Line Operations

#### Download Tournament Data
```bash
./numerai --download
```

#### Train Models
```bash
./numerai --train
```

#### Submit Predictions
```bash
./numerai --submit
```

#### View Model Performance
```bash
./numerai --performance
```

### TUI Dashboard Controls

- `q` - Quit
- `p` - Pause/Resume training
- `s` - Start Training
- `h` - Show Help
- `n` - Create new model

## Architecture

### Core Modules

- **API Client** (`src/api/client.jl`) - GraphQL API integration
- **ML Pipeline** (`src/ml/`) - Model training and prediction
- **TUI Dashboard** (`src/tui/`) - Terminal user interface
- **Scheduler** (`src/scheduler/`) - Automated tournament participation
- **Notifications** (`src/notifications.jl`) - macOS alerts
- **Performance** (`src/performance/`) - M4 Max optimizations

### Data Flow

1. **Data Download** - Fetches latest tournament data (train, validation, live)
2. **Feature Engineering** - Preprocessing and feature neutralization
3. **Model Training** - XGBoost/LightGBM ensemble training
4. **Prediction Generation** - Creates submissions for live data
5. **Submission Upload** - Automatically uploads to Numerai

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
julia --project=. test/test_api.jl        # Test API connectivity
julia --project=. test/test_download.jl   # Test data downloads
julia --project=. test/test_tui.jl        # Test TUI components
```

Run tests with coverage:
```bash
julia --project=. -e "using Pkg; Pkg.test(coverage=true)"
```

## Performance Optimization

The system automatically optimizes for M4 Max:
- Configures BLAS for optimal thread usage
- Manages memory allocation for large datasets
- Parallel processing with ThreadsX.jl
- Efficient data loading with Parquet.jl

For best performance, run Julia with multiple threads:
```bash
julia -t 16 ./numerai
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
├── src/                  # Source code
│   ├── api/             # API client
│   ├── ml/              # ML pipeline
│   ├── tui/             # Dashboard
│   └── scheduler/       # Automation
├── test/                # Test suite
├── data/                # Tournament data
├── models/              # Trained models
├── config.toml          # Configuration
└── numerai              # Executable
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