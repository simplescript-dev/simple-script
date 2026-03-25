import { loadTodos, saveTodos } from "./storage"

function main() {
    const dbPath = "/tmp/ss_todos.txt"

    if (args() < 2) {
        showHelp()
        exit(0)
    }

    const cmd = arg(1)

    if (cmd == "add") {
        if (args() < 3) {
            println("usage: todo add <task>")
            exit(1)
        }
        const task = arg(2)
        addTodo(dbPath, task)
    } else if (cmd == "list") {
        listTodos(dbPath)
    } else if (cmd == "done") {
        if (args() < 3) {
            println("usage: todo done <number>")
            exit(1)
        }
        const num = arg(2).toInt()
        markDone(dbPath, num)
    } else if (cmd == "clear") {
        writeFile(dbPath, "")
        println("all todos cleared")
    } else {
        println("unknown command: " + cmd)
        showHelp()
    }
}

function showHelp() {
    println("todo — SimpleScript Task Manager")
    println("")
    println("Commands:")
    println("  todo add <task>    Add a new task")
    println("  todo list          List all tasks")
    println("  todo done <n>      Mark task #n as done")
    println("  todo clear         Remove all tasks")
}

function addTodo(path: string, task: string) {
    const db = loadTodos(path)
    const nextId = db.size() + 1
    db.set(nextId.toString(), "[ ] " + task)
    saveTodos(path, db)
    println("added: " + task)
}

function listTodos(path: string) {
    const db = loadTodos(path)
    if (db.size() == 0) {
        println("no todos yet. add one with: todo add <task>")
        return
    }

    println("=== TODO (" + db.size() + " tasks) ===")
    for (let i = 1; i <= db.size(); i++) {
        const task = db.getString(i.toString())
        println("  " + i + ". " + task)
    }
}

function markDone(path: string, num: int) {
    const db = loadTodos(path)
    const key = num.toString()

    if (db.has(key) == 0) {
        println("task #" + num + " not found")
        return
    }

    const task = db.getString(key)
    if (task.startsWith("[x]") == 1) {
        println("task #" + num + " already done")
        return
    }

    const newTask = "[x]" + task.substring(3, task.length() - 3)
    db.set(key, newTask)
    saveTodos(path, db)
    println("done: " + newTask)
}
