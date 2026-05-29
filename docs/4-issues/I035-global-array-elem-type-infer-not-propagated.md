# I035 — 全局无标注数组 var 元素类型未传播致 array-get 全局物化失败

**父决策:** D171 §收口验收 finding（global_scalar_materialize 标量物化修复轮）衍生。该轮修了全局非字面量 int/bool 标量物化（comparison/逻辑/算术/int-fn-call），但**无标注全局数组** `let a = [1,2,3]` 的 `a[i]` 全局 array-get 仍 llc 硬失败 —— 独立根因。
**状态:** **[x] Resolved at `bootstrap/gen/gen_decls.ss` genGlobalVar else 分支（2026-05-29，候选 B 接口层 trap，`global_array_elem_infer.options.md` GATE 6/6 + `.bugfix` 6 gate PASS）**。
**颗粒度:** 预估微改~标准改（genGlobalVar 补 inferArrayElemType→setVarType(Array<elem>) 传播，对齐 genVarDecl:576-581）。
**依赖:** 无硬依赖；与 global_scalar_materialize 标量物化修复（gen_decls.ss genGlobalVar/emitGlobalInits）同函数、不同根因（推断 vs 物化）。同族 I038（inferArrayElemType 覆盖不全,原 I034,2026-05-30 经 I037 改号）。
**创建:** 2026-05-29
**立项由:** global_scalar_materialize 轮 regression test 验证 —— 无标注全局 array-get `let gArr=[10,20,30]; let gIdx=gArr[1]` 实测 `store ptr %13, ptr @gIdx` llc 硬失败，而标注版 `let gArr: Array<int>=[..]` GREEN（prints 20），精确指认根因 = 全局数组 varType 推断缺失。

---

## 现象（最小变量隔离实证）

```
# 无标注 — RED（llc 硬失败）
let a = [10, 20, 30]
let m = a[1]            # @m = global ptr null + store ptr <i32> → llc error

# 显式标注 — GREEN（prints 20，global_scalar_materialize 物化修复已覆盖）
let a: Array<int> = [10, 20, 30]
let m = a[1]            # @m = global i32 0 + store i32 → ✓
```

对照局部作用域：`function main(){ let a=[10,20,30]; let m=a[1] }` 无标注**亦 GREEN**（prints 10）。
**仅全局 scope + 无标注组合**崩。

## 根因（global/local var decl 不对称）

`genVarDecl`（局部，`gen_decls.ss:576-581`）对无标注数组 init 调
`inferArrayElemType(initId)` → `setVarType(name, "Array<${elem}>")` 传播元素类型；
`genGlobalVar`（全局，`gen_decls.ss` else 分支）**缺此传播** → 全局 `let a=[10,20,30]`
的 varType 退化为 "ptr"（丢元素类型）→ `inferType(a[1])` 经 `getVarType(a)="ptr"`
无法判定元素类型 → 返非 int → 全局物化（global_scalar_materialize int/bool 分支）
不触发 → 落 else `global ptr null` + `store ptr <i32>` → llc 硬失败。

**单一概念根** = genGlobalVar 与 genVarDecl 在「无标注数组元素类型传播」上的不对称。
（与 I038 同族：均是 `inferArrayElemType` 链路覆盖完整性问题；I038 是 METHOD_CALL/
函数返回/嵌套形态覆盖，本 I035 是 global var decl 入口未调用传播。）

## 候选路径（待 Execute 轮 PSM §字段 10 展开）

- **接口层（推荐）**:genGlobalVar else 分支补 `inferArrayElemType→setVarType(Array<elem>)`
  传播，对齐 genVarDecl:576-581（SSoT 化 local/global var decl 的元素类型传播契约）。
- **数据层（次优）**:仅在 array-get 物化点补元素类型回查 —— 治标不治本，其他依赖
  全局数组 varType 的 codegen 路径仍受同局限。

## GREEN 判据（立项目标，非本轮）

无标注全局数组 `let a=[..]; let m=a[i]` 编译通过 + 值正确 + comptime==runtime parity；
全局/局部 var decl 元素类型传播对称。

---

## 解决（2026-05-29，本轮，候选 B 接口层 trap）

**实际站点**:`gen_decls.ss` `genGlobalVar` else 分支 annotation=="" 子支补
`else if (realType == "ptr") { const aeType = inferArrayElemType(initId); if (aeType != "") { gType = \`Array<${aeType}>\` } }`
（**对齐 `genVarDecl:587-593`** 局部路径——本 doc 创建时记为 `:576-581`，实际现位 587-593，行漂移；
逻辑完全镜像 `typeAnn=="" && initType=="ptr" → inferArrayElemType → setVarType(Array<elem>)`）。
SSoT 化 local/global var decl 元素类型传播契约,**不在 array-get 物化点补回查**（候选 A 被否）。

**GREEN（`tests/phase5/global_array_elem_infer.ss`，11 assert，VCM §3 pre-fix exit 1↔fixed exit 0）**:
无标注全局 int 数组 array-get（值/显示/入算术）、string 数组（ptr slot）、bool 数组（"true" 显示）、
comptime==runtime parity（`comptime { let ca=[10,20,30]; return ca[1] }`）、局部对称 working-reference 全 ✅。
net_new_ifs=2 / net_new_fns=0 / same_pattern_count=0 / bootstrap 三阶段固定点 / 全测 baseline 持平
（3 pre-existing 不变，+1 新测）/ reflection_health GATE PASS（gen_decls 763≤bm765，**无 bump**）/ sunset GATE OK。

**carve-out（本轮验证衍生，正交不混入）**:无标注全局 **double** 数组 array-get（及一切全局非字面量
double `let g=1.5+2.5`）仍 llc 硬失败——但**根因不同**:I035（本）是 propagation 侧（元素类型已正确传播为
`Array<double>`、`d` 已正确推为 `double`），崩在 **materialization 侧**（emitGlobalInits 把 double 值
`store ptr` 入 ptr-默认 slot）= global_scalar_materialize int/bool 物化家族**未做 double 扩展**的独立
gap → **立项 [[I036]]**（`I036-global-double-scalar-materialize.md`）。I035 的元素类型传播对 double 同样
生效（IR 实证 `@d`/`@da` 类型推断正确），仅物化未覆盖。
