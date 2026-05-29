# global_scalar_materialize.options — 全局非字面量 int/bool 初值物化 ptr 误用(llc 硬失败)

> Bug 修复 Harness 轨1 前置方案对比表(MNK §字段 10）。D171 §收口验收 comparison-area
> 最后一个 runtime 全局物化 correctness gap。**[⚠ 偏离 feat/d171-sema-q2 comptime 主线 —
> 用户授权(同 I033/I034 runtime parity 收口模式)]**

## RED / 现象

```
printf 'let g=1<2\nfunction main(){println(`${g}`)}\n' > /tmp/gcmp.ss
bin/ss run /tmp/gcmp.ss 2>&1 | grep -c 'error: llc'    # = 2（>0 成立）
# llc-18: error: integer constant must have integer type
#   store ptr 1, ptr @g, align 8
```

同崩:`let h=true&&false`（逻辑）/ `let c=a+b`（算术，引用其他全局）/ `let m=arr[0]`
（array-get int）/ `let k=f()`（int 函数调用）。局部作用域同表达式全 GREEN（`let g=1<2`
局部显 "true"、`let k=f()` 显 "7"）—— **仅全局 scope 崩**。

## 根因定位（§实证 grep 证据）

| 锚 | 命令 + 输出 | 含义 |
|---|---|---|
| 物化误用 | `gen_decls.ss:287` `@${name} = global ptr null, align 8` | else 分支对所有非 fn 类型无条件物化 ptr slot |
| store 误用 | `gen_decls.ss:339` `store ptr ${val}, ptr @${gname}` | runtime init 把 i32 值存入 ptr slot → llc 类型错 |
| 读取侧 | `exprs_simple.ss:17` `load ${ssTypeToLLVM(vType)}, ptr ${varRef(name)}` | genIdent 已按 getVarType 分派 load 类型——设 gType=int/bool 即自动 `load i32` |
| 对齐模板 | `gen_decls.ss:258` COMPTIME_EXPR 分支 `@${name} = global i32 ${ceLit}, align 4` + `gType=ceType` | 同函数 int/bool 物化模板，直接复用 |
| 实测 IR | `%5 = call i32 @f()` + `store ptr %5, ptr @k` | genExpr 返 i32，存入 ptr slot（类型错） |

**单一概念根**:gen_decls.ss 全局物化接口边界（声明 + store 两站点）对非字面量 int/bool
丢失类型 —— 物化 ptr slot 而值是 i32。I034 把 comparison/logical 推断改 "bool"、I033 修了
显示，但**全局物化路径从未支持非字面量 int/bool**（I034 前 realType="int" 同样撞此 else
分支，潜伏已久）。

## 候选方案对比

| # | 层次 | 方案 | 假设破裂消除/绕过 | 长久/演化 |
|---|---|---|---|---|
| **A** | **数据层 patch** | emitGlobalInits 调用方对 int/bool 值 `inttoptr i32→ptr` 再 `store ptr`，`global ptr null` 不变；读取侧 genIdent 加 `ptrtoint` 还原 | **未消除**——slot 类型仍错（ptr 装 int），假设破裂仅延后到读取侧；inttoptr/ptrtoint 污染读取全链 | N 年返工度**高**：做 B/C 时必删；违反 CLAUDE.md §Root Cause（调用方 workaround） |
| **B** ✅ | **接口层 trap** | gen_decls.ss 全局物化边界单一真相源：genGlobalVar else 分支 realType==int/bool → `global i32 0, align 4` + gType=realType；emitGlobalInits 对称发 `store i32`。读取侧 genIdent 经 getVarType→ssTypeToLLVM 自动 `load i32`（literal int 全局已验此路径） | **消除**——物化点按 realType 分派 i32 slot，声明+store+load 三处类型自洽；与同函数 COMPTIME_EXPR 分支（gen_decls.ss:258）int/bool 物化模板对齐，零新抽象 | N 年返工度**低**：i32 物化是终态分派，若未来做 C 统一函数则 int/bool 分支自然并入（迁移非返工）；业界（LLVM/GCC）全局初始化均按类型分派 slot |
| **C** | **架构层 refactor** | 抽 `materializeGlobal(type, valExpr)` 统一所有全局物化（int/bool/double/string/fn/ptr/array），消除 genGlobalVar + emitGlobalInits 双站点"声明与 store 类型手动同步"的脆弱性 | **从架构消除**双站点同步破裂源（更上游） | 依赖未设计的统一抽象；scope 超本 finding（须迁全类型）；业界演化"先按类型分派(B)后抽象统一(C)"——B 先于 C |

### 假设破裂入口

> **"genGlobalVar else 分支对所有非 fn 类型物化 `global ptr null` 的假设，在 realType=int/bool
> 时破裂"** —— genExpr 对 comparison（zext i1→i32）/ 逻辑（genShortCircuit i32）/ 算术
> （add i32）/ array-get（内部 trunc i64→i32）/ int-call（call i32）产出 **i32 寄存器**，存入
> ptr slot → llc "integer constant must have integer type" 硬失败。
>
> - 候选 A 用 inttoptr **绕过**（假设破裂仍在，slot 类型错，延后到读取侧）
> - 候选 B 在物化点按 realType 分派 i32 slot **消除**该破裂（本 finding 可达最深根）
> - 候选 C 用统一物化函数从架构**消除**"双站点手动同步"这一更上游破裂源（scope 超本 finding）

## 决策行

**选 B 因** 接口层（gen_decls 全局物化边界）是全局声明+store 的单一真相源，realType=int/bool
走 i32 物化模板即让声明/store/读取三处类型自洽、消除根因，与同函数 COMPTIME_EXPR 分支
（gen_decls.ss:258）既有 int/bool 模板完全对齐（零新抽象），与 I033/I034「接口层根因」同族。
**不选 A** 因数据层 inttoptr 强转 slot 类型仍错（假设破裂未消除）+ 污染读取全链，违反 §Root
Cause 第一法则。**不选 C** 因架构层统一物化函数 scope 超本 finding（string/double/fn/array 全
迁移）、违反 commit 半径，且业界演化 B 先于 C；C 留独立 refactor issue（B 落地后 int/bool
分支自然并入，非返工）。根因解决度排序:B（消除，终态分派）> C（消除但越界）> A（绕过）。

## §实证

### grep 证据（根因定位）

见上「根因定位」表 5 锚：物化误用 `gen_decls.ss:287` / store 误用 `gen_decls.ss:339` /
读取侧自动分派 `exprs_simple.ss:17` / 对齐模板 `gen_decls.ss:258` / 实测 IR `store ptr %5`。

### 最危险假设 + 最小 spike（局部 working-reference，不改编译器）

- **最危险假设**:genExpr 对所有非字面量 int/bool 全局初值返 **i32**（非 i64），故 `store i32` 类型安全。
- **最小 spike（局部 working-reference 试切）**:同表达式在局部作用域走 genVarDecl，已 GREEN：
  - `function main(){let g=1<2; println(\`${g}\`)}` → 输出 **true**（局部 store i32 成立 → 证 genExpr 返 i32）
  - `function f():int{return 7} function main(){let k=f(); println(\`${k}\`)}` → 输出 **7**
  - IR 级实证:comparison `zext i1 .. to i32`（exprs_binary.ss:57/171）；array-get
    `%10=call i64 @ss_arrayGet` → `%11=trunc i64 %10 to i32`（exprs_simple.ss:61 内部 trunc）；
    int-call `call i32 @f`；算术 `add i32`。**全部 i32，无 i64 漏网**（Map.getInt 可能 i64 = I003b
    backlog 独立 scope，prompt 明确不混入）。
- **spike 结论**:局部 working path 证明 genExpr 对 int/bool 表达式返 i32，全局只需复用同 i32
  物化模板（候选 B）。`store i32 ${val}` 无需额外 trunc 安全网。本改 <20 LOC + 1 文件，未触发
  §字段 12 大规模修改 spike 门槛，局部 working-reference 即充分 de-risk。

## GREEN 验收判据

- 全局 comparison/逻辑/算术/array-get/int-call 初值全编译通过
- 显示 parity:comparison/逻辑 → "true"/"false"，int → 数值，comptime==runtime
- bootstrap 三阶段固定点 + 全测 baseline 持平（3 pre-existing 不变，+1 新 regression test）
- reflection_health / sunset / bugfix / d_doc gate 全 PASS
