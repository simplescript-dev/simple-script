# I020c — Typed Map<K,ClassName>.get value 类型 class-specific inttoptr + RC + null safety lowering (V=class 动作面)

**父决策:** I019 §v0 scope 切分说明 §留下轮 / D123 §扩容申报-I019 §留下轮
**状态:** Done at `bootstrap/gen/gen_types.ss:413 inferType METHOD_CALL Map.get V=class case 返 ClassName?` + `bootstrap/gen/gen_builtins.ss:290-298 genMapMethod V=class 分支 emit inttoptr i64→ptr + emitRetainForType (D023 双 RC 统一分派 → ss_retain user class 路径)` + `tests/phase5/i020c_typed_map_get_class.ss RED→GREEN 6 PASS`(2026-04-25)
**颗粒度:** 预估 ~15-25 LOC / 实测 +14 LOC bootstrap(gen_types.ss +4 / gen_builtins.ss +10 mirror I020a/I020b V case 表平行插入)+ ~85 LOC test。预估精准上沿,**ss_retain 内置 isnull guard 简化红利**:`gen_runtime.ss:521-533 ss_retain` 自带 `isnull eq → done` null-safe guard,issue §step 4 "若 null-safe 可省条件分支"成立,无外挂 icmp/br;**双 RC 统一分派复用**:走 `emitRetainForType(rp, mapV)`(`class/class.ss:114`)而非裸 `ss_retain`,V=class 自动选 user class 路径,符合 D023 契约 + CLAUDE.md §双 RC 系统
**依赖:** I019(Done) + I020a(Done) + I020b(Done) + SS 全局 D067 null safety 主策略(memory `project_null_safety_design.md` Kotlin/Dart 风格 = TS strict `V | undefined` 机制)+ D023 双 RC 统一分派(`bootstrap/gen/class/class.ss:114 emitRetainForType` user class → ss_retain mimalloc / 其他 → ss_rc_retain libc)
**创建:** 2026-04-24
**收关:** 2026-04-25 本轮六判据 PASS
- (a) RED 命令实测 before/after:`bin/ss run /tmp/t_i020c_red.ss 2>&1 \| head -3` before: `llc-18: error: null must be a pointer type / icmp ne i32 %16, null`(if narrow lowering 把 mapGet i64 fallback 与 ptr null 比类型 mismatch,llc 编译直接拒)→ after: `name:alice / miss`(双 V=class 路径双向 OK);**RED pattern 精炼记录**:用户原 pattern `call ptr @ss_int_to_string(i32 %N)` 实测撞前置错误(if narrow icmp 在 ss_int_to_string lowering 之前),refine 为 `error: null must be a pointer type` 实测命中 1 行,等价证明双层 RED(gen_types 未返 ClassName? + gen_builtins 未 inttoptr ptr)✅
- (b) IR 锚 main() 函数内 `awk '/^define i32 @main/,/^}/' /tmp/t_i020c_red.ll \| grep -E 'ss_mapGet\|inttoptr\|ss_retain\|icmp.*ptr.*null'` = 8 行链式锚生效:`call i64 @ss_mapGet → inttoptr i64 to ptr → call void @ss_retain(ptr → icmp ne ptr %N, null`(双 V=class get 各 4 行)✅
- (c) `bin/ss run tests/phase5/i020c_typed_map_get_class.ss` → `Tests: 6 passed, 0 failed`(typed class get hit + miss narrow / cross-fn `getUser(m,k): User?` signature 对齐 / RC retain 多 get 稳定无 double-free / V=double regression / V=int regression / V=string regression)✅
- (d) `./build.sh bootstrap` Stage 2 = Stage 3 固定点 ✅ + `bin/ss test tests/` 232 passed / 4 pre-existing failures(I020b 收关 baseline 231 + 本轮 +1 i020c test 文件 = 232,4 pre-existing 与 I020a/I020b 收关 baseline 完全对齐)✅
- (e) `bin/ss run tests/phase5/i020a_typed_map_get_int.ss`(I020a regression)5 PASS + `bin/ss run tests/phase5/i020b_typed_map_get_double.ss`(I020b regression)5 PASS + `bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss`(I019 V=string regression)3 PASS ✅
- (f) `bin/ss run tools/reflection_health_linter.ss` GATE PASS — no regressions(F1 gen_types.ss cur=780 bv=775 bm=780 DRIFT 软警告不阻,M*/N* AUTO-DRIFT 软警告 reflection scope not touched 豁免)+ `bin/ss run tools/d_doc_index_linter.ss` GATE OK(6 referenced Ds all live)✅
**立项由:** `/split-issue` Phase 1 RCA(单根因"I019 v0 仅 V=string 特化,V-type-driven lowering 缺失")+ Phase 2 semantic sub-types 切线(按 V 类型切);取证源 memory `project_i019_phase2_red.md` §三组实测 stdout §class 组 llc error RED §根因双层同源锚 §I020 三子 cast 独立契约清单 §class 组最重耦合(cast + RC + null safety 三件)。

