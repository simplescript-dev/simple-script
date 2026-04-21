# D118: 反射 Sidecar 彻底清理 — D097 §后续工作 5 承接

**Status:** Executing (Execute 0-1 Done,2-5 待执行,2026-04-21 Plan 起草 + Execute 1 Done)
**Depends on:** D088 §第一性需求(obj.fields() + obj[name]) / D093 §决策(evalExpr 单函数 dispatch) / **D097 §后续工作 5 "逐步删除 classXxxAnnotation* Map、__* sidecar、nGetS1(x)== 字符串分支"** / D117 Execute 5 Done(interpCollectFields / interpCtFieldsArray 两函数已删,commit `6e264fd`)/ D098 §Phase B(Meta 对象 InternPool 承载)/ D111 §决策 1 internPoolGetOrInsert / D095 Stage C(FieldMeta reflection 源头)/ D096 L2κ(m.annotations reflection 源头)
**Date:** 2026-04-21

---

## 第一性需求

D097 §后续工作 5 明言:"**逐步删除 classXxxAnnotation* Map、__* sidecar、nGetS1(x)== 字符串分支**"。D117 Execute 0-5 完成 Meta 对象实例化(ClassMeta/FieldMeta/MethodMeta/AnnotationMeta/ParamMeta 五类)+ evalExpr MEMBER_ACCESS on Meta + genForIn 通用 fold + interpCollectFields/interpCtFieldsArray 两字符串路径函数整删,但**annotation 源数据存储仍是 CSV Map 中间态**:`class_register.ss` 阶段 AST ANNOTATION_LIST → split → CSV 拼接存 3 个 Map,`interpBuildTypeInfo` 再从 Map getString + split 回 AST 构造 AnnotationMeta,绕一圈回到起点。

**否定证据**:不做 → `bootstrap/gen/class/class.ss:15-64` 3 个 `classXxxAnnotation*` Map 保留 → `extractAnnotationsReflection()` 30 行中间拼接函数保留 → `interp_obj.ss:144-170` 3 处 `.getString(key).split(",")` 保留 → reflection_health_linter M2 / M5 / M7b 无法继续单调压低(D117 Execute 4 M2 +378/tol 380 已用到 99% 预算)→ D097 §累积方向严禁 record 配 §削减方向单调推进 的 linter 设计失去压力来源 → D088 §第一性需求"反射是 Meta 对象自然成员访问,不是累积子支路"命题永不完全兑现。

## 当前事实(2026-04-21 snapshot,D117 commit `6e264fd` 后)

**残余点位**(`grep -rn "class\w*Annotation\w*" bootstrap/` = 13 处 + `grep -rn "nGetS1([a-zA-Z_0-9]+) ==" bootstrap/` = 22 处,反射相关 ~7 处):

### Class A — `classXxxAnnotation*` CSV Map(3 Map,13 处)

| 点位 | 用途 |
|---|---|
| `class.ss:15-16, 18, 61-62, 64` | 3 Map **定义 + 初始化**(2 组) |
| `class_register.ss:53-76` | **`extractAnnotationsReflection()` 30 行函数** — AST → CSV 拼接 |
| `class_register.ss:141, 171` | extractAnnotationsReflection 2 调用点(field / method) |
| `interp_obj.ss:144` | `classFieldAnnotations.getString(ftKey).split(",")` CSV 读 |
| `interp_obj.ss:150` | `classFieldAnnotationArgs.getString(faArgKey).split(",")` CSV 读 |
| `interp_obj.ss:169` | `classMethodAnnotations.getString(mAnnKey).split(",")` CSV 读 |
| `member_access.ss:27` | `classFieldAnnotations.getString(faKey)` CSV 读(边界补偿,见 Class C) |

### Class B — 反射 `nGetS1(x) == "..."` 字符串分支(~7 处反射 + 15 处非反射)

