// SimpleScript HTTP Library
// Built on top of TCP primitives (tcpListen/tcpAccept/tcpRead/tcpWrite/tcpClose)

// ── Request parsing ──────────────────────────────────────────

function parseRequest(raw: string): Map<string, string> {
    const req = new Map()
    const headerEnd = raw.indexOf("\r\n\r\n")
    let headerSection = raw
    let body = ""
    if (headerEnd >= 0) {
        headerSection = raw.substring(0, headerEnd)
        body = raw.substring(headerEnd + 4, raw.length() - headerEnd - 4)
    }

    // First line: METHOD /path HTTP/1.1
    const firstNL = headerSection.indexOf("\r\n")
    let firstLine = headerSection
    let restHeaders = ""
    if (firstNL >= 0) {
        firstLine = headerSection.substring(0, firstNL)
        restHeaders = headerSection.substring(firstNL + 2, headerSection.length() - firstNL - 2)
    }

    // Parse method and path
    const sp1 = firstLine.indexOf(" ")
    if (sp1 >= 0) {
        req.set("method", firstLine.substring(0, sp1))
        const afterMethod = firstLine.substring(sp1 + 1, firstLine.length() - sp1 - 1)
        const sp2 = afterMethod.indexOf(" ")
        if (sp2 >= 0) {
            const fullPath = afterMethod.substring(0, sp2)
            // Split path and query string
            const qIdx = fullPath.indexOf("?")
            if (qIdx >= 0) {
                req.set("path", fullPath.substring(0, qIdx))
                const qs = fullPath.substring(qIdx + 1, fullPath.length() - qIdx - 1)
                req.set("query", qs)
                // I018 §路径 B — Spring Boot @RequestParam 契约:URL query key=value
                // 按 `&` 拆后各自入 req map,Controller 用 req.get("<key>") 取 query param
                // (req["query"] 整串 backward compat 保留)。空 value 存空串。
                if (qs != "") {
                    const qParts = qs.split("&")
                    for (qp in qParts) {
                        const eqIdx = qp.indexOf("=")
                        if (eqIdx > 0) {
                            const qk = qp.substring(0, eqIdx)
                            const qv = qp.substring(eqIdx + 1, qp.length() - eqIdx - 1)
                            req.set(qk, qv)
                        } else if (qp.length() > 0) {
                            req.set(qp, "")
                        }
                    }
                }
            } else {
                req.set("path", fullPath)
                req.set("query", "")
            }
        }
    }

    // Parse headers
    let remaining = restHeaders
    while (remaining != "") {
        const nlIdx = remaining.indexOf("\r\n")
        let line = remaining
        if (nlIdx >= 0) {
            line = remaining.substring(0, nlIdx)
            remaining = remaining.substring(nlIdx + 2, remaining.length() - nlIdx - 2)
        } else {
            remaining = ""
        }
        if (line != "") {
            const colonIdx = line.indexOf(": ")
            if (colonIdx >= 0) {
                const hName = line.substring(0, colonIdx).toLowerCase()
                const hVal = line.substring(colonIdx + 2, line.length() - colonIdx - 2)
                req.set(hName, hVal)
            }
        }
    }

    req.set("body", body)
    return req
}

// ── Response building ────────────────────────────────────────

function httpResponse(status: int, contentType: string, body: string): string {
    let statusText = "OK"
    if (status == 201) { statusText = "Created" }
    if (status == 204) { statusText = "No Content" }
    if (status == 301) { statusText = "Moved Permanently" }
    if (status == 302) { statusText = "Found" }
    if (status == 400) { statusText = "Bad Request" }
    if (status == 401) { statusText = "Unauthorized" }
    if (status == 403) { statusText = "Forbidden" }
    if (status == 404) { statusText = "Not Found" }
    if (status == 405) { statusText = "Method Not Allowed" }
    if (status == 500) { statusText = "Internal Server Error" }

    const contentLen = body.length()
    let response = `HTTP/1.1 ${status} ${statusText}\r\n`
    response = `${response}Content-Type: ${contentType}\r\n`
    response = `${response}Content-Length: ${contentLen}\r\n`
    response = `${response}Connection: close\r\n`
    response = `${response}\r\n`
    response = `${response}${body}`
    return response
}

function httpOk(body: string): string {
    return httpResponse(200, "text/plain", body)
}

function httpJson(body: string): string {
    return httpResponse(200, "application/json", body)
}

function httpHtml(body: string): string {
    return httpResponse(200, "text/html", body)
}

function httpNotFound(body: string): string {
    return httpResponse(404, "text/plain", body)
}

function httpError(body: string): string {
    return httpResponse(500, "text/plain", body)
}

function httpRedirect(url: string): string {
    let response = "HTTP/1.1 302 Found\r\n"
    response = `${response}Location: ${url}\r\n`
    response = `${response}Content-Length: 0\r\n`
    response = `${response}Connection: close\r\n`
    response = `${response}\r\n`
    return response
}

// ── Server ───────────────────────────────────────────────────

function httpServe(port: int, handler: fn) {
    const fd = tcpListen(port)
    if (fd < 0) {
        println(`error: failed to listen on port ${port}`)
        exit(1)
    }
    println(`listening on http://localhost:${port}`)

    while (1 == 1) {
        const client = tcpAccept(fd)
        if (client < 0) { continue }

        try {
            const raw = tcpRead(client, 65536)
            if (raw.length() > 0) {
                const req = parseRequest(raw)
                const response = handler(req)
                tcpWrite(client, response)
            }
        } catch (e) {
            const errResp = httpError(`server error: ${e}`)
            tcpWrite(client, errResp)
        }
        tcpClose(client)
    }
}
