// Test: string .includes() method (alias for .contains())

function main() {
    const greeting = "Hello, World!"

    // Basic includes
    if (greeting.includes("Hello") == false) { throw("includes Hello failed") }
    if (greeting.includes("World") == false) { throw("includes World failed") }
    if (greeting.includes("xyz") == true) { throw("includes xyz should be false") }

    // Empty string
    if (greeting.includes("") == false) { throw("includes empty should be true") }

    // Single char
    if (greeting.includes(",") == false) { throw("includes comma failed") }
    if (greeting.includes("Z") == true) { throw("includes Z should be false") }

    // Exact match
    const exact = "abc"
    if (exact.includes("abc") == false) { throw("includes exact match failed") }

    // Contains still works
    if (greeting.contains("Hello") == false) { throw("contains still works") }

    println("string_includes: all passed")
}
