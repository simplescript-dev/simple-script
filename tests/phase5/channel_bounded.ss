// Channel<T> bounded channel tests — D082 bounded enhancement

import { assert } from "./import/asserts"

function main() {
    // Test 1: Unbounded still works (regression)
    const ch1 = new Channel<int>()
    ch1.send(1)
    ch1.send(2)
    ch1.send(3)
    assert(ch1.receive() == 1, "unbounded FIFO 1")
    assert(ch1.receive() == 2, "unbounded FIFO 2")
    assert(ch1.receive() == 3, "unbounded FIFO 3")

    // Test 2: Bounded channel capacity 2 — non-blocking within capacity
    const ch2 = new Channel<int>(2)
    ch2.send(10)
    ch2.send(20)
    assert(ch2.receive() == 10, "bounded cap=2 first")
    assert(ch2.receive() == 20, "bounded cap=2 second")

    // Test 3: Bounded channel — sender blocks when full, unblocks on receive
    const ch3 = new Channel<int>(2)
    ch3.send(100)
    ch3.send(200)
    // Channel full (2/2). Sender in thread will block.
    const t1 = Thread.start(() => {
        ch3.send(300)
        return 1
    })
    // Drain one — frees space, unblocks sender thread
    const v1 = ch3.receive()
    assert(v1 == 100, "bounded block first")
    const v2 = ch3.receive()
    assert(v2 == 200, "bounded block second")
    const v3 = ch3.receive()
    assert(v3 == 300, "bounded block third from thread")
    t1.join()

    // Test 4: Bounded capacity 1 — like synchronous channel with buffer 1
    const ch4 = new Channel<int>(1)
    ch4.send(42)
    const t2 = Thread.start(() => {
        ch4.send(43)
        return 1
    })
    assert(ch4.receive() == 42, "cap=1 first")
    assert(ch4.receive() == 43, "cap=1 second from thread")
    t2.join()

    // Test 5: Bounded with strings
    const ch5 = new Channel<string>(2)
    ch5.send("hello")
    ch5.send("world")
    assert(ch5.receive() == "hello", "bounded string first")
    assert(ch5.receive() == "world", "bounded string second")

    // Test 6: Bounded producer-consumer with multiple items
    const ch6 = new Channel<int>(3)
    const producer = Thread.start(() => {
        let i = 0
        while (i < 10) {
            ch6.send(i)
            i = i + 1
        }
        return 0
    })
    let sum = 0
    let j = 0
    while (j < 10) {
        sum = sum + ch6.receive()
        j = j + 1
    }
    producer.join()
    assert(sum == 45, "bounded producer-consumer sum")

    // Test 7: Close wakes blocked sender
    const ch7 = new Channel<int>(1)
    ch7.send(1)
    // Channel full. Sender thread will block, then get woken by close.
    const senderFailed = ref(0)
    const t3 = Thread.start(() => {
        // This send will block because channel is full.
        // When channel is closed, sender wakes and throws.
        // We catch the exception to verify behavior.
        try {
            ch7.send(2)
        } catch (e) {
            senderFailed.value = 1
        }
        return 0
    })
    // Small delay to let thread block on send
    let spin = 0
    while (spin < 100000) {
        spin = spin + 1
    }
    ch7.close()
    t3.join()
    assert(senderFailed.value == 1, "close wakes blocked sender")

    println("All bounded channel tests passed!")
}
