// Test: Array higher-order methods find/findIndex/some/every/includes

function main() {
    let arr = [10, 20, 30, 40, 50]

    // ── find ──────────────────────────────────────────
    const found = arr.find((x: int): int => x > 25 ? 1 : 0)
    if (found != 30) { exit(1) }

    // find returns 0 when no match
    const notFound = arr.find((x: int): int => x > 100 ? 1 : 0)
    if (notFound != 0) { exit(2) }

    // ── findIndex ─────────────────────────────────────
    const idx = arr.findIndex((x: int): int => x > 25 ? 1 : 0)
    if (idx != 2) { exit(3) }

    // findIndex returns -1 when no match
    const noIdx = arr.findIndex((x: int): int => x > 100 ? 1 : 0)
    if (noIdx != -1) { exit(4) }

    // findIndex: first element match
    const firstIdx = arr.findIndex((x: int): int => x == 10 ? 1 : 0)
    if (firstIdx != 0) { exit(5) }

    // ── some ──────────────────────────────────────────
    const hasLarge = arr.some((x: int): int => x > 40 ? 1 : 0)
    if (hasLarge != 1) { exit(6) }

    const hasHuge = arr.some((x: int): int => x > 100 ? 1 : 0)
    if (hasHuge != 0) { exit(7) }

    // ── every ─────────────────────────────────────────
    const allPositive = arr.every((x: int): int => x > 0 ? 1 : 0)
    if (allPositive != 1) { exit(8) }

    const allLarge = arr.every((x: int): int => x > 25 ? 1 : 0)
    if (allLarge != 0) { exit(9) }

    // ── includes ──────────────────────────────────────
    if (arr.includes(30) != 1) { exit(10) }
    if (arr.includes(99) != 0) { exit(11) }
    if (arr.includes(10) != 1) { exit(12) }
    if (arr.includes(50) != 1) { exit(13) }

    // ── empty array edge cases ────────────────────────
    let empty: Array<int> = []
    const emptyFind = empty.find((x: int): int => 1)
    if (emptyFind != 0) { exit(14) }

    const emptyIdx = empty.findIndex((x: int): int => 1)
    if (emptyIdx != -1) { exit(15) }

    const emptySome = empty.some((x: int): int => 1)
    if (emptySome != 0) { exit(16) }

    // every on empty array returns true (vacuous truth)
    const emptyEvery = empty.every((x: int): int => 0)
    if (emptyEvery != 1) { exit(17) }

    if (empty.includes(1) != 0) { exit(18) }
}
