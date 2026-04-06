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
    // Int enum: values()
    let vals = Color.values()
    if (vals.length() != 3) { exit(1) }
    if (vals[0] != 0) { exit(1) }
    if (vals[1] != 1) { exit(1) }
    if (vals[2] != 2) { exit(1) }

    // Int enum: names()
    let names = Color.names()
    if (names.length() != 3) { exit(1) }
    if (names[0] != "Red") { exit(1) }
    if (names[1] != "Green") { exit(1) }
    if (names[2] != "Blue") { exit(1) }

    // String enum: values()
    let dirs = Direction.values()
    if (dirs.length() != 4) { exit(1) }
    if (dirs[0] != "up") { exit(1) }
    if (dirs[1] != "down") { exit(1) }
    if (dirs[2] != "left") { exit(1) }
    if (dirs[3] != "right") { exit(1) }

    // String enum: names()
    let dnames = Direction.names()
    if (dnames.length() != 4) { exit(1) }
    if (dnames[0] != "Up") { exit(1) }
    if (dnames[1] != "Down") { exit(1) }
    if (dnames[2] != "Left") { exit(1) }
    if (dnames[3] != "Right") { exit(1) }

    println("enum_methods: all passed")
}
