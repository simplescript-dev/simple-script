// D123 Phase 1 — @SpringBootApplication comptime 入口骨架
//
// comptime block 内 reflect.classes() 枚举编译单元所有 class,过滤 @RestController
// 注解,收集 className CSV(Phase 1 scope:只扫,不 dispatch)。Phase 2 将基于
// 此扫描再展开 @GetMapping 路由表 + runtime dispatcher(见 D123 §3 Phase 2)。
//
// 根因路径:D088 §第一性需求 + D120 reflect.classes() + D127 annotation value types。
// 禁 runtime 反射 / @comptimeEmit 字符串拼接 / @derive 替代(D088 §反模式 L377-386)。

// Phase 2+ consumer 占位:comptime 扫到的 controller 名 + method 列表 + @GetMapping
// 参数将 materialize 为 RouteMeta 常量段,Phase 1 仅保留类 shape。
class ControllerMeta {
    className: string
}

class SpringApplication {
    static function run(appName: string, args: Array<string>) {
        const controllerNames = comptime {
            let acc = ""
            for (c in reflect.classes()) {
                for (ann in c.annotations) {
                    if (ann.name == "RestController") {
                        if (acc != "") { acc = acc + "," }
                        acc = acc + c.name
                    }
                }
            }
            return acc
        }

        println("Started " + appName)
        let count = 0
        if (controllerNames != "") {
            count = controllerNames.split(",").length()
        }
        if (count == 0) {
            println("Controllers: 0")
        } else {
            println("Controllers: " + count + " [" + controllerNames + "]")
        }
    }
}
