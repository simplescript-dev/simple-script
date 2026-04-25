# I020b — Typed Map<K,double>.get value 类型 double-specific bitcast lowering (V=double 动作面)

**父决策:** I019 §v0 scope 切分说明 §留下轮 / D123 §扩容申报-I019 §留下轮
**状态:** Done at `bootstrap/gen/gen_types.ss:412 inferType METHOD_CALL Map.get V=double case` + `bootstrap/gen/gen_builtins.ss:282-289 genMapMethod V=double 分支 emit bitcast i64→double` + `tests/phase5/i020b_typed_map_get_double.ss RED→GREEN 5 PASS`(2026-04-25)
**颗粒度:** 预估 ~5-10 LOC / 实测 +9 LOC bootstrap(gen_types.ss +1 / gen_builtins.ss +8 mirror I020a V=int 分支结构,无需重构 early-return 因 I020a 已完成)+ 55 LOC test。预估精准,gen_builtins.ss early-return 重构红利直接继承 I020a,r64 在前 bitcast→rd 在后 LLVM SSA #-order 约束自然满足。
**依赖:** I019(Done, extractMapValueType helper + inferType Map.get string 分支骨架 + genMapMethod objType 参)/ I020a(Done, early-return 重构 + V=int 分支)
**创建:** 2026-04-24
**收关:** 2026-04-25 本轮六判据 PASS
- (a) RED 命令实测 stdout + IR 层四锚 before/after:`bin/ss run /tmp/t_i020b_red.ss` stdout `4614253070214989087 / 1`(3.14 IEEE-754 位 `0x40091EB851EB851F` + f(v) 类型撞错算错)→ `3.14 / 4.14`(bitcast 双向对称 + signature 对齐)✅;IR 锚 `call double @f(i64` 1→0 / `bitcast i64.*to double` 0→1 / `store double .*, ptr %v\.` 0→1 / `call i64 @ss_mapGet` 1 仍存 ✅
- (b) `bin/ss run tests/phase5/i020b_typed_map_get_double.ss` → `Tests: 5 passed, 0 failed`(typed double get / 跨函数 signature / miss 0.0 / I020a regression / I019 regression)✅ 跨函数 signature test 用精确二进制 double(0.5 + 1.0 = 1.5)避开 fp round-to-nearest 累积误差,只验签名对齐
- (c) `bin/ss run tests/phase5/i020a_typed_map_get_int.ss` → `Tests: 5 passed`(I020a V=int regression GREEN)✅ + `bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss` → `Tests: 3 passed`(I019 V=string regression GREEN)✅
- (d) `./build.sh bootstrap` Stage 2 = Stage 3 固定点 ✅ + `bin/ss test tests/` 231 passed / 4 pre-existing failures(与 I020a 收关 230 passed 对齐,本轮 +1 test = i020b 新增)✅
- (e) `bin/ss run tools/reflection_health_linter.ss` GATE PASS(F1 gen_types.ss cur=777 bv=775 bm=780 DRIFT 软警告不阻,reflection scope not touched M*/N* AUTO-DRIFT 软警告豁免)✅
- (f) `bin/ss run tools/d_doc_index_linter.ss` GATE OK(6 referenced Ds all live)✅
**立项由:** `/split-issue` Phase 1 RCA(单根因"I019 v0 仅 V=string 特化,V-type-driven lowering 缺失")+ Phase 2 semantic sub-types 切线(按 V 类型切);取证源 memory `project_i019_phase2_red.md` §三组实测 stdout §double 组 RED §IEEE-754 位模式核对。

---

## 问题

I019 v0 只对 V="string" 做了 typed Map.get lowering 特化,V="double" 场景:
- `bootstrap/gen/gen_types.ss:410` inferType METHOD_CALL Map.get 未覆盖 V="double",回落 `methodRetTypes.set("get","i64")` fallback(`gen_registry.ss:190`)
- `bootstrap/gen/gen_builtins.ss:262-266` genMapMethod 未加 double V 分支,走 `call i64 @ss_mapGet` 无反向 `bitcast i64 to double`

一句话:typed Map<K,double>.get 静态类型推断 + codegen 路由双层未对 V=double 特化,mapSet 侧已 `bitcast double→i64` 存入,mapGet 侧未反向 bitcast 导致位模式 i64 原值泄露。

可观测否定证据(明 RED,非巧合):
- `echo 'function main() { let m: Map<string,double> = new Map(); m.set("k", 3.14); println("got:" + m.get("k")) }' | bin/ss run` → stdout `got:4614253070214989087`
- **IEEE-754 位模式核对**:3.14 double = `0x40091EB851EB851F` = `4614253070214989087`,确认 mapSet 侧 `bitcast double→i64` 存,mapGet 未反向 bitcast
- oracle 期望 `got:3.14`

---

## 第一性需求

typed Map.get 静态类型推断 + codegen 路由双层对 V=double 特化,恢复 bitcast 双向对称,消除 mapSet/mapGet 路径位模式泄露。Why 两层:

