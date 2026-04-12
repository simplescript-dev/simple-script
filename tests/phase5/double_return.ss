// I009: Functions returning double must not corrupt int parameters

function intToDouble(n: int): double {
    if (n != 42) { exit(1) }
    return parseDouble(`${n}`) * 1.5
}

function twoIntParams(a: int, b: int): double {
    if (a != 3) { exit(1) }
    if (b != 7) { exit(1) }
    return parseDouble(`${a + b}`)
}

function mixedParams(name: string, count: int): double {
    if (name != "hello") { exit(1) }
    if (count != 5) { exit(1) }
    return parseDouble(`${count}`) * 2.0
}

function doubleParams(a: double, b: double): double {
    return a + b
}

function main() {
    const r1 = intToDouble(42)
    if (r1 != 63.0) { exit(1) }

    const r2 = twoIntParams(3, 7)
    if (r2 != 10.0) { exit(1) }

    const r3 = mixedParams("hello", 5)
    if (r3 != 10.0) { exit(1) }

    const r4 = doubleParams(3, 7)
    if (r4 != 10.0) { exit(1) }
}
