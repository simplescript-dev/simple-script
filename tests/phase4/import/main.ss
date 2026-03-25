import { add, multiply, factorial } from "./math"
import { repeat, padRight } from "./utils"

function main() {
    // Math functions from math.ss
    println("=== Math ===")
    println("add(3, 4) = " + add(3, 4))
    println("multiply(5, 6) = " + multiply(5, 6))
    println("factorial(10) = " + factorial(10))

    // Utils from utils.ss
    println("")
    println("=== Utils ===")
    println(repeat("*", 20))
    println(padRight("Name", 15) + "| Age")
    println(repeat("-", 20))
    println(padRight("Alice", 15) + "| 30")
    println(padRight("Bob", 15) + "| 25")
}
