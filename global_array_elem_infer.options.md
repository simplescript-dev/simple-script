# global_array_elem_infer.options — 无标注全局数组 var 元素类型未传播致 array-get 全局物化 llc 硬失败(I035)

> Bug 修复 Harness 轨1 前置方案对比表(MNK §字段 10）。D171 §收口验收 comparison-area
> 全局物化 gap 最后一块（array-get **推断侧**，非标量物化侧）。**[⚠ 偏离 feat/d171-sema-q2
> comptime 主线 — 用户授权（同 I033/I034/global_scalar_materialize runtime parity 收口模式）—
> I035 是 D171:170 立项的全局 array-get 推断侧 gap，根因在 gen_decls.ss genGlobalVar 元素类型传播缺失]**

## RED / 现象

```
printf 'let a=[10,20,30]\nlet m=a[1]\nfunction main(){println(`${m}`)}\n' > /tmp/garr.ss
bin/ss run /tmp/garr.ss 2>&1 | grep -c 'error: llc'    # = 2（>0 成立）
# llc-18: error: '%10' defined with type 'i64' but expected 'ptr'
#   store ptr %10, ptr @m, align 8
```

**作用域不对称**（精确隔离三例）:
- 局部无标注 `function main(){let a=[10,20,30]; let m=a[1]; println(`${m}`)}` → **GREEN，prints 20**（genVarDecl:587-593 已传播 `Array<int>`）
- 标注全局 `let a: Array<int> = [10,20,30]; let m=a[1]` → **GREEN，prints 20**（annotation 直接给 `a` 类型；global_scalar_materialize 轮已覆盖标注 array-get int 物化）
- **无标注全局** `let a=[10,20,30]; let m=a[1]` → **RED，llc 硬失败** ← 仅此组合崩

## 根因定位（§实证 grep 证据）

| 锚 | 命令 + 输出 | 含义 |
|---|---|---|
| 局部已传播 | `gen_decls.ss:588` `if (typeAnn == "" && initType == "ptr") { … setVarType(name, \`Array<${aeType}>\`) }` | genVarDecl 局部路径 **honors** 元素类型传播契约 |
| 全局缺传播 | `gen_decls.ss:279-305` genGlobalVar else 分支：annotation=="" 时仅 `realType != "ptr"` 才设 gType，**realType=="ptr"(数组)分支不存在** → setVarType(name, "ptr") 丢元素类型 | genGlobalVar **不 honor** 同一契约 → 与局部不对称 |
| 推断退化 | `gen_types.ss:627` `iaElem = inferArrayElemType(nGetI1(id))` → IDENT a 走 `getVarType("a")`=="ptr"，无 `<` → 返 "" → `inferType(a[1])` 返 "i64" | 元素类型丢失 → array-get 推断退化 i64 |
| 物化误用 | RED IR `store ptr %10, ptr @m`（`%10`=i64）| realType="i64" 落 else `@m=global ptr null` + emitGlobalInits `store ptr <i64>` → llc 类型不匹配 |
| 物化已就绪 | `gen_decls.ss:286` `realType=="int"\|\|"bool"` → `@m=global i32 0`；`gen_assigns.ss:41` `emitI64ToValue` llType=="i32" → `trunc i64→i32` | **元素类型一旦为 int，全局物化 + 值 trunc 全链已就绪**（标注路径已验）——仅缺类型传播 |

**单一概念根**:gen_decls.ss 的 **var-decl 元素类型传播契约**在局部站点（genVarDecl:587-593）honored、在全局站点（genGlobalVar）缺失 —— 接口层不对称。`a` 丢 `Array<int>` → 下游 `a[1]` 推断退化 i64 → 全局物化 ptr slot + store i64 崩。这是 array-get **推断侧** gap，与 global_scalar_materialize 修的**标量物化侧**（realType 已知时的 slot 分派）正交互补。

## 候选方案对比

| # | 层次 | 方案 | 假设破裂消除/绕过 | 长久/演化 |
|---|---|---|---|---|
| **A** | **数据层 patch** | 在 array-get 消费侧补偿：genIndexAccess（exprs_simple.ss）或 inferType INDEX_ACCESS（gen_types.ss:627）对「全局 IDENT 数组无元素类型」时回查 ARRAY_LIT 节点首元素 inferType；或物化点强 `inttoptr`/`trunc` 凑类型 | **未消除**——decl 站点契约仍不对称（`a` varType 仍 "ptr"），仅在每个消费点（INDEX_ACCESS / for-in / join / spread …）各自回查，回查逻辑随消费点扩散 | N 年返工度**高**：每新增数组消费 codegen 都要重复回查；违反 CLAUDE.md §Root Cause（消费侧 workaround，prompt 明令禁止） |
| **B** ✅ | **接口层 trap** | gen_decls.ss `genGlobalVar` else 分支 annotation=="" 子支补 `else if (realType == "ptr")` → `inferArrayElemType(initId)` → `gType = Array<elem>`，镜像 genVarDecl:587-593。元素类型在 **decl 站点**确立，下游 inferType/物化/trunc 全链自动受益（标注路径已验此链） | **消除**——全局/局部 var decl 在同一接口契约（无标注 + 初值推断 ptr → 传播元素类型）下对称；array-get 推断退化的源头（`a` 丢类型）被根除，所有消费点（不止 array-get）自动正确 | N 年返工度**低**：decl-site 传播是终态；inferArrayElemType 已支持 ARRAY_LIT（gen_types.ss:153 finding A 遗产）；业界（任何带局部类型推断的编译器）均在 decl 站点确立类型，消费侧只读 |
| **C** | **架构层 refactor** | 抽共享 helper `propagateDeclArrayElemType(typeAnn, baseType, initId): string`，genVarDecl + genGlobalVar **同调一函数**，从结构上杜绝「第三个 var-decl 路径忘了传播」的再生不对称 | **从结构消除**契约复制（单函数单一真相源，无法 drift） | 依赖「第三 caller 会出现」的预测——实际仅 2 个 var-decl 路径（局部/全局），genDestructureArray 是**逐元素**不同语义不复用；触碰已工作的局部路径增风险、收益 speculative → §反 over-engineer。业界演化「先对称两站点(B)、出现第三站点再抽象(C)」——B 先于 C |

### 假设破裂入口

> **「genGlobalVar else 分支对 annotation=="" 的数组初值不传播元素类型（varType 退 "ptr"）的假设，在
> 下游 `let m=a[1]` 需按元素类型推断/物化时破裂」** —— `a` 丢 `Array<int>` → `inferType(a[1])` 经
> `inferArrayElemType`(IDENT→getVarType→无 `<`) 退化返 `i64` → genGlobalVar 对 `m` 落 else 物化
> `@m=global ptr null`，且 genIndexAccess `emitI64ToValue(_, "")` 不 trunc 值留 i64 → `store ptr <i64>` llc 崩。
>
> - 候选 A 在每个**消费点**回查 ARRAY_LIT **绕过**（假设破裂仍在，`a` 的 decl 契约仍不对称，回查逻辑随消费点扩散）
> - 候选 B 在**全局 decl 站点**传播元素类型 **消除**该破裂（本 finding 可达最深根，与局部站点对称）
> - 候选 C 用共享 helper 从架构**消除**「契约在两站点各写一份」的更上游再生源（但仅 2 caller，speculative）

## 决策行

**选 B 因** 接口层（gen_decls.ss var-decl 元素类型传播契约）是元素类型确立的单一真相源，在 `genGlobalVar`
else 分支补 `realType=="ptr"→inferArrayElemType→gType=Array<elem>` 即让全局/局部 decl 站点对称、根除
`a` 丢类型的源头（array-get 推断退化、物化、trunc 全链自动正确，非仅修 array-get 一个消费点），与
genVarDecl:587-593 局部路径完全镜像（零新抽象），与 I033/I034/global_scalar_materialize「接口层根因」同族。
**不选 A** 因数据层在消费侧回查使 decl 契约仍不对称、回查逻辑随每个数组消费 codegen 扩散，违反 §Root
Cause 第一法则（prompt 明令「勿在 array-get 物化点补回查 workaround」）。**不选 C** 因架构层共享 helper 依赖
「会出现第三 var-decl caller」的预测（实际仅 2 个，genDestructureArray 逐元素语义不复用）、触碰已工作的局部
路径增风险、收益 speculative，违反 §反 over-engineer；C 留「若现第三 caller 即抽 helper」的下轮锚（届时
「同模式第二次」触发 SSoT 抽取，非本轮）。根因解决度排序:B（消除，decl 站点对称，终态）> C（消除但 speculative
越界）> A（绕过，消费侧扩散）。

## §实证

### grep 证据（根因定位）

见上「根因定位」表 5 锚：局部已传播 `gen_decls.ss:588` / 全局缺传播 `gen_decls.ss:279-305` /
推断退化 `gen_types.ss:627`（inferArrayElemType IDENT→getVarType 无 `<`→""）/ 物化误用 RED IR
`store ptr %10`（i64）/ 物化已就绪 `gen_decls.ss:286` + `gen_assigns.ss:41`（trunc i64→i32）。

补充实测:
- `grep -n "inferArrayElemType" bootstrap/gen/gen_decls.ss` → 仅 `:402`(genDestructureArray) `:589`(genVarDecl)，**genGlobalVar 无**（确认缺失，非误读）
- `inferArrayElemType` 已处理 ARRAY_LIT:`gen_types.ss:153-160`（finding A 遗产，首元素 inferType）→ 候选 B 依赖项已落地

### 最危险假设 + 最小 spike（局部/标注 working-reference 夹逼，不改编译器）

- **最危险假设**:传播 `Array<int>` 给 `a` 后，下游 `m=a[1]` 按 **decl 顺序**(emitGlobalVars 顺序 a 先于 m)
  重推为 int → 物化 i32 slot **且** genIndexAccess `emitI64ToValue(rawR, "int")` trunc 值为 i32 → `store i32` 自洽。
- **最小 spike（双 working-reference 试切，本 session 实跑）**:
  - 局部无标注 `function main(){let a=[10,20,30]; let m=a[1]; println(\`${m}\`)}` → **输出 20**（genVarDecl:587-593
    传播 `Array<int>` 成立 → 证「元素类型一旦传播，array-get 推断/trunc 全链正确」）
  - 标注全局 `let a: Array<int> = [10,20,30]; let m=a[1]; …` → **输出 20**（证「元素类型一旦已知，全局 i32 物化 +
    store i32 全链正确」——global_scalar_materialize 标量物化遗产）
  - 两 GREEN 夹逼:唯一缺口 = **无标注全局 decl 站点的元素类型传播**（候选 B 补此一点，下游全链已就绪）
- **spike 结论**:double working-reference 证明候选 B 依赖的「元素类型传播 → 推断/物化/trunc 全链」两端均已工作，
  本改仅 +4 行（1 文件 gen_decls.ss，未触 §字段 12 大规模门槛 `>20 LOC 或 ≥2 文件`），局部 working-reference 即充分 de-risk。

## GREEN 验收判据

- 无标注全局 array-get（**int/string/bool 元素**）编译通过 + 值正确 + comptime==runtime
- 全局/局部 var decl 元素类型传播对称（genGlobalVar ↔ genVarDecl:587-593）
- bootstrap 三阶段固定点 + 全测 baseline 持平（3 pre-existing 不变，+1 新 regression test）
- reflection_health（gen_decls 759+4=763 ≤ bm 765，**无需 bump**）/ sunset / bugfix / d_doc gate 全 PASS

> **carve-out（本轮验证衍生，正交不混入）**:无标注全局 **double** 数组 array-get（及一切全局非字面量
> double `let g=1.5+2.5`）仍 llc 硬失败 —— 但**根因不同**:I035 的元素类型传播对 double **已正确生效**
> （IR 实证 `@d`/`@da` 类型推断正确、`d` 推为 double），崩在 **materialization 侧**（emitGlobalInits 把
> double 值 `store ptr` 入 ptr-默认 slot）= global_scalar_materialize int/bool 物化家族**未做 double
> 扩展**的独立 gap → 立项 **I036**（`I036-global-double-scalar-materialize.md`），非本轮 propagation 修复范围。
