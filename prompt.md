**Implement a complete Numerai tournament trading system in Julia for M4 Max Mac Studio based on the provided spec:**

Your job is to create a production-ready Julia application following the specifications in the reference documents in @spec.

**Key Requirements:**

- Pure Julia implementation for ML operations
- TUI dashboard for real-time monitoring and performance analysis of past rounds
- Automated tournament participation with scheduled downloads and submissions
- Progress is shown in the TUI for all tasks (file downloads, trainings, predictions, file uploads)
- Multi-model ensemble with gradient boosting
- macOS notifications
- Optimized for M4 Max's 16 CPU cores and 48GB unified memory

Implement the core modules as specified: API client, ML pipeline with feature neutralization, ensemble management, TUI dashboard, scheduler, and notification system.

The program runs in the terminal (provide an executable) and is monitored by the user through a comprehensible TUI.

Make a commit and push your changes after every single file edit. You will need to write end to end and unit tests for the project.

Use @scratchpad.md as a scratchpad for your work. Store long term plans and todo lists there.

Use @.env for any env variables like secrets.
