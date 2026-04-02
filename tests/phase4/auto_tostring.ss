class Point {
    x: int
    y: int

    function toString(): string {
        return "(" + this.x + ", " + this.y + ")"
    }
}

class Color {
    r: int
    g: int
    b: int

    function toString(): string {
        return "rgb(" + this.r + ", " + this.g + ", " + this.b + ")"
    }
}

function main() {
    const p = new Point(10, 20)
    println(p)              // auto calls toString()

    const c = new Color(255, 128, 0)
    println(c)

    // Multi-arg also works
    println("point:", p, "color:", c)

    // Regular strings still work
    println("hello")
    println(42)
}
