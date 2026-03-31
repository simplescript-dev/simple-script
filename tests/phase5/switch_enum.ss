enum Color { Red, Green, Blue }

function colorName(c: int): string {
    switch (c) {
        case Color.Red -> return "red"
        case Color.Green -> return "green"
        case Color.Blue -> return "blue"
        default -> return "unknown"
    }
    return ""
}

function main() {
    if (colorName(0) != "red") { exit(1) }
    if (colorName(1) != "green") { exit(1) }
    if (colorName(2) != "blue") { exit(1) }
    if (colorName(99) != "unknown") { exit(1) }
    println("switch_enum: all passed")
}
