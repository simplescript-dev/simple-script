// Test: comptime type discovery — classNames()/enumNames() for metaprogramming

import { assertEqual, assertTrue } from "@/lib/test"

enum Status { Active = 1, Inactive = 2 }
enum Color { Red = 1, Green = 2, Blue = 3 }

class Animal {
    name: string
    legs: int
}

class Vehicle {
    brand: string
    wheels: int
}

// Discover all classes and generate a count function
comptime {
    const classes = classNames()
    @comptimeEmit(`
function registeredClassCount(): int {
    return ${classes.length()}
}
`)
}

// Discover all enums and generate a count function
comptime {
    const enums = enumNames()
    @comptimeEmit(`
function registeredEnumCount(): int {
    return ${enums.length()}
}
`)
}

// Auto-generate factory-style describe function for each user class
comptime {
    const classes = classNames()
    let i = 0
    while (i < classes.length()) {
        const cls = classes[i]
        const info = getTypeInfo(cls)
        // Generate a describe function that lists field names
        let fieldList = ""
        let j = 0
        while (j < info.fields.length()) {
            if (j > 0) { fieldList = fieldList + "," }
            fieldList = fieldList + info.fields[j].name
            j = j + 1
        }
        @comptimeEmit(`
function describe_${cls}(): string {
    return "${cls}(${fieldList})"
}
`)
        i = i + 1
    }
}

// Generate enum registry: function that maps name to variant count
comptime {
    const enums = enumNames()
    let body = ""
    let i = 0
    while (i < enums.length()) {
        const en = enums[i]
        const info = getTypeInfo(en)
        if (i > 0) { body = body + "\n    " }
        body = body + `if (name == "${en}") { return ${info.variants.length()} }`
        i = i + 1
    }
    @comptimeEmit(`
function enumVariantCount(name: string): int {
    ${body}
    return -1
}
`)
}

function main() {
    test("comptime discovery — classNames returns user classes", () => {
        // Should include at least Animal and Vehicle
        assertTrue(registeredClassCount() >= 2)
    })
    test("comptime discovery — enumNames returns user enums", () => {
        // Should include at least Status and Color
        assertTrue(registeredEnumCount() >= 2)
    })
    test("comptime discovery — auto-generated describe functions", () => {
        assertEqual(describe_Animal(), "Animal(name,legs)")
        assertEqual(describe_Vehicle(), "Vehicle(brand,wheels)")
    })
    test("comptime discovery — enum registry from discovery", () => {
        assertEqual(enumVariantCount("Status"), 2)
        assertEqual(enumVariantCount("Color"), 3)
        assertEqual(enumVariantCount("Unknown"), -1)
    })
}
