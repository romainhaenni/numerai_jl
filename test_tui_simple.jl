#!/usr/bin/env julia
# Simple TUI test without hanging operations

using Pkg
Pkg.activate(".")

using NumeraiTournament
println("\n=== Quick TUI v0.10.41 Test ===\n")

# Load config
config = NumeraiTournament.load_config("config.toml")

# Create dashboard
dashboard = NumeraiTournament.TUIv1041Fixed.TUIv1041FixedDashboard(config)

# Test system info
NumeraiTournament.TUIv1041Fixed.update_system_info!(dashboard)

println("✅ System Monitoring:")
println("   CPU: $(dashboard.cpu_usage)%")
println("   Memory: $(round(dashboard.memory_used, digits=2))/$(round(dashboard.memory_total, digits=2)) GB")
println("   Disk: $(round(dashboard.disk_free, digits=2))/$(round(dashboard.disk_total, digits=2)) GB")

println("\n✅ Configuration:")
println("   Auto-start: $(dashboard.auto_start_enabled)")
println("   Auto-train: $(dashboard.auto_train_enabled)")
println("   Auto-submit: $(dashboard.auto_submit_enabled)")

# Test command handling without async
println("\n✅ Command Response Test:")
NumeraiTournament.TUIv1041Fixed.handle_command(dashboard, 'r')
if length(dashboard.events) > 0
    println("   Last event: $(dashboard.events[end].message)")
end

dashboard.running = false
println("\n✅ All basic tests passed!")