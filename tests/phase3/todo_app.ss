class Todo {
    id: int
    title: string
    done: int

    function getTitle(): string {
        return this.title
    }

    function isDone(): int {
        return this.done
    }

    function display(): string {
        if (this.done == 1) {
            return `[x] ${this.title}`
        }
        return `[ ] ${this.title}`
    }
}

function main() {
    // Create todos
    const t1 = new Todo(1, "Buy milk", 0)
    const t2 = new Todo(2, "Write compiler", 1)
    const t3 = new Todo(3, "Learn SimpleScript", 0)

    // Display all
    println("=== TODO List ===")
    println(t1.display())
    println(t2.display())
    println(t3.display())

    // Count done
    let doneCount = 0
    if (t1.isDone() == 1) { doneCount = doneCount + 1 }
    if (t2.isDone() == 1) { doneCount = doneCount + 1 }
    if (t3.isDone() == 1) { doneCount = doneCount + 1 }

    println(`Done: ${doneCount}/3`)

    // Repeat a string n times
    const stars = repeat("*", 20)
    println(stars)

    // Compute stats
    println(`Total todos: 3`)
    println(`Completed: ${doneCount}`)
    println(`Remaining: ${3 - doneCount}`)
}

function repeat(s: string, n: int): string {
    let result = ""
    for (let i = 0; i < n; i++) {
        result = result + s
    }
    return result
}
