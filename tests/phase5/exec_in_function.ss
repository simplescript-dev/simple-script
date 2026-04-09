function run(): string {
    const result = exec("echo hello")
    if (result.exitCode != 0) {
        return ""
    }
    return result.stdout
}

function main() {
    println(run())
}
