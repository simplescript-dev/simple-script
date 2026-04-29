enum Season { Spring, Summer, Autumn, Winter }

function classify(n: int): string {
    switch (n) {
        case 1, 2, 3 -> return "small"
        case 4, 5, 6 -> return "medium"
        default -> return "large"
    }
    return ""
}

function isHot(s: int): int {
    switch (s) {
        case Season.Summer -> return 1
        case Season.Spring, Season.Autumn -> return 0
        case Season.Winter -> return -1
        default -> return -99
    }
    return -99
}

function vowel(c: string): int {
    switch (c) {
        case "a", "e", "i", "o", "u" -> return 1
        default -> return 0
    }
    return 0
}

function httpCategory(code: int): string {
    switch (code) {
        case 200, 201, 204 -> return "success"
        case 301, 302, 304 -> return "redirect"
        case 400, 401, 403, 404 -> return "client_error"
        case 500, 502, 503 -> return "server_error"
        default -> return "other"
    }
    return ""
}

function main() {
    if (classify(1) != "small") { exit(1) }
    if (classify(2) != "small") { exit(1) }
    if (classify(3) != "small") { exit(1) }
    if (classify(5) != "medium") { exit(1) }
    if (classify(9) != "large") { exit(1) }

    if (isHot(1) != 1) { exit(1) }
    if (isHot(0) != 0) { exit(1) }
    if (isHot(2) != 0) { exit(1) }
    if (isHot(3) != -1) { exit(1) }

    if (vowel("a") != 1) { exit(1) }
    if (vowel("e") != 1) { exit(1) }
    if (vowel("u") != 1) { exit(1) }
    if (vowel("x") != 0) { exit(1) }

    if (httpCategory(200) != "success") { exit(1) }
    if (httpCategory(201) != "success") { exit(1) }
    if (httpCategory(404) != "client_error") { exit(1) }
    if (httpCategory(503) != "server_error") { exit(1) }
    if (httpCategory(100) != "other") { exit(1) }

    println("switch_multicase: all passed")
}
