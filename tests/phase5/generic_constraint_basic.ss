interface Rankable {
    function rank(): int
}

class Player(name: string, score: int) : Rankable {
    function rank(): int {
        return this.score
    }
}

class Team(label: string, wins: int) : Rankable {
    function rank(): int {
        return this.wins
    }
}

function best<T extends Rankable>(a: T, b: T): T {
    if (a.rank() > b.rank()) { return a }
    return b
}

function showRank<T extends Rankable>(item: T): int {
    return item.rank()
}

function main() {
    const p1 = new Player("Alice", 100)
    const p2 = new Player("Bob", 200)
    const winner = best(p1, p2)
    if (winner.name != "Bob") { exit(1) }
    if (winner.score != 200) { exit(1) }

    const t1 = new Team("Red", 5)
    const t2 = new Team("Blue", 3)
    const topTeam = best(t1, t2)
    if (topTeam.label != "Red") { exit(1) }

    if (showRank(p1) != 100) { exit(1) }
    if (showRank(t2) != 3) { exit(1) }

    // Explicit type args with constraint
    const w2 = best<Player>(p1, p2)
    if (w2.score != 200) { exit(1) }

    println("generic_constraint_basic: all passed")
}
