#!/usr/bin/env julia

# Standalone test for the improved keyboard input functionality
# This tests only the keyboard input code without module dependencies

using REPL

# Global keyboard input channel and task for non-blocking input
const KEYBOARD_CHANNEL = Channel{Char}(32)
const KEYBOARD_TASK = Ref{Task}()

# Initialize keyboard input monitoring
function init_keyboard_input()
    if !isdefined(KEYBOARD_TASK, :x) || istaskdone(KEYBOARD_TASK.x)
        KEYBOARD_TASK.x = @async begin
            try
                terminal = REPL.TerminalMenus.terminal

                # Enable raw mode for the entire session
                if isa(stdin, Base.TTY)
                    raw_enabled = REPL.TerminalMenus.enableRawMode(terminal)

                    if raw_enabled
                        try
                            while true
                                # Read a key - this will block until a key is pressed
                                key_code = REPL.TerminalMenus.readKey(terminal.in_stream)

                                # Convert to character if it's a regular ASCII key
                                if key_code <= 127
                                    char = Char(key_code)
                                    # Put the character in the channel (non-blocking)
                                    if isopen(KEYBOARD_CHANNEL)
                                        put!(KEYBOARD_CHANNEL, char)
                                    end
                                end
                                # Ignore special keys for now
                            end
                        finally
                            # Restore normal mode when done
                            REPL.TerminalMenus.disableRawMode(terminal)
                        end
                    end
                end
            catch e
                # Task ended, possibly due to shutdown
                println("Keyboard task ended: $e")
            end
        end
    end
end

# Clean up keyboard input monitoring
function cleanup_keyboard_input()
    try
        if isdefined(KEYBOARD_TASK, :x) && !istaskdone(KEYBOARD_TASK.x)
            # This will trigger the finally block in the task
            Base.throwto(KEYBOARD_TASK.x, InterruptException())
        end
        close(KEYBOARD_CHANNEL)
    catch
        # Ignore cleanup errors
    end
end

# Read a single key without Enter (non-blocking)
function read_key_nonblocking()
    key = ""

    try
        # Check if there's a key available in the channel
        if isready(KEYBOARD_CHANNEL)
            char = take!(KEYBOARD_CHANNEL)
            key = string(char)
        end
    catch
        # Channel might be closed or other error
    end

    return lowercase(key)
end

# Test function
function test_improved_keyboard()
    println("Testing improved keyboard input functionality...")
    println("Note: This test may not work in non-interactive environments")
    println()

    # Test TTY detection
    if isa(stdin, Base.TTY)
        println("✅ stdin is a TTY - keyboard input should work")
    else
        println("⚠️  stdin is not a TTY - keyboard input may not work in this environment")
        println("   (This is normal when running from scripts or CI)")
    end

    println("\n1. Initializing keyboard input...")
    init_keyboard_input()

    # Check if task is running
    if isdefined(KEYBOARD_TASK, :x) && !istaskdone(KEYBOARD_TASK.x)
        println("✅ Keyboard monitoring task is running")
    else
        println("❌ Failed to start keyboard monitoring task")
        return
    end

    println("\n2. Testing non-blocking key reading...")
    println("   If you're in an interactive terminal, press 'h' followed by 'q':")

    start_time = time()
    timeout = 10.0  # 10 second timeout
    received_keys = String[]

    while time() - start_time < timeout
        key = read_key_nonblocking()

        if !isempty(key)
            push!(received_keys, key)
            println("   📧 Received key: '$key'")

            if key == "q"
                println("   ✅ Quit key detected - stopping test")
                break
            elseif key == "h"
                println("   ✅ Help key detected")
            end
        end

        sleep(0.05)  # Small delay
    end

    if isempty(received_keys)
        println("   ⚠️  No keys received (this is normal in non-interactive environments)")
    else
        println("   ✅ Successfully received $(length(received_keys)) key(s): $(join(received_keys, ", "))")
    end

    println("\n3. Cleaning up...")
    cleanup_keyboard_input()
    println("✅ Cleanup complete")

    println("\n📊 Test Results:")
    if isa(stdin, Base.TTY) && !isempty(received_keys)
        println("✅ PASS: Keyboard input is working correctly")
    elseif !isa(stdin, Base.TTY)
        println("⚠️  SKIP: Not in interactive environment (expected)")
    else
        println("❓ UNKNOWN: No keys received (may need interactive testing)")
    end
end

# Run the test
test_improved_keyboard()