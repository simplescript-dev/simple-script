# I020a — Typed Map<K,int>.get value 类型 int-specific cast lowering (V=int 动作面)

**父决策:** I019 §v0 scope 切分说明 §留下轮 / D123 §扩容申报-I019 §留下轮
**状态:** Done at `bootstrap/gen/gen_types.ss:411 inferType METHOD_CALL Map.get V=int case` + `bootstrap/gen/gen_builtins.ss:267-274 genMapMethod V=int 分支 emit trunc i64→i32` + `tests/phase5/i020a_typed_map_get_int.ss RED→GREEN 5 PASS`(2026-04-25)
**颗粒度:** 预估 ~5-10 LOC / 实测 +24 LOC bootstrap(gen_types.ss +3 / gen_builtins.ss +20 重构 if-else→early-return + V=int 分支)+ 60 LOC test。预估失准根因:LLVM 数字寄存器必须严格按 def 顺序递增(`nextReg()` 返 `%N` 数字命名),V=int 需 r64 在前 trunc→r 在后,无法复用原 const r 预分配,被迫重构整个 if-else 为 early-return。教训:I019 §教训"naive 失败再 complex"应叠加"先 grep `nextReg()` 调用顺序约束"前置 audit。
**依赖:** I019(Done, extractMapValueType helper + inferType Map.get string 分支骨架 + genMapMethod objType 参)
**创建:** 2026-04-24
**收关:** 2026-04-25 本轮三判据 PASS
- (a) RED 命令实测 IR 层四锚 before/after:`call i32 @f(i64` 1→0 / `store i32 .*, ptr %v\.` 0→1 / `load i32, ptr %v\.` 0→2 / `ss_int_to_string(i32` 3→4 + `%9 = call i64 @ss_mapGet` / `%10 = trunc i64 %9 to i32` 紧邻锚生效 ✅
- (b) `bin/ss run tests/phase5/i020a_typed_map_get_int.ss` → `Tests: 5 passed, 0 failed`(typed int get / 跨函数签名 / miss / I019 regression / untyped backward compat)✅
- (c) `bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss` → `Tests: 3 passed`(I019 V=string regression GREEN)✅
- (d) `./build.sh bootstrap` Stage 2 = Stage 3 固定点(两次自举)+ `bin/ss test tests/` 230 passed / 4 pre-existing failures(stash baseline 反向证明无新 regression)✅
- (e) `bin/ss run tools/reflection_health_linter.ss` GATE PASS(F1 gen_types.ss cur=777 ≤ bm=780, reflection scope not touched M*/N* AUTO-DRIFT 软警告豁免)✅
- (f) `bin/ss run tools/d_doc_index_linter.ss` GATE OK(6 referenced Ds all live)✅
**立项由:** `/split-issue` Phase 1 RCA(单根因"I019 v0 仅 V=string 特化,V-type-driven lowering 缺失")+ Phase 2 semantic sub-types 切线(按 V 类型切,I003-I006 annotation value 先例);取证源 memory `project_i019_phase2_red.md` §三组实测 stdout §int 组表面 GREEN §类型层隐性负债。

---

## 问题

I019 v0 只对 V="string" 做了 typed Map.get lowering 特化,V="int" 场景:
- `bootstrap/gen/gen_types.ss:410` inferType METHOD_CALL Map.get 未覆盖 V="int",回落 `methodRetTypes.set("get","i64")` fallback(`gen_registry.ss:190`)
- `bootstrap/gen/gen_builtins.ss:262-266` genMapMethod 未加 int V 分支,走 `call i64 @ss_mapGet` 无 `trunc i64 to i32`

一句话:typed Map<K,int>.get 静态类型推断 + codegen 路由双层未对 V=int 特化,表面 stdout 巧合 GREEN 掩盖类型层真 RED。

可观测否定证据:
- `echo 'function main() { let m: Map<string,int> = new Map(); m.set("k", 42); println("got:" + m.get("k")) }' | bin/ss run` → stdout `got:42`(表面 GREEN,i64 42 与 int 42 数值对齐,concat path 走 i64→string 打印)
- **但类型层真 RED**:`let v: int = m.get("k")` 实际 `v` varType 被记 "i64"(inferType fallback);传入 `function f(n: int): int { ... } f(v)` 签名 check 不对齐 int 契约

---

## 第一性需求

typed Map.get 静态类型推断 + codegen 路由双层对 V=int 特化,消除"concat 巧合 GREEN / 跨函数签名真 RED"类型层隐性负债。Why 两层:

- **Why1**:不做 → `let v: int = m.get("k"); f(v)`(`f(n: int)`)签名路径不对齐 int 契约,用户被迫写"getInt" 双轨制倒逼回潮 → 违反 CLAUDE.md §编译器吸收复杂度
- **Why2**:→ Phase 4+ @RequestParam(name="age", type=int)/@PathVariable(int) 绑参完全不可达;`Map<string,int>` 计数器 / 配置字典 Spring parity 场景全线不可能

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | `inferType` Map.get 分支加 `extractMapValueType(mgT) == "int"` case 返 "int";`genMapMethod` V=int 分支 emit `%ri64 = call i64 @ss_mapGet(...); %ri32 = trunc i64 %ri64 to i32` 返 %ri32 | 最小对称 I019 V=string 骨架,`extractMapValueType` helper 已在 `gen_types.ss:77-88` 就位;双层各加 2-3 LOC;无需改 runtime `ss_mapGet` 契约;`methodRetTypes.set("get","i64")` fallback 保留 untyped Map backward compat ✅ |
| **B** | 新增 `ss_mapGetInt(ptr, ptr): i32` 运行时 | 多 runtime path 膨胀 + V=int/double/class 各起一条 path;D088 §反模式边界接触(statically knowable cast 用 trunc 足够)✗ |
| **C** | 删 `methodRetTypes.set("get","i64")` fallback 全局转向 | untyped `let m = new Map(); m.get("k")` 场景 backward compat 破 ✗ |

