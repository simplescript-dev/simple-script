// D123 Phase 4 — @RestController + @GetMapping(path = "/hello") + @RequestParam 单 string 入参
//
// Java oracle: examples/spring-parity/hello/java/src/main/java/hello/HelloController.java
// 期望 parity:curl "http://localhost:8080/hello?name=SS" → body == "Hello, SS!"(byte-identical Java)
//
// 注解形态:D127 §A.3 ASSIGN 单形(`path = "/hello"` / `name = "name"`),与 Java
// `@GetMapping("/hello")` + `@RequestParam("name")` 通过 args.getString 语义对齐(parity 看 byte)。
//
// I014 §路径 A + I018 §路径 A + I021 §路径 A:dispatcher 按 paramSpecs 静态展开为
// `call ptr @HelloController_hello(ptr null, ptr %<ss_mapGetString ret>)`,
// 形参签名字面对齐 Java `@RequestParam(name = "name") String name`,不再手 unpack req map。

@RestController
class HelloController {
    @GetMapping(path = "/hello")
    function hello(@RequestParam(name = "name") name: string): string {
        return "Hello, " + name + "!"
    }
}
