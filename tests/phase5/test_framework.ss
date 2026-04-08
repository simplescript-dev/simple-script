import { assertEqual, assertTrue, assertFalse } from "@/lib/test"

function add(a: int, b: int): int {
    return a + b
}

function main() {
    test("basic addition", (): void => {
        assertEqual(1 + 1, 2)
        assertEqual(add(3, 4), 7)
    })

    test("string equality", (): void => {
        assertEqual("hello", "hello")
        assertEqual("a" + "b", "ab")
    })

    test("boolean assertions", (): void => {
        assertTrue(1 == 1)
        assertTrue(5 > 3)
        assertFalse(1 == 2)
        assertFalse(3 > 5)
    })

    test("negative numbers", (): void => {
        assertEqual(-1 + 1, 0)
        assertEqual(5 - 10, -5)
    })
}
