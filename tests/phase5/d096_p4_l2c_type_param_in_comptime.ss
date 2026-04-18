class Foo { x: int = 0; y: string = "" }
class Bar { a: int = 0 }

function mkName<T>(): string {
    return comptime { return T.name }
}

function fieldCount<T>(): int {
    return comptime {
        let cnt = 0
        for (f in T.fields()) { cnt = cnt + 1 }
        return cnt
    }
}

function pair<T, U>(): string {
    return comptime { return T.name + "/" + U.name }
}

function main() {
    println(mkName<Foo>())
    println(`n=${fieldCount<Foo>()}`)
    println(pair<Foo, Bar>())
}