反射相关(本 Plan 范围):
- `check_stmts.ss:386` — `METHOD_CALL && nGetS1 == "fields"` for-in 迭代器识别
- `class_comptime.ss:104` — `MEMBER_ACCESS && nGetS1 == "name"` foldComptimeIdentsInTree Meta 字段 fold
- `gen_types.ss:437` — `nGetS1 == "name"` on STRING_LIT TypeValue
- `gen_types.ss:441` — Meta 字段 `name`/`type`/`returnType` 三元组类型推导
- `exprs.ss:25` — `MEMBER_ACCESS && nGetS1 == "name"` isCtStringIdx
- `exprs.ss:30` — ctVars Meta object 判别

非反射(不在本 Plan 范围):
- `"Eq"/"exit"/"Neg"/"methodOf"/"As"/"Thread"/"annotationMapping"/"main"/"NullCoalesce"/"Map"/"start"` 等 15 处,为 AST kind/关键字合法检查,非累积路径

### Class C — `member_access.ss:22-32` for-in 边界补偿(D117 Execute 3 遗留)

`evalMemberAccess` L7-33 对 `f.name / f.type / f.annotations`(f 是 for-in unroll 绑定的 comptime const)走**string-ctVars-bound** 路径读 `comptimeConsts + classFieldTypes + classFieldAnnotations` 三 Map,而非 FieldMeta 对象字段读。D117 Execute 3 commit `bda5813` 说明:"stmts_loop_forin.ss cls.fields loop 边界补偿:FieldMeta object unwrap 回 string tv 绑 ctVars,让 foldComptimeIdentsInTree 对 `get_${f.name}` 模板的 scalar fold 路径不变"。

此"补偿"**本身是 sidecar 残留的另一形态**:Meta 对象不能直接被 for-in unroll 绑定为 ctVars,退化为 scalar string 绑定 + 三 Map 查找。根治需:(a) for-in unroll 绑 f 为 FieldMeta object tvId(非 string name); (b) foldComptimeIdentsInTree 识别 Meta object ctVars → rewrite 到 interpGetField; (c) 删除 `evalMemberAccess` L7-33 的 string-ctVars 分支。

### Class D — D097 概念 `__*` sidecar(**本项无残余,闭合**)

`grep -rn '"__' bootstrap/` 实际仅 2 项非反射:`__return__`(PIR MOVE marker,`pir_opt.ss:39` / `pir_lower.ss:179`)+ `__comptime__`(scope 名,`stmts_core.ss:50-51`),均非反射 sidecar。D097 §第一性问题 L16 "`__sidecar` sidecar 键伴随 comptimeConsts" 描述的历史形态在 D117 Execute 5 前已随 `interpCtFieldsArray`/`interpCollectFields` 删除同步消除。本项**无工作**。

## 决策(分 5 §)

### §决策 1 — Class-level annotations 路径是架构模板,field/method 照此改造

`interp_obj.ss:180-196` class-level annotations 段**已是 AST 直读纯净形态**:

```ss
for (ap in nGetList(nGetI4(parseInt(classNodeIds.getString(typeName)))).split(",")) {
    const aId = parseInt(ap)
    if (aId > 0) {
        const annName = nGetS1(aId)
        // inline AnnotationMeta 构造 + args 遍历 + InternPool dedup
        ...
    }
}
```

无 CSV Map 中间态,零 `extractAnnotationsReflection` 依赖。**此即 field / method annotations 的改造目标形态**。

**field annotations**:从 `classNodeIds[typeName]` → class AST → paramList → PARAM.list → ANNOTATION_LIST id,遍历每个 ANNOTATION,inline 构造 AnnotationMeta(内含 args 遍历 STRING_LIT)。

**method annotations**:从 `classNodeIds[typeName]` → class AST → methodsBlock → FUNC_DECL.I4 → ANNOTATION_LIST id,同上。注意 `class_register.ss:186-189` 历史注释指 accessor get/set "annotation collapse onto one key",**AST 直读天然分离两个 FUNC_DECL,比 CSV Map collapse 更准** — 这是 progress,不是 regression。

