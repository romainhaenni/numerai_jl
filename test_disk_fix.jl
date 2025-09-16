#!/usr/bin/env julia

# Test disk space monitoring fix

using Pkg
Pkg.activate(@__DIR__)

# Load the module
using NumeraiTournament

# Test the disk space function
println("Testing disk space monitoring fix...")
disk_info = NumeraiTournament.Utils.get_disk_space_info()
println("Disk info results:")
println("  Free GB: $(disk_info.free_gb)")
println("  Total GB: $(disk_info.total_gb)")
println("  Used GB: $(disk_info.used_gb)")
println("  Used %: $(disk_info.used_pct)")

# Verify we get non-zero values
if disk_info.free_gb > 0 && disk_info.total_gb > 0
    println("✅ SUCCESS: Disk space monitoring is working correctly!")
else
    println("❌ FAILED: Still getting zero values")
end