interface Animal {
    function speak(): string
}

class Dog(name: string) : Animal {
    function speak(): string {
        return "woof"
    }
}

class Cat(name: string) : Animal {
    function speak(): string {
        return "meow"
    }
}

function getAnimal(kind: int): Animal {
    if (kind == 1) {
        return new Dog("Rex")
    }
    return new Cat("Luna")
}

function main() {
    const a = getAnimal(1)
    println(a.speak())
    const b = getAnimal(2)
    println(b.speak())
}
