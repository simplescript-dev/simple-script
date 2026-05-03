class Pt {
    x: int = 0
    y: int = 0
}

function main() {
    const p = new Pt(x: 5, y: 10)
    println(p.x)
    println(p.y)
    const q = new Pt()
    println(q.x)
    println(q.y)
    return 0
}