### §决策 2 — 删 3 Map + extractAnnotationsReflection

§决策 1 兑现后,以下全部删除:
- `class.ss:15-16, 18` 3 Map 声明(3 行)
- `class.ss:61-62, 64` 3 Map 初始化(3 行)
- `class_register.ss:53-76` `extractAnnotationsReflection()` 函数(24 行有效代码)
- `class_register.ss:141, 171` 2 调用点(2 行)
- `interp_obj.ss:144-155` field annotations CSV split block(12 行)
- `interp_obj.ss:168-177` method annotations CSV split block(10 行)

**合计 ~54 行物理删除**,函数数 -1,可变 state 点数 -5(3 Map let + 2 Map() 初始化 ASSIGN)。

### §决策 3 — member_access.ss:22-32 边界根治(Class C)

**方案对比**(3 方案,选 A):

| 方案 | 策略 | 实现成本 | 选否 |
|---|---|---|---|
| **A: FieldMeta object ctVars 绑定** | for-in unroll 绑 f 为 FieldMeta tvId(非 name string),foldComptimeIdentsInTree 识别 Meta object ctVars → interpGetField fold | 中(改 stmts_loop_forin.ss + class_comptime.ss foldComptime 分支扩) | **选**(根治累积路径) |
| B: 保留 string-ctVars 绑定,L27 改查 Meta 对象 | member_access.ss:27 不读 classFieldAnnotations,改查 FieldMeta object .annotations field | 低 | 否(仍 string-ctVars 中间态,累积路径形态未根治,只换存储) |
| C: 不管 member_access.ss:22-32,留下轮处理 | 本 Plan 只删 Class A/B,Class C 留 D119 | 最低 | 否(§决策 2 删 classFieldAnnotations Map 后 L27 `classFieldAnnotations.getString` 编译失败,必须同步处理) |

**选 A 理由**:Class C 的 string-ctVars 边界是"Meta 对象不能被 for-in unroll 绑定"的**能力缺口**,根治即兑现 D117 §决策 5 "Meta 数组通用 iteration"真正意义。§决策 1 已建立 FieldMeta object 链,ctVars 绑定扩展成本低于保留累积路径。

### §决策 4 — nGetS1 反射字符串分支收敛评估(Class B)

7 处反射相关 nGetS1 字符串分支中:

| 点位 | 可合并性 | 处理 |
|---|---|---|
| `check_stmts.ss:386` `nGetS1 == "fields"` | **低** — METHOD_CALL iterator kind 检查是 forIn checker 入口,不是累积路径(iterator 是 Meta 数组就走通用 fold,此处检查本身不增加"每字段 +1") | **保留,标"已在 D117 §决策 5 最小化,无削减"** |
| `class_comptime.ss:104` `MEMBER_ACCESS && nGetS1 == "name"` | **可合并** — 本身是 foldComptimeIdentsInTree Meta 字段 fold 分支,与 §决策 3 方案 A 的 Meta object ctVars fold 路径是**同一件事** | **合并到 §决策 3 Execute 轮** |
| `gen_types.ss:437` `nGetS1 == "name"` STRING_LIT | **低** — TypeValue 旧路径,与 D117 §决策 4 evalMemberAccess string/TypeValue 统一走 interpBuildTypeInfo interpGetField 部分重叠;但 gen 期类型推导 inferType 与 fold 时刻不同,保留无累积风险 | **保留** |
| `gen_types.ss:441` Meta 字段 `name/type/returnType` 三元组 | **低** — inferType 返 "string" 的**白名单保护**,是 Meta 对象已知字段类型表;可抽 `isMetaStringField(name)` helper 合并,但物理削减 M4 仅 -2 | **保留,抽 helper 物理收益 ≤ tol,不值得折腾** |
| `exprs.ss:25` `MEMBER_ACCESS && nGetS1 == "name"` | **可合并** — 与 class_comptime.ss:104 同质,isCtStringIdx 对 Meta 字段的 fold 预判 | **合并到 §决策 3 Execute 轮** |
| `exprs.ss:30` ctVars Meta object 判别 | **低** — isCtStringIdx 的 Meta object 类型分派,是 §决策 3 的**基础设施**,保留 | **保留(被 §决策 3 复用扩展)** |

