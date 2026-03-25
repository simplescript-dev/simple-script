enum Color {
    Red,
    Green,
    Blue
}

function colorName(c: int): string {
    switch (c) {
        case 0 -> return "Red"
        case 1 -> return "Green"
        case 2 -> return "Blue"
        default -> return "Unknown"
    }
}

function main() {
    println(colorName(0))
    println(colorName(1))
    println(colorName(2))
    println(colorName(99))
}
