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

// ── Comptime: generate singleton factory functions for beans (D087 Phase 4a) ──
// Replaces hardcoded LLVM IR factory generation in gen_annotations.ss.
// Uses @typeInfo reflection + emit() to generate the same factory pattern:
//   @__ann_cache_ClassName (global ptr null) + @__ann_factory_ClassName()

comptime {
    // Collect all bean classes across DI annotations
    let beanSet = new Map()
    let beanNames: Array<string> = []

    function collectBeans(annName: string) {
        const classes = getAnnotatedClasses(annName)
        let j = 0
        while (j < classes.length()) {
            const cn = classes[j]
            if (beanSet.has(cn) == 0) {
                beanSet.set(cn, "1")
                beanNames = beanNames.push(cn)
            }
            j = j + 1
        }
    }

    collectBeans("Component")
    collectBeans("Service")
    collectBeans("Repository")
    collectBeans("RestController")
    collectBeans("SpringBootApplication")

    // Generate singleton factory + method wrappers for each bean class
    let wrappersDone = new Map()
    let bi = 0
    while (bi < beanNames.length()) {
        const className = beanNames[bi]
        const info = getTypeInfo(className)

        // ── Factory: cached singleton @__ann_factory_ClassName ──
        emit(`@__ann_cache_${className} = internal global ptr null\n`)
        let body = `define ptr @__ann_factory_${className}() {\nentry:\n`
        body = body + `  %cached = load ptr, ptr @__ann_cache_${className}\n`
        body = body + `  %isNull = icmp eq ptr %cached, null\n`
        body = body + `  br i1 %isNull, label %create, label %done\n`
        body = body + `create:\n`

        const fields = info.fields
        let callArgs = ""
        let fi = 0
        while (fi < fields.length()) {
            const f = fields[fi]
            const fType = f.type
            let argVal = ""
            if (beanSet.has(fType) == 1) {
                body = body + `  %dep.${fi} = call ptr @__ann_factory_${fType}()\n`
                argVal = `ptr %dep.${fi}`
            } else {
                if (fType == "int" || fType == "bool") {
                    argVal = "i32 0"
                } else if (fType == "double") {
                    argVal = "double 0.0"
                } else {
                    argVal = "ptr null"
                }
            }
            if (callArgs == "") {
                callArgs = argVal
            } else {
                callArgs = callArgs + ", " + argVal
            }
            fi = fi + 1
        }

        if (callArgs == "") {
            body = body + `  %inst = call ptr @${className}_new()\n`
        } else {
            body = body + `  %inst = call ptr @${className}_new(${callArgs})\n`
        }
        body = body + `  store ptr %inst, ptr @__ann_cache_${className}\n`
        body = body + `  br label %done\n`
        body = body + `done:\n`
        body = body + `  %result = load ptr, ptr @__ann_cache_${className}\n`
        body = body + `  ret ptr %result\n}\n\n`

        emit(body)
        registerFunction(`__ann_factory_${className}`, className, 0)

        // ── Method wrappers: parameter bridging for annotated methods ──
        // Framework knowledge (HttpServletRequest/Response/PathVariable) lives here, not in compiler
        const methods = info.methods
        let wmi = 0
        while (wmi < methods.length()) {
            const wm = methods[wmi]
            if (wm.annotations.length() > 0) {
                const wrapName = `__ann_wrapper_${className}_${wm.name}`
                if (wrappersDone.has(wrapName) == 0) {
                    wrappersDone.set(wrapName, "1")
                    let wBody = `define ptr @${wrapName}(ptr %request, ptr %response) {\nentry:\n`
                    wBody = wBody + `  %inst = call ptr @__ann_factory_${className}()\n`
                    let wCallArgs = "ptr %inst"
                    let pvIdx = 0
                    const wParams = wm.params
                    let wpi = 0
                    while (wpi < wParams.length()) {
                        const wp = wParams[wpi]
                        if (wp.annotation != "") {
                            const pvRef = addStringConst(wp.name)
                            wBody = wBody + `  %pv.${pvIdx} = call ptr @HttpServletRequest_getPathVariable(ptr %request, ptr ${pvRef})\n`
                            wCallArgs = wCallArgs + `, ptr %pv.${pvIdx}`
                            pvIdx = pvIdx + 1
                        } else if (wp.type == "HttpServletRequest") {
                            wCallArgs = wCallArgs + ", ptr %request"
                        } else if (wp.type == "HttpServletResponse") {
                            wCallArgs = wCallArgs + ", ptr %response"
                        } else {
                            wCallArgs = wCallArgs + ", ptr null"
                        }
                        wpi = wpi + 1
                    }
                    wBody = wBody + `  %r = call ptr @${className}_${wm.name}(${wCallArgs})\n`
                    wBody = wBody + `  ret ptr %r\n}\n\n`
                    emit(wBody)
                    registerFunction(wrapName, "string", 2)
                }
            }
            wmi = wmi + 1
        }

        bi = bi + 1
    }
}

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
