# Startup script for Numerai Tournament System
# This file is automatically loaded when starting Julia with --project

using Pkg

# Ensure all dependencies are installed
println("📦 Checking dependencies...")
Pkg.instantiate()

# Precompile the main module for faster startup
println("⚡ Precompiling NumeraiTournament...")
using NumeraiTournament

# Load environment variables if .env exists
if isfile(".env")
    println("🔐 Loading environment variables...")
    for line in readlines(".env")
        if !startswith(line, "#") && contains(line, "=")
            key, value = split(line, "=", limit=2)
            ENV[strip(key)] = strip(value)
        end
    end
end

# Display system information
println("\n🖥️  System Information:")
println("   Julia: v$(VERSION)")
println("   Threads: $(Threads.nthreads())")
println("   Memory: $(round(Sys.total_memory() / 1024^3, digits=1)) GB")
println("   Platform: $(Sys.MACHINE)")

println("\n✅ Numerai Tournament System ready!")
println("   Run './numerai --help' for usage information")