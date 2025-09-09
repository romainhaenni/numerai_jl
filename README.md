# Numerai Tournament Trading System - Julia Implementation

A production-ready Julia application for automated participation in the Numerai tournament, optimized for M4 Max Mac Studio.

## Features

- 🤖 **Multi-Model Ensemble**: XGBoost and LightGBM with advanced feature neutralization
- 📊 **Real-time TUI Dashboard**: Monitor performance, staking, and predictions
- ⏰ **Automated Scheduler**: Handles all tournament rounds automatically
- 🔔 **macOS Notifications**: Native alerts for important events
- 🚀 **M4 Max Optimized**: Leverages 16 CPU cores and 48GB unified memory
- 📈 **Live Performance Tracking**: Real-time correlation, MMC, FNC, and Sharpe metrics

## Installation

1. Install Julia 1.10+ from https://julialang.org/downloads/

2. Clone the repository:
```bash
git clone https://github.com/yourusername/numerai_jl.git
cd numerai_jl
```

3. Install dependencies:
```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

4. Set up your Numerai API credentials in `.env`:
```bash
NUMERAI_PUBLIC_ID=your_public_key
NUMERAI_SECRET_KEY=your_secret_key
```

## Usage

### Interactive Dashboard
```bash
./numerai
```

**Keyboard Controls:**
- `q` - Quit
- `p` - Pause/Resume training
- `s` - Start training
- `r` - Refresh data
- `n` - New model wizard
- `h` - Toggle help
- `↑/↓` - Navigate models
- `Enter` - View model details

### Automated Scheduler
```bash
./numerai --headless
```

Runs continuously and:
- Downloads data for each round
- Trains/updates models
- Generates and submits predictions
- Monitors performance
- Sends macOS notifications

### Manual Operations

**Download tournament data:**
```bash
./numerai --download
```

**Train models:**
```bash
./numerai --train
```

**Submit predictions:**
```bash
./numerai --submit --model main_model
```

**Show model performances:**
```bash
./numerai --performance
```

## Configuration

Edit `config.toml` to customize:

```toml
# Models to manage
models = ["main_model", "experimental_model"]

# Tournament settings
auto_submit = true
stake_amount = 100.0

# Training parameters
[training]
target_column = "target_cyrus_v4_20"
neutralize = true
neutralize_proportion = 0.5
```

## TUI Dashboard

The dashboard provides six real-time panels:

### 📊 Model Performance
- Live correlation metrics for each model
- MMC, FNC, and Sharpe ratios
- Active/inactive status indicators

### 💰 Staking Status
- Total NMR staked
- At-risk amounts
- Expected payouts
- Current round information

### 📈 Live Predictions
- Sparkline visualization of predictions
- Statistical summaries
- Historical trends

### 🔔 Recent Events
- Timestamped activity log
- Color-coded by severity
- Submission confirmations

### ⚙️ System Status
- CPU and memory usage
- Active model count
- System uptime

### 🚀 Training Progress
- Real-time training metrics
- Epoch progress
- Validation scores

## Architecture

### Core Modules

- **API Client**: GraphQL interface for Numerai API
- **ML Pipeline**: Ensemble model training and prediction
- **Feature Neutralization**: Advanced neutralization techniques
- **Data Pipeline**: Efficient Parquet file handling
- **TUI Dashboard**: Term.jl-based real-time interface
- **Scheduler**: Cron-based tournament automation
- **Notifications**: Native macOS alerts

### Performance Optimizations

- Multi-threaded training using all 16 cores
- Memory-efficient data structures
- Lazy data loading for large datasets
- Optimized feature neutralization algorithms

## Testing

Run the test suite:
```bash
julia --project=. test/runtests.jl
```

## Tournament Schedule

- **Weekend Rounds**: Saturday 18:00 UTC - Monday 14:30 UTC
- **Daily Rounds**: Tuesday-Friday (shorter windows)
- **Automatic Participation**: Scheduler handles all submissions

## Requirements

- macOS (optimized for M4 Max)
- Julia 1.10+
- 8GB+ RAM recommended
- Active Numerai account
- API credentials

## License

MIT License

## Support

For issues or questions:
- Open an issue on GitHub
- Check Numerai forums: https://forum.numer.ai/
- Review official docs: https://docs.numer.ai/
