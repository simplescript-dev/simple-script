// Thread.start + .join basic tests (D082 Phase 2)
import { assertEqual, assertTrue } from "@/lib/test"

function compute(): int {
    let sum = 0
    let i = 0
    while (i < 1000) {
        sum = sum + i
        i = i + 1
    }
    return sum
}

function main() {
    test("Thread.start returns int via join", () => {
        const t = Thread.start((): int => {
            return 42
        })
        const result = t.join()
        assertEqual(result, 42)
    })

    test("Thread.start returns string via join", () => {
        const t = Thread.start((): string => {
            return "hello from thread"
        })
        assertEqual(t.join(), "hello from thread")
    })

    test("Multiple threads in parallel", () => {
        const ta = Thread.start((): int => { return 10 })
        const tb = Thread.start((): int => { return 20 })
        const tc = Thread.start((): int => { return 30 })
        const sum = ta.join() + tb.join() + tc.join()
        assertEqual(sum, 60)
    })

    test("Thread with heavier computation", () => {
        const t = Thread.start((): int => {
            return compute()
        })
        assertEqual(t.join(), 499500)
    })

    test("Fire-and-forget no crash", () => {
        Thread.start((): int => {
            return 0
        })
        assertTrue(1 == 1)
    })
}
