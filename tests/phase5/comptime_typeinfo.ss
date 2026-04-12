// Test: @typeInfo compile-time reflection (D087 Phase 3a)

class Player {
    name: string
    health: int
    score: double

    function greet(): string {
        return "hello"
    }

    function takeDamage(amount: int): int {
        return this.health - amount
    }
}

comptime {
    const info = @typeInfo(Player)

    // Class name
    println(info.name)

    // Fields
    println(info.fields.length())
    println(info.fields[0].name)
    println(info.fields[0].type)
    println(info.fields[1].name)
    println(info.fields[1].type)
    println(info.fields[2].name)
    println(info.fields[2].type)

    // Methods
    println(info.methods.length())
    println(info.methods[0].name)
    println(info.methods[0].returnType)

    // Method params
    const m1 = info.methods[1]
    println(m1.name)
    println(m1.params.length())
    println(m1.params[0].name)
    println(m1.params[0].type)
}

function main() {
    println("runtime ok")
}
