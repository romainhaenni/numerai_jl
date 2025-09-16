#!/usr/bin/env julia

# Alternative keyboard input implementation
# This provides a simpler approach based on other TUI implementations in the project

using REPL

# Alternative implementation using REPL.Terminals.raw! directly
function read_key_nonblocking_simple()
    key = ""

    try
        if isa(stdin, Base.TTY)
            # Create terminal
            terminal = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

            # Temporarily enable raw mode
            REPL.Terminals.raw!(terminal, true)

            try
                # Check if there's input available without blocking
                if bytesavailable(stdin) > 0
                    char = read(stdin, Char)
                    key = string(char)
                end
            finally
                # Always restore normal mode
                REPL.Terminals.raw!(terminal, false)
            end
        end
    catch
        # Silently ignore errors
    end

    return lowercase(key)
end

# Another alternative using timeout-based approach
function read_key_nonblocking_timeout()
    key = ""

    try
        if isa(stdin, Base.TTY)
            # Use @async with timeout for non-blocking behavior
            read_task = @async begin
                terminal = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
                REPL.Terminals.raw!(terminal, true)
                try
                    return read(stdin, Char)
                finally
                    REPL.Terminals.raw!(terminal, false)
                end
            end

            # Very short timeout to make it non-blocking
            if istaskdone(read_task)
                char = fetch(read_task)
                key = string(char)
            elseif timedwait(() -> istaskdone(read_task), 0.001) == :ok
                char = fetch(read_task)
                key = string(char)
            end
        end
    catch
        # Silently ignore errors
    end

    return lowercase(key)
end

# Test both implementations
function test_alternative_implementations()
    println("Testing alternative keyboard input implementations...")
    println()

    if isa(stdin, Base.TTY)
        println("✅ stdin is a TTY - testing can proceed")
    else
        println("⚠️  stdin is not a TTY - testing may not work")
    end

    println("\n1. Testing simple raw mode implementation:")
    for i in 1:5
        key = read_key_nonblocking_simple()
        if !isempty(key)
            println("   📧 Simple method detected: '$key'")
        end
        sleep(0.1)
    end

    println("\n2. Testing timeout-based implementation:")
    for i in 1:5
        key = read_key_nonblocking_timeout()
        if !isempty(key)
            println("   📧 Timeout method detected: '$key'")
        end
        sleep(0.1)
    end

    println("\n✅ Alternative implementations test complete")
end

test_alternative_implementations()

# Print the implementations for reference
println("\n" * "="^60)
println("ALTERNATIVE IMPLEMENTATION OPTIONS:")
println("="^60)

println("""
Option 1: Simple REPL.Terminals.raw! approach
==============================================
function read_key_nonblocking()
    key = ""
    try
        if isa(stdin, Base.TTY)
            terminal = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
            REPL.Terminals.raw!(terminal, true)
            try
                if bytesavailable(stdin) > 0
                    char = read(stdin, Char)
                    key = string(char)
                end
            finally
                REPL.Terminals.raw!(terminal, false)
            end
        end
    catch
        # Silently ignore errors
    end
    return lowercase(key)
end

Option 2: Channel-based approach (current implementation)
========================================================
# This is what we implemented in tui_operational.jl
# Uses a background task with Channel for buffering keystrokes

Option 3: Direct REPL.TerminalMenus approach
===========================================
function read_key_nonblocking()
    key = ""
    try
        if isa(stdin, Base.TTY)
            terminal = REPL.TerminalMenus.terminal
            if REPL.TerminalMenus.enableRawMode(terminal)
                try
                    if bytesavailable(stdin) > 0
                        key_code = REPL.TerminalMenus.readKey(terminal.in_stream)
                        if key_code <= 127
                            key = string(Char(key_code))
                        end
                    end
                finally
                    REPL.TerminalMenus.disableRawMode(terminal)
                end
            end
        end
    catch
        # Silently ignore errors
    end
    return lowercase(key)
end
""")