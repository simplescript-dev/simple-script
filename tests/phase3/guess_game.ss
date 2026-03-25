function main() {
    const secret = 42
    let attempts = 0
    let guessed = 0

    println("=== Guess the Number (1-100) ===")

    while (guessed == 0) {
        print("Your guess: ")
        const input = readLine()
        const guess = input.toInt()
        attempts = attempts + 1

        if (guess == secret) {
            println(`Correct! You got it in ${attempts} attempts!`)
            guessed = 1
        } else if (guess < secret) {
            println("Too low, try higher!")
        } else {
            println("Too high, try lower!")
        }
    }
}
