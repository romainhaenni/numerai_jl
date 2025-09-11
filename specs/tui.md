## TUI Dashboard Features Summary

The Numerai Trading System TUI provides a comprehensive real-time monitoring interface directly in your terminal:

**Key Requirements:**

- Pure Julia implementation for ML operations
- TUI dashboard for real-time monitoring and performance analysis of past rounds
- Automated tournament participation with scheduled downloads and submissions
- Progress is shown in the TUI for all tasks (file downloads, trainings, predictions, file uploads)
- Optimized for M4 Max's 16 CPU cores and 48GB unified memory
- Status Panels are split horizontally, with an additional event log panel below the status panels


### **📊 Model Performance Panel**
- **Live correlation metrics** for each model in your ensemble
- **Sharpe ratio tracking** to monitor risk-adjusted returns
- **MMC (Meta Model Contribution)** scores showing unique value added
- **FNC (Feature Neutral Correlation)** displaying neutralization effectiveness
- Tabular format with color-coded values for quick scanning

### **💰 Staking Status Panel**
- **Total NMR staked** across all models
- **At-risk amounts** for current round
- **Expected payouts** based on recent performance
- **Current round number** and submission status
- Real-time updates as rounds progress

### **📈 Live Predictions Visualization**
- **Sparkline charts** showing prediction history trends
- Visual representation of model confidence over time
- 8-row height graph for detailed pattern recognition
- Auto-scaling to show relevant data ranges

### **🔔 Recent Events Log**
- **Timestamped event stream** with 30 most recent activities
- **Color-coded messages** by type:
  - 🟢 Green for successful submissions
  - 🔴 Red for errors requiring attention
  - 🟡 Yellow for warnings
  - ⚪ White for general information
- Includes submission confirmations, training completions, and system alerts

### **⚙️ System Status Bar**
- **CPU usage percentage** with performance core utilization
- **Memory consumption** in GB (crucial for 48GB M4 Max monitoring)
- **Active vs total models** counter
- **System uptime** formatted as days/hours/minutes
- Real-time resource monitoring without external tools

### **Interactive Controls**
- `q` - Quit
- `p` - Pause/Resume training
- `s` - Start Training
- `h` - Show Help
- `n` - create new model with wizard for any settings
- Keyboard-driven interface for efficiency

### **Visual Design Elements**
- **Panel-based layout** with clear separation of concerns
- **6-column grid system** for responsive information display
- **Emoji indicators** for quick visual parsing (🤖📊💰📈🔔⚙️)
- Optimized for standard terminal sizes while scaling gracefully

### **Real-time Updates**
- **Asynchronous data refresh** without blocking the UI
- **Event-driven architecture** for instant notification display
- **Auto-updating metrics** as new tournament data arrives

### **Integration Features**
- **Direct connection to ML pipeline** - shows training progress in real-time
- **API status monitoring** - displays connection health to Numerai servers

This TUI transforms your terminal into a professional-grade trading dashboard, providing all essential information at a glance while maintaining the efficiency and simplicity of a text-based interface. It's designed specifically for traders who prefer keyboard-driven workflows and want to monitor their Numerai tournament participation without leaving their development environment.
