// Test: ** exponentiation operator and **= compound assignment

function main() {
    // Basic int ** int
    if (2 ** 10 != 1024) { exit(1) }
    if (3 ** 3 != 27) { exit(2) }
    if (5 ** 0 != 1) { exit(3) }
    if (1 ** 100 != 1) { exit(4) }

    // Right-associativity: 2 ** 3 ** 2 == 2 ** (3 ** 2) == 2 ** 9 == 512
    if (2 ** 3 ** 2 != 512) { exit(5) }

    // Mixed with other operators
    if (2 ** 3 * 2 != 16) { exit(6) }   // (2**3)*2 = 16
    if (3 + 2 ** 4 != 19) { exit(7) }   // 3+(2**4) = 19

    // Double ** double
    const d1 = 2.0 ** 3.0
    if (d1 < 7.99 || d1 > 8.01) { exit(8) }

    // Int ** double (result is double)
    const d2 = 4 ** 0.5
    if (d2 < 1.99 || d2 > 2.01) { exit(9) }

    // **= compound assignment
    let x = 2
    x **= 5
    if (x != 32) { exit(10) }

    let y = 3
    y **= 3
    if (y != 27) { exit(11) }

    // **= with double
    let z = 2.0
    z **= 10.0
    if (z < 1023.9 || z > 1024.1) { exit(12) }

    // ** inside template expression
    const msg = `result: ${2 ** 8}`
    if (msg != "result: 256") { exit(13) }
}
