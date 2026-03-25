function main() {
    const pi = 3.14159
    const radius = 5.0
    const area = pi * radius * radius
    println(`area = ${area}`)

    const temp = 36.6
    if (temp > 37.5) {
        println("fever")
    } else if (temp > 36.0) {
        println("normal")
    } else {
        println("low")
    }
}
