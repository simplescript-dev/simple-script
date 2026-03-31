function main() {
    // Integer array destructuring
    const nums: Array<int> = [10, 20, 30]
    const [a, b, c] = nums
    if (a != 10) { exit(1) }
    if (b != 20) { exit(1) }
    if (c != 30) { exit(1) }

    // String array destructuring (from split)
    const words = "hello,world".split(",")
    const [x, y] = words
    if (x != "hello") { exit(1) }
    if (y != "world") { exit(1) }

    // String array with type annotation
    const items: Array<string> = ["foo", "bar"]
    const [p, q] = items
    if (p != "foo") { exit(1) }
    if (q != "bar") { exit(1) }

    // Rest element with int array
    const nums2: Array<int> = [1, 2, 3, 4, 5]
    const [first, ...rest] = nums2
    if (first != 1) { exit(1) }
    if (rest.length() != 4) { exit(1) }
    if (rest[0] != 2) { exit(1) }
    if (rest[3] != 5) { exit(1) }

    // Rest element with string array
    const tags: Array<string> = ["hello", "world", "foo"]
    const [head, ...tail] = tags
    if (head != "hello") { exit(1) }
    if (tail.length() != 2) { exit(1) }
    if (tail[0] != "world") { exit(1) }
    if (tail[1] != "foo") { exit(1) }

    println("destruct_array: all passed")
}