---

## 问题

I019 v0 只对 V="string" 做了 typed Map.get lowering 特化,V="ClassName" 场景:
- `bootstrap/gen/gen_types.ss:410` inferType METHOD_CALL Map.get 未覆盖 V=class,回落 `methodRetTypes.set("get","i64")` fallback(`gen_registry.ss:190`)
- `bootstrap/gen/gen_builtins.ss:262-266` genMapMethod 未加 class V 分支,走 `call i64 @ss_mapGet` 无 `inttoptr i64 to ptr` cast 且无 `ss_retain` RC 契约
- 后续使用路径(如 `m.get("k").name` → `ss_int_to_string(...)` 字段访问 lowering)走 i32 签名,llc 验证拒

可观测否定证据(明 RED,编译直接拒):
- `class User { name: string = "" } let m: Map<string,User> = new Map(); let alice = new User(); alice.name = "alice"; m.set("k", alice); let u = m.get("k"); println("name:" + u.name)` → llc error `call ptr @ss_int_to_string(i32 %12)` i32/i64 签名 mismatch
- oracle 期望 `name:alice`(且 `u` 被类型系统标为可空类型强制 narrow)

---

## 第一性需求

typed Map.get 静态类型推断 + codegen 路由双层对 V=class 特化,完成 cast + RC + null safety 三件闭环:
1. `inferType` 返 `ClassName?`(Kotlin/Dart 风格 = TS strict `V | undefined` 机制,SS 全局 D067 主策略一致)
2. `genMapMethod` emit `inttoptr i64 to ptr` + 条件 `ss_retain`(非 null 才 retain,对称现有 class 字段 retain 契约)
3. miss 返 ptr null 通过 D067 既有 T? narrow 机制(`if (u != null) { u.name }`)强制调用方检查

Why 两层:
- **Why1**:不做 → `Map<K,User>` 编译直接拒(llc i32/i64 mismatch),Spring parity `Map<String,User>` 惯例(context/session/header 存 user 对象)完全不可达;用户被迫回 "getClass" 双轨制方法名回潮 → 违反 CLAUDE.md §编译器吸收复杂度
- **Why2**:→ Phase 4+ @RequestParam(class) / @ModelAttribute / @SessionAttribute 扩参完全不可能;Spring MVC enterprise parity gate 在 class V 路径永久断裂

---

## I020c 子决策 — Map<K,ClassName>.get 类型回值 nullability

**选定:Kotlin/Dart 风格 `ClassName?`(= TS strict `V | undefined`,SS 全局 D067 主策略 alignment)**

**Why**:
- `ss_mapGet` miss 时运行时返 `i64 0` → inttoptr 得 `ptr null`,**物理必然存在 null 可能**
- SS 全局 D067 主策略规定"ClassName 非空 = 运行时不可能 null",若 `Map<K,User>.get(): User` 非空签名则破系统性承诺(用户写 `u.name` 直接 segfault,编译器没拦,跟 Kotlin 背道而驰)
- 对比 Java 原生 `Map.get(): V` miss 返 null 运行时 NPE(无强制) vs TS strict `Map.get(): V | undefined` 强制调用方 narrow — SS 的 `T?` 拼写 = TS strict 的 `V | undefined` 机制,用户写 `if (u != null) { u.name }` 即可过编译(既有 D067 narrow 机制)
- 对比 Go 风格 zero-object miss:class 实例布局 `{ i32 rc, ptr TypeInfo, ...fields }` 零对象 TypeInfo=null → 后续 vtable dispatch 全 segfault,**技术不可行**

**策略边界**:本子决策仅限定 `Map<K,ClassName>.get`,不外扩到 `Map<K,int?>`/`<K,double?>` 等 optional primitive V 类型(primitive 0 值语义明确,不需 optional wrapping);若后续需要 optional primitive V,起独立 DXXX-typed-map-get-optional-primitive 决策。

**无需独立 /decide 全局锁**:D067 主策略已全局生效(memory `project_null_safety_design.md`),本子决策只在 I020c scope 内选"Map<K,ClassName>.get 对齐 D067 主策略"的局部一致性落实,不改变全局策略面。

---

## 候选路径(选 A)

