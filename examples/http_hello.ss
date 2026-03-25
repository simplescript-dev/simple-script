// Minimal HTTP server in pure SimpleScript
function handleRequest(request: string): string {
    // Extract method and path from first line
    let method = "GET"
    let path = "/"
    let spacePos = request.indexOf(" ")
    if (spacePos > 0) {
        method = request.substring(0, spacePos)
        const rest = request.substring(spacePos + 1, request.length() - spacePos - 1)
        const sp2 = rest.indexOf(" ")
        if (sp2 > 0) {
            path = rest.substring(0, sp2)
        }
    }

    // Route
    let body = ""
    let status = "200 OK"
    let contentType = "application/json"
    if (path == "/") {
        body = "{\"message\":\"Hello from SimpleScript!\"}"
    } else if (path == "/health") {
        body = "{\"status\":\"ok\"}"
    } else {
        status = "404 Not Found"
        body = "{\"error\":\"not found\",\"path\":\"" + path + "\"}"
    }

    return "HTTP/1.1 " + status + "\r\nContent-Type: " + contentType + "\r\nContent-Length: " + body.length() + "\r\nConnection: close\r\n\r\n" + body
}

function main() {
    const port = 8080
    const server = tcpListen(port)
    if (server < 0) {
        println("Failed to listen on port " + port)
        exit(1)
    }
    println("Listening on http://localhost:" + port)

    while (1 == 1) {
        const client = tcpAccept(server)
        if (client < 0) { continue }
        const request = tcpRead(client, 4096)
        const response = handleRequest(request)
        tcpWrite(client, response)
        tcpClose(client)
    }
}
