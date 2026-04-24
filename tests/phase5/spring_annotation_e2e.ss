// D127 §B I009 — 端到端集成:真 Spring Boot 风格 @RequestMapping 五值类型
// 同时存在于一个 annotation 的 args,验证 evalAnnotationArg 跨 kind 分派时
// 共享的 interpClasses / enumValues / classNodeIds 全局状态互不污染(I001-
// I006 单测逐 kind 独立 Done,混合场景是新增证据)。五 kind 覆盖:STRING_LIT
// (path) / MEMBER_ACCESS enum(method) / ARRAY_LIT(headers) / IDENT 裸类名
// (handler) / INT_LIT(order)。D123 Phase 1 前置 gate(I009 §备注)。

import { assertEqual } from "@/lib/test"

enum HttpMethod { GET, POST }
class JsonHandler {}

@RequestMapping(
    path = "/api/users",
    method = HttpMethod.GET,
    headers = ["Accept=application/json"],
    handler = JsonHandler,
    order = 10
)
class UserController {}

function main() {
    test("I009 — STRING path 读回", () => {
        const v = comptime {
            let t = ""
            for (a in UserController.annotations) {
                if (a.args.has("path") == 1) { t = a.args.getString("path") }
            }
            return t
        }
        assertEqual(v, "/api/users")
    })

    test("I009 — MEMBER_ACCESS enum method 读回", () => {
        const v = comptime {
            let t = ""
            for (a in UserController.annotations) {
                if (a.args.has("method") == 1) { t = a.args.getString("method") }
            }
            return t
        }
        assertEqual(v, "GET")
    })

    test("I009 — ARRAY_LIT headers[0] 读回", () => {
        const v = comptime {
            let t = ""
            for (a in UserController.annotations) {
                if (a.args.has("headers") == 1) {
                    const arr = a.args.getArray("headers")
                    t = arr[0]
                }
            }
            return t
        }
        assertEqual(v, "Accept=application/json")
    })

    test("I009 — IDENT handler 类名读回", () => {
        const v = comptime {
            let t = ""
            for (a in UserController.annotations) {
                if (a.args.has("handler") == 1) { t = a.args.getString("handler") }
            }
            return t
        }
        assertEqual(v, "JsonHandler")
    })

    test("I009 — INT_LIT order 读回", () => {
        const v = comptime {
            let t = 0
            for (a in UserController.annotations) {
                if (a.args.has("order") == 1) { t = a.args.getInt("order") }
            }
            return t
        }
        assertEqual(v, 10)
    })

    test("I009 — 五 key 存在性 + 未声明 key 缺失(独立变量累加)", () => {
        const passed = comptime {
            let pathPresent = 0
            let methodPresent = 0
            let headersPresent = 0
            let handlerPresent = 0
            let orderPresent = 0
            let bogusAbsent = 0
            for (a in UserController.annotations) {
                if (a.args.has("path") == 1) { pathPresent = 1 }
                if (a.args.has("method") == 1) { methodPresent = 1 }
                if (a.args.has("headers") == 1) { headersPresent = 1 }
                if (a.args.has("handler") == 1) { handlerPresent = 1 }
                if (a.args.has("order") == 1) { orderPresent = 1 }
                if (a.args.has("nonexistent") == 0) { bogusAbsent = 1 }
            }
            return pathPresent + methodPresent + headersPresent + handlerPresent + orderPresent + bogusAbsent
        }
        // 6 = 5 期望存在 key 全命中 + 1 期望缺失 key 确认缺失;任一失败总和 < 6,
        // 差值对应"哪几项失败",每个子项有独立命名变量方便 diff-bisect
        assertEqual(passed, 6)
    })
}
