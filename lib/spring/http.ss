// SimpleScript Spring HTTP — ResponseEntity & HttpStatus
// Mirrors Spring's ResponseEntity<T> for building HTTP responses

import { httpResponse } from "@/lib/http"

// ── HttpStatus (enum with values, like Spring's HttpStatus) ──

enum HttpStatus {
    OK = 200,
    CREATED = 201,
    NO_CONTENT = 204,
    MOVED_PERMANENTLY = 301,
    FOUND = 302,
    BAD_REQUEST = 400,
    UNAUTHORIZED = 401,
    FORBIDDEN = 403,
    NOT_FOUND = 404,
    METHOD_NOT_ALLOWED = 405,
    CONFLICT = 409,
    INTERNAL_SERVER_ERROR = 500,
    BAD_GATEWAY = 502,
    SERVICE_UNAVAILABLE = 503
}

// ── ResponseEntity ───────────────────────────────────────────
// Immutable response object. Use builder methods (chaining via new instances).
//
// Usage:
//   return ResponseEntity.ok("{\"users\": []}")
//   return ResponseEntity.created("{\"id\": 1}")
//   return ResponseEntity.status(HttpStatus.NOT_FOUND).body("{\"error\": \"not found\"}")
//   return ResponseEntity.badRequest().body("{\"error\": \"invalid\"}")

class ResponseEntity(statusCode: int, contentType: string, responseBody: string) {
    function body(data: string): ResponseEntity {
        return new ResponseEntity(this.statusCode, this.contentType, data)
    }

    function contentType(ct: string): ResponseEntity {
        return new ResponseEntity(this.statusCode, ct, this.responseBody)
    }

    function build(): string {
        return httpResponse(this.statusCode, this.contentType, this.responseBody)
    }
}

// ── Static factory methods (like ResponseEntity.ok()) ────────

function ResponseEntity_ok(body: string): ResponseEntity {
    return new ResponseEntity(HttpStatus.OK, "application/json", body)
}

function ResponseEntity_created(body: string): ResponseEntity {
    return new ResponseEntity(HttpStatus.CREATED, "application/json", body)
}

function ResponseEntity_noContent(): ResponseEntity {
    return new ResponseEntity(HttpStatus.NO_CONTENT, "text/plain", "")
}

function ResponseEntity_badRequest(): ResponseEntity {
    return new ResponseEntity(HttpStatus.BAD_REQUEST, "application/json", "")
}

function ResponseEntity_notFound(): ResponseEntity {
    return new ResponseEntity(HttpStatus.NOT_FOUND, "application/json", "")
}

function ResponseEntity_status(code: int): ResponseEntity {
    return new ResponseEntity(code, "application/json", "")
}

function ResponseEntity_redirect(url: string): string {
    let resp = "HTTP/1.1 302 Found\r\n"
    resp = `${resp}Location: ${url}\r\n`
    resp = `${resp}Content-Length: 0\r\n`
    resp = `${resp}Connection: close\r\n\r\n`
    return resp
}
