
Fix More Issues:
- in TUI, provide one panel that contains all the information (sticky to the top of the terminal):
```
🔧 SYSTEM DIAGNOSTICS:
   CPU Usage: 89% (Load: 10.69, 6.34, 4.97)
   Memory: 46.3 GB / 48.0 GB (96%)
   Disk Space: 0.0 GB free / 0.0 GB total
   Process Memory: 0.0 MB
   Threads: 16 (Julia: 16)
   Uptime: 0s

⚙️  CONFIGURATION STATUS:
   API Keys: ✅ Set via ENV (I3ME...BV7E, 337B...SBHE)
   Tournament ID: 8
   Data Directory: ✅ data
   Models Directory: ✅ models
   Feature Set: medium
   Environment Variables: NUMERAI_PUBLIC_ID=***, NUMERAI_SECRET_KEY=***, JULIA_NUM_THREADS=16..., PATH=/Users/romain/src/Nu...

📊 CURRENT MODEL STATUS:
   Model: numeraijl
   Active: No

📁 LOCAL DATA FILES:
   Model Files:
   Data Files:
     • features.json (283.9 KB, 2025-09-15 06:48)
     • live.parquet (7.9 MB, 2025-09-15 06:45)
     • train.parquet (2.2 GB, 2025-09-15 06:43)
     • validation.parquet (3.3 GB, 2025-09-15 06:45)
   Config Files:
     • config.toml (956 B, 2025-09-12 10:40)

💾 LAST KNOWN GOOD STATE:
   ❌ No previous good state recorded

🌐 NETWORK STATUS:
   Connection: ✅ Connected
   Last Check: 2025-09-15T07:46:33.622
   API Latency: 0.0ms
   Consecutive Failures: 0

🔍 TROUBLESHOOTING SUGGESTIONS:
   1. Check Numerai API status at https://status.numer.ai
   2. Reduce API request frequency by increasing refresh_rate in config.toml
   3. Try running: r to retry dashboard initialization

⌨️  RECOVERY COMMANDS:
   r  - Retry dashboard initialization
   n  - Test network connectivity
   c  - Check configuration files
   d  - Download fresh tournament data
   l  - View detailed error logs
   s  - Start training (original functionality)
   /save - Save current diagnostic report
   /diag - Run full system diagnostics
   /reset - Reset all error counters
   /backup - Create configuration backup
   q  - Quit dashboard
   h  - Show help
```
-> below this panel there is another panel that is listing up the revent events
-> the info and events panel are updating all the time so that these panels show really the current state of the pipeline and system

- bug:
```
⚠️  RENDERING ERROR DETAILS:
   Error Type: MethodError
   Message: MethodError(haskey, (TournamentDashboard(TournamentConfig("I3MEFCUZJQ4BEU5TSO7MY7XDIU2UBV7E", "337BEF4U2RZO6VOUHJGSOHAIWB7XT2M56PNL66HMS6KVWPZRC4XPMVEIVDLVSBHE", ["numeraijl"], "data", "models", true, 1.0, 12, 8, "medium", false, 1.0, 100.0, 10000.0, Dict{String, Any}("training" => Dict("progress_bar_width" => 20, "default_epochs" => 100), "refresh_rate" => 1.0, "network_timeout" => 5, "network_check_interval" => 60.0, "panels" => Dict("staking_panel_width" => 40, "predictions_panel_width" => 40, "events_panel_width" => 60, "training_panel_width" => 40, "events_panel_height" => 22, "system_panel_width" => 40, "help_panel_width" => 40, "model_panel_width" => 60), "charts" => Dict{String, Real}("correlation_bar_width" => 20, "sparkline_width" => 40, "sparkline_height" => 8, "histogram_width" => 40, "correlation_positive_threshold" => 0.02, "performance_sparkline_height" => 4, "correlation_negative_threshold" => -0.02, "histogram_bins" => 20, "mini_chart_width" => 10, "bar_chart_width" => 40, "performance_sparkline_width" => 30), "model_update_interval" => 30.0, "limits" => Dict("performance_history_max" => 100, "events_history_max" => 100, "api_error_history_max" => 50, "max_events_display" => 20)), 0.1, "target_cyrus_v4_20", false, 0.5, true, 52, 2), NumeraiTournament.API.NumeraiClient("I3MEFCUZJQ4BEU5TSO7MY7XDIU2UBV7E", "337BEF4U2RZO6VOUHJGSOHAIWB7XT2M56PNL66HMS6KVWPZRC4XPMVEIVDLVSBHE", Dict("Accept" => "application/json", "Content-Type" => "application/json", "Authorization" => "Token I3MEFCUZJQ4BEU5TSO7MY7XDIU2UBV7E\$337BEF4U2RZO6VOUHJGSOHAIWB7XT2M56PNL66HMS6KVWPZRC4XPMVEIVDLVSBHE"), 8), Dict{Symbol, Any}(:mmc => 0.0, :sharpe => 0.0, :fnc => 0.0, :is_active => false, :tc => 0.0, :name => "numeraijl", :corr => 0.0), Dict{Symbol, Any}[Dict(:mmc => 0.0, :sharpe => 0.0, :fnc => 0.0, :is_active => false, :tc => 0.0, :name => "numeraijl", :corr => 0.0)], Dict{Symbol, Any}[Dict(:type => :info, :message => "Dashboard started", :time => Dates.DateTime("2025-09-15T07:46:35.769")), Dict(:type => :info, :message => "Auto-submit enabled, starting automatic pipeline...", :time => Dates.DateTime("2025-09-15T07:46:35.775"))], Dict{Symbol, Any}(:memory_used => 0.0, :threads => 16, :uptime => 0, :model_active => false, :memory_total => 48.0, :cpu_usage => 0, :julia_version => "1.11.6"), Dict{Symbol, Any}(:loss => 0.0, :model_name => "numeraijl", :val_score => 0.0, :is_training => false, :current_epoch => 0, :eta => "N/A", :progress => 0, :total_epochs => 0), Float64[], Dict{Symbol, Any}[], true, false, false, 1.0, "", false, false, nothing, nothing, nothing, false, Dict{NumeraiTournament.Dashboard.ErrorCategory, Int64}(NumeraiTournament.Dashboard.API_ERROR => 0, NumeraiTournament.Dashboard.TIMEOUT_ERROR => 0, NumeraiTournament.Dashboard.AUTH_ERROR => 0, NumeraiTournament.Dashboard.NETWORK_ERROR => 0, NumeraiTournament.Dashboard.DATA_ERROR => 0, NumeraiTournament.Dashboard.VALIDATION_ERROR => 0, NumeraiTournament.Dashboard.SYSTEM_ERROR => 0), Dict{Symbol, Any}(:api_latency => 0.0, :last_check => Dates.DateTime("2025-09-15T07:46:33.622"), :is_connected => true, :consecutive_failures => 0), NumeraiTournament.Dashboard.CategorizedError[], NumeraiTournament.Dashboard.EnhancedDashboard.ProgressTracker(0.0, "", 0.0, 0.0, 0.0, "", 0.0, 0.0, 0.0, "", 0, 0, 0.0, 0.0, 0.0, "", 0, 0, false, false, false, false, Dates.DateTime("2025-09-15T09:46:33.622"))), :get_staking_info), 0x000000000000697b)
```


