
Fix More Issues:

- bug:
```
📋 RECENT EVENTS:
────────────────────────────────────────────────────────────
   [08:10:11] ℹ️ Auto-submit enabled, starting automatic pipelin...
   [08:10:11] ℹ️ Dashboard started
┌ Info: Logging initialized
│   log_file = "logs/numerai_20250915_101019.log"
│   console_level = Info
└   file_level = Debug
┌ Info: Downloading dataset
└   type = "train"
┌ Info: Starting download
└   file = "train"
┌ Error: Download failed
│   file = "train"
│   error = "MethodError(Core.kwcall, ((name = \"train\",), NumeraiTournament.Dashboard.var\"#5#6\"{TournamentDashboard}(TournamentDashboard(TournamentConfig(\"I3MEFCUZJQ4BEU5TSO7MY7XDIU2UBV7E\", \"337BEF4U2RZO6VOUHJGSOHAIWB7XT2M56PNL66HMS6KVWPZRC4XPMVEIVDLVSBHE\", [\"numeraijl\"], \"data\", \"models\", true, 1.0, 12, 8, \"medium\", false, 1.0, 100.0, 10000.0, Dict{String, Any}(\"training\" => Dict(\"progress_bar_width\" => 20, \"default_epochs\" => 100), \"refresh_rate\" => 1.0, \"network_timeout\" => 5, \"network_check_interval\" => 60.0, \"panels\" => Dict(\"st" ⋯ 2926 bytes ⋯ "ournament.Dashboard.NETWORK_ERROR => 0, NumeraiTournament.Dashboard.DATA_ERROR => 0), Dict{Symbol, Any}(:api_latency => 0.0, :last_check => Dates.DateTime(\"2025-09-15T08:10:09.941\"), :is_connected => true, :consecutive_failures => 0), NumeraiTournament.Dashboard.CategorizedError[], NumeraiTournament.Dashboard.EnhancedDashboard.ProgressTracker(0.0, \"\", 0.0, 0.0, 0.0, \"\", 0.0, 0.0, 0.0, \"\", 0, 0, 0.0, 0.0, 0.0, \"\", 0, 0, false, false, false, false, Dates.DateTime(\"2025-09-15T10:10:09.941\")))), :start), 0x000000000000697b)"
└ @ NumeraiTournament.API ~/src/Numerai/numerai_jl/src/logger.jl:229
┌ Error: Download failed
│   error =
│    MethodError: no method matching (::NumeraiTournament.Dashboard.var"#5#6"{TournamentDashboard})(::Symbol; name::String)
│    This method may not support any kwargs.
│
│    Closest candidates are:
│      (::NumeraiTournament.Dashboard.var"#5#6")(::Any, Any...) got unsupported keyword argument "name"
│       @ NumeraiTournament ~/src/Numerai/numerai_jl/src/tui/dashboard_commands.jl:138
│
└ @ NumeraiTournament.Dashboard ~/src/Numerai/numerai_jl/src/tui/dashboard_commands.jl:176
┌ Error: Dashboard event
│   message = "Failed to download data. Pipeline aborted."
└ @ NumeraiTournament.Dashboard ~/src/Numerai/numerai_jl/src/logger.jl:229
```


- The TUI status information (system status, recent events, training progress) are not updating
- if there is a download running then show a progress bar
- if there is a upload running then show a progress bar
- if there is training running show a progress bar or a spinner
- if there is prediction running show a progress bar or a spinner
- after the download of live, train and validation data, i can not see the system performing a training
- typing the commands + Enter -> nothing happens => i want to enter a command key and instantly the program to run this command (without approving it with the Enter key)

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
