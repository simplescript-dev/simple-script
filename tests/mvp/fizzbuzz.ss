function fizzbuzz(n: int): string {
    if (n % 15 == 0) {
        return "FizzBuzz"
    }
    if (n % 3 == 0) {
        return "Fizz"
    }
    if (n % 5 == 0) {
        return "Buzz"
    }
    return `${n}`
}

function main() {
    for (let i = 1; i <= 20; i++) {
        println(fizzbuzz(i))
    }
}
