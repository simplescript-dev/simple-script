import { SpringApplication, Get } from "@/lib/spring/boot"
import { HttpServletRequest, HttpServletResponse, createServletRequest, createServletResponse } from "@/lib/jakarta/servlet"

// ── Beans ───────────────────────────────────────────────────

@Service
class GreetingService {
    function greet(name: string): string {
        return `Hello, ${name}!`
    }
}

@Service
class UserService {
    greetingService: GreetingService

    function welcome(name: string): string {
        return this.greetingService.greet(name)
    }
}

// ── Controller with DI ──────────────────────────────────────

@RestController
@RequestMapping("/api")
class GreetingController {
    userService: UserService
    statusService: StatusService

    @GetMapping("/greet/{name}")
    function greet(@PathVariable name: string, request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
        const msg = this.userService.welcome(name)
        return response.write(`{"message":"${msg}"}`)
    }

    @GetMapping("/status")
    function status(request: HttpServletRequest, response: HttpServletResponse): HttpServletResponse {
        return response.write(this.statusService.checkReady())
    }
}

// ── Bean with @PostConstruct ────────────────────────────────

@Service
class ConfigService {
    status: string = "uninitialized"

    @PostConstruct
    function init() {
        this.status = "ready"
    }

    function getStatus(): string {
        return this.status
    }
}

// Service that depends on ConfigService — verifies PostConstruct ran
@Service
class StatusService {
    configService: ConfigService

    function checkReady(): string {
        return this.configService.getStatus()
    }
}

// ── Application entry point ─────────────────────────────────

@SpringBootApplication
class Application {}

// ── Test via direct dispatch ────────────────────────────────

function main() {
    // Register routes (triggered by annotation codegen)
    // Test by calling dispatcherServlet directly
    const headers = new Map()
    headers.set("method", "GET")
    headers.set("path", "/api/greet/Alice")
    const req = new HttpServletRequest(headers, new Map())
    const resp = new HttpServletResponse(200, "application/json", "", new Map())

    // Import dispatcherServlet from boot
    const result = dispatcherServlet(req, resp)
    const body = result.body

    if (body != "{\"message\":\"Hello, Alice!\"}") {
        println("FAIL: expected {\"message\":\"Hello, Alice!\"}, got: " + body)
        exit(1)
    }

    println("PASS: Spring DI injection works")

    // Test @PostConstruct: ConfigService.init() should have set status="ready"
    const statusHeaders = new Map()
    statusHeaders.set("method", "GET")
    statusHeaders.set("path", "/api/status")
    const statusReq = new HttpServletRequest(statusHeaders, new Map())
    const statusResp = new HttpServletResponse(200, "text/plain", "", new Map())
    const statusResult = dispatcherServlet(statusReq, statusResp)
    if (statusResult.body != "ready") {
        println("FAIL: @PostConstruct not called, expected 'ready', got: " + statusResult.body)
        exit(1)
    }
    println("PASS: @PostConstruct called after bean construction")
}