**结论**:本 Plan 真正能合并的 Class B 点位 = `class_comptime.ss:104` + `exprs.ss:25` 两处,合并入 §决策 3 Execute 轮;其余 5 处标 **"D097 §后续工作 5 范围内已最小化"**,D097 §后续工作 5 闭合无需再动。

### §决策 5 — Meta 对象 RC 生命周期(D117 §新张力 5 承接)

§决策 1 field/method annotations 改 AST 直读后,`interpBuildTypeInfo` 内 inline 构造的 AnnotationMeta 实例数量扩大(每 class 的 每 field 的 每 annotation + 每 method 的 每 annotation)。这些 Meta 实例**不进入 Perceus RC 管理**,与 D117 §新张力 5 对策一致:InternPool 常驻对象。

**检查项**:Execute 2 后跑 `./build.sh bootstrap` 固定点,若有 Meta 实例被 pir_lower.ss 误判为 RC 候选(插入 release),需在 pir_lower.ss 加 Meta class 例外列表,或确认 interpBuildTypeInfo 构造路径不经 genVal → pir 常规 liveness 路径(应不经,因是 interp_* comptime 路径,纯 eval fold)。**高置信推定本项非问题**,Execute 轮仅做 spot-check 即可。

## Rejected Alternatives

### §A — 保留 classXxxAnnotation Map,仅优化 CSV 拼接性能

表面减少 split 调用次数,累积 Map 本体保留。违 D097 §第一性问题 L13-17 "累积式扩展不是根因解决"。Map 存在本身 = 累积路径证据物。

### §B — 把 3 Map 搬进 InternPool 变 `|` 分隔 key

形式换皮,累积路径本质不变。违 feedback_reflection_root_cause_gate "M5 +N5 抗 '把 Map 搬到 class 字段' 规避"同族约束。

### §C — 不处理 member_access.ss:22-32 Class C,留 D119

§决策 2 删 classFieldAnnotations Map 后 member_access.ss:27 `classFieldAnnotations.getString` 编译失败,必须同步处理;§决策 3 方案 A 根治 vs 方案 B "L27 改查 FieldMeta object" 降级方案成本差仅 ~30 分钟,无拆分收益。

### §D — 单 commit 合并所有 Execute

§决策 2 +§决策 3 两处改动面合计 ~80 行改动 + ~54 行删除,单 commit 失败恢复成本高。P14 "Atomic task execution" 指"同一任务顺序步骤不跨轮切分",不禁止 Execute 逐一 commit。按 D117 节奏 Execute 1-2-3 分 commit,M2/N2 每步削减可见。

### §E — 保留 nGetS1 反射 7 处全部不动

违 §决策 4 评估结果 — 其中 2 处(`class_comptime.ss:104` + `exprs.ss:25`)与 §决策 3 Execute 轮根治路径同源,合并改动**无额外成本**,削减 M4 / M2 可贡献 baseline 压低。

### §F — 不写 D118,把工作续到 D117 Execute 6+

违 P16 "一决策一文档"+ P19 "D117 Status=Done 不应重开" + CLAUDE.md "交互式单文档(本轮用户指定 D097 §后续工作 5 cleanup Plan)"。D118 独立承接 D097 §后续工作 5 闭环,P19 状态流转清晰(D117 Done ✓ / D118 Planned → Execute 逐条 Done)。

## 新张力(D118 引出)

