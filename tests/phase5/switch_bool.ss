function describe(flag: bool): string {
    switch (flag) {
        case true -> return "yes"
        case false -> return "no"
    }
    return ""
}

function main() {
    if (describe(true) != "yes") { exit(1) }
    if (describe(false) != "no") { exit(1) }
    println("switch_bool: all passed")
}
