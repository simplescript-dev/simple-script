// SS-LIM-2 spike: Array<class T> indexed write (codegen + parser).
// Repro 1: arr[i] = new Class — was llc i64/ptr type mismatch on ss_arraySet.
// Repro 2: obj.field[i] = v — was parse error (INDEX_ACCESS+ASSIGN unhandled).

class Item {
    name: string
}

class Holder {
    items: Array<int>
}

class Box {
    items: Array<Item>
}

function main() {
    // Case 1 — Repro 1: ptr element (new instance, owned)
    let arr: Array<Item> = []
    arr = arr.push(new Item("a"))
    arr[0] = new Item("c")
    if (arr[0].name != "c") { exit(1) }

    // Case 2 — Repro 2: int element via member-access LHS
    let h = new Holder([1, 2, 3])
    h.items[0] = 99
    if (h.items[0] != 99) { exit(2) }
    if (h.items[1] != 2) { exit(3) }
    if (h.items[2] != 3) { exit(4) }

    // Case 3 — ptr element via member-access LHS (composite of Repro 1+2)
    let b = new Box([new Item("x")])
    b.items[0] = new Item("y")
    if (b.items[0].name != "y") { exit(5) }

    // Case 4 — borrowed (not owned) class assign: should retain via emitRetainForType
    let src = new Item("borrowed")
    let arr2: Array<Item> = []
    arr2 = arr2.push(new Item("orig"))
    arr2[0] = src
    if (arr2[0].name != "borrowed") { exit(6) }
    if (src.name != "borrowed") { exit(7) }  // src still alive after array set

    // Case 5 — primitive (string) element via var-name LHS (regression guard for existing path)
    let strs: Array<string> = []
    strs = strs.push("alpha")
    strs[0] = "omega"
    if (strs[0] != "omega") { exit(8) }

    // Case 6 — double element
    let dubs: Array<double> = []
    dubs = dubs.push(1.5)
    dubs[0] = 2.75
    if (dubs[0] != 2.75) { exit(9) }

    // Case 7 — int element via var-name LHS (regression guard)
    let nums: Array<int> = []
    nums = nums.push(10)
    nums[0] = 42
    if (nums[0] != 42) { exit(10) }

    // Case 8 — chain: arr[i].field[j] = v (parse_stmts.ss chain branch coverage)
    let bs: Array<Box> = []
    bs = bs.push(new Box([new Item("p"), new Item("q")]))
    bs[0].items[1] = new Item("r")
    if (bs[0].items[1].name != "r") { exit(11) }
    if (bs[0].items[0].name != "p") { exit(12) }

    println("SS-LIM-2 spike: all 8 cases PASS")
}
