// Todo REST API — Spring Boot style
// Demonstrates: HTTP server, JSON, class, try/catch, Map, arrow functions

import { SpringApplication, Get, Post, Delete } from "@/lib/spring/boot"
import { HttpServletRequest, HttpServletResponse } from "@/lib/jakarta/servlet"
import { HttpStatus } from "@/lib/spring/http"
import { JSON, JsonNode } from "@/lib/json"

// ── Data store ───────────────────────────────────────────────

let todos = new Map()
let nextId = 1

// ── Handlers ─────────────────────────────────────────────────

function listTodos(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const keys = todos.keys()
    let json = "["
    let first = 1
    if (keys != "") {
        let remaining = keys
        while (remaining != "") {
            let k = remaining
            const nlIdx = remaining.indexOf("\n")
            if (nlIdx >= 0) {
                k = remaining.substring(0, nlIdx)
                remaining = remaining.substring(nlIdx + 1, remaining.length() - nlIdx - 1)
            } else {
                remaining = ""
            }
            if (k != "") {
                if (first == 1) { first = 0 } else { json = `${json},` }
                json = `${json}${todos.getString(k)}`
            }
        }
    }
    return response.write(`${json}]`)
}

function createTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const body = request.getInputStream()
    if (body == "") {
        return response.sendError(HttpStatus.BAD_REQUEST, `{"error":"body required"}`)
    }
    const parsed = JSON.parse(body)
    const title = parsed.getString("title")
    if (title == "") {
        return response.sendError(HttpStatus.BAD_REQUEST, `{"error":"title required"}`)
    }
    const id = nextId
    nextId = nextId + 1
    const todo = `{"id":${id},"title":"${title}","done":false}`
    todos.set(`${id}`, todo)
    return response.setStatus(HttpStatus.CREATED).write(todo)
}

function getTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = request.getParameter("id")
    if (id == "") {
        return response.sendError(HttpStatus.BAD_REQUEST, `{"error":"id required"}`)
    }
    if (todos.has(id) == 1) {
        return response.write(todos.getString(id))
    }
    return response.sendError(HttpStatus.NOT_FOUND, `{"error":"todo not found"}`)
}

function deleteTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = request.getParameter("id")
    if (todos.has(id) == 1) {
        todos.delete(id)
        return response.setStatus(HttpStatus.NO_CONTENT)
    }
    return response.sendError(HttpStatus.NOT_FOUND, `{"error":"todo not found"}`)
}

function home(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    return response.setContentType("text/html").write("<h1>Todo API</h1><p>Endpoints: GET/POST /api/todos, GET/DELETE /api/todo?id=N</p>")
}

// ── Application ──────────────────────────────────────────────

function main() {
    Get("/", home)
    Get("/api/todos", listTodos)
    Post("/api/todos", createTodo)
    Get("/api/todo", getTodo)
    Delete("/api/todo", deleteTodo)

    const app = new SpringApplication()
    app.run(8080)
}
