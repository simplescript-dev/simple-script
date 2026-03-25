import { tokenize, tkGet, tkKind, tkValue, tkCount } from "./lexer"

function main() {
    const src = "function main() {\n    println(`abc`)\n}\n"
    println("source: " + src.length() + " chars")
    println("tokenizing...")
    const tokens = tokenize(src)
    println("done, count=" + tkCount())
    let i = 0
    while (i < tkCount()) {
        const k = tkKind(tkGet(tokens, i))
        const v = tkValue(tkGet(tokens, i))
        if (k == "EOF") { break }
        println(i + ": " + k + " = " + v)
        i = i + 1
    }
}
