// Test: closures with higher-order array methods (map, filter, reduce)

function testFilterWithCapture() {
    const nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    const threshold = 5
    const big = nums.filter((x: int): int => x > threshold ? 1 : 0)
    if (big.length() != 5) { exit(1) }
}

function testMapWithCapture() {
    const nums = [1, 2, 3]
    const multiplier = 10
    const scaled = nums.map((x: int): int => x * multiplier)
    if (scaled[0] != 10) { exit(1) }
    if (scaled[1] != 20) { exit(1) }
    if (scaled[2] != 30) { exit(1) }
}

function testReduceWithCapture() {
    const nums = [1, 2, 3, 4]
    const bonus = 100
    // Sum all elements plus bonus per element
    const total = nums.reduce((acc: int, x: int): int => acc + x + bonus, 0)
    // (0+1+100) + (101+2+100) + (203+3+100) + (306+4+100) = 410
    if (total != 410) { exit(1) }
}

function main() {
    testFilterWithCapture()
    testMapWithCapture()
    testReduceWithCapture()
}
