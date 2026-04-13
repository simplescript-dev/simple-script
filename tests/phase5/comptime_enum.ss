// Test: enum support in comptime {} blocks
// D088 Phase 8 — interpreter supports ENUM_DECL

import { assertEqual } from "@/lib/test"

function main() {
    // Test 1: int enum variant access
    const v1: int = comptime {
        enum Color { Red = 1, Green = 2, Blue = 3 }
        return Color.Red + Color.Blue
    }
    assertEqual(v1, 4)

    // Test 2: string enum variant access
    const v2: string = comptime {
        enum Direction { Up = "up", Down = "down", Left = "left" }
        return Direction.Up
    }
    assertEqual(v2, "up")

    // Test 3: enum names()
    const v3: string = comptime {
        enum Status { Active = 1, Inactive = 2, Pending = 3 }
        const names = Status.names()
        return names[0] + "," + names[1] + "," + names[2]
    }
    assertEqual(v3, "Active,Inactive,Pending")

    // Test 4: enum values() sum
    const v4: int = comptime {
        enum Priority { Low = 10, Medium = 20, High = 30 }
        const vals = Priority.values()
        return vals[0] + vals[1] + vals[2]
    }
    assertEqual(v4, 60)

    // Test 5: enum valueOf()
    const v5: string = comptime {
        enum Fruit { Apple = "apple", Banana = "banana" }
        return Fruit.valueOf("Banana")
    }
    assertEqual(v5, "banana")

    // Test 6: enum in control flow
    const v6: string = comptime {
        enum Level { Debug = 0, Info = 1, Warn = 2, Error = 3 }
        let label = ""
        if (Level.Warn > Level.Info) {
            label = "warn>info"
        }
        return label
    }
    assertEqual(v6, "warn>info")

    println("all comptime enum tests passed")
}
