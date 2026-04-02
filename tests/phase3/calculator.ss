class Calculator {
    result: double

    function add(n: double): double {
        return this.result + n
    }

    function sub(n: double): double {
        return this.result - n
    }

    function mul(n: double): double {
        return this.result * n
    }

    function div(n: double): double {
        if (n == 0.0) {
            println("error: division by zero")
            return this.result
        }
        return this.result / n
    }

    function getResult(): double {
        return this.result
    }
}

function abs(n: double): double {
    if (n < 0.0) {
        return 0.0 - n
    }
    return n
}

function max(a: int, b: int): int {
    if (a > b) {
        return a
    }
    return b
}

function min(a: int, b: int): int {
    if (a < b) {
        return a
    }
    return b
}

function clamp(value: int, lo: int, hi: int): int {
    return max(lo, min(value, hi))
}

function main() {
    // Calculator
    const calc = new Calculator(100.0)
    println(`100 + 50 = ${calc.add(50.0)}`)
    println(`100 - 30 = ${calc.sub(30.0)}`)
    println(`100 * 2.5 = ${calc.mul(2.5)}`)
    println(`100 / 3 = ${calc.div(3.0)}`)
    calc.div(0.0)

    // Math functions
    println(`abs(-42.5) = ${abs(-42.5)}`)
    println(`abs(42.5) = ${abs(42.5)}`)
    println(`max(10, 20) = ${max(10, 20)}`)
    println(`min(10, 20) = ${min(10, 20)}`)
    println(`clamp(150, 0, 100) = ${clamp(150, 0, 100)}`)
    println(`clamp(-10, 0, 100) = ${clamp(-10, 0, 100)}`)
    println(`clamp(50, 0, 100) = ${clamp(50, 0, 100)}`)
}