1. **Execute 1-2 加法在前削减在后** — interpBuildTypeInfo 改 AST 直读会扩 field/method annotations 构造 block(20-30 行加),classXxxAnnotation Map + extractAnnotationsReflection 删除在 Execute 3 才发生。单 commit 内 linter M2 / N2 可能出现短暂 DRIFT 逼近 tol。**对策**:Execute 1 完成 field annotations AST 直读 + Execute 3 同 commit 删 `classFieldAnnotations` Map(拆分为 1 commit;Execute 2 method 同 commit 删 `classMethodAnnotations` Map);extractAnnotationsReflection 函数随最后一个调用点删除。三步合并为 Execute 1-2-3,**每步 commit 净削减 > 0**,linter GATE PASS
2. **accessor get/set annotation 分离** — AST 直读后两个 FUNC_DECL 独立产出 MethodMeta(`MTH|<cls>.<mName>`),原 CSV Map collapse 成一 key 的历史形态消失。InternPool key 可能冲突:两个 FUNC_DECL mName 相同则 `MTH|<cls>.<mName>` key 相同 → InternPool hit 返第一个 MethodMeta,第二个丢失 annotation。**对策**:Execute 2 MethodMeta key 区分 get/set(如 `MTH|<cls>.<mName>.get` / `.set`),对应改 member_access.ss / evalExpr 的 method lookup 路径。若 SS 当前 accessor + 普通 method 同名冲突已被 checker 拒绝,本张力转 backlog(Execute 2 spot-check 确认)
3. **`classNodeIds[typeName]` 可能未命中** — 继承链父类 fields / methods 的 annotations 从子类 typeName 查不到 `classNodeIds`。`interpBuildTypeInfo:130-135` 已处理 fields 父类链(`interpClassParents` walk),methods 从 `classMethods` CSV 拿,**annotations 改 AST 直读后需同样沿 interpClassParents walk 拿父类 classNode**。对策:Execute 1/2 改 AST 直读时复用 L130-135 父类链模板,每层 typeName 查 classNodeIds 遍历 PARAM/FUNC_DECL annotation
4. **for-in unroll 绑 FieldMeta object(§决策 3 方案 A)影响 D117 Execute 4 已建立代码路径** — D117 Execute 4 改过 `stmts_loop_forin.ss` + `class_comptime.ss` foldComptimeIdentsInTree + `exprs.ss isCtStringIdx` + `gen_types.ss inferType` 四处协调 `ctVars Meta object` 分支。本 Plan §决策 3 方案 A 进一步把 f 从 string 绑定改为 Meta object 绑定,需**动同一批代码**。风险:改动面叠加容易 regression。**对策**:Execute 4 单独一轮,先跑 d095/d096 全系列 + Meta fold 测试,bootstrap 固定点 + reflection linter GATE PASS 再递交
5. **Meta 对象 RC 误判**(§决策 5 承接)— 低置信风险,Execute 2 spot-check 确认 pir_lower.ss 不经 interp_* comptime 构造路径

## 下一步(Plan 下的 Execute 顺序)

每步 `./build.sh bootstrap` 固定点 + `bin/ss run tools/reflection_health_linter.ss` GATE PASS(任一指标升 = regression 阻断)+ `bin/ss test tests/` 无新回归(pre-existing 4 failed 列表:spring_web_params / d096_p4_l2_reactive / harness_bug / harness_task,vs D117 最后 commit `6e264fd` 一致)。

0. [x] Done at `docs/3-decisions/D118-*.md`(2026-04-21) — **Execute 0 (Plan 起草)**:grep 盘点 3 类残余(Class A 13 处 + Class B 7 反射 nGetS1 + Class C 1 处 member_access 边界 + Class D 闭合)+ 架构对比(`interp_obj.ss:180-196` class-level annotations 纯 AST 直读作 field/method 模板)+ §决策 5 项 + §Rejected 6 项 + §新张力 5 项。linter 削减空间估算:M2 -135 / M4 -4 / M5 -5 / M7b -1 / N2 -675

