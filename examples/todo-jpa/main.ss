// Todo API with JPA persistence
// Data persisted to ./data/todos.json

import { SpringApplication, Get, Post, Delete } from "@/lib/spring/boot"
import { HttpServletRequest, HttpServletResponse } from "@/lib/jakarta/servlet"
import { HttpStatus } from "@/lib/spring/http"
import { JpaRepository, JpaRepository_create } from "@/lib/spring/data"
import { JSON } from "@/lib/json"

let todoRepo = JpaRepository.create("todos")

function listTodos(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    return response.write(todoRepo.findAll())
}

function createTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const body = request.getInputStream()
    if (body == "") {
        return response.sendError(HttpStatus.BAD_REQUEST, `{"error":"body required"}`)
    }
    const saved = todoRepo.save(body)
    return response.setStatus(HttpStatus.CREATED).write(saved)
}

function getTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = parseInt(request.getParameter("id"))
    const todo = todoRepo.findById(id)
    if (todo == "") {
        return response.sendError(HttpStatus.NOT_FOUND, `{"error":"not found"}`)
    }
    return response.write(todo)
}

function deleteTodo(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const id = parseInt(request.getParameter("id"))
    if (todoRepo.existsById(id) == 0) {
        return response.sendError(HttpStatus.NOT_FOUND, `{"error":"not found"}`)
    }
    todoRepo.deleteById(id)
    return response.setStatus(HttpStatus.NO_CONTENT)
}

function countTodos(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    return response.write(`{"count":${todoRepo.count()}}`)
}

function main() {
    Get("/api/todos", listTodos)
    Post("/api/todos", createTodo)
    Get("/api/todo", getTodo)
    Delete("/api/todo", deleteTodo)
    Get("/api/todos/count", countTodos)

    const app = new SpringApplication()
    app.run(8080)
}
