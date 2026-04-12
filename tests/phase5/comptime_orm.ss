// Test: comptime-driven ORM — generate SQL from annotated @Entity classes
//
// Demonstrates: getTypeInfo + field annotations + getAnnotatedClasses +
// comptime helper functions + @comptimeEmit — all working together.

import { assertEqual } from "@/lib/test"

@Entity
class User {
    @Id
    id: int
    @Column("user_name")
    name: string
    @Column("email_addr")
    email: string
    age: int
}

@Entity
class Product {
    @Id
    id: int
    @Column("product_name")
    name: string
    price: double
}

comptime {
    function sqlType(ssType: string): string {
        if (ssType == "int") { return "INTEGER" }
        if (ssType == "double") { return "REAL" }
        return "TEXT"
    }

    function columnName(f: FieldInfo): string {
        let j = 0
        while (j < f.annotations.length()) {
            const ann = f.annotations[j]
            if (ann.name == "Column" && ann.args != "") { return ann.args }
            j = j + 1
        }
        return f.name
    }

    function isIdField(f: FieldInfo): int {
        let j = 0
        while (j < f.annotations.length()) {
            if (f.annotations[j].name == "Id") { return 1 }
            j = j + 1
        }
        return 0
    }

    function genCreateTable(className: string): string {
        const info = getTypeInfo(className)
        let cols = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { cols = cols + ", " }
            cols = cols + columnName(f) + " " + sqlType(f.type)
            if (isIdField(f) == 1) { cols = cols + " PRIMARY KEY" }
            i = i + 1
        }
        return "CREATE TABLE " + className + " (" + cols + ")"
    }

    function genInsertSQL(className: string): string {
        const info = getTypeInfo(className)
        let cols = ""
        let placeholders = ""
        let i = 0
        while (i < info.fields.length()) {
            const f = info.fields[i]
            if (i > 0) { cols = cols + ", "; placeholders = placeholders + ", " }
            cols = cols + columnName(f)
            placeholders = placeholders + "?"
            i = i + 1
        }
        return "INSERT INTO " + className + " (" + cols + ") VALUES (" + placeholders + ")"
    }

    const uCreate = genCreateTable("User")
    const uInsert = genInsertSQL("User")
    const pCreate = genCreateTable("Product")

    const entities = getAnnotatedClasses("Entity")
    let eCount = entities.length()
    let eNames = ""
    let ei = 0
    while (ei < entities.length()) {
        if (ei > 0) { eNames = eNames + "," }
        eNames = eNames + entities[ei]
        ei = ei + 1
    }

    @comptimeEmit(`
function userCreateSQL(): string { return "${uCreate}" }
function userInsertSQL(): string { return "${uInsert}" }
function productCreateSQL(): string { return "${pCreate}" }
function entityCount(): int { return ${eCount} }
function entityNames(): string { return "${eNames}" }
`)
}

function main() {
    test("ORM User CREATE TABLE", () => {
        assertEqual(userCreateSQL(), "CREATE TABLE User (id INTEGER PRIMARY KEY, user_name TEXT, email_addr TEXT, age INTEGER)")
    })
    test("ORM User INSERT", () => {
        assertEqual(userInsertSQL(), "INSERT INTO User (id, user_name, email_addr, age) VALUES (?, ?, ?, ?)")
    })
    test("ORM Product CREATE TABLE", () => {
        assertEqual(productCreateSQL(), "CREATE TABLE Product (id INTEGER PRIMARY KEY, product_name TEXT, price REAL)")
    })
    test("ORM entity discovery", () => {
        assertEqual(entityCount(), 2)
    })
}