- **Why1**:不做 → `let v: double = m.get("k")` 拿到的是 double 3.14 bit-pattern 的 i64 整数值,任何后续算术 / 比较 / print 全部失真;用户被迫回 "getDouble" 双轨制方法名倒逼回潮 → 违反 CLAUDE.md §编译器吸收复杂度
- **Why2**:→ Phase 4+ @RequestParam(double) / `Map<string,double>` 配置参数(timeout / 权重 / 百分比)Spring parity 场景全线不可能;科学计算 / 金融算法领域 SS 全线失格

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | `inferType` Map.get 分支加 `extractMapValueType(mgT) == "double"` case 返 "double";`genMapMethod` V=double 分支 emit `%ri64 = call i64 @ss_mapGet(...); %rd = bitcast i64 %ri64 to double` 返 %rd | 最小对称 I019 V=string 骨架;mapSet 侧已有 bitcast double→i64(`gen_builtins.ss` mapSet 路径)完美对称;`extractMapValueType` helper 就位;miss 默认值 i64 0 bitcast 得 double 0.0 自然对齐(IEEE-754 位 0 = +0.0)✅ |
| **B** | 新增 `ss_mapGetDouble(ptr, ptr): double` 运行时 | 多 runtime path + V=int/double/class 各起一条;D088 §反模式边界接触;bitcast 静态可知不需运行时 ✗ |
| **C** | mapSet/mapGet 全局用 ptr 存 double 而非 i64 bitcast | 运行时契约大改,与 mapSet i64 成对逻辑全推翻 ✗ |

---

## 步骤

1. RED 最小隔离测试:`/tmp/t_i020b_red.ss` 覆盖 typed double get hit;改前实测 stdout `got:4614253070214989087`(IEEE-754 位泄露),改后 stdout `got:3.14`
2. `bootstrap/gen/gen_types.ss:410` 附近加 `if (extractMapValueType(mgT) == "double") { return "double" }` 分支
3. `bootstrap/gen/gen_builtins.ss:262-266` 加 `else if (objType.startsWith("Map<") == 1 && extractMapValueType(objType) == "double")` 分支 emit `bitcast i64 to double`
4. 新建 `tests/phase5/i020b_typed_map_get_double.ss`:覆盖 typed double get / miss 默认值 0.0 / 算术运算(v + 1.0)/ I019 regression
5. `./build.sh bootstrap` 固定点
6. `bin/ss run tools/reflection_health_linter.ss` GATE(预估 F1 +2/+3 LOC 在 baseline 内;若触发按 D097 §baseline 扩容申报走)
7. `bin/ss run tools/d_doc_index_linter.ss` OK

---

## 反向 / 备选

**备选 B(ss_mapGetDouble 新 runtime)**:
- 优点:V=double 独立 runtime entry 语义清晰
- 缺点:路径 A 的 `bitcast` 静态可知不需运行时分支;多 runtime path 与 I020a 同症 ✗

**备选 C(全局存 ptr 非 bitcast i64)**:
- 优点:消除 i64 bitcast 中间态
- 缺点:mapSet i64 成对逻辑全推翻;运行时 ss_mapSet/ss_mapGet 契约大改 ✗

**不做 → 后果**:
- `let v: double = m.get("k")` 永远拿到 bit-pattern i64 整数值,算术 / print 全失真
- Phase 4+ @RequestParam(double) 不可达
- `Map<string,double>` 科学计算 / 金融场景全线不可能

---

## 验收 RED 命令

```bash
# RED 最小隔离测试(IEEE-754 位泄露 vs 正确 bitcast 双验)
echo 'function main() {
  let m: Map<string,double> = new Map()
  m.set("k", 3.14)
  let v: double = m.get("k")
  println("got:" + v)
  println("v+1.0=" + (v + 1.0))
}' > /tmp/t_i020b_red.ss && bin/ss run /tmp/t_i020b_red.ss
# before 期望:got:4614253070214989087 (IEEE-754 位泄露)
# after 期望 :got:3.14 / v+1.0=4.14 (bitcast 反向恢复)

bin/ss run tests/phase5/i020b_typed_map_get_double.ss       # PASS
./build.sh bootstrap                                         # 固定点
bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss   # I019 V=string regression GREEN
bin/ss run tools/reflection_health_linter.ss                # F1 GATE PASS
bin/ss run tools/d_doc_index_linter.ss                      # OK
```

---

## 风险 / 表面 / 下轮升根

**纯 cast 面**,无 RC / 无 null safety 耦合,与 I020a 对称。`extractMapValueType` helper v0 naive 限制同 I020a 说明。miss 默认值 i64 0 bitcast 得 double 0.0 自然对齐,不需额外 miss 处理。

**不表面**:mapSet 侧 bitcast double→i64 路径不改,仅 mapGet 侧加反向 bitcast,双向对称补齐。

---

## 触发场景

- I019 §v0 scope 切分说明 §留下轮 显式 hard prereq
- Phase 4+ @RequestParam(double) / @PathVariable(double) 扩参实施前
- `Map<string,double>` 金融百分比 / 权重 / timeout 配置 Spring parity 场景
- 科学计算 / 统计 / ML 领域 Map<K,double> 字典操作

---

## 备注

- **根因锚**:本 issue 修 I019 §v0 scope 遗留"typed Map<K,V>.get V-type-driven lowering 缺失"单根因在 **V=double 动作面**:`gen_types.ss:410` inferType 分支 + `gen_builtins.ss:262-266` genMapMethod 分支双层各加 V=double case + `bitcast i64 to double` 反向 cast。根因锚源头:memory `project_i019_phase2_red.md` §三组实测 stdout §double RED §IEEE-754 位模式核对 §根因双层同源锚 §I020 三子 cast 独立契约清单。
- mapSet 侧 `bitcast double→i64` 已存在(I020b 仅补 mapGet 侧反向对称)
- miss 默认值 i64 0 bitcast 得 double 0.0(IEEE-754 位 0 = +0.0)自然对齐
- `extractMapValueType` helper 就位无需新建
- 预估对照:~5-10 LOC 细档,与 I020a 结构对称
