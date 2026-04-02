// SimpleScript Spring HTTP — ResponseEntity & HttpStatus

import { httpResponse } from "@/lib/http"

// ── HttpStatus ───────────────────────────────────────────────

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
//
// Usage (Spring Boot style):
//   ResponseEntity.ok(body)
//   ResponseEntity.created(body)
//   ResponseEntity.status(HttpStatus.NOT_FOUND).body(msg).build()
//   ResponseEntity.badRequest().body(msg).build()
//   ResponseEntity.notFound().build()
//   ResponseEntity.noContent().build()

class ResponseEntity {
    statusCode: int
    contentType: string
    responseBody: string

    // Instance methods (builder chain)
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

// Static factory methods — called as ResponseEntity.ok(), ResponseEntity.created(), etc.
function ResponseEntity_ok(data: string): ResponseEntity {
    return new ResponseEntity(HttpStatus.OK, "application/json", data)
}

function ResponseEntity_created(data: string): ResponseEntity {
    return new ResponseEntity(HttpStatus.CREATED, "application/json", data)
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
