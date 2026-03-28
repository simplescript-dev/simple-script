// SimpleScript Spring Boot — Application Bootstrap
// Usage: SpringApplication.run(8080)

import { parseRequest, httpResponse, httpOk, httpJson, httpNotFound, httpError } from "@/lib/http"

// ── Route registry ───────────────────────────────────────────

let routes = ""
let routeCount = 0
let routeReady = 0

function initRoutes() {
    if (routeReady == 1) { return }
    routes = new Map()
    routeReady = 1
}

function registerRoute(method: string, path: string, handler: fn) {
    initRoutes()
    const key = `${method}:${path}`
    routes.set(key, handler)
    routeCount = routeCount + 1
}

function Get(path: string, handler: fn) {
    registerRoute("GET", path, handler)
}

function Post(path: string, handler: fn) {
    registerRoute("POST", path, handler)
}

function Put(path: string, handler: fn) {
    registerRoute("PUT", path, handler)
}

function Delete(path: string, handler: fn) {
    registerRoute("DELETE", path, handler)
}

// ── Request dispatcher ───────────────────────────────────────

function dispatch(req: Map<string, string>): string {
    const method = req.getString("method")
    const path = req.getString("path")
    const key = `${method}:${path}`

    if (routes.has(key) == 1) {
        const handler = routes.get(key)
        return handler(req)
    }

    // Try path without trailing slash
    if (path.endsWith("/") == 1 && path != "/") {
        const trimmedPath = path.substring(0, path.length() - 1)
        const key2 = `${method}:${trimmedPath}`
        if (routes.has(key2) == 1) {
            const handler2 = routes.get(key2)
            return handler2(req)
        }
    }

    return httpNotFound(`Cannot ${method} ${path}`)
}

// ── Spring Application ───────────────────────────────────────

class SpringApplication() {
    function run(port: int) {
        const fd = tcpListen(port)
        if (fd < 0) {
            println(`error: failed to listen on port ${port}`)
            exit(1)
        }

        println("")
        println("  .   ____          _            __ _ _")
        println(" /\\\\ / ___'_ __ _ _(_)_ __  __ _ \\ \\ \\ \\")
        println("( ( )\\___ | '_ | '_| | '_ \\/ _` | \\ \\ \\ \\")
        println(" \\\\/  ___)| |_)| | | | |_) | (_| |  ) ) ) )")
        println("  '  |____| .__|_| |_|_| |_\\__, | / / / /")
        println(" =========|_|==============|___/=/_/_/_/")
        println("")
        println(`  SimpleScript Spring Boot v0.1.0`)
        println(`  Running on http://localhost:${port}`)
        println(`  ${routeCount} route(s) registered`)
        println("")

        while (1 == 1) {
            const client = tcpAccept(fd)
            if (client < 0) { continue }
            try {
                const raw = tcpRead(client, 65536)
                if (raw.length() > 0) {
                    const req = parseRequest(raw)
                    const method = req.getString("method")
                    const path = req.getString("path")
                    const response = dispatch(req)
                    println(`${method} ${path}`)
                    tcpWrite(client, response)
                }
            } catch (e) {
                const errResp = httpError(`Internal Server Error: ${e}`)
                tcpWrite(client, errResp)
            }
            tcpClose(client)
        }
    }
}
