#!/usr/bin/env julia

# Test keyboard input handling

using Pkg
Pkg.activate(dirname(@__DIR__))

println("Testing keyboard input functionality...")
println("Press keys to test (q to quit):")

# Test the raw TTY mode implementation
function read_key_nonblocking()
    key = ""

    if isa(stdin, Base.TTY)
        try
            # Set raw mode
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 1)

            # Check if data available
            if bytesavailable(stdin) > 0
                char = read(stdin, Char)
                key = string(char)
                println("  Received key: '$key' (code: $(Int(char)))")
            end

            # Restore normal mode
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid}, Int32), stdin.handle, 0)
        catch e
            println("  Error: $e")
        end
    else
        println("  Warning: stdin is not a TTY")
    end

    return lowercase(key)
end

# Main test loop
running = true
while running
    key = read_key_nonblocking()

    if key == "q"
        println("Quit command received!")
        running = false
    elseif key == "d"
        println("Download command received!")
    elseif key == "t"
        println("Training command received!")
    elseif !isempty(key)
        println("Unknown key: '$key'")
    end

    sleep(0.1)  # Small delay to prevent CPU spinning
end

println("Test complete!")