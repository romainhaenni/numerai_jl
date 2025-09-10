using Term

# Test Grid usage
p1 = Term.Panel("Panel 1"; title="First")
p2 = Term.Panel("Panel 2"; title="Second")  
p3 = Term.Panel("Panel 3"; title="Third")

println("Testing Grid with panels:")

# Try different grid constructions (lowercase)
try
    g1 = grid(p1, p2)
    println("✅ grid with 2 panels works")
    println(g1)
catch e
    println("❌ grid with 2 panels failed: ", e)
end

try
    g2 = grid(p1, p2, p3)
    println("✅ grid with 3 panels works")
    println(g2)
catch e
    println("❌ grid with 3 panels failed: ", e)
end

# Try with array
try
    panels = [p1, p2, p3]
    g3 = grid(panels...)
    println("✅ grid with splatted array works")
    println(g3)
catch e
    println("❌ grid with splatted array failed: ", e)
end