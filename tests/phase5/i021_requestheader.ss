// I021-requestheader — @RequestHeader HTTP header → 形参绑参端到端测试
// 验 lib/http.ss parseRequest 头入 req __hdr_ prefix 隔离 namespace + comptime _ssRoutes
// RequestHeader 分支(name lowercase normalize)+ invoke sentinel kind == "RequestHeader"
// emit ss_mapGetString(req, "__hdr_<lower-name>") 复用 RequestParam/PathVariable cast
// 通道(int/double/ptr 分派);消除 dispatcher 字面 lookup query/header 同 namespace 撞 key
// + comptime 无 RequestHeader 分支 silent miscompile 双根因。
//
// fix at: lib/http.ss:78 __hdr_ prefix
//       + lib/spring/boot/application.ss PARAM_KIND_REQUEST_HEADER + comptime RequestHeader 分支
//       + bootstrap/eval/method_call.ss:135 §useParamSpecs RequestHeader kind 共享分支 + lookupKey if-elseif 链
//
// Coverage:
//   ① 单 header string — User-Agent → ua: string(主用例,RED 由 silent miscompile 垃圾内存 → "ua=SimpleScript/1.0" 翻 GREEN)
//   ② typed cast int — X-Count → count: int(复用 I021bc cast 通道,ss_parseInt + i32)
//   ③ typed cast double — X-Score → score: double(ss_parseDouble + double)
//   ④ 多 header 共 endpoint — Authorization + X-Request-Id 双形参独立 __hdr_authorization / __hdr_x-request-id namespace
//   ⑤ 大小写不敏感(comptime 单边) — SS `@RequestHeader("USER-AGENT")` 大写 + comptime lowercase normalize 命中 __hdr_user-agent 小写
//   ⑥ 全链路 raw HTTP — parseRequest 真喂 `USER-AGENT: ...\r\n` raw → lib/http.ss:76 lowercase + line 80 __hdr_ prefix
//      + comptime lowercase + sentinel __hdr_<lower-name> 四点对齐;case ⑤ 只验 comptime 一半,⑥ 验整链路
//   ⑦ 静态 IR 锚 — shell-level grep `ss_mapGetString.*__hdr_user-agent` ≥ 1 由 VCM §2 行为验
//
// 本文件承载 ①②③④⑤⑥,⑦ 由 shell-level grep 验证(MNK §VCM §2)。

import { assertEqual } from "@/lib/test"
import { dispatch, dispatchBody } from "@/lib/spring/boot/application"
import { parseRequest } from "@/lib/http"

@RestController
class HdrCtl {
    @GetMapping(path = "/agent")
    function agent(@RequestHeader(name = "user-agent") ua: string): string {
        return "ua=" + ua
    }

    @GetMapping(path = "/count")
    function count(@RequestHeader(name = "x-count") count: int): string {
        return "count=" + count
    }

    @GetMapping(path = "/score")
    function score(@RequestHeader(name = "x-score") score: double): string {
        return "score=" + score
    }

    @GetMapping(path = "/auth")
    function auth(@RequestHeader(name = "authorization") tok: string, @RequestHeader(name = "x-request-id") rid: string): string {
        return "tok=" + tok + ",rid=" + rid
    }

    @GetMapping(path = "/upper")
    function upper(@RequestHeader(name = "USER-AGENT") ua: string): string {
        return "ua=" + ua
    }
}

function main() {
    test("I021-requestheader 单 header string — User-Agent → ua: string GREEN", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/agent")
        req.set("__hdr_user-agent", "SimpleScript/1.0")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "ua=SimpleScript/1.0")
    })

    test("I021-requestheader typed cast int — X-Count → count: int 复用 I021bc cast 通道", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/count")
        req.set("__hdr_x-count", "42")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "count=42")
    })

    test("I021-requestheader typed cast double — X-Score → score: double", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/score")
        req.set("__hdr_x-score", "3.14")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "score=3.14")
    })

    test("I021-requestheader 多 header 共 endpoint — Authorization + X-Request-Id 双形参独立 namespace", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/auth")
        req.set("__hdr_authorization", "Bearer xyz")
        req.set("__hdr_x-request-id", "req-7")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "tok=Bearer xyz,rid=req-7")
    })

    test("I021-requestheader 大小写不敏感 — SS 写 USER-AGENT comptime lowercase 命中 __hdr_user-agent", () => {
        let req: Map<string, string> = new Map()
        req.set("method", "GET")
        req.set("path", "/upper")
        req.set("__hdr_user-agent", "SimpleScript/2.0")
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "ua=SimpleScript/2.0")
    })

    test("I021-requestheader 全链路 raw HTTP — parseRequest USER-AGENT raw → __hdr_user-agent 整链路对齐", () => {
        const raw = "GET /upper HTTP/1.1\r\nUSER-AGENT: SimpleScript/3.0\r\n\r\n"
        const req = parseRequest(raw)
        const body = dispatchBody(dispatch(req))
        assertEqual(body, "ua=SimpleScript/3.0")
    })
}
