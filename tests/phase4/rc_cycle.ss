// Test: Cycle detection — non-owning containers prevent memory issues
// Node.children: Array<Node> creates a self-referential type graph
// The compiler detects the cycle and marks children as non-owning

class Node {
    value: int
    children: Array<Node>
}

class Parent {
    name: string
    kids: Array<Parent>
}

function testSelfRef() {
    const a = new Node(1, [])
    const b = new Node(2, [])
    println(a.value)
    println(b.value)
}

function testPtrFields() {
    const p1 = new Parent("Alice", [])
    const p2 = new Parent("Bob", [])
    println(p1.name)
    println(p2.name)
}

function main() {
    testSelfRef()
    testPtrFields()
    println("rc_cycle ok")
}
