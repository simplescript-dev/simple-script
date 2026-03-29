// Todo REST API with JPA + SQLite persistence
// Data stored in SQLite (in-memory for demo)

import { SpringApplication, Get, Post, Delete } from "@/lib/spring/boot"
import { HttpServletRequest, HttpServletResponse } from "@/lib/jakarta/servlet"
import { HttpStatus } from "@/lib/spring/http"
import { JpaRepository, JpaRepositoryFactory } from "@/lib/spring/data"
import { ResultSet, rsNext } from "@/lib/java/sql"

let todoRepo = JpaRepositoryFactory.create("sqlite::memory:", "todos", "id,title,done")

function initDb() {
    todoRepo.execute("CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, done INTEGER DEFAULT 0)")
}

function listTodos(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    let rs = todoRepo.findAll()
    let json = "["
    let first = 1
    while (rs.next() == 1) {
        if (first == 1) { first = 0 } else { json = `${json},` }
        json = `${json}{"id":${rs.getInt("id")},"title":"${rs.getString("title")}","done":${rs.getInt("done")}}`
        rs = rsNext(rs)
    }
    return response.write(`${json}]`)
}

function createTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const body = request.getInputStream()
    if (body == "") {
        return response.sendError(HttpStatus.BAD_REQUEST, `{"error":"body required"}`)
    }
    // Extract title from JSON body (simple parse)
    const titleStart = body.indexOf("\"title\"")
    if (titleStart < 0) {
        return response.sendError(HttpStatus.BAD_REQUEST, `{"error":"title required"}`)
    }
    const valStart = body.indexOf(":", titleStart)
    const qStart = body.indexOf("\"", valStart + 1)
    const qEnd = body.indexOf("\"", qStart + 1)
    const title = body.substring(qStart + 1, qEnd - qStart - 1)

    todoRepo.save("title", `'${title}'`)
    const id = todoRepo.count()
    return response.setStatus(HttpStatus.CREATED).write(`{"id":${id},"title":"${title}","done":0}`)
}

function getTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = parseInt(request.getParameter("id"))
    const rs = todoRepo.findById(id)
    if (rs.next() == 0) {
        return response.sendError(HttpStatus.NOT_FOUND, `{"error":"not found"}`)
    }
    return response.write(`{"id":${rs.getInt("id")},"title":"${rs.getString("title")}","done":${rs.getInt("done")}}`)
}

function deleteTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = parseInt(request.getParameter("id"))
    if (todoRepo.existsById(id) == 0) {
        return response.sendError(HttpStatus.NOT_FOUND, `{"error":"not found"}`)
    }
    todoRepo.deleteById(id)
    return response.setStatus(HttpStatus.NO_CONTENT)
}

function toggleTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = parseInt(request.getParameter("id"))
    const rs = todoRepo.findById(id)
    if (rs.next() == 0) {
        return response.sendError(HttpStatus.NOT_FOUND, `{"error":"not found"}`)
    }
    const currentDone = rs.getInt("done")
    const newDone = currentDone == 0 ? 1 : 0
    todoRepo.update(id, `done = ${newDone}`)
    return response.write(`{"id":${id},"done":${newDone}}`)
}

function main() {
    initDb()

    Get("/api/todos", listTodos)
    Post("/api/todos", createTodo)
    Get("/api/todo", getTodo)
    Delete("/api/todo", deleteTodo)
    Post("/api/todo/toggle", toggleTodo)

    const app = new SpringApplication()
    app.run(8080)
}
