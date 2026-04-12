// Test: inline comptime expressions — comptime { return expr } in expression position

import { assertEqual } from "@/lib/test"

function main() {
    test("comptime inline int", () => {
        const x = comptime { return 6 * 7 }
        assertEqual(x, 42)
    })
    test("comptime inline string", () => {
        const s = comptime { return "hello" + " " + "world" }
        assertEqual(s, "hello world")
    })
    test("comptime inline arithmetic", () => {
        const a = comptime { return 100 + 200 + 300 }
        const b = comptime { return 10 * 5 }
        assertEqual(a + b, 650)
    })
    test("comptime inline with logic", () => {
        const result = comptime {
            let sum = 0
            let i = 1
            while (i <= 10) {
                sum = sum + i
                i = i + 1
            }
            return sum
        }
        assertEqual(result, 55)
    })
    test("comptime inline string concat", () => {
        const greeting = comptime {
            const parts: Array<string> = []
            parts = parts.push("Hello")
            parts = parts.push(", ")
            parts = parts.push("SimpleScript!")
            return parts[0] + parts[1] + parts[2]
        }
        assertEqual(greeting, "Hello, SimpleScript!")
    })
    test("comptime inline in expression", () => {
        // Use comptime expr as part of a larger expression
        const total = 10 + comptime { return 32 }
        assertEqual(total, 42)
    })
}
