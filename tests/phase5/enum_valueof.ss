enum Color {
    Red = 0,
    Green = 1,
    Blue = 2
}

enum Direction {
    Up = "up",
    Down = "down",
    Left = "left",
    Right = "right"
}

function main() {
    // Int enum: valueOf
    if (Color.valueOf("Red") != 0) { exit(1) }
    if (Color.valueOf("Green") != 1) { exit(2) }
    if (Color.valueOf("Blue") != 2) { exit(3) }

    // String enum: valueOf
    if (Direction.valueOf("Up") != "up") { exit(4) }
    if (Direction.valueOf("Down") != "down") { exit(5) }
    if (Direction.valueOf("Left") != "left") { exit(6) }
    if (Direction.valueOf("Right") != "right") { exit(7) }

    // valueOf with variable argument
    const name = "Green"
    if (Color.valueOf(name) != 1) { exit(8) }

    // valueOf result in expression
    const val = Color.valueOf("Blue") + 10
    if (val != 12) { exit(9) }

    // valueOf with string enum in template
    const dir = Direction.valueOf("Left")
    const msg = `direction: ${dir}`
    if (msg != "direction: left") { exit(10) }

    // valueOf invalid name — should throw
    let caught = 0
    try {
        Color.valueOf("Purple")
    } catch (e) {
        caught = 1
    }
    if (caught != 1) { exit(11) }

    // valueOf invalid name on string enum — should throw
    caught = 0
    try {
        Direction.valueOf("North")
    } catch (e) {
        caught = 1
    }
    if (caught != 1) { exit(12) }

    println("enum_valueof: all passed")
}
