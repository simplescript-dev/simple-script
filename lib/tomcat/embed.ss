// Tomcat Embedded Core — SimpleScript Implementation
// Source: https://mvnrepository.com/artifact/org.apache.tomcat.embed/tomcat-embed-core
// Embedded HTTP server with Servlet container

import { parseRequest } from "@/lib/http"
import { HttpServletRequest, HttpServletResponse, createServletRequest, createServletResponse } from "@/lib/jakarta/servlet"

// ── Connector ────────────────────────────────────────────────

class Connector(port: int, protocol: string) {
    function getPort(): int { return this.port }
    function getProtocol(): string { return this.protocol }
}

// ── Servlet (interface) ──────────────────────────────────────

interface Servlet {
    function service(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse
}

// ── Tomcat ───────────────────────────────────────────────────

class Tomcat(port: int, hostname: string, baseDir: string) {
    function setPort(p: int): Tomcat {
        return new Tomcat(p, this.hostname, this.baseDir)
    }

    function setHostname(h: string): Tomcat {
        return new Tomcat(this.port, h, this.baseDir)
    }

    function setBaseDir(dir: string): Tomcat {
        return new Tomcat(this.port, this.hostname, dir)
    }

    function getConnector(): Connector {
        return new Connector(this.port, "HTTP/1.1")
    }

    function start(handler: fn) {
        const fd = tcpListen(this.port)
        if (fd < 0) {
            println(`Tomcat: failed to start on port ${this.port}`)
            exit(1)
        }

        println(`Tomcat initialized with port(s): ${this.port} (http)`)
        println(`Tomcat started on port ${this.port}`)

        while (1 == 1) {
            const client = tcpAccept(fd)
            if (client < 0) { continue }
            try {
                const raw = tcpRead(client, 65536)
                if (raw.length() > 0) {
                    const parsed = parseRequest(raw)
                    const request = createServletRequest(parsed)
                    let response = createServletResponse()
                    response = handler(request, response)
                    tcpWrite(client, response.flushBuffer())
                }
            } catch (e) {
                const errResp = createServletResponse()
                const errOut = errResp.sendError(500, `Internal Server Error: ${e}`)
                tcpWrite(client, errOut.flushBuffer())
            }
            tcpClose(client)
        }
    }
}

// ── Factory ──────────────────────────────────────────────────

function createTomcat(): Tomcat {
    return new Tomcat(8080, "localhost", "/tmp")
}
