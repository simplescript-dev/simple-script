// Type checking: INDEX_ACCESS inference + INDEX_ASSIGN checking.
// Tests that array element types flow through checkerInferType.

class Item {
    const name: string
    value: int
}

function takeString(s: string): string {
    return s
}

function takeInt(n: int): int {
    return n
}

function takeItem(item: Item): string {
    return item.name
}

function main() {
    // INDEX_ACCESS: element type inference from typed arrays
    const names: Array<string> = ["alice", "bob", "charlie"]
    const first: string = names[0]
    takeString(names[1])

    const nums: Array<int> = [10, 20, 30]
    const n: int = nums[0]
    takeInt(nums[1])

    // INDEX_ACCESS: List<T> alias
    const items: List<string> = ["x", "y"]
    const ls: string = items[0]

    // INDEX_ASSIGN: correct types
    let arr: Array<int> = [1, 2, 3]
    arr[0] = 42
    arr[1] = takeInt(5)

    let sarr: Array<string> = ["a", "b"]
    sarr[0] = "hello"
    sarr[1] = takeString("world")

    // Built-in function return types
    const line: string = readFile("/dev/null")
    const parsed: int = parseInt("42")
    const pd: double = parseDouble("3.14")
    const exists: int = fileExists("/dev/null")
    const code: int = charCodeAt("A", 0)

    // Class array element type
    const itemList: Array<Item> = [new Item("sword", 10)]
    takeItem(itemList[0])

    println("type_check_index: all passed")
}
