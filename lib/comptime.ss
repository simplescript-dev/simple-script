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

    // ── Copy derive: generates copy() returning new instance with same field values ──

    function ctGenMethodCopy(className: string): string {
        const info = getTypeInfo(className)
        let args = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { args = args + ", " }
            args = args + f.name + ": this." + f.name
            i = i + 1
        }
        return "function copy(): " + className + " {\n    return new " + className + "(" + args + ")\n}"
    }

    function ctDeriveCopy(className: string) {
        @comptimeEmit(ctGenMethodCopy(className))
    }

    // ── String helpers ──

    function ctCapitalize(s: string): string {
        return s.charAt(0).toUpperCase() + s.substring(1, s.length())
    }

    // ── With derive: generates withXxx() per-field wither methods (immutable builder) ──

    function ctGenMethodWithField(className: string, info: TypeInfo, fieldIdx: int): string {
        const target = info.fields[fieldIdx]
        const cap = ctCapitalize(target.name)
        let args = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { args = args + ", " }
            if (i == fieldIdx) {
                args = args + f.name + ": " + f.name
            } else {
                args = args + f.name + ": this." + f.name
            }
            i = i + 1
        }
        return "function with" + cap + "(" + target.name + ": " + target.type + "): " + className + " {\n    return new " + className + "(" + args + ")\n}"
    }

    function ctDeriveWith(className: string) {
        const info = getTypeInfo(className)
        let i = 0
        while (i < info.fields.length()) {
            @comptimeEmit(ctGenMethodWithField(className, info, i))
            i = i + 1
        }
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

    // ── String utilities for code generation ──

    // Join comma-separated items with a custom separator
    function ctJoin(items: string, sep: string): string {
        if (items == "") { return "" }
        const parts = items.split(",")
        let result = ""
        let i = 0
        while (i < parts.length()) {
            if (i > 0) { result = result + sep }
            result = result + parts[i]
            i = i + 1
        }
        return result
    }

    // Repeat a string N times
    function ctRepeat(s: string, n: int): string {
        let result = ""
        let i = 0
        while (i < n) {
            result = result + s
            i = i + 1
        }
        return result
    }

    // Add prefix to each newline-separated line
    function ctIndent(code: string, prefix: string): string {
        const lines = code.split("\n")
        let result = ""
        let i = 0
        while (i < lines.length()) {
            if (i > 0) { result = result + "\n" }
            if (lines[i] != "") {
                result = result + prefix + lines[i]
            }
            i = i + 1
        }
        return result
    }

    // Wrap each comma-separated item with prefix/suffix, join with sep
    function ctWrap(items: string, prefix: string, suffix: string, sep: string): string {
        if (items == "") { return "" }
        const parts = items.split(",")
        let result = ""
        let i = 0
        while (i < parts.length()) {
            if (i > 0) { result = result + sep }
            result = result + prefix + parts[i] + suffix
            i = i + 1
        }
        return result
    }

    // ── Default derive: generates empty() returning zero-value instance ──

    function ctGenMethodEmpty(className: string): string {
        const info = getTypeInfo(className)
        let args = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { args = args + ", " }
            if (f.type == "int") {
                args = args + f.name + ": 0"
            } else if (f.type == "double") {
                args = args + f.name + ": 0.0"
            } else {
                args = args + f.name + ": \"\""
            }
            i = i + 1
        }
        return "function empty(): " + className + " {\n    return new " + className + "(" + args + ")\n}"
    }

    function ctDeriveDefault(className: string) {
        @comptimeEmit(ctGenMethodEmpty(className))
    }

    // ── Field iteration template helper ──

    // Apply a template to each field of a class, join with separator.
    // Replaces $name with field name and $type with field type in each expansion.
    function ctForEachField(className: string, template: string, sep: string): string {
        const info = getTypeInfo(className)
        let result = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { result = result + sep }
            let line = template.replace("$name", f.name)
            line = line.replace("$type", f.type)
            result = result + line
            i = i + 1
        }
        return result
    }

    // ── Hash derive: generates hashCode(): int ──

    function ctGenMethodHash(className: string): string {
        const info = getTypeInfo(className)
        let body = "    let h = 17\n"
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (f.type == "int") {
                body = body + "    h = h * 31 + this." + f.name + "\n"
            } else if (f.type == "string") {
                body = body + "    h = h * 31 + this." + f.name + ".length()\n"
            }
            i = i + 1
        }
        body = body + "    if (h < 0) { h = 0 - h }\n"
        body = body + "    return h"
        return "function hashCode(): int {\n" + body + "\n}"
    }

    function ctDeriveHash(className: string) {
        @comptimeEmit(ctGenMethodHash(className))
    }

    // ── Comparable derive: generates compareTo(other): int ──

    function ctGenMethodCompareTo(className: string): string {
        const info = getTypeInfo(className)
        let body = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            body = body + "    if (this." + f.name + " < other." + f.name + ") { return -1 }\n"
            body = body + "    if (this." + f.name + " > other." + f.name + ") { return 1 }\n"
            i = i + 1
        }
        body = body + "    return 0"
        return "function compareTo(other: " + className + "): int {\n" + body + "\n}"
    }

    function ctDeriveComparable(className: string) {
        @comptimeEmit(ctGenMethodCompareTo(className))
    }

    // ── Lookup table generation ──

    // Generate a lookup function from comma-separated keys and values
    // retType: "string" or "int"; fallback: value returned when key not found
    function ctGenLookup(funcName: string, keys: string, values: string, retType: string, fallback: string): string {
        const keyParts = keys.split(",")
        const valParts = values.split(",")
        let body = ""
        let i = 0
        while (i < keyParts.length()) {
            if (i < valParts.length()) {
                if (retType == "string") {
                    body = body + "    if (key == \"" + keyParts[i] + "\") { return \"" + valParts[i] + "\" }\n"
                } else {
                    body = body + "    if (key == \"" + keyParts[i] + "\") { return " + valParts[i] + " }\n"
                }
            }
            i = i + 1
        }
        return "function " + funcName + "(key: string): " + retType + " {\n" + body + "    return " + fallback + "\n}"
    }

    // Generate a reverse lookup function (value -> key)
    function ctGenReverseLookup(funcName: string, keys: string, values: string, valType: string, fallback: string): string {
        const keyParts = keys.split(",")
        const valParts = values.split(",")
        let body = ""
        let i = 0
        while (i < keyParts.length()) {
            if (i < valParts.length()) {
                if (valType == "string") {
                    body = body + "    if (value == \"" + valParts[i] + "\") { return \"" + keyParts[i] + "\" }\n"
                } else {
                    body = body + "    if (value == " + valParts[i] + ") { return \"" + keyParts[i] + "\" }\n"
                }
            }
            i = i + 1
        }
        return "function " + funcName + "(value: " + valType + "): string {\n" + body + "    return " + fallback + "\n}"
    }

    // ── Collection utilities ──

    // Replace all occurrences of old with rep in s
    function ctReplaceAll(s: string, old: string, rep: string): string {
        if (old == "") { return s }
        let result = ""
        let remaining = s
        let pos = remaining.indexOf(old)
        while (pos >= 0) {
            result = result + remaining.substring(0, pos) + rep
            remaining = remaining.substring(pos + old.length(), remaining.length())
            pos = remaining.indexOf(old)
        }
        return result + remaining
    }

    // Apply template to each comma-separated item, join with separator.
    // Replaces all $item with item value, all $index with 0-based position.
    function ctMap(items: string, template: string, sep: string): string {
        if (items == "") { return "" }
        const parts = items.split(",")
        let result = ""
        let i = 0
        while (i < parts.length()) {
            if (i > 0) { result = result + sep }
            let line = ctReplaceAll(template, "$item", parts[i])
            line = ctReplaceAll(line, "$index", `${i}`)
            result = result + line
            i = i + 1
        }
        return result
    }

    // Generate comma-separated integer sequence: start,start+1,...,end-1
    function ctRange(start: int, end: int): string {
        let result = ""
        let i = start
        while (i < end) {
            if (i > start) { result = result + "," }
            result = `${result}${i}`
            i = i + 1
        }
        return result
    }

    // Count items in comma-separated list (0 for empty string)
    function ctLen(items: string): int {
        if (items == "") { return 0 }
        return items.split(",").length()
    }

    // Check if target exists in comma-separated list (1=found, 0=not found)
    function ctContains(items: string, target: string): int {
        if (items == "") { return 0 }
        const parts = items.split(",")
        let i = 0
        while (i < parts.length()) {
            if (parts[i] == target) { return 1 }
            i = i + 1
        }
        return 0
    }

    // Apply template to paired items from two comma-separated lists, join with sep.
    // Replaces all $key from keys list, all $value from values list.
    function ctZip(keys: string, values: string, template: string, sep: string): string {
        if (keys == "") { return "" }
        const kParts = keys.split(",")
        const vParts = values.split(",")
        let result = ""
        let i = 0
        while (i < kParts.length()) {
            if (i > 0) { result = result + sep }
            let line = ctReplaceAll(template, "$key", kParts[i])
            if (i < vParts.length()) {
                line = ctReplaceAll(line, "$value", vParts[i])
            } else {
                line = ctReplaceAll(line, "$value", "")
            }
            result = result + line
            i = i + 1
        }
        return result
    }

}