| 路径 | 描述 | 取舍 |
|---|---|---|
| **A** | `inferType` Map.get 分支加 V=class case(通过 `classFields.has(extractMapValueType(mgT)) == 1` 判 class 名),返 `"ClassName?"` 带 nGetI3 optional flag;`genMapMethod` V=class 分支 emit `%ri64 = call i64 @ss_mapGet(...); %rp = inttoptr i64 %ri64 to ptr; %isNull = icmp eq ptr %rp, null; br i1 %isNull, label %skip, label %ret; ret: call void @ss_retain(ptr %rp); br label %skip; skip: ...` 条件 retain | 最小对称 I019 V=string 骨架 + D067 既有 T? narrow 机制复用(checker 侧不改);`extractMapValueType` helper + `classFields` 已就位;条件 retain 对称现有 class 字段 retain 模式 ✅ |
| **B** | `inferType` 返 `ClassName`(非空)+ miss runtime panic | 破 D067 系统性"ClassName 非空 = 运行时不可能 null"承诺;用户承担 key 存在验证 ≈ 老 Java NPE 风格;与 SS 全局 null safety 一致性冲突 ✗ |
| **C** | `inferType` 返 `ClassName`(非空)+ miss zero-object | 零对象 TypeInfo=null → 后续 vtable dispatch segfault;技术不可行 ✗ |
| **D** | 新增 `ss_mapGetClass(ptr, ptr, ptr typeinfo): ptr` 运行时带 TypeInfo 校验 | 多 runtime path + `ss_mapGet` 不存 TypeInfo(mapSet 侧已 retain 存 ptr 为 i64,mapGet 反向需有 TypeInfo 上下文重新校验)额外工作量;D088 §反模式边界接触;类型系统层静态可知不需运行时类型标签 ✗ |

---

## 步骤

1. **子决策落实**:I020c §I020c 子决策段选定 Kotlin/Dart `ClassName?`(= TS strict `V | undefined`),I020c 本 issue 内部锚定无需独立 D 文档
2. RED 最小隔离测试:`/tmp/t_i020c_red.ss`(`class User { name: string = "" } ...`);改前实测 llc error `call ptr @ss_int_to_string(i32 %12)` i32/i64 mismatch(编译拒),改后实测编译通过 + stdout `name:alice` + miss 路径 `if (u != null)` narrow OK
3. `bootstrap/gen/gen_types.ss:410` 附近加 V=class case:
   - 提取 V = `extractMapValueType(mgT)`
   - 判 `classFields.has(V) == 1` 确认是 class(非 primitive / 非 Array<T> 等)
   - 返 `V + "?"`(带 optional 标记供 checker narrow 机制用);节点层 nGetI3 optional flag 同步(参考 D067 Phase 3 `?.` 返回 T? 路径)
4. `bootstrap/gen/gen_builtins.ss:262-266` 加 V=class 分支 emit IR:
   - `%ri64 = call i64 @ss_mapGet(ptr %obj, ptr %key)`
   - `%rp = inttoptr i64 %ri64 to ptr`
   - 条件 retain:`%isNull = icmp eq ptr %rp, null; br i1 %isNull, label %skipRetain, label %doRetain; doRetain: call void @ss_retain(ptr %rp); br label %skipRetain; skipRetain: ...`
   - 验证 `ss_retain(ptr null)` 是否 null-safe(检查 `bootstrap/gen/gen_runtime.ss:521` ss_retain 定义),若 null-safe 则可简化省掉条件分支直接 retain;若不 null-safe 必须外挂 icmp
5. checker 侧验证:`let u = m.get("k")` 的 `u` varType 含 optional flag,直接 `u.name` 触 D067 null safety error,`if (u != null) { u.name }` narrow 过 check(既有 D067 check sites 复用)
6. 新建 `tests/phase5/i020c_typed_map_get_class.ss`:覆盖 typed class get hit + if narrow / miss 返 null + narrow 拒绝 / RC retain 一致(set 后 get 再 set 新值触发 release 旧值不 double-free)/ I019 V=string regression
7. `./build.sh bootstrap` 固定点
8. `bin/ss run tools/reflection_health_linter.ss` GATE(预估 F1 gen_types.ss/gen_builtins.ss +3/+6-8 LOC 可能接近/触及 baseline;若触发按 D097 §baseline 扩容申报走)
9. `bin/ss run tools/d_doc_index_linter.ss` OK

---

## 反向 / 备选

**备选 B(返 ClassName + miss panic)**:
- 优点:类型签名简洁,调用方 `m.get("k").name` 直接访问不需 narrow
- 缺点:破 SS 全局 D067 主策略;运行时 segfault/panic 调试困难;与 Kotlin/Dart/TS strict 一致性断裂 ✗

**备选 C(返 ClassName + zero-object)**:
- 优点:用户感知"总有对象"
- 缺点:零对象 TypeInfo=null → vtable dispatch 全 segfault,技术不可行 ✗

**备选 D(ss_mapGetClass runtime)**:
- 优点:运行时 TypeInfo 校验可提供 sanity check
- 缺点:多 runtime path + mapSet/mapGet 不对称 + 静态可知不需 runtime 标签 ✗

