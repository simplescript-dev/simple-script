class Point {
    x: int
    y: int

    function distanceSq(other: Point): int {
        const dx = this.x - other.x
        const dy = this.y - other.y
        return dx * dx + dy * dy
    }

    function toString(): string {
        return `(${this.x}, ${this.y})`
    }
}

function main() {
    const a = new Point(3, 4)
    const b = new Point(0, 0)
    println(`a = ${a.toString()}`)
    println(`b = ${b.toString()}`)
    println(`distanceSq = ${a.distanceSq(b)}`)
}
