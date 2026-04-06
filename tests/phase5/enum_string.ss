enum Direction {
    Up = "up",
    Down = "down",
    Left = "left",
    Right = "right"
}

enum HttpMethod {
    Get = "GET",
    Post = "POST",
    Put = "PUT",
    Delete = "DELETE"
}

function dirLabel(d: string): string {
    switch (d) {
        case Direction.Up -> return "going up"
        case Direction.Down -> return "going down"
        case Direction.Left -> return "going left"
        case Direction.Right -> return "going right"
        default -> return "unknown"
    }
    return ""
}

function main() {
    // Direct access
    if (Direction.Up != "up") { exit(1) }
    if (Direction.Down != "down") { exit(1) }
    if (HttpMethod.Get != "GET") { exit(1) }
    if (HttpMethod.Delete != "DELETE") { exit(1) }

    // Variable assignment
    let dir = Direction.Left
    if (dir != "left") { exit(1) }

    // Switch with string enum
    if (dirLabel(Direction.Up) != "going up") { exit(1) }
    if (dirLabel(Direction.Right) != "going right") { exit(1) }
    if (dirLabel("other") != "unknown") { exit(1) }

    // String enum in switch subject variable
    let method = HttpMethod.Post
    let result = ""
    switch (method) {
        case HttpMethod.Get -> result = "get"
        case HttpMethod.Post -> result = "post"
        default -> result = "other"
    }
    if (result != "post") { exit(1) }

    println("enum_string: all passed")
}
