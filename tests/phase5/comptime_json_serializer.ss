// Test: comptime-driven JSON serializer — auto-generate toJson from class fields

import { assertEqual } from "@/lib/test"

class User {
    id: int
    name: string
    score: double
}

class Point {
    x: int
    y: int
}

comptime {
    function genToJson(className: string): string {
        const info = getTypeInfo(className)
        let body = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            let line = "    r = r + "
            if (i > 0) { line = line + "\",\" + " }
            line = line + "q + \"" + f.name + "\" + q + \":\" + "
            if (f.type == "string") {
                line = line + "q + obj." + f.name + " + q"
            } else {
                line = line + "\"\" + obj." + f.name
            }
            body = body + line + "\n"
            i = i + 1
        }
        return "function serialize" + className + "(obj: " + className + "): string {\n    const q = \"\\\"\"\n    let r = \"{\"\n" + body + "    return r + \"}\"\n}"
    }

    const code = genToJson("User") + "\n\n" + genToJson("Point")
    @comptimeEmit(code)
}

function main() {
    test("User toJson", () => {
        const u = new User(id: 1, name: "Alice", score: 95.5)
        const json = serializeUser(u)
        assertEqual(json, "{\"id\":1,\"name\":\"Alice\",\"score\":95.5}")
    })
    test("Point toJson", () => {
        const p = new Point(x: 10, y: 20)
        assertEqual(serializePoint(p), "{\"x\":10,\"y\":20}")
    })
    test("User toJson empty string", () => {
        const u = new User(id: 0, name: "", score: 0.0)
        assertEqual(serializeUser(u), "{\"id\":0,\"name\":\"\",\"score\":0}")
    })
}
