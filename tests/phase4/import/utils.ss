function repeat(s: string, n: int): string {
    let result = ""
    for (let i = 0; i < n; i++) {
        result = result + s
    }
    return result
}

function padRight(s: string, width: int): string {
    let result = s
    while (result.length() < width) {
        result = result + " "
    }
    return result
}
