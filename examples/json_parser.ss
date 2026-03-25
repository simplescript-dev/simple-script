// SimpleScript JSON-like Parser + CSV Parser
// Uses single quotes to embed JSON with double quotes

function main() {
    // JSON parsing
    const json = '{"name":"Alice","age":30,"city":"Beijing"}'
    println("=== JSON Parser ===")
    println("Input: " + json)

    const data = parseJson(json)
    println("  name: " + data.getString("name"))
    println("  age: " + data.get("age"))
    println("  city: " + data.getString("city"))

    // CSV parsing with split()
    println("")
    println("=== CSV Parser ===")
    const csv = "name,age,city\nAlice,30,Beijing\nBob,25,Shanghai\nCharlie,35,Shenzhen"
    const lines = csv.split("\n")

    println("Rows: " + lines.length())
    for (let i = 1; i < lines.length(); i++) {
        const fields = lines[i].split(",")
        println("  " + fields[0] + " | " + fields[1] + " | " + fields[2])
    }
}

function parseJson(json: string): string {
    const result = Map()
    const len = json.length()
    let i = 1

    while (i < len) {
        const ch = json.charAt(i)
        if (ch == "}") { break }
        if (ch == "," || ch == " ") { i = i + 1; continue }

        if (ch == '"') {
            i = i + 1
            let keyStart = i
            while (i < len && json.charAt(i) != '"') { i = i + 1 }
            const key = json.substring(keyStart, i - keyStart)
            i = i + 2

            if (json.charAt(i) == '"') {
                i = i + 1
                let valStart = i
                while (i < len && json.charAt(i) != '"') { i = i + 1 }
                result.set(key, json.substring(valStart, i - valStart))
                i = i + 1
            } else {
                let valStart = i
                while (i < len && json.charAt(i) != ',' && json.charAt(i) != '}') { i = i + 1 }
                result.set(key, json.substring(valStart, i - valStart).toInt())
            }
        } else {
            i = i + 1
        }
    }
    return result
}
