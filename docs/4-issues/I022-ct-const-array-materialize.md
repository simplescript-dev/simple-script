# I022 — ct const Array<T> materialize 漏 push 第 2/3 元素(runComptimeBlockBody RETURN flag leak)

**父决策:** D128 §A.1/A.2 顶级 ctArray 全局 scope `:_ssRoutes` / I014 §路径 A ct-array unroll
**状态:** Done at `bootstrap/gen/stmts/stmts_core.ss:67-72` + `bootstrap/gen/stmts/stmts_loop_forin.ss:115` + `bootstrap/gen/stmts/stmts_loop_forin.ss:130` + `bootstrap/gen/gen_types.ss:260-263`(2026-04-25 修)
**颗粒度:** 14 LOC(3 文件 codegen 改);0 test(I022 是 I021bc 实施前置阻塞,GREEN 由 I021bc 端到端测覆盖 — `tests/phase5/i021bc_*.ss` multi-method @GetMapping 路由全 dispatch)
**依赖:** 无(根因独立)
**创建:** 2026-04-25
**立项由:** I021bc Execute 实施轮 RED 探测发现 — 加 V=int / V=double 路由后 multi-method 反射只 dispatch 第一条,核 IR 发现 ct const `Array<UserClass>` 在 ct → runtime materialize 时 storage 只装第一个元素;最小复现 `const A: Array<int> = comptime { let arr = []; arr = arr.push(10); arr = arr.push(20); arr = arr.push(30); return arr }` → for-in 只输出 `10`;`A.length() = 3` 但 IR 里 `@.str.*` 只 emit "/a" 不 emit "/b" "/c"。**为什么 I021 v0(V=string `/hello`)偶然 work**:hello 是 _ssRoutes 第一条,正好被唯一 materialize 的元素覆盖

---

## 问题

ct const `Array<*>` push 多次后 length 字段 ct 计算正确(返 3),但 runtime for-in only 跑第一次 iter 即 break。可观测 RED 证据(2026-04-25 实测):

```ss
const A: Array<int> = comptime {
    let arr: Array<int> = []
    arr = arr.push(10); arr = arr.push(20); arr = arr.push(30)
    return arr
}
function main() {
    println("len=" + A.length())  // → "len=3" ✅
    for (n in A) { println(n) }   // → "10" 仅一行 ❌(预期 10 / 20 / 30)
}
```

更严重的下游:`const C: Array<int> = [100, 200, 300]`(top-level literal,**不是 comptime block**)在前面 ct const A/B 为相邻声明时,for-in body 内的 IDENT n 表达式被错误 ct 化为前一个 ct const 的最后元素值(`30 30 30` 而非 `100 200 300`)。

---

## 单一根因

**`runComptimeBlockBody` 出口不 reset `interpReturnFlag/Val/Break/Continue` flag**,ct block `return arr` 的 RETURN flag (=1) leak 到下游 codegen 路径;ct-array unroll for-in (`bootstrap/gen/stmts/stmts_loop_forin.ss:91-115`)的 `interpCheckLoopExit() == 1` 在第一次 iter 后误判 break,只 emit 一次 IR(用第一个元素的 ct value)。

DEBUG 反事实证据(`emitIR ; DEBUG_FORIN_*` 加调试后实测):
```
; DEBUG_FORIN_ENTER ctArrId=1 ctArrLen=3 cf=main item=n
; DEBUG_FORIN_ITER ctFi=0 elem=2 terminated=0 brk=0 ret=1   ← interpReturnFlag=1 entry
; DEBUG_FORIN_AFTER_BLOCK ctFi=0 terminated=0 brk=0 ret=1
; DEBUG_FORIN_EXIT finalCtFi=0 ctArrLen=3                    ← 只跑 1 iter,break
```

第二根因(同源):**ct unroll 出口不 clean ctVars[`${currentFunc}:${itemName}`]**,leak 到下游同名 runtime for-in body 的 IDENT 解析(走 evalIdent ctVars 命中,被 ct 化为残留 ct val,而非走 runtime genIdent)。这是为什么 top-level literal `const C` 的 for-in 体内 n 表达式被 hardcode 为前一个 ct const 的最后值。

---

## 修复(单根因双修复点;Done at 2026-04-25)

| Touch point | 文件:行 | 改动 |
|---|---|---|
| 注册端 — runComptimeBlockBody exit reset | `bootstrap/gen/stmts/stmts_core.ss:67-72` | 出口 saved retVal,reset interpReturnFlag/Val/Break/Continue;改返 retVal: int(原 void)。ct block RETURN flag 不再 leak |
| 消费端 — caller 用返回值替代全局读 | `bootstrap/gen/gen_types.ss:260-263` | COMPTIME_EXPR 处理改 `const ceRetVal = runComptimeBlockBody(...)`,删旧 `const ceRetFlag = interpReturnFlag` 等 4 行,if 条件改 `ceRetVal > 0`。其他 4 caller (stmts.ss/class.ss/class_annotation.ss × 2) 不读 retVal,接口兼容 |
| ct-array/map unroll itemName 清理 | `bootstrap/gen/stmts/stmts_loop_forin.ss:115/130` | ct unroll 出口加 `ctVars.delete(${currentFunc}:${itemName})`;array + map 路径对称 |

---

## 验收(已 PASS)

```bash
# 最小复现 GREEN
cat > /tmp/probe_ct_const_arr.ss << 'EOF'
class R { p: string }
const ROUTES: Array<R> = comptime {
    let arr: Array<R> = []
    arr = arr.push(new R(p: "/a"))
    arr = arr.push(new R(p: "/b"))
    arr = arr.push(new R(p: "/c"))
    return arr
}
function main() {
    println("len=" + ROUTES.length())
    for (r in ROUTES) { println(r.p) }
}
EOF
bin/ss build /tmp/probe_ct_const_arr.ss -o /tmp/probe && /tmp/probe
# before: len=3 / /a (仅一行)
# after:  len=3 / /a / /b / /c ✅

# top-level literal n leak 修复
const C: Array<int> = [100, 200, 300]    # before: 30 30 30 / after: 100 200 300 ✅

# multi-method @GetMapping 反射 unroll
# examples/spring-parity/hello/ss/HelloController.ss + 加 /age + /calc 路由
# before: Routes: /hello|HelloController.hello;  (单条)
# after:  Routes: /hello|HelloController.hello;/age|HelloController.age;/calc|HelloController.calc; ✅

./build.sh bootstrap   # Stage 2 = Stage 3 固定点 ✅
```

---

## 备注

- **本 issue 由 I021bc Execute RED 探测意外发现**:I021bc 立项假设 V=int / V=double silent miscompile(`Hello, -591256928!` 类型),但 RED 实测看到 `not found`(404) — 真根因更深 = ct const Array materialize。修完 I022 后 I021bc 假设的 silent miscompile 才真正可观测(`n=-1116582928` 类型),I021bc 实施轮可继续(funcParamTypes 注册补 + invoke sentinel cast emit 双修复点)
- **§Root Cause 第一法则**:本 issue 单根因(runComptimeBlockBody 出口 flag leak)对应两个修复点(reset flag + delete itemName ctVar),反事实证(任一修不全则两类 leak 仍存)成立 — 同根因双 touch point,符合 (b) 大重构原则
- **scope 不扩**:不动 funcParamTypes / invoke sentinel(I021bc 范围)
