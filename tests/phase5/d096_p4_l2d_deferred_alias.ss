class Foo { x: int = 0 }
class Bar { tag: string = "" }

function single<T>() {
    const R = comptime { return T }
    const r = new R(x: 5)
    println(`x=${r.x}`)
}

function both<T, U>() {
    const A = comptime { return T }
    const B = comptime { return U }
    const a = new A(x: 7)
    const b = new B(tag: "hi")
    println(`${a.x}/${b.tag}`)
}

function main() {
    single<Foo>()
    both<Foo, Bar>()
}
