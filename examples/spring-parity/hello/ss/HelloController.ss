// D123 Phase 2 — @RestController + @GetMapping(path = "/hello") 单端点
//
// Java oracle: examples/spring-parity/hello/java/src/main/java/hello/HelloController.java
// 期望 parity:curl http://localhost:8080/hello → body == "Hello, World!" 与 Java 端 byte-identical
//
// 注解形态:D127 §A.3 ASSIGN 单形(`path = "/hello"`),与 Java `@GetMapping("/hello")`
// 通过 args.getString("path") comptime 读出语义对齐(parity 看 HTTP payload byte 级,
// 不看源码字面;Java oracle 用单位置参,SS 端 path 走 ASSIGN 命名参均 OK)。

@RestController
class HelloController {
    @GetMapping(path = "/hello")
    function hello(): string {
        return "Hello, World!"
    }
}
