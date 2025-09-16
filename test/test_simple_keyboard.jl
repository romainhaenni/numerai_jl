#!/usr/bin/env julia

# Simple test for keyboard input using REPL.TerminalMenus directly

println("Testing REPL.TerminalMenus keyboard input...")
println("Press any key (it should be detected immediately):")

using REPL

function test_direct_keyboard()
    try
        terminal = REPL.TerminalMenus.terminal

        if isa(stdin, Base.TTY)
            println("Setting up raw mode...")
            raw_enabled = REPL.TerminalMenus.enableRawMode(terminal)

            if raw_enabled
                println("Raw mode enabled. Press a key now:")
                try
                    # Read one key
                    key_code = REPL.TerminalMenus.readKey(terminal.in_stream)

                    if key_code <= 127
                        char = Char(key_code)
                        println("Key detected: '$char' (code: $key_code)")
                        println("✅ Success! Key was detected immediately without Enter.")
                    else
                        println("Special key detected (code: $key_code)")
                    end
                finally
                    REPL.TerminalMenus.disableRawMode(terminal)
                    println("Raw mode disabled.")
                end
            else
                println("❌ Failed to enable raw mode")
            end
        else
            println("❌ stdin is not a TTY")
        end
    catch e
        println("❌ Error: $e")
    end
end

test_direct_keyboard()
println("Test complete!")