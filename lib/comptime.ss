// lib/comptime.ss — Comptime standard library
//
// Import this to get reusable comptime helpers for reflection-driven code generation.
// Functions defined here persist across comptime blocks in the same compilation unit.

comptime {
    // ── SQL helpers ──

    function ctSqlType(ssType: string): string {
        if (ssType == "int") { return "INTEGER" }
        if (ssType == "double") { return "REAL" }
        return "TEXT"
    }

    function ctColumnName(f: FieldInfo): string {
        let j = 0
        while (j < f.annotations.length()) {
            const ann = f.annotations[j]
            if (ann.name == "Column" && ann.args != "") { return ann.args }
            j = j + 1
        }
        return f.name
    }

    function ctIsIdField(f: FieldInfo): int {
        let j = 0
        while (j < f.annotations.length()) {
            if (f.annotations[j].name == "Id") { return 1 }
            j = j + 1
        }
        return 0
    }

    function ctGenCreateTable(className: string): string {
        const info = getTypeInfo(className)
        let cols = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { cols = cols + ", " }
            cols = cols + ctColumnName(f) + " " + ctSqlType(f.type)
            if (ctIsIdField(f) == 1) { cols = cols + " PRIMARY KEY" }
            i = i + 1
        }
        return "CREATE TABLE " + className + " (" + cols + ")"
    }

    function ctGenInsertSQL(className: string): string {
        const info = getTypeInfo(className)
        let cols = ""
        let placeholders = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { cols = cols + ", "; placeholders = placeholders + ", " }
            cols = cols + ctColumnName(f)
            placeholders = placeholders + "?"
            i = i + 1
        }
        return "INSERT INTO " + className + " (" + cols + ") VALUES (" + placeholders + ")"
    }

    // ── Enum serialization helpers ──

    function ctGenNameOf(enumName: string): string {
        const info = getTypeInfo(enumName)
        let body = ""
        let i = 0
        while (i < info.variants.length()) {
            const v = info.variants[i]
            if (info.isString == 1) {
                body = body + "    if (value == \"" + v.value + "\") { return \"" + v.name + "\" }\n"
            } else {
                body = body + "    if (value == " + v.value + ") { return \"" + v.name + "\" }\n"
            }
            i = i + 1
        }
        let paramType = "int"
        if (info.isString == 1) { paramType = "string" }
        return "function " + enumName + "_nameOf(value: " + paramType + "): string {\n" + body + "    return \"unknown\"\n}"
    }

    function ctGenFromString(enumName: string): string {
        const info = getTypeInfo(enumName)
        let body = ""
        let i = 0
        while (i < info.variants.length()) {
            const v = info.variants[i]
            if (info.isString == 1) {
                body = body + "    if (name == \"" + v.name + "\") { return \"" + v.value + "\" }\n"
            } else {
                body = body + "    if (name == \"" + v.name + "\") { return " + v.value + " }\n"
            }
            i = i + 1
        }
        let retType = "int"
        let fallback = "-1"
        if (info.isString == 1) { retType = "string"; fallback = "\"\"" }
        return "function " + enumName + "_fromString(name: string): " + retType + " {\n" + body + "    return " + fallback + "\n}"
    }

    // ── JSON serialization helpers ──

    function ctGenToJson(className: string, funcName: string): string {
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
        return "function " + funcName + "(obj: " + className + "): string {\n    const q = \"\\\"\"\n    let r = \"{\"\n" + body + "    return r + \"}\"\n}"
    }
}
