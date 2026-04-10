// SimpleScript Spring Boot — Application Bootstrap
// Route matching aligned with Spring Boot 4.0 PathPatternParser behavior
// - {var} captures one path segment
// - {*var} captures remaining segments (tail, end-only)
// - * matches one segment (no capture)
// - /** matches remaining segments (no capture, end-only)
// - No automatic trailing-slash matching (Spring Boot 4.0 removed this)

// ── Imports ──────────────────────────────────────────────────

import { HttpServletRequest, HttpServletResponse, createServletResponse } from "@/lib/jakarta/servlet"
import { Tomcat, createTomcat } from "@/lib/tomcat/embed"
import { httpNotFound } from "@/lib/http"

// ── Annotation handler ───────────────────────────────────────
// Single handler for all Spring Boot annotations.
// Class annotations (methodName==""): factory fn creates cached singleton.
// Method annotations: wrapper fn has (request, response)->response signature.

let controllerBasePaths = new Map()

function springAnnotationHandler(annName: string, className: string, methodName: string, annArg: string, fnPtr: fn): string {
    if (methodName == "") {
        // Class-level annotation
        if (annName == "RequestMapping") {
            controllerBasePaths.set(className, annArg)
            return ""
        }
        if (annName == "Component" || annName == "Service" || annName == "Repository" || annName == "RestController") {
            fnPtr()
        }
        return ""
    }
    // Method-level annotation
    if (annName == "PostConstruct") {
        fnPtr("", "")
        return ""
    }
    // Route annotations
    let fullPath = annArg
    if (controllerBasePaths.has(className) == 1) {
        fullPath = `${controllerBasePaths.getString(className)}${annArg}`
    }
    if (annName == "GetMapping") { registerRoute("GET", fullPath, fnPtr) }
    if (annName == "PostMapping") { registerRoute("POST", fullPath, fnPtr) }
    if (annName == "PutMapping") { registerRoute("PUT", fullPath, fnPtr) }
    if (annName == "DeleteMapping") { registerRoute("DELETE", fullPath, fnPtr) }
    if (annName == "PatchMapping") { registerRoute("PATCH", fullPath, fnPtr) }
    return ""
}

// Register Spring Boot annotations with the compiler's annotation dispatch
annotationMapping("Component", springAnnotationHandler)
annotationMapping("Service", springAnnotationHandler)
annotationMapping("Repository", springAnnotationHandler)
annotationMapping("SpringBootApplication", springAnnotationHandler)
annotationMapping("RestController", springAnnotationHandler)
annotationMapping("RequestMapping", springAnnotationHandler)
annotationMapping("PostConstruct", springAnnotationHandler)
annotationMapping("GetMapping", springAnnotationHandler)
annotationMapping("PostMapping", springAnnotationHandler)
annotationMapping("PutMapping", springAnnotationHandler)
annotationMapping("DeleteMapping", springAnnotationHandler)
annotationMapping("PatchMapping", springAnnotationHandler)

// ── Route registry ───────────────────────────────────────────

// Each route: { method, pattern (original string), segments (parsed), handler }
// Segment types: "L:xxx" literal, "C:xxx" capture {xxx}, "W" wildcard *, "T:xxx" tail {*xxx}, "T:" tail /**
let routeMethods: Array<string> = []
let routePatterns: Array<string> = []
let routeSegments: Array<string> = []
let routeHandlers: Array<fn> = []
let routeCount = 0

// Parse pattern string into "|"-separated segment descriptors
function parsePattern(pattern: string): string {
    let result = ""
    let path = pattern
    // Strip leading /
    if (path.startsWith("/") == 1) {
        path = path.substring(1, path.length() - 1)
    }
    if (path == "") { return "" }
    // Split by /
    const parts = path.split("/")
    let i = 0
    while (i < parts.length()) {
        const seg = parts[i]
        let desc = ""
        if (seg == "**") {
            // /** tail match (must be last segment)
            desc = "T:"
        } else if (seg.startsWith("{*") == 1 && seg.endsWith("}") == 1) {
            // {*varName} tail capture
            const varName = seg.substring(2, seg.length() - 3)
            desc = `T:${varName}`
        } else if (seg.startsWith("{") == 1 && seg.endsWith("}") == 1) {
            // {varName} single-segment capture
            const varName = seg.substring(1, seg.length() - 2)
            desc = `C:${varName}`
        } else if (seg == "*") {
            // * single-segment wildcard
            desc = "W"
        } else {
            // Literal segment
            desc = `L:${seg}`
        }
        if (result == "") { result = desc } else { result = `${result}|${desc}` }
        i = i + 1
    }
    return result
}

function registerRoute(method: string, pattern: string, handler: fn) {
    const segs = parsePattern(pattern)
    routeMethods = routeMethods.push(method)
    routePatterns = routePatterns.push(pattern)
    routeSegments = routeSegments.push(segs)
    routeHandlers = routeHandlers.push(handler)
    routeCount = routeCount + 1
}

function Get(path: string, handler: fn) { registerRoute("GET", path, handler) }
function Post(path: string, handler: fn) { registerRoute("POST", path, handler) }
function Put(path: string, handler: fn) { registerRoute("PUT", path, handler) }
function Delete(path: string, handler: fn) { registerRoute("DELETE", path, handler) }
function Patch(path: string, handler: fn) { registerRoute("PATCH", path, handler) }

