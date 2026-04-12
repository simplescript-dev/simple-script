// Test: comptime code generation via emit() + registerFunction() (D087 Phase 3b)
// comptime blocks can emit LLVM IR and register functions callable at runtime.

import { assertEqual } from "@/lib/test"

// Emit a zero-parameter function that returns 42
comptime {
    emit("define i32 @getFortyTwo() {\n")
    emit("entry:\n")
    emit("  ret i32 42\n")
    emit("}\n")
    registerFunction("getFortyTwo", "int", 0)
}

// Emit a one-parameter function that adds 10 to its argument
comptime {
    emit("define i32 @addTen(i32 %0) {\n")
    emit("entry:\n")
    emit("  %1 = add i32 %0, 10\n")
    emit("  ret i32 %1\n")
    emit("}\n")
    registerFunction("addTen", "int", 1)
}

// Emit using template string (build IR dynamically)
comptime {
    const name = "doubleIt"
    const ir = `define i32 @${name}(i32 %0) {\nentry:\n  %1 = mul i32 %0, 2\n  ret i32 %1\n}\n`
    emit(ir)
    registerFunction(name, "int", 1)
}

function main() {
    test("comptime emit zero-arg function", () => {
        assertEqual(getFortyTwo(), 42)
    })
    test("comptime emit one-arg function", () => {
        assertEqual(addTen(5), 15)
        assertEqual(addTen(0), 10)
    })
    test("comptime emit with template string", () => {
        assertEqual(doubleIt(7), 14)
        assertEqual(doubleIt(0), 0)
    })
}
