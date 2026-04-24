// D123 Phase 3 Step 1 — @RestController + @GetMapping(path = "/hello") 单端点 + req map 参数绑定
//
// Java oracle: examples/spring-parity/hello/java/src/main/java/hello/HelloController.java
// 期望 parity:curl "http://localhost:8080/hello?name=SS" → body == "Hello, SS!"(byte-identical Java)
//
// 注解形态:D127 §A.3 ASSIGN 单形(`path = "/hello"`),与 Java `@GetMapping("/hello")`
// 通过 args.getString("path") comptime 读出语义对齐(parity 看 HTTP payload byte 级)。
//
// I014 §路径 A + I018 §路径 A:hello instance 形态对齐 Java,dispatcher emit
// `call ptr @HelloController_hello(ptr null, ptr %req)` 透 runtime req map。
// I019 §路径:typed Map<string,string>.get inferType 直接返 string, codegen 路由 ss_mapGetString,
// 用户写法 `req.get("name")` 字面对齐 Java(消除 I018 §风险 §下轮升根路径 getString 表面绕过)。

@RestController
class HelloController {
    @GetMapping(path = "/hello")
    function hello(req: Map<string, string>): string {
        return "Hello, " + req.get("name") + "!"
    }
}
