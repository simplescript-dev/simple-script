// Jakarta Servlet API 6.0 — SimpleScript Implementation
// Source: https://mvnrepository.com/artifact/jakarta.servlet/jakarta.servlet-api
// Only the subset used by Spring Boot REST APIs

// ── Cookie ───────────────────────────────────────────────────

class Cookie {
    name: string
    value: string

    function getName(): string { return this.name }
    function getValue(): string { return this.value }
}

// ── HttpServletRequest ───────────────────────────────────────

class HttpServletRequest {
    headers: Map<string, string>
    attributes: Map<string, string>

    function getMethod(): string {
        return this.headers.getString("method")
    }

    function getRequestURI(): string {
        return this.headers.getString("path")
    }

    function getPathInfo(): string {
        return this.headers.getString("path")
    }

    function getQueryString(): string {
        return this.headers.getString("query")
    }

    function getParameter(name: string): string {
        const query = this.getQueryString()
        if (query == "") { return "" }
        let remaining = query
        while (remaining != "") {
            let pair = remaining
            const ampIdx = remaining.indexOf("&")
            if (ampIdx >= 0) {
                pair = remaining.substring(0, ampIdx)
                remaining = remaining.substring(ampIdx + 1, remaining.length() - ampIdx - 1)
            } else {
                remaining = ""
            }
            const eqIdx = pair.indexOf("=")
            if (eqIdx >= 0) {
                const pName = pair.substring(0, eqIdx)
                const pVal = pair.substring(eqIdx + 1, pair.length() - eqIdx - 1)
                if (pName == name) { return pVal }
            }
        }
        return ""
    }

    function getHeader(name: string): string {
        return this.headers.getString(name.toLowerCase())
    }

    function getContentType(): string {
        return this.getHeader("content-type")
    }

    function getContentLength(): int {
        const cl = this.getHeader("content-length")
        if (cl == "") { return 0 }
        return parseInt(cl)
    }

    function getInputStream(): string {
        return this.headers.getString("body")
    }

    function getAttribute(name: string): string {
        return this.attributes.getString(name)
    }

    function setAttribute(name: string, value: string) {
        this.attributes.set(name, value)
    }

    // Path variable from route pattern {var} — stored by DispatcherServlet
    function getPathVariable(name: string): string {
        return this.attributes.getString(name)
    }

    function getRemoteAddr(): string {
        return "127.0.0.1"
    }

    function getProtocol(): string {
        return "HTTP/1.1"
    }

    function getScheme(): string {
        return "http"
    }
}

// ── HttpServletResponse ──────────────────────────────────────

class HttpServletResponse {
    status: int
    contentType: string
    body: string
    responseHeaders: Map<string, string>

    function setStatus(code: int): HttpServletResponse {
        return new HttpServletResponse(code, this.contentType, this.body, this.responseHeaders)
    }

    function getStatus(): int {
        return this.status
    }

    function setContentType(ct: string): HttpServletResponse {
        return new HttpServletResponse(this.status, ct, this.body, this.responseHeaders)
    }

    function getContentType(): string {
        return this.contentType
    }

    function setHeader(name: string, value: string): HttpServletResponse {
        this.responseHeaders.set(name, value)
        return this
    }

    function getWriter(): HttpServletResponse {
        return this
    }

    function write(data: string): HttpServletResponse {
        return new HttpServletResponse(this.status, this.contentType, this.body + data, this.responseHeaders)
    }

    function sendError(code: int, message: string): HttpServletResponse {
        return new HttpServletResponse(code, "text/plain", message, this.responseHeaders)
    }

    function sendRedirect(url: string): HttpServletResponse {
        this.responseHeaders.set("Location", url)
        return new HttpServletResponse(302, "text/plain", "", this.responseHeaders)
    }

    function containsHeader(name: string): int {
        return this.responseHeaders.has(name)
    }

    function flushBuffer(): string {
        let statusText = "OK"
        if (this.status == 201) { statusText = "Created" }
        if (this.status == 204) { statusText = "No Content" }
        if (this.status == 301) { statusText = "Moved Permanently" }
        if (this.status == 302) { statusText = "Found" }
        if (this.status == 400) { statusText = "Bad Request" }
        if (this.status == 401) { statusText = "Unauthorized" }
        if (this.status == 403) { statusText = "Forbidden" }
        if (this.status == 404) { statusText = "Not Found" }
        if (this.status == 405) { statusText = "Method Not Allowed" }
        if (this.status == 409) { statusText = "Conflict" }
        if (this.status == 500) { statusText = "Internal Server Error" }
        let resp = `HTTP/1.1 ${this.status} ${statusText}\r\n`
        resp = `${resp}Content-Type: ${this.contentType}\r\n`
        resp = `${resp}Content-Length: ${this.body.length()}\r\n`
        resp = `${resp}Connection: close\r\n`
        resp = `${resp}\r\n`
        resp = `${resp}${this.body}`
        return resp
    }
}

// ── Filter / FilterChain ─────────────────────────────────────

interface Filter {
    function doFilter(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse
}

// ── Factory methods ──────────────────────────────────────────

function createServletRequest(rawHeaders: Map<string, string>): HttpServletRequest {
    return new HttpServletRequest(rawHeaders, new Map())
}

function createServletResponse(): HttpServletResponse {
    return new HttpServletResponse(200, "application/json", "", new Map())
}