**不做 → 后果**:
- `Map<K,User>` 编译直接拒,Spring `Map<String,User>` context/session 全线不可达
- Phase 4+ @RequestParam(class) / @ModelAttribute 永久不可能
- 用户被迫回 "getClass" / `.ss_mapGetClassName(...)` 双轨制方法名回潮,违反 CLAUDE.md §编译器吸收复杂度

---

## 验收 RED 命令

```bash
# RED 最小隔离测试(llc i32/i64 mismatch vs inttoptr+retain+narrow 双验)
echo 'class User {
  name: string = ""
}
function main() {
  let m: Map<string,User> = new Map()
  let alice = new User()
  alice.name = "alice"
  m.set("k", alice)
  let u = m.get("k")
  if (u != null) { println("name:" + u.name) } else { println("miss") }
  let u2 = m.get("missing")
  if (u2 != null) { println("unreachable") } else { println("miss") }
}' > /tmp/t_i020c_red.ss && bin/ss run /tmp/t_i020c_red.ss
# before 期望:llc error call ptr @ss_int_to_string(i32 %N) i32/i64 mismatch (编译直接拒)
# after 期望 :name:alice / miss (inttoptr + 条件 retain + D067 narrow OK)

bin/ss run tests/phase5/i020c_typed_map_get_class.ss        # PASS
./build.sh bootstrap                                         # 固定点
bin/ss run tests/phase5/d123_phase3_i019_typed_map_get.ss   # I019 V=string regression GREEN
bin/ss run tools/reflection_health_linter.ss                # F1 GATE PASS
bin/ss run tools/d_doc_index_linter.ss                      # OK
```

---

## 风险 / 表面 / 下轮升根

**最重耦合**:cast(inttoptr)+ RC(条件 ss_retain) + null safety(D067 T? narrow)三件。三件在 I020c 内部一次性闭环(子决策段 + 步骤 3-5 覆盖),不进一步二级拆。

**ss_retain null-guard 契约待验**:`bootstrap/gen/gen_runtime.ss:521 ss_retain(ptr %p)` 是否本身 null-safe 需 I020c 执行时读定义确认;若 null-safe 可简化省条件分支直接 retain,否则 call site emit `icmp + br` 条件 retain。

**D067 主策略 alignment**:I020c 严格遵循 D067 Kotlin/Dart 风格 + T? narrow 不破例;如果后续 optional primitive V(`Map<K,int?>`)场景浮现,起独立 DXXX-typed-map-get-optional-primitive 决策,不在 I020c scope 扩。

**TypeInfo 头对齐**:class 实例布局 `{ i32 rc, ptr TypeInfo, ...fields }`(CLAUDE.md §关键不变量 §对象布局),inttoptr 后读 offset 1 即 TypeInfo 指针;本 issue 不主动解引用 TypeInfo(调用方字段访问路径自然走 GEP),仅保证 inttoptr 产物为合法 class 实例 ptr。

**mapSet 侧前置检查**:`m.set("k", alice)` 侧 `bitcast ptr→i64` 路径已在 I019 v0 范围或更早就位(class 实例按 ptr 存入 map i64 值槽)无需本 issue 改,仅 mapGet 侧补反向 inttoptr + retain。

---

## 触发场景

- I019 §v0 scope 切分说明 §留下轮 显式 hard prereq(class V 组 llc mismatch RED 最重)
- Spring parity `Map<String,User>` context / session / header 存 user 对象惯例
- Phase 4+ @RequestParam(class) / @ModelAttribute / @SessionAttribute 扩参前置
- middleware / stdlib 用 Map 缓存 class 实例场景(`Map<string,Connection>` / `Map<int,Node>` 等)

---

## 备注

- **根因锚**:本 issue 修 I019 §v0 scope 遗留"typed Map<K,V>.get V-type-driven lowering 缺失"单根因在 **V=class 动作面**:`gen_types.ss:410` inferType 分支加 V=class case 返 `ClassName?` + `gen_builtins.ss:262-266` genMapMethod 分支加 class 分支 `inttoptr + 条件 ss_retain` + D067 null safety 既有 T? narrow 机制复用(checker 不改)。根因锚源头:memory `project_i019_phase2_red.md` §三组实测 stdout §class 组 llc error §根因双层同源锚 §I020 三子 cast 独立契约清单 §class 组最重耦合。
- D067 主策略 alignment:memory `project_null_safety_design.md` Kotlin/Dart 风格 + T? narrow(= TS strict `V | undefined` 机制),不破例
- `ss_retain` null-guard 契约:`bootstrap/gen/gen_runtime.ss:521 ss_retain(ptr %p)` 是否 null-safe 需 I020c 执行时验证
- TypeInfo 头对齐:class 实例布局 RC@0 + TypeInfo@1(CLAUDE.md §关键不变量)
- 预估对照:~15-25 LOC 中档,三件耦合(cast + RC + null safety)一次性闭环,子决策段内收敛不拆