1. [x] Done at `bootstrap/eval/interp_obj.ss:140-175` + `class.ss:12-15,54-57` + `class_register.ss:50-63,122-125` + `member_access.ss:22-33`(2026-04-21) — **Execute 1 (field annotations AST 直读 + 删 classFieldAnnotations/Args Map)**:
   - ✓ `interp_obj.ss:144-174` FieldMeta annotations AST 直读 — fromIC 路径 `nGetList(parseInt(fp))` / 非 fromIC `classFieldList(classNodeIds[typeName])` + `paramName(npId) == fName` 查 PARAM → `nGetList(npId)` 取 ANNOTATION_LIST id;inline AnnotationMeta 构造 + STRING_LIT args 遍历 + `ANN|FLD|${ftKey}.${annName}` InternPool dedup
   - ✓ 删 `class.ss:15-16, 61-62` 2 Map(`classFieldAnnotations` + `classFieldAnnotationArgs`)定义与初始化
   - ✓ 删 `class_register.ss` registerClass 内 field annotations 分支调用(原 L138-142 5 行)+ `extractAnnotationsReflection` 函数签名收敛 5→3 参数(删 `argsMap` + `withArgs`,删 args 提取 14 行分支)+ L153 调用点 method-only 3 参数形态(保留至 Execute 2 删函数)
   - ✓ `member_access.ss:22-33` — f.annotations 走 `interpBuildTypeInfo` 填 `FLD|${cls}.${fld}` InternPool → `interpGetField(fieldMetaTvId, "annotations")`;ctVars 绑 string 暂留 Execute 3 Class C 根治
   - ✓ bootstrap 固定点 + tests 215 passed / 4 pre-existing failed 一致
   - ✓ `bin/ss run tools/reflection_health_linter.ss` GATE PASS:M1 +14 / M2 +349 / M3a +52 / N2 +1745 DRIFT 全在 tol 内;M4 -27 / M5 -11 / M7b -2 / N3 -2419 PROGRESS;F1 gen_decls.ss 691→690 PROGRESS。**Execute 2-3 未合并前短暂加法方向,Execute 2-3 完成后削减方向 record**
   - ✓ RED 校验:`grep -rn "classFieldAnnotations\|classFieldAnnotationArgs" bootstrap/` 5→0
   - ✓ simplify 审:Agent 1 Finding 3 应用(interp_obj.ss:148-152 改用 `classFieldList` + `paramName` 已存在 helper,与 class_register.ss:105-113 / gen_generic_class.ss:70-77 风格一致);Finding 1 field/class annotation block 复制粘贴延至 Execute 2 方法 annotations 迁时共抽 `buildAnnotationMetaArray` helper

2. [ ] Planned — **Execute 2 (method annotations AST 直读 + 删 classMethodAnnotations Map + 删 extractAnnotationsReflection)**:
   - 改 `interp_obj.ss:162-177` MethodMeta block — annotations 段从 classNodeIds[typeName] + 父类链遍历 methodsBlock FUNC_DECL.I4,inline 构造 AnnotationMeta
   - accessor get/set InternPool key 冲突张力 2 检查:MethodMeta key 增加 `.get`/`.set` 后缀或确认 SS checker 已拒绝同名(执行 spot-check)
   - 删 `class.ss:18, 64` `classMethodAnnotations` Map 定义 + 初始化
   - 改 `class_register.ss:171` — 删 extractAnnotationsReflection 调用
   - 删 `class_register.ss:53-76` — `extractAnnotationsReflection` 函数(30 行)
   - linter 预期:M2 -45 / M5 -1 / M7b -1 / N2 -225
   - RED 命令:`grep -rn "classMethodAnnotations\|extractAnnotationsReflection" bootstrap/ \| wc -l` 必须降至 0
   - spot-check:pir_lower.ss 不经 interpBuildTypeInfo Meta 构造路径(§决策 5 承接)

