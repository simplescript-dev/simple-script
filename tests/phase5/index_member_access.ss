// Test: array[i].field, array[i].method(), array[i].fn_field() chaining
class Item {
    name: string
    value: int

    function doubled(): int {
        return this.value * 2
    }
}

class Nested {
    item: Item
}

function doWork(x: string): string { return x + "!" }

class Plugin {
    name: string
    run: fn
}

function main() {
    let items: Array<Item> = []
    items = items.push(new Item("alpha", 10))
    items = items.push(new Item("beta", 20))

    // array[i].field
    if (items[0].name != "alpha") { exit(1) }
    if (items[1].value != 20) { exit(1) }

    // array[i].method()
    if (items[0].doubled() != 20) { exit(1) }
    if (items[1].doubled() != 40) { exit(1) }

    // array[i].field with variable index
    let idx = 1
    if (items[idx].name != "beta") { exit(1) }

    // nested: array[i].field.field
    let wrappers: Array<Nested> = []
    wrappers = wrappers.push(new Nested(new Item("nested", 99)))
    if (wrappers[0].item.name != "nested") { exit(1) }
    if (wrappers[0].item.value != 99) { exit(1) }

    // array[i].fn_field(args) — fn type field call after index access
    let plugins: Array<Plugin> = []
    plugins = plugins.push(new Plugin("p1", doWork))
    plugins[0].run("test")

    // array[i].field as statement (no chaining)
    items[0].value

    println("index_member_access: all passed")
}
