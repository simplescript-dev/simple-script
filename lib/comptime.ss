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

    // Core: accessor is "obj" (standalone) or "this" (class method)
    function ctJsonBody(className: string, accessor: string): string {
        const info = getTypeInfo(className)
        let body = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            let line = "    r = r + "
            if (i > 0) { line = line + "\",\" + " }
            line = line + "q + \"" + f.name + "\" + q + \":\" + "
            if (f.type == "string") {
                line = line + "q + " + accessor + "." + f.name + " + q"
            } else {
                line = line + "\"\" + " + accessor + "." + f.name
            }
            body = body + line + "\n"
            i = i + 1
        }
        return body
    }

    function ctGenToJson(className: string, funcName: string): string {
        const body = ctJsonBody(className, "obj")
        return "function " + funcName + "(obj: " + className + "): string {\n    const q = \"\\\"\"\n    let r = \"{\"\n" + body + "    return r + \"}\"\n}"
    }

    // ── Method generators (for class-level comptime / @derive) ──

    function ctGenMethodToJson(className: string): string {
        const body = ctJsonBody(className, "this")
        return "function toJson(): string {\n    const q = \"\\\"\"\n    let r = \"{\"\n" + body + "    return r + \"}\"\n}"
    }

    function ctGenMethodToString(className: string): string {
        const info = getTypeInfo(className)
        let body = "    return \"" + className + "(\""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { body = body + " + \", \"" }
            body = body + " + \"" + f.name + "=\" + this." + f.name
            i = i + 1
        }
        body = body + " + \")\""
        return "function toString(): string {\n" + body + "\n}"
    }

    // ── Equals generator ──

    function ctGenMethodEquals(className: string): string {
        const info = getTypeInfo(className)
        let body = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            body = body + "    if (this." + f.name + " != other." + f.name + ") { return 0 }\n"
            i = i + 1
        }
        body = body + "    return 1"
        return "function equals(other: " + className + "): int {\n" + body + "\n}"
    }

    // ── @derive handlers ──
    // Convention: @derive("Xxx") calls ctDeriveXxx(className)
    // Users can define their own ctDeriveXxx(className) in comptime blocks.

    function ctDeriveToJson(className: string) {
        @comptimeEmit(ctGenMethodToJson(className))
    }

    function ctDeriveToString(className: string) {
        @comptimeEmit(ctGenMethodToString(className))
    }

    function ctDeriveEquals(className: string) {
        @comptimeEmit(ctGenMethodEquals(className))
    }

    // ── Structural validation helpers ──

    function ctAssertHasField(cls: string, field: string) {
        if (hasField(cls, field) == 0) {
            compileError(`${cls} must have field '${field}'`)
        }
    }

    function ctAssertHasMethod(cls: string, method: string) {
        if (hasMethod(cls, method) == 0) {
            compileError(`${cls} must have method '${method}'`)
        }
    }

    function ctAssertImplements(cls: string, iface: string) {
        if (hasInterface(cls, iface) == 0) {
            compileError(`${cls} must implement ${iface}`)
        }
    }

    function ctAssertExtends(child: string, parent: string) {
        if (isSubclassOf(child, parent) == 0) {
            compileError(`${child} must extend ${parent}`)
        }
    }
}