- The TUI status information (system status, recent events, training progress) are not updating
- if there is a download running then show a progress bar
- if there is a upload running then show a progress bar
- if there is training running show a progress bar or a spinner
- if there is prediction running show a progress bar or a spinner
- after the download of live, train and validation data, i can not see the system performing a training
- typing the commands + Enter -> nothing happens

---
study @specs/* to learn about the program specifications and @scratchpad.md to understand plan so far.

The source code of the program is in @src/*

First task is to study @scratchpad.md (it may be incorrect), it can contain additional user instructions which you must consider as critical priority. Then study existing source code in @src/ and compare it against the program specifications. From that create/update @scratchpad.md which is a bullet point list sorted in priority of the items which have yet to be implemented. Think extra hard and plan in advance. Consider searching for TODO, minimal implementations and placeholders. Study @scratchpad.md to determine starting point for research and keep it up to date with items considered complete/incomplete.

ULTIMATE GOAL: Your job is to create a Julia application following the specifications in the reference documents in @specs/. The TUI and data pipeline must work without any issues! Do not take shortcuts, no recovery mode and fakes allowed, deliver working software, test by yourself by writing and running tests.

Use @scratchpad.md as a scratchpad for your work. Store long term plans and todo lists there. Follow the @scratchpad.md and choose the most important thing. Before making changes search codebase (don't assume not implemented). You may use up to 500 parallel subagents for all operations but only 1 subagent for build/tests of Julia. For any bugs you notice, it's important to resolve them or document them in @scratchpad.md to be resolved using a subagent even if it is unrelated to the current piece of work after documenting it in @scratchpad.md. When the issue is resolved, update @scratchpad.md and remove the item using a subagent.

You will need to write and run end to end and unit tests for the project. After implementing functionality or resolving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Think hard. Important: When authoring documentation capture why the tests and the backing implementation is important.

Update @README.md so that the user knows how to use and configure the program.

Make a commit and push your changes after every single file edit. After the commit do a "git push" to push the changes to the remote repository. If you create new branches, make sure to merge them into main and delete them afterwards. Do not leave feature branches open without merging them. Resolve any merge issues.

Do not assume the program is production-ready unless: ALL tests run through successfully, no missing references in the code, the data pipeline runs automatically without issues.

Important: We want single sources of truth, no migrations/adapters. If tests unrelated to your work fail then it's your job to resolve these tests as part of the increment of change.

As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1 if 0.0.0 does not exist.

You may add extra logging if required to be able to debug the issues.

Put test files into @test. Put example scripts into @examples.

ALWAYS KEEP @scratchpad.md up to do date with your learnings using a subagent. Especially after wrapping up/finishing your turn.

When you learn something new about how to run the compiler or examples make sure you update @CLAUDE.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.

IMPORTANT when you discover a bug resolve it even if it is unrelated to the current piece of work after documenting it in @scratchpad.md

Keep CLAUDE.md up to date with information on how to build the program and your learnings to optimise the build/test loop using a subagent.

For any bugs you notice, it's important to resolve them or document them in @scratchpad.md to be resolved using a subagent.

When @scratchpad.md becomes large periodically clean out the items that are completed from the file using a subagent.

If you find inconsistencies in the specs/* then use the oracle and then update the specs.

DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS. DO IT OR I WILL YELL AT YOU

SUPER IMPORTANT DO NOT IGNORE. DO NOT PLACE STATUS REPORT UPDATES INTO @CLAUDE.md
