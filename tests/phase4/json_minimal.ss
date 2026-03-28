import { jsonParse, jsonStringify, jnGetType, jnAsString, jnAsInt, jnGet, jnGetString, jnGetInt, jnArrayLen, jnArrayGet, jnNewObject, jnSetField, jnNewString, jnNewInt, jnNewArray, jnAddElement } from "@/lib/json"

function main() {
    // Parse empty object
    const obj1 = jsonParse("{}")
    println(jnGetType(obj1))

    // Parse object with string value
    const obj2 = jsonParse("{\"name\": \"Alice\", \"city\": \"NYC\"}")
    println(jnGetString(obj2, "name"))
    println(jnGetString(obj2, "city"))

    // Parse object with int value
    const obj3 = jsonParse("{\"age\": 30}")
    println(jnGetInt(obj3, "age"))

    // Parse array
    const arr = jsonParse("[1, 2, 3]")
    println(jnGetType(arr))
    println(jnArrayLen(arr))
    println(jnAsInt(jnArrayGet(arr, 0)))
    println(jnAsInt(jnArrayGet(arr, 2)))

    // Parse nested object
    const nested = jsonParse("{\"user\": {\"name\": \"Bob\"}}")
    const user = jnGet(nested, "user")
    println(jnGetString(user, "name"))

    // Parse bool and null
    const obj4 = jsonParse("{\"active\": true, \"deleted\": false, \"meta\": null}")
    println(jnGetType(jnGet(obj4, "active")))
    println(jnGetType(jnGet(obj4, "meta")))

    // Build and stringify
    const built = jnNewObject()
    jnSetField(built, "x", jnNewInt(42))
    jnSetField(built, "y", jnNewString("hello"))
    println(jsonStringify(built))

    // Array stringify
    const arr2 = jnNewArray()
    jnAddElement(arr2, jnNewInt(1))
    jnAddElement(arr2, jnNewInt(2))
    jnAddElement(arr2, jnNewString("three"))
    println(jsonStringify(arr2))

    println("done")
}