---

## 步骤

1. RED 最小隔离测试:`/tmp/t_i020a_red.ss` 覆盖 typed int get hit + 跨函数 `f(n: int)` signature 传值;改前实测 inferType 返 "i64" / varType 记 "i64",改后 inferType 返 "int" 且 `f(v)` 通过 signature check
2. `bootstrap/gen/gen_types.ss:410` 附近加 `if (extractMapValueType(mgT) == "int") { return "int" }` 分支(对称已有 string 分支位置)
3. `bootstrap/gen/gen_builtins.ss:262-266` 加 `else if (objType.startsWith("Map<") == 1 && extractMapValueType(objType) == "int")` 分支 emit `trunc i64 to i32`
4. 新建 `tests/phase5/i020a_typed_map_get_int.ss`:覆盖 typed int get / miss 默认值 i32 0 / 跨函数 `f(n: int)` signature 传值 / I019 regression(V=string 路由 ss_mapGetString 仍 work)
5. `./build.sh bootstrap` 固定点验证
6. `bin/ss run tools/reflection_health_linter.ss` GATE(预估 F1 gen_types.ss/gen_builtins.ss +2/+3 LOC 在 baseline 内;若触发按 D097 §baseline 扩容申报走)
7. `bin/ss run tools/d_doc_index_linter.ss` OK

---

## 反向 / 备选

**备选 B(ss_mapGetInt 新 runtime)**:
- 优点:V=int 独立 runtime entry 语义清晰
- 缺点:多 runtime path 膨胀 LOC + 每 V 各起一条;路径 A 的 `trunc` cast 静态可知不需运行时 ✗

**备选 C(删 fallback)**:
- 优点:彻底清理方法名 fallback
- 缺点:untyped `let m = new Map(); m.get("k")` 场景 backward compat 破 ✗

**不做 → 后果**:
- `let v: int = m.get("k")` 实际 v 被当 i64;跨函数 `f(n: int)` 签名验证持续失真
- Phase 4+ @RequestParam(int) 不可达
- int value 场景用户被迫回 "getInt" 双轨制方法名倒逼回潮 → 违反 CLAUDE.md §编译器吸收复杂度

---

## 验收 RED 命令

```bash
# RED 最小隔离测试(表面 GREEN 与类型层 RED 双验)
echo 'function f(n: int): int { return n + 1 }
function main() {
  let m: Map<string,int> = new Map()
  m.set("k", 42)
  let v: int = m.get("k")
  println("v=" + v)
  println("f(v)=" + f(v))
}' > /tmp/t_i020a_red.ss && bin/ss run /tmp/t_i020a_red.ss
# after 期望:v=42 / f(v)=43 (inferType 返 "int" 且 f(v) 过 signature check)

bin/ss run tests/phase5/i020a_typed_map_get_int.ss          # PASS
./build.sh bootstrap                                         # 固定点
bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss   # I019 V=string regression GREEN
bin/ss run tools/reflection_health_linter.ss                # F1 GATE PASS
bin/ss run tools/d_doc_index_linter.ss                      # OK
```

---

## 风险 / 表面 / 下轮升根

**纯 cast 面**,无 RC / 无 null safety 耦合。`extractMapValueType` helper v0 naive first-comma split 对 `Map<Map<...>,int>` 嵌套 K 不生效(I019 v0 scope 限定,非 Spring 典型),本 issue 不扩。

**不表面**:`methodRetTypes.set("get","i64")` fallback 保留(untyped Map backward compat),仅 typed Map<K,int>.get 特化分支生效。

---

## 触发场景

- I019 §v0 scope 切分说明 §留下轮 显式 hard prereq
- Phase 4+ @RequestParam(int) / @PathVariable(int) 扩参实施前
- `Map<string,int>` 计数器 / 配置字典 Spring parity 场景

---

## 备注

- **根因锚**:本 issue 修 I019 §v0 scope 遗留"typed Map<K,V>.get V-type-driven lowering 缺失"单根因在 **V=int 动作面**:`gen_types.ss:410` inferType 分支 + `gen_builtins.ss:262-266` genMapMethod 分支双层各加 V=int case + `trunc i64 to i32` cast。根因锚源头:memory `project_i019_phase2_red.md` §三组实测 stdout §int 组 §根因双层同源锚 §I020 三子 cast 独立契约清单。
- `methodRetTypes.set("get","i64")` fallback 不删(untyped Map backward compat)
- `extractMapValueType` helper 已在 `gen_types.ss:77-88`,无需新 helper
- 预估对照:~5-10 LOC 细档,轻于 I019 v0(int V 纯 cast 无 ptr 链路)
