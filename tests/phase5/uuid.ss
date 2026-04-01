import { UUID } from "@/lib/uuid"

function main() {
    // Test v4 generation
    const id1 = UUID.v4()
    const id2 = UUID.v4()
    // Length must be 36 (8-4-4-4-12 + 4 dashes)
    if (id1.length() != 36) { exit(1) }
    if (id2.length() != 36) { exit(1) }

    // Must be valid UUIDs
    if (UUID.isValid(id1) != 1) { exit(2) }
    if (UUID.isValid(id2) != 1) { exit(2) }

    // Two generated UUIDs should differ
    if (id1 == id2) { exit(3) }

    // Version must be 4
    if (UUID.version(id1) != 4) { exit(4) }
    if (UUID.version(id2) != 4) { exit(4) }

    // Check dash positions: 8, 13, 18, 23
    if (id1.charAt(8) != "-") { exit(5) }
    if (id1.charAt(13) != "-") { exit(5) }
    if (id1.charAt(18) != "-") { exit(5) }
    if (id1.charAt(23) != "-") { exit(5) }

    // Check version char at position 14
    if (id1.charAt(14) != "4") { exit(6) }

    // Check variant char at position 19 (must be 8, 9, a, or b)
    const vc = id1.charAt(19)
    if (vc != "8" && vc != "9" && vc != "a" && vc != "b") { exit(7) }

    // Test nil UUID
    const nilId = UUID.nil()
    if (nilId != "00000000-0000-0000-0000-000000000000") { exit(8) }
    if (UUID.isValid(nilId) != 1) { exit(8) }
    if (UUID.version(nilId) != 0) { exit(8) }

    // Test isValid — valid cases
    if (UUID.isValid("550e8400-e29b-41d4-a716-446655440000") != 1) { exit(9) }
    if (UUID.isValid("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") != 1) { exit(9) }

    // Test isValid — invalid cases
    if (UUID.isValid("") != 0) { exit(10) }
    if (UUID.isValid("not-a-uuid") != 0) { exit(10) }
    if (UUID.isValid("550e8400-e29b-41d4-a716-44665544000") != 0) { exit(10) }
    if (UUID.isValid("550e8400-e29b-41d4-a716-4466554400000") != 0) { exit(10) }
    if (UUID.isValid("550e8400xe29b-41d4-a716-446655440000") != 0) { exit(10) }
    if (UUID.isValid("550e8400-e29b-41d4-a716-44665544000g") != 0) { exit(10) }

    // Test parse — normalization to lowercase
    const parsed = UUID.parse("550E8400-E29B-41D4-A716-446655440000")
    if (parsed != "550e8400-e29b-41d4-a716-446655440000") { exit(11) }

    // Test parse — invalid input returns ""
    if (UUID.parse("invalid") != "") { exit(12) }

    // Test version extraction
    if (UUID.version("550e8400-e29b-41d4-a716-446655440000") != 4) { exit(13) }
    if (UUID.version("550e8400-e29b-11d4-a716-446655440000") != 1) { exit(13) }
    if (UUID.version("550e8400-e29b-31d4-a716-446655440000") != 3) { exit(13) }
    if (UUID.version("550e8400-e29b-51d4-a716-446655440000") != 5) { exit(13) }

    // Test version on invalid input
    if (UUID.version("invalid") != 0) { exit(14) }

    // Generate multiple UUIDs and check all are valid
    let i = 0
    while (i < 20) {
        const u = UUID.v4()
        if (UUID.isValid(u) != 1) { exit(15) }
        if (UUID.version(u) != 4) { exit(15) }
        if (u.charAt(14) != "4") { exit(15) }
        const v = u.charAt(19)
        if (v != "8" && v != "9" && v != "a" && v != "b") { exit(15) }
        i = i + 1
    }

    println("UUID tests passed")
}