3. [ ] Planned — **Execute 3 (member_access.ss 22-32 for-in 边界根治 Class C + 收敛 Class B 2 处)**:
   - `stmts_loop_forin.ss` for-in unroll 绑 f 为 FieldMeta object tvId(非 string name),ctVars entry type=object
   - `class_comptime.ss:104` `MEMBER_ACCESS && nGetS1 == "name"` 合并至 Meta object ctVars fold 路径统一处理(Class B 点位 1)
   - `exprs.ss:25` `MEMBER_ACCESS && nGetS1 == "name"` isCtStringIdx 合并同上(Class B 点位 2)
   - 删 `member_access.ss:22-32` f.name/.type/.annotations string-ctVars 三分支
   - 跑 d095/d096 全系列 + Meta fold 测试回归
   - linter 预期:M2 -40 / M4 -4 / N2 -225
   - RED 命令:`grep -rn "classFieldAnnotations\|classFieldAnnotationArgs\|classMethodAnnotations" bootstrap/ \| wc -l` 全 0

4. [ ] Planned — **Execute 4 (D097 §后续工作 5 Status 回写 + baseline record + D118 Status Done)**:
   - D097 §后续工作 5 段落(L74-L84)各条回写 `[x] Done at <file:line>`
   - D097 §第一性问题 L13-17 追加 "2026-04-21 D117+D118 后累积路径清除" 闭合段
   - `bin/ss run tools/reflection_health_linter.ss record` 写入新 baseline(M2 -120 / M4 -4 / M5 -3 / M7b -1 / N2 -625 削减方向合规)
   - commit message 显式标削减路径与 baseline delta
   - D118 Status: Planned → **Done ✓**

5. [ ] Optional / 延至 D119 — **Execute 5 (Class B 剩余 5 处 nGetS1 评估归档)**:
   - `check_stmts.ss:386 / gen_types.ss:437, 441 / exprs.ss:30` 5 处 §决策 4 评估"保留"
   - D118 §决策 4 结论文字化:**"D097 §后续工作 5 范围内已最小化"** 归档到 D118 §决策 4 补充段
   - 若未来出现反射新维度扩展冲击这 5 处,启 D119 重评
   - 本 Execute 仅文档整理,零代码改动

---

## 参考

- D088 §第一性需求(obj.fields() + obj[name])
- D093 §决策(evalExpr 单函数 dispatch) / §Rejected A/C/D(interp_* 独立求值器否决)
- **D097 §后续工作 5(本 Plan 承接主目标)** / §第一性问题 L13-17(累积路径根因) / L70 累积方向严禁 record
- D098 §Phase B L123-128(Meta 对象 InternPool 承载)
- D111 §决策 1 `internPoolGetOrInsert` / §决策 3 `|` 分隔 key 设计
- **D117 §决策 1-5 + Execute 0-5 Done**(本 Plan 前置)/ §新张力 4-5(D118 §新张力 4-5 承接)
- D095 Stage C(FieldMeta reflection 源头) / D096 L2κ(m.annotations reflection 源头)
- `bootstrap/eval/interp_obj.ss:122-198`(interpBuildTypeInfo + class-level annotations AST 直读模板)
- `bootstrap/gen/class/class_register.ss:53-76, 141, 171`(extractAnnotationsReflection + 调用点)
- `bootstrap/gen/class/class.ss:15-64`(3 classXxxAnnotation Map 定义 + 初始化)
- `bootstrap/eval/member_access.ss:22-32`(for-in unroll 边界补偿 Class C)
- `tools/reflection_health_linter.ss`(本 Plan Execute 必跑 GATE) / `tools/linter_baseline.txt`(M1-N5 + F1)
- `memory/feedback_reflection_root_cause_gate.md` / `feedback_pfv_process.md` / `feedback_no_workaround.md` / `feedback_dual_entry_is_dual_track.md` / `feedback_interactive_one_doc.md`
