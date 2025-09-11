study @specs/* to learn about the program specifications and @scratchpad.md to understand plan so far.

The source code of the program is in @src/*

First task is to study @scratchpad.md (it may be incorrect) and is to use up to 500 subagents to study existing source code in @src/ and compare it against the program specifications. From that create/update @scratchpad.md which is a bullet point list sorted in priority of the items which have yet to be implemented. Think extra hard and plan in advance. Consider searching for TODO, minimal implementations and placeholders. Study @scratchpad.md to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents.

ULTIMATE GOAL: Your job is to create a production-ready Julia application following the specifications in the reference documents in @specs/. The TUI and data pipeline must work without any issues! Do not take shortcuts, no recovery mode and fakes allowed, deliver working software, test by yourself by writing tests.

Use @scratchpad.md as a scratchpad for your work. Store long term plans and todo lists there. Follow the @scratchpad.md and choose the most important thing. Before making changes search codebase (don't assume not implemented) using subagents. You may use up to 500 parallel subagents for all operations but only 1 subagent for build/tests of Julia. For any bugs you notice, it's important to resolve them or document them in @scratchpad.md to be resolved using a subagent even if it is unrelated to the current piece of work after documenting it in @scratchpad.md. When the issue is resolved, update @scratchpad.md and remove the item using a subagent.

You will need to write and run end to end and unit tests for the project. After implementing functionality or resolving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Think hard. Important: When authoring documentation capture why the tests and the backing implementation is important.

Make a commit and push your changes after every single file edit. After the commit do a "git push" to push the changes to the remote repository. If you create new branches, make sure to merge them into main and delete them afterwards. Do not leave feature branches open without merging them. Resolve any merge issues.

Do not assume ready for production. We improve the program iteratively, to be production ready is not a goal. The goal is to have a model for the tournament that has maximal return.

Important: We want single sources of truth, no migrations/adapters. If tests unrelated to your work fail then it's your job to resolve these tests as part of the increment of change.

As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1 if 0.0.0 does not exist.

You may add extra logging if required to be able to debug the issues.

Put test files into @test. Put example scripts into @examples.

ALWAYS KEEP @scratchpad.md up to do date with your learnings using a subagent. Especially after wrapping up/finishing your turn.

When you learn something new about how to run the compiler or examples make sure you update @CLAUDE.md using a subagent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.

IMPORTANT when you discover a bug resolve it using subagents even if it is unrelated to the current piece of work after documenting it in @scratchpad.md

Keep CLAUDE.md up to date with information on how to build the program and your learnings to optimise the build/test loop using a subagent.

For any bugs you notice, it's important to resolve them or document them in @scratchpad.md to be resolved using a subagent.

When @scratchpad.md becomes large periodically clean out the items that are completed from the file using a subagent.

If you find inconsistencies in the specs/* then use the oracle and then update the specs.

DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS. DO IT OR I WILL YELL AT YOU

SUPER IMPORTANT DO NOT IGNORE. DO NOT PLACE STATUS REPORT UPDATES INTO @CLAUDE.md
