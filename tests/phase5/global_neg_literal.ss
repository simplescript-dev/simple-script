// Test: global variables with negative literal initializers
let gNegInt = -1
let gNegInt2 = -42
let gNegDouble = -3.14
let gPosInt = 100

function main() {
    // Verify negative int globals
    if (gNegInt != -1) { exit(1) }
    if (gNegInt2 != -42) { exit(2) }

    // Verify negative double global
    if (gNegDouble > -3.13 || gNegDouble < -3.15) { exit(3) }

    // Verify positive int global still works
    if (gPosInt != 100) { exit(4) }

    // Verify arithmetic with negative globals
    let sum = gNegInt + gNegInt2
    if (sum != -43) { exit(5) }

    // Verify mutation of negative globals
    gNegInt = -99
    if (gNegInt != -99) { exit(6) }
}
