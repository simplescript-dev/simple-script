// Markdown to HTML — built with SimpleScript

function main() {
    if (args() < 2) {
        println("Usage: markdown <file.md>")
        exit(1)
    }
    const content = readFile(arg(1))
    println("<!DOCTYPE html><html><body>")
    const lines = content.split("\n")
    let inList = 0
    for (line in lines) {
        const t = line.trim()
        if (t == "") {
            if (inList == 1) { println("</ul>"); inList = 0 }
            continue
        }
        if (t.startsWith("### ") == 1) {
            println("<h3>" + t.substring(4, t.length() - 4) + "</h3>")
        } else if (t.startsWith("## ") == 1) {
            println("<h2>" + t.substring(3, t.length() - 3) + "</h2>")
        } else if (t.startsWith("# ") == 1) {
            println("<h1>" + t.substring(2, t.length() - 2) + "</h1>")
        } else if (t.startsWith("- ") == 1) {
            if (inList == 0) { println("<ul>"); inList = 1 }
            println("  <li>" + t.substring(2, t.length() - 2) + "</li>")
        } else {
            if (inList == 1) { println("</ul>"); inList = 0 }
            println("<p>" + t + "</p>")
        }
    }
    if (inList == 1) { println("</ul>") }
    println("</body></html>")
}
