#!/usr/bin/env julia

# Test the improved keyboard input handling

using Pkg
Pkg.activate(dirname(@__DIR__))

# Load the TUI module
push!(LOAD_PATH, joinpath(dirname(@__DIR__), "src"))
using .TUIOperational

println("Testing improved keyboard input functionality...")
println("This test uses the new REPL.TerminalMenus-based implementation")
println("Press keys to test (q to quit):")
println()

# Test the keyboard input functions directly
println("1. Testing keyboard input initialization...")
TUIOperational.init_keyboard_input()
println("   ✓ Keyboard input initialized")

# Test main loop
println("\n2. Testing non-blocking key reading...")
println("   Press keys now (they should be detected immediately without Enter):")

running = true
key_count = 0

while running && key_count < 10  # Limit to 10 keys for testing
    key = TUIOperational.read_key_nonblocking()

    if key == "q"
        println("   ✓ Quit command received!")
        running = false
    elseif key == "d"
        println("   ✓ Download command received!")
        key_count += 1
    elseif key == "t"
        println("   ✓ Training command received!")
        key_count += 1
    elseif key == "s"
        println("   ✓ Submit command received!")
        key_count += 1
    elseif key == "r"
        println("   ✓ Refresh command received!")
        key_count += 1
    elseif !isempty(key)
        println("   ✓ Unknown key: '$key' (press 'q' to quit)")
        key_count += 1
    end

    sleep(0.05)  # Small delay to prevent CPU spinning
end

# Cleanup
println("\n3. Testing cleanup...")
TUIOperational.cleanup_keyboard_input()
println("   ✓ Keyboard input cleaned up")

println("\nTest complete!")
println("If keys were detected immediately without pressing Enter, the fix is working!")