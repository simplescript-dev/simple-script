class Point {
    x: int
    y: int

    function getX(): int { return this.x }
    function getY(): int { return this.y }
}

function extract<T>(obj: T): T {
    return obj
}

function main() {
    const p = new Point(3, 4)
    const q = extract(p)
    if (q.getX() != 3) { exit(1) }
    if (q.getY() != 4) { exit(1) }

    println("generic_class_arg: all passed")
}
