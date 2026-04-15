// Test: D089 Phase 4 — comptime function calls and class operations
// Verifies that genVal/genStmt can handle CALL, NEW_EXPR, MEMBER_ACCESS,
// METHOD_CALL, MEMBER_ASSIGN when comptimeDepth > 0.

import { assertEqual } from "@/lib/test"

// Test 1: comptime function call
comptime {
    function ctAdd(a: int, b: int): int {
        return a + b
    }
    const r = ctAdd(3, 4)
    println(r)
}

// Test 2: comptime class + new + field access
comptime {
    class Point { x: int; y: int }
    const p = new Point(x: 3, y: 4)
    println(p.x + p.y)
}

// Test 3: comptime method call
comptime {
    class Calculator {
        value: int
        function add(n: int): int {
            return this.value + n
        }
    }
    const calc = new Calculator(value: 10)
    println(calc.add(5))
}

// Test 4: comptime member assign
comptime {
    class Counter { count: int }
    const c = new Counter(count: 0)
    c.count = 42
    println(c.count)
}

// Test 5: comptime recursive function
comptime {
    function fib(n: int): int {
        if (n <= 1) { return n }
        return fib(n - 1) + fib(n - 2)
    }
    println(fib(10))
}

// Test 6: comptime function accessing outer variables (scope chain)
comptime {
    let total = 0
    function addToTotal(n: int) {
        total = total + n
    }
    addToTotal(10)
    addToTotal(20)
    addToTotal(30)
    println(total)
}

function main() {
    println("comptime class ops ok")
}
