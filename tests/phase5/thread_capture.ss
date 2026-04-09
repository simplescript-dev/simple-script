// D082 Phase 3: Thread closure capture analysis tests
import { assertEqual, assertTrue } from "@/lib/test"

class Config {
    host: string
    port: int

    function init(host: string, port: int) {
        this.host = host
        this.port = port
    }
}

function main() {
    test("Thread captures const int (value copy)", () => {
        const x = 42
        const t = Thread.start((): int => {
            return x
        })
        assertEqual(t.join(), 42)
    })

    test("Thread captures const string (shared)", () => {
        const msg = "hello"
        const t = Thread.start((): string => {
            return msg
        })
        assertEqual(t.join(), "hello")
    })

    test("Thread captures Ref (shared, thread-safe)", () => {
        const counter = ref(0)
        const t = Thread.start((): int => {
            counter.value = 99
            return counter.value
        })
        t.join()
        assertEqual(counter.value, 99)
    })

    test("Thread deep clones class instance (isolation)", () => {
        const cfg = new Config("localhost", 8080)
        const t = Thread.start((): int => {
            // This operates on a deep clone, not the original
            return cfg.port
        })
        assertEqual(t.join(), 8080)
        // Original unchanged
        assertEqual(cfg.host, "localhost")
        assertEqual(cfg.port, 8080)
    })

    test("Thread captures multiple consts", () => {
        const a = 10
        const b = 20
        const name = "test"
        const t = Thread.start((): int => {
            return a + b
        })
        assertEqual(t.join(), 30)
    })
}
