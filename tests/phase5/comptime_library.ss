// Test: comptime standard library — import shared helpers, generate code

import { assertEqual } from "@/lib/test"
import { } from "@/lib/comptime"

@Entity
class Order {
    @Id
    id: int
    @Column("customer_name")
    customer: string
    total: double
}

enum Priority { Low = 1, Medium = 2, High = 3 }

comptime {
    // Use library helpers — defined in lib/comptime.ss comptime block
    const createSQL = ctGenCreateTable("Order")
    const insertSQL = ctGenInsertSQL("Order")

    const enumCode = ctGenNameOf("Priority") + "\n" + ctGenFromString("Priority")
    const jsonCode = ctGenToJson("Order", "orderToJson")

    @comptimeEmit(`
function getOrderCreateSQL(): string { return "${createSQL}" }
function getOrderInsertSQL(): string { return "${insertSQL}" }
${enumCode}
${jsonCode}
`)
}

function main() {
    test("comptime library ORM", () => {
        assertEqual(getOrderCreateSQL(), "CREATE TABLE Order (id INTEGER PRIMARY KEY, customer_name TEXT, total REAL)")
        assertEqual(getOrderInsertSQL(), "INSERT INTO Order (id, customer_name, total) VALUES (?, ?, ?)")
    })
    test("comptime library enum serializer", () => {
        assertEqual(Priority_nameOf(1), "Low")
        assertEqual(Priority_nameOf(3), "High")
        assertEqual(Priority_fromString("Medium"), 2)
        assertEqual(Priority_fromString("invalid"), -1)
    })
    test("comptime library JSON serializer", () => {
        const o = new Order(id: 42, customer: "Bob", total: 99.5)
        assertEqual(orderToJson(o), "{\"id\":42,\"customer\":\"Bob\",\"total\":99.5}")
    })
}
