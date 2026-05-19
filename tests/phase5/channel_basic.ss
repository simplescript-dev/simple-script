// Channel<T> basic tests — D082 Phase 4

import { assert } from "./import/asserts"

function main() {
    // Basic send and receive
    const ch1 = new Channel<int>()
    ch1.send(42)
    const val = ch1.receive()
    assert(val == 42, "send/receive int")

    // Multiple values FIFO
    const ch2 = new Channel<int>()
    ch2.send(1)
    ch2.send(2)
    ch2.send(3)
    assert(ch2.receive() == 1, "FIFO first")
    assert(ch2.receive() == 2, "FIFO second")
    assert(ch2.receive() == 3, "FIFO third")

    // Channel with strings
    const ch3 = new Channel<string>()
    ch3.send("hello")
    ch3.send("world")
    assert(ch3.receive() == "hello", "string first")
    assert(ch3.receive() == "world", "string second")

    // Channel between threads
    const ch4 = new Channel<int>()
    const t1 = Thread.start(() => {
        ch4.send(100)
        return 0
    })
    const fromThread = ch4.receive()
    t1.join()
    assert(fromThread == 100, "receive from thread")

    // Producer-consumer pattern
    const ch5 = new Channel<int>()
    const producer = Thread.start(() => {
        ch5.send(10)
        ch5.send(20)
        ch5.send(30)
        return 0
    })
    const a = ch5.receive()
    const b = ch5.receive()
    const c = ch5.receive()
    producer.join()
    assert(a + b + c == 60, "producer-consumer sum")

    // Close channel
    const ch6 = new Channel<int>()
    ch6.send(99)
    ch6.close()
    assert(ch6.receive() == 99, "receive after close")

    println("All channel tests passed!")
}
