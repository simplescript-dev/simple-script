import { assertEqual } from "@/lib/test"

comptime {
    class Point { x: int; y: int }
    const p = new Point(x: 10, y: 20)
    const { x, y } = p
    @comptimeEmit(`function ctSumXY(): int { return ${x + y} }\n`)
}

comptime {
    class Pair { first: int; second: int }
    const pr = new Pair(first: 7, second: 35)
    const { first: a, second: b } = pr
    @comptimeEmit(`function ctSumPair(): int { return ${a + b} }\n`)
}

comptime {
    class Single { only: int }
    const s = new Single(only: 99)
    const { only, missing } = s
    @comptimeEmit(`function ctOnlyVal(): int { return ${only} }\n`)
}

comptime {
    class Triple { a: int; b: int; c: int }
    const t = new Triple(a: 1, b: 2, c: 3)
    const { a, b, c } = t
    const [d, e] = [a + b, b + c]
    @comptimeEmit(`function ctMixSum(): int { return ${d + e} }\n`)
}

comptime {
    class Greeting { hello: string; name: string }
    const g = new Greeting(hello: "hi", name: "ss")
    const { hello, name } = g
    @comptimeEmit(`function ctGreet(): string { return "${hello}_${name}" }\n`)
}

function main() {
    test("comptime destructure 2 fields", () => {
        assertEqual(ctSumXY(), 30)
    })
    test("comptime destructure with rename", () => {
        assertEqual(ctSumPair(), 42)
    })
    test("comptime destructure missing field → null (no crash)", () => {
        assertEqual(ctOnlyVal(), 99)
    })
    test("comptime destructure object + array nested", () => {
        assertEqual(ctMixSum(), 8)
    })
    test("comptime destructure string fields", () => {
        assertEqual(ctGreet(), "hi_ss")
    })
}
