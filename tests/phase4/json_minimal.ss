import { JSON, JsonNode } from "@/lib/json"

function main() {
    // Parse object
    const obj = JSON.parse('{"name":"Alice","age":30}')
    println(obj.getString("name"))
    println(obj.getInt("age"))
    println(obj.type())

    // Parse nested
    const nested = JSON.parse('{"user":{"name":"Bob"}}')
    println(nested.get("user").getString("name"))

    // Build + stringify
    const built = JSON.create().put("x", "hello").put("y", 42)
    println(JSON.stringify(built))

    println("done")
}
