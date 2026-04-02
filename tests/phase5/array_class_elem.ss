class Point {
    x: int
    y: int
}

function main() {
    let p1 = new Point(1, 2)
    let p2 = new Point(3, 4)
    let points: Array<Point> = [p1, p2]

    // for-in with Array<Point>
    let sum = 0
    for (p in points) {
        sum = sum + p.x + p.y
    }
    if (sum != 10) { exit(1) }

    // index access with Array<Point>
    let first = points[0]
    if (first.x != 1) { exit(1) }
    if (first.y != 2) { exit(1) }
}
