function PROMPT(instruction: string): string {
    println(instruction)
    return instruction
}

function onMounted(f: fn) {
    f()
}
