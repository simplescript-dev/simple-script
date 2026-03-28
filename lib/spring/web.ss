// SimpleScript Spring Web — HttpServletRequest & HttpServletResponse
// Mirrors Java Servlet API for Spring Boot style development

import { parseRequest, httpResponse } from "@/lib/http"

// ── HttpServletRequest ───────────────────────────────────────

class HttpServletRequest(data: Map<string, string>) {
    function getMethod(): string {
        return this.data.getString("method")
    }

    function getRequestURI(): string {
        return this.data.getString("path")
    }

    function getPathInfo(): string {
        return this.data.getString("path")
    }

    function getParameter(name: string): string {
        const query = this.data.getString("query")
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
        return this.data.getString(name.toLowerCase())
    }

    function getBody(): string {
        return this.data.getString("body")
    }

    function getContentType(): string {
        return this.data.getString("content-type")
    }

    function getContentLength(): int {
        const cl = this.data.getString("content-length")
        if (cl == "") { return 0 }
        return parseInt(cl)
    }

    function getQueryString(): string {
        return this.data.getString("query")
    }
}

// ── HttpServletResponse (functional style) ───────────────────

function ResponseOk(body: string): string {
    return httpResponse(200, "application/json", body)
}

function ResponseHtml(body: string): string {
    return httpResponse(200, "text/html", body)
}

function ResponseCreated(body: string): string {
    return httpResponse(201, "application/json", body)
}

function ResponseNotFound(body: string): string {
    return httpResponse(404, "application/json", body)
}

function ResponseError(body: string): string {
    return httpResponse(500, "application/json", body)
}

function ResponseRedirect(url: string): string {
    return httpResponse(302, "text/plain", "")
}

// ── Factory ──────────────────────────────────────────────────

function createRequest(rawData: string): HttpServletRequest {
    const parsed = parseRequest(rawData)
    return new HttpServletRequest(parsed)
}
