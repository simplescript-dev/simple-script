import { SpringApplication } from "@/lib/spring/boot"
import { HttpServletRequest, HttpServletResponse } from "@/lib/jakarta/servlet"

// ── Service ────────────────────────────────────────────────

@Service
class EchoService {
    function echo(msg: string): string {
        return msg
    }
}

// ── Controller testing @RequestParam, @RequestHeader, @RequestBody ──

@RestController
@RequestMapping("/api")
class TestController {
    echoService: EchoService

    @GetMapping("/search")
    function search(@RequestParam keyword: string, @RequestParam page: string, request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
        return response.write(`keyword=${keyword},page=${page}`)
    }

    @GetMapping("/agent")
    function agent(@RequestHeader userAgent: string, request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
        return response.write(`ua=${userAgent}`)
    }

    @PostMapping("/echo")
    function echo(@RequestBody body: string, request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
        return response.write(this.echoService.echo(body))
    }

    @PostMapping("/full")
    function full(@RequestBody body: string, @RequestHeader contentType: string, request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
        return response.write(`type=${contentType},body=${body}`)
    }
}

@SpringBootApplication
class Application {}

// ── Tests ──────────────────────────────────────────────────

function main() {
    // Test 1: @RequestParam
    const h1 = new Map()
    h1.set("method", "GET")
    h1.set("path", "/api/search")
    h1.set("query", "keyword=hello&page=2")
    const req1 = new HttpServletRequest(h1, new Map())
    const resp1 = new HttpServletResponse(200, "text/plain", "", new Map())
    const r1 = dispatcherServlet(req1, resp1)
    if (r1.body != "keyword=hello,page=2") {
        println("FAIL @RequestParam: expected 'keyword=hello,page=2', got: " + r1.body)
        exit(1)
    }
    println("PASS: @RequestParam extracts query parameters")

    // Test 2: @RequestHeader
    const h2 = new Map()
    h2.set("method", "GET")
    h2.set("path", "/api/agent")
    h2.set("useragent", "SimpleScript/1.0")
    const req2 = new HttpServletRequest(h2, new Map())
    const resp2 = new HttpServletResponse(200, "text/plain", "", new Map())
    const r2 = dispatcherServlet(req2, resp2)
    if (r2.body != "ua=SimpleScript/1.0") {
        println("FAIL @RequestHeader: expected 'ua=SimpleScript/1.0', got: " + r2.body)
        exit(1)
    }
    println("PASS: @RequestHeader extracts HTTP headers")

    // Test 3: @RequestBody
    const h3 = new Map()
    h3.set("method", "POST")
    h3.set("path", "/api/echo")
    h3.set("body", "{\"name\":\"Alice\"}")
    const req3 = new HttpServletRequest(h3, new Map())
    const resp3 = new HttpServletResponse(200, "application/json", "", new Map())
    const r3 = dispatcherServlet(req3, resp3)
    if (r3.body != "{\"name\":\"Alice\"}") {
        println("FAIL @RequestBody: expected '{\"name\":\"Alice\"}', got: " + r3.body)
        exit(1)
    }
    println("PASS: @RequestBody extracts request body")

    // Test 4: @RequestBody + @RequestHeader combined
    const h4 = new Map()
    h4.set("method", "POST")
    h4.set("path", "/api/full")
    h4.set("body", "test-data")
    h4.set("contenttype", "text/plain")
    const req4 = new HttpServletRequest(h4, new Map())
    const resp4 = new HttpServletResponse(200, "text/plain", "", new Map())
    const r4 = dispatcherServlet(req4, resp4)
    if (r4.body != "type=text/plain,body=test-data") {
        println("FAIL combined: expected 'type=text/plain,body=test-data', got: " + r4.body)
        exit(1)
    }
    println("PASS: @RequestBody + @RequestHeader combined works")
}
