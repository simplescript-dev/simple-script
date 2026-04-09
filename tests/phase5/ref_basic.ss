// D082: Basic ref() and watch() test

function assert(cond: int, msg: string) {
    if (cond == 0) {
        println("FAIL: " + msg)
        exit(1)
    }
}

function main() {
    // ref(int) — create and read
    const count = ref(0)
    assert(count.value == 0, "ref(0) initial value")

    // .value = direct write
    count.value = 42
    assert(count.value == 42, "ref.value = 42")

    // .value += compound
    count.value += 8
    assert(count.value == 50, "ref.value += 8")

    count.value -= 10
    assert(count.value == 40, "ref.value -= 10")

    count.value *= 2
    assert(count.value == 80, "ref.value *= 2")

    // ref(string)
    const name = ref("alice")
    assert(name.value == "alice", "ref string initial")
    name.value = "bob"
    assert(name.value == "bob", "ref string set")

    // watch: callback fires on change
    const score = ref(0)
    const called = ref(0)
    watch(score, (newVal: int, oldVal: int) => {
        called.value = 1
    })
    score.value = 100
    assert(called.value == 1, "watch callback fired")

    println("all ref tests passed")
}
