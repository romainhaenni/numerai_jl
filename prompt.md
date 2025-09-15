
Fix More Issues:
- bug when starting the program:
```
❯ ./numerai
Starting Numerai Tournament System with 16 threads...
Press 'h' in the TUI for help or use --help for command line options

 Activating project at `~/src/Numerai/numerai_jl`
Precompiling NumeraiTournament...
Info Given NumeraiTournament was explicitly requested, output will be shown live
[ Info: lib_lightgbm found in system dirs!
ERROR: LoadError: syntax: "using" expression not at top level
Stacktrace:
[1] include(mod::Module, _path::String)
  @ Base ./Base.jl:562
[2] include(x::String)
  @ NumeraiTournament ~/src/Numerai/numerai_jl/src/NumeraiTournament.jl:1
[3] top-level scope
  @ ~/src/Numerai/numerai_jl/src/NumeraiTournament.jl:96
[4] top-level scope
  @ stdin:6
in expression starting at /Users/romain/src/Numerai/numerai_jl/src/tui/dashboard.jl:1
in expression starting at /Users/romain/src/Numerai/numerai_jl/src/NumeraiTournament.jl:1
in expression starting at stdin:6
 ✗ NumeraiTournament
 0 dependencies successfully precompiled in 19 seconds. 366 already precompiled.

ERROR: LoadError: The following 1 direct dependency failed to precompile:

NumeraiTournament

Failed to precompile NumeraiTournament [a1b2c3d4-e5f6-7890-1234-567890abcdef] to "/Users/romain/.julia/compiled/v1.11/NumeraiTournament/jl_46J4VS".
[ Info: lib_lightgbm found in system dirs!
ERROR: LoadError: syntax: "using" expression not at top level
Stacktrace:
[1] include(mod::Module, _path::String)
  @ Base ./Base.jl:562
[2] include(x::String)
  @ NumeraiTournament ~/src/Numerai/numerai_jl/src/NumeraiTournament.jl:1
[3] top-level scope
  @ ~/src/Numerai/numerai_jl/src/NumeraiTournament.jl:96
[4] top-level scope
  @ stdin:6
in expression starting at /Users/romain/src/Numerai/numerai_jl/src/tui/dashboard.jl:1
in expression starting at /Users/romain/src/Numerai/numerai_jl/src/NumeraiTournament.jl:1
in expression starting at stdin:
in expression starting at /Users/romain/src/Numerai/numerai_jl/start_tui.jl:17
```


- TUI looks not nice -> provide only one panel with all infos in it.
- `Press 'n' for new model | '/' for commands | 'h' for help` -> the TUI commands are not working
- The TUI status information (system status, recent events, training progress) are not updating
- if there is a download running then show a progress bar
- if there is a upload running then show a progress bar
- if there is training running show a progress bar or a spinner
- if there is prediction running show a progress bar or a spinner
- after the download of live, train and validation data, i can not see the system performing a training

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
