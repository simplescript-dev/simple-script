class Pt {
    x: int = 7
    y: int = 11
}

function main() {
    // form 2: full named arg
    const a = new Pt(x: 5, y: 10)
    println(a.x)
    println(a.y)
    // form 3: 全 default 空 ctor (silent bug fix — uses default expr 7/11, not zero)
    const b = new Pt()
    println(b.x)
    println(b.y)
    // form 1: partial named arg (D149 main feature)
    const c = new Pt(x: 100)
    println(c.x)
    println(c.y)
    const d = new Pt(y: 200)
    println(d.x)
    println(d.y)
    return 0
}
