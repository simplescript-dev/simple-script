// SimpleScript Spring Boot — Application Bootstrap
// Built on Jakarta Servlet API + Tomcat Embedded Core

import { HttpServletRequest, HttpServletResponse, createServletResponse } from "@/lib/jakarta/servlet"
import { Tomcat, createTomcat } from "@/lib/tomcat/embed"
import { httpNotFound } from "@/lib/http"

// ── Route registry ───────────────────────────────────────────

let routes = new Map()
let routeCount = 0

function registerRoute(method: string, path: string, handler: fn) {
    routes.set(`${method}:${path}`, handler)
    routeCount = routeCount + 1
}

function Get(path: string, handler: fn) { registerRoute("GET", path, handler) }
function Post(path: string, handler: fn) { registerRoute("POST", path, handler) }
function Put(path: string, handler: fn) { registerRoute("PUT", path, handler) }
function Delete(path: string, handler: fn) { registerRoute("DELETE", path, handler) }
function Patch(path: string, handler: fn) { registerRoute("PATCH", path, handler) }

// ── DispatcherServlet ────────────────────────────────────────

function dispatcherServlet(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const method = request.getMethod()
    const path = request.getRequestURI()
    const key = `${method}:${path}`

    if (routes.has(key) == 1) {
        const handler = routes.get(key)
        return handler(request, response)
    }

    // Try without trailing slash
    if (path.endsWith("/") == 1 && path != "/") {
        const key2 = `${method}:${path.substring(0, path.length() - 1)}`
        if (routes.has(key2) == 1) {
            const handler2 = routes.get(key2)
            return handler2(request, response)
        }
    }

    return response.sendError(404, `Cannot ${method} ${path}`)
}

// ── SpringApplication ────────────────────────────────────────

class SpringApplication() {
    function run(port: int) {
        println("")
        println("  .   ____          _            __ _ _")
        println(" /\\\\ / ___'_ __ _ _(_)_ __  __ _ \\ \\ \\ \\")
        println("( ( )\\___ | '_ | '_| | '_ \\/ _` | \\ \\ \\ \\")
        println(" \\\\/  ___)| |_)| | | | |_) | (_| |  ) ) ) )")
        println("  '  |____| .__|_| |_|_| |_\\__, | / / / /")
        println(" =========|_|==============|___/=/_/_/_/")
        println("")
        println(`  SimpleScript Spring Boot v0.1.0`)
        println(`  Powered by Tomcat Embedded`)
        println(`  ${routeCount} route(s) registered`)
        println("")

        const tomcat = createTomcat().setPort(port)
        tomcat.start(dispatcherServlet)
    }
}
