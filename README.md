# Numerai Tournament System

A production-ready Julia application for automated Numerai tournament participation with ML capabilities, TUI dashboard, and macOS notifications.

## Features

- 🤖 **Automated Tournament Participation**: Hourly round detection and automatic submissions
- 🎯 **Multi-Target Ensemble**: Support for 20+ Numerai targets with feature neutralization
- 📺 **TUI Dashboard**: Real-time monitoring for comprehensive status tracking
- 🔔 **macOS Notifications**: Native system notifications for important events
- ⚡ **M4 Max Optimized**: Fully utilizes 16 CPU cores and 48GB unified memory

## Configuration

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your Numerai API credentials:
   ```bash
   NUMERAI_PUBLIC_ID=your_public_id
   NUMERAI_SECRET_KEY=your_secret_key
   ```

## Usage

### Run the executable:
```bash
./numerai_jl [options]
```

## TUI Dashboard

The terminal UI provides real-time monitoring with:
- Tournament round status and timing
- Model performance metrics
- Recent event logs
- System resource monitoring

### Keyboard Controls:
- `q` - Quit
- `p` - Pause/Resume training
- `s` - Start Training
- `h` - Show Help
