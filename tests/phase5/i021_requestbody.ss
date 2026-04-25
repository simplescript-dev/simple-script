// I021-requestbody — @RequestBody POST/PUT/PATCH JSON body → class 反序列化端到端测试
// 验 comptime _ssRoutes httpMethod + 5 method 识别 + RequestBody push spec /
//   dispatcher matchPath 加 httpMethod 比对 / invoke sentinel kind == "RequestBody"
//   分支 emit ss_mapGetString(req, "body") + JSON_parse + JsonNode.nodeId 取 + per-class
//   @ClassName_deserialize / codegen 自动生成 emitClassDeserializeFn(gen_type_ops.ss)
//   字段递归 jnGet*(lib/json.ss primitive helpers)
//
// fix at: lib/json.ss jnGetInt/Double/String/Bool primitive helpers
//       + lib/spring/boot/application.ss RouteMeta.httpMethod + comptime 5 method + RequestBody
//       + bootstrap/eval/method_call.ss:159 §useParamSpecs RequestBody kind 分支
//       + bootstrap/gen/gen_type_ops.ss:emitClassDeserializeFn per-class 自动生成
//
// Coverage:
//   ① 单 class 简单字段 string + int — POST /users body {"name":"alice","age":30} → user=alice,age=30(主用例)
//   ② 字段顺序乱 — JSON 字段 age 先 name 后 vs class 声明 name 先 age 后
//   ③ JSON 字段缺失 — body {"name":"bob"} 缺 age → fallback 默认值 0(v0 简化,留 I021-requestbody-validation)
//   ④ 纯 string 字段 class — Note { text: string }
//   ⑤ double 浮点字段 — Price { amount: double, currency: string }
//   ⑥ HTTP method GET vs POST 区分 — GET /users/{id} 走 show 不撞 createUser POST /users
//   ⑦ 静态 IR 锚 — `grep "@User_deserialize" main.ll` ≥ 1 由 shell-level 验
//
// 本文件承载 ①-⑥,⑦ 由 shell-level grep 验证(MNK §VCM §2)。

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"

class User {
    name: string
    age: int
}

class Note {
    text: string
}

class Price {
    amount: double
    currency: string
}

@RestController
class RbCtl {
    @PostMapping(path = "/users")
    function createUser(@RequestBody user: User): string {
        return "user=" + user.name + ",age=" + user.age
    }

    @PostMapping(path = "/notes")
    function createNote(@RequestBody note: Note): string {
        return "note:" + note.text
    }

    @PostMapping(path = "/prices")
    function createPrice(@RequestBody price: Price): string {
        return "price=" + price.amount + " " + price.currency
    }

    @GetMapping(path = "/users/{id}")
    function show(@PathVariable(name = "id") id: int): string {
        return "show:user=" + id
    }
}

function main() {
    test("I021-requestbody 主用例 — POST /users body name+age → user=alice,age=30 GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/users")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"alice\",\"age\":30}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "user=alice,age=30")
    })

    test("I021-requestbody 字段顺序乱 — JSON age 先 name 后 vs class 声明顺序无关", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/users")
        req.set("method", "POST")
        req.set("body", "{\"age\":42,\"name\":\"bob\"}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "user=bob,age=42")
    })

    test("I021-requestbody 字段缺失 — age 缺 → fallback 默认 0(v0 简化)", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/users")
        req.set("method", "POST")
        req.set("body", "{\"name\":\"charlie\"}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "user=charlie,age=0")
    })

    test("I021-requestbody 纯 string 字段 — Note { text }", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/notes")
        req.set("method", "POST")
        req.set("body", "{\"text\":\"hello world\"}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "note:hello world")
    })

    test("I021-requestbody double 字段 — Price { amount, currency }", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/prices")
        req.set("method", "POST")
        req.set("body", "{\"amount\":99.95,\"currency\":\"USD\"}")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "price=99.95 USD")
    })

    test("I021-requestbody HTTP method 区分 — GET /users/42 走 show 不撞 createUser POST /users", () => {
        let req: Map<string, string> = new Map()
        req.set("path", "/users/42")
        req.set("method", "GET")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "show:user=42")
    })
}