// ── Pattern matching ────────────────────────────────────────

// Match parsed segments against path segments. Returns 1 if match, 0 if not.
// Captured variables are stored in the captures Map.
function matchSegments(segStr: string, pathParts: Array<string>, captures: Map<string, string>): int {
    if (segStr == "") {
        // Pattern "/" matches only empty path
        return pathParts.length() == 0 ? 1 : 0
    }
    const segs = segStr.split("|")
    let si = 0
    let pi = 0
    while (si < segs.length()) {
        const seg = segs[si]
        if (seg.startsWith("T:") == 1) {
            // Tail: consumes all remaining path segments
            const varName = seg.substring(2, seg.length() - 2)
            if (varName != "") {
                // {*varName} — capture remaining as joined path
                let tail = ""
                while (pi < pathParts.length()) {
                    if (tail == "") { tail = pathParts[pi] } else { tail = `${tail}/${pathParts[pi]}` }
                    pi = pi + 1
                }
                captures.set(varName, tail)
            } else {
                // /** — just consume everything
                pi = pathParts.length()
            }
            return 1
        }
        // Non-tail segments require a path segment to exist
        if (pi >= pathParts.length()) { return 0 }
        const part = pathParts[pi]
        if (seg == "W") {
            // * — match any single segment
            pi = pi + 1
        } else if (seg.startsWith("C:") == 1) {
            // {var} — capture single segment
            const varName = seg.substring(2, seg.length() - 2)
            captures.set(varName, part)
            pi = pi + 1
        } else if (seg.startsWith("L:") == 1) {
            // Literal — exact match
            const literal = seg.substring(2, seg.length() - 2)
            if (part != literal) { return 0 }
            pi = pi + 1
        } else {
            return 0
        }
        si = si + 1
    }
    // All segments consumed — path must also be fully consumed
    return pi == pathParts.length() ? 1 : 0
}

// ── Pattern specificity (PathPatternParser compareTo) ────────
// Lower score = more specific = higher priority
// Score per segment: literal=0, capture=1, wildcard=2, tail=3
// Compare: total score first, then fewer segments wins, then pattern string

function patternScore(segStr: string): int {
    if (segStr == "") { return 0 }
    const segs = segStr.split("|")
    let score = 0
    let i = 0
    while (i < segs.length()) {
        const seg = segs[i]
        if (seg.startsWith("L:") == 1) {
            score = score + 0
        } else if (seg.startsWith("C:") == 1) {
            score = score + 10
        } else if (seg == "W") {
            score = score + 20
        } else if (seg.startsWith("T:") == 1) {
            score = score + 100
        }
        i = i + 1
    }
    return score
}

function segmentCount(segStr: string): int {
    if (segStr == "") { return 0 }
    return segStr.split("|").length()
}

// ── DispatcherServlet ────────────────────────────────────────

function dispatcherServlet(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
    const method = request.getMethod()
    const path = request.getRequestURI()

    // Split path into segments
    let pathStr = path
    if (pathStr.startsWith("/") == 1) {
        pathStr = pathStr.substring(1, pathStr.length() - 1)
    }
    let pathParts: Array<string> = []
    if (pathStr != "") {
        pathParts = pathStr.split("/")
    }

    // Find best matching route (lowest score = most specific)
    let bestIdx = -1
    let bestScore = 999999
    let bestSegCount = 999999
    let bestCaptures = new Map()

    let i = 0
    while (i < routeCount) {
        if (routeMethods[i] == method) {
            const captures = new Map()
            if (matchSegments(routeSegments[i], pathParts, captures) == 1) {
                const score = patternScore(routeSegments[i])
                const sc = segmentCount(routeSegments[i])
                if (score < bestScore || (score == bestScore && sc > bestSegCount)) {
                    bestScore = score
                    bestSegCount = sc
                    bestIdx = i
                    bestCaptures = captures
                }
            }
        }
        i = i + 1
    }

    if (bestIdx >= 0) {
        // Store captured path variables as request attributes
        const keys = bestCaptures.keys()
        let ki = 0
        while (ki < keys.length()) {
            request.setAttribute(keys[ki], bestCaptures.getString(keys[ki]))
            ki = ki + 1
        }
        const handler = routeHandlers[bestIdx]
        return handler(request, response)
    }

    return response.sendError(404, `Cannot ${method} ${path}`)
}

// ── SpringApplication ────────────────────────────────────────

class SpringApplication {
    function run(port: int) {
        println("")
        println("  .   ____          _            __ _ _")
        println(" /\\\\ / ___'_ __ _ _(_)_ __  __ _ \\ \\ \\ \\")
        println("( ( )\\___ | '_ | '_| | '_ \\/ _` | \\ \\ \\ \\")
        println(" \\\\/  ___)| |_)| | | | |_) | (_| |  ) ) ) )")
        println("  '  |____| .__|_| |_|_| |_\\__, | / / / /")
        println(" =========|_|==============|___/=/_/_/_/")
        println("")
        println(`  SimpleScript Spring Boot v0.2.0`)
        println(`  Powered by Tomcat Embedded`)
        println(`  ${routeCount} route(s) registered`)
        println("")

        const tomcat = createTomcat().setPort(port)
        tomcat.start(dispatcherServlet)
    }
}
