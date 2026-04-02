class Node {
    value: int
    next: int

    function getValue(): int {
        return this.value
    }
}

function main() {
    // Build a simple "stack" using function calls
    let size = 0

    // Test: multiple class instances
    const n1 = new Node(10, 0)
    const n2 = new Node(20, 0)
    const n3 = new Node(30, 0)

    println(`n1=${n1.getValue()}, n2=${n2.getValue()}, n3=${n3.getValue()}`)

    // Test: while loop with complex condition
    let sum = 0
    let i = 1
    while (i <= 100) {
        sum = sum + i
        i = i + 1
    }
    println(`sum 1..100 = ${sum}`)

    // Test: nested if
    const score = 85
    const grade = getGrade(score)
    println(`score=${score}, grade=${grade}`)
}

function getGrade(score: int): string {
    if (score >= 90) {
        return "A"
    } else if (score >= 80) {
        return "B"
    } else if (score >= 70) {
        return "C"
    } else if (score >= 60) {
        return "D"
    } else {
        return "F"
    }
}
