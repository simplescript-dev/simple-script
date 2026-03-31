// Test: List<T> type alias (maps to Array internally, D021)

function main() {
    // List<string> works like Array<string>
    let items: List<string> = ["hello", "world"]
    if (items.length() != 2) { exit(1) }
    items = items.push("!")
    if (items.length() != 3) { exit(1) }

    // List<int>
    let nums: List<int> = [10, 20, 30]
    if (nums.length() != 3) { exit(1) }

    // Array<string> still works
    let old: Array<string> = ["a", "b"]
    if (old.length() != 2) { exit(1) }

    println("list_type: all passed")
}
