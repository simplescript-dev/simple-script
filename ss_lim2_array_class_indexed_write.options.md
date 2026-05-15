# SS-LIM-2 Array<class T> indexed write — 修法方案对比

> 后置补建（违反轨 1 前置 gate；本轮已直接落 A+E 修法 + bootstrap 固定点 GREEN + 7 case spike PASS + reflection_health_linter GATE PASS。补此表是为根因分析归档与后续 commit 合规。）

## 现象

- Repro 1 codegen: `arr[i] = new Item("c")` → `'%X' defined with type 'ptr' but expected 'i64'` on `ss_arraySet`
- Repro 2 parser: `h.items[0] = 99` → `parse error: expected newline or '}', found ASSIGN`

## Repro 1（codegen 路径）候选对比

| 候选 | 层次 | 描述 | 优 | 劣 | 假设破裂 | 决策 |
|---|---|---|---|---|---|---|
| **A** | 数据/codegen 分发器 | `stmts_simple.ss:117-132` 用 `ssTypeToLLVM(vt) == "ptr"` 取代字符串名 `"string"/"ptr"` 判断；统一走 `emitRetainForType`/`emitReleaseForType` + `isOwnedExpr`；class / interface / Generic<...> / T? 全部自动覆盖 | 真根因（dispatch 缺抽象，应按 LLVM 类型分派而非按字符串名）；表层一次性覆盖 5 类 ptr；与既有 D088 字段写路径同构（同样的 emitRetainForType/isOwnedExpr）；零 cascading | 需要重新跑 bootstrap 固定点 + 测试套件验证既有 string array 行为不退化 | 假设 H1「class 类型 inferType 返回 'ptr'」破裂—— 实测 inferType 返回 class 名 "Item"，所以原代码 `vt == "string" \|\| vt == "ptr"` 完全 miss class | ✓ |
| B | 接口/runtime contract | 改 `ss_arraySet` 签名 `i64 %val` → `ptr %val`，让所有 caller 不再 cast；ptr 与 i64 同宽 64bit 在 x86_64 等价 | 看似最干净（runtime 接受 ptr）| 5 处 caller 全要联动改（`stmts_simple.ss:129/132` + `gen_methods.ss:27/31/53` + `gen_calls.ss:722` + `gen_rt_string.ss:172/190/200` + `gen_rt_map.ss:330` + 自身 LLVM IR 定义 line 58-65）；array 内部数据 buffer 仍是 i64[]，存进去也要 cast，contract 上 ptr 但语义仍是 i64 → 名实分离 | 假设 H2「runtime 改签名 = root cause」破裂——bug 在分发器选错路径而不是 runtime 接收类型；改 runtime 等于把锅甩给所有 caller | ✗ |
| C | 数据/inferType | 让 inferType 对 class 实例返回 "ptr"，原代码就能 hit "ptr" 分支 | 改一处 inferType 即可 | 信息丢失—— class 名是后续 gen_methods/方法调用关键依据；改后会破坏 deep_clone/shallow_clone 静态分派、override 方法查找等下游；且 `emitRetainForType("ptr")` 走 `ss_rc_retain`（旧 RC 系统）不是 `ss_retain`（class 走 mimalloc），class 实例会进错 RC 系统 leak | 假设 H3「inferType 应擦除 class → ptr」破裂——class 名是承载类型信息的载体，下游需要它 | ✗ |
| D | 接口/RC 选择器 | 在原 string/ptr 分支内加 class 判断 `if (isUserClass(vt)) ss_retain(...) else ss_rc_retain(...)` | 最小 diff | 仍按字符串名分发，重复 emitRetainForType 已经做的事，违反 DRY；未来加 fn 类型 / Iface 类型 又得动这里 | 假设 H4「特例叠加可以解决」破裂——这是分发抽象的回归，不是分发本身的修补 | ✗ |

**选 A 因：根因在分发抽象（按字符串名 vs 按 LLVM 类型），其他三案要么改错层（B/C）要么是补丁堆叠（D）。A 复用 D088 已落地的 emitRetainForType/isOwnedExpr 模式，与编译器既有抽象一致。**

## Repro 2（parser 路径）候选对比

| 候选 | 层次 | 描述 | 优 | 劣 | 假设破裂 | 决策 |
|---|---|---|---|---|---|---|
| **E** | 数据/AST 节点 + 接口/parser | INDEX_ASSIGN 节点扩 `nGetI3(id)` 槽承载 obj 表达式；`nGetS1==""` + `nGetI3>0` = 表达式形式（h.items[0]=v），`nGetS1!=""` = 旧 var-name 形式（x[i]=v）兼容；parser 在 chain 路径 + fall-through 路径都补 INDEX_ACCESS+ASSIGN 检测 → 调 `makeIndexAssign` helper；codegen `genIndexAssign` 按槽分派 arrPtr 来源；checker 同步给 obj 表达式做 checkExpr | 真根因（AST 缺槽承载"被索引对象"，应像 MEMBER_ASSIGN 持 I1 obj）；与 MEMBER_ASSIGN 现有形态对称；零 breaking change（旧 var-name 形式继续 work）；comptime / D088 fast-path 用槽位判别守护住，generic 形式 fall through 到 runtime 路径 | 三处文件联动（parse/checker/gen）；helper 抽取一次 | 假设 H5「parser 单点扩」破裂——chain 路径（`arr[i].field[j]=v`）也要同步处理，否则非对称 | ✓ |
| F | 接口/parser lowering | parser 把 `h.items[0]=v` rewrite 为 `let _t = h.items; _t[0]=v` 两条 stmt | 不改 AST | RC 多一次 retain/release（_t 持有数组 ptr）；改变 stmt 计数 / 行号映射；@ct comptime 路径下 _t 也要 ct 表跟踪；引入临时变量名冲突可能 | 假设 H6「lowering 等价」破裂——临时变量额外 RC + comptime 路径污染，等价但不等效 | ✗ |
| G | 架构/lvalue 子语言 | 起独立 lvalue parsing pass，统一处理 `x` / `obj.field` / `arr[i]` / `obj.field[i]` / 任意嵌套链 | 长期视野最干净 | 大改 parser + checker + 所有 ASSIGN 节点 kind；本轮 scope 爆炸（≥10 文件）；当前 SS 只有 INDEX_ASSIGN / MEMBER_ASSIGN / ASSIGN 三套，未到需要统一的复杂度阈值 | 假设 H7「现在就需要 lvalue 抽象」破裂——三套 ASSIGN 节点对称扩展即可；统一 lvalue 是 N+1 工程 | ✗（远期 §F） |

**选 E 因：根因是 AST 槽位缺失，不是 parser 单点 case 缺失。E 与 MEMBER_ASSIGN（持 I1 obj 表达式 + S1 字段名）形态对称，扩槽位是最小可表达的根因修补；F 用 lowering 绕过 AST 缺口属于工作流 workaround；G 是远期演化目标但本轮 scope 不需要。**

## 跨 Repro 联动

A + E 互不耦合：codegen 修法（A）与 parser 修法（E）打不同层。A 修法对 var-name 形式 `arr[i]=new Item()` 与 obj-expr 形式 `b.items[0]=new Item("y")` 都生效（spike Case 1 + Case 3 同时 GREEN 实证）。

## 假设破裂总览

- H1（class inferType 返 ptr）破裂 → 选 A
- H2（runtime 签名是根因）破裂 → 否 B
- H3（inferType 应擦除 class）破裂 → 否 C
- H4（特例叠加可解决）破裂 → 否 D
- H5（parser 单点修法）破裂 → E 必须 chain + fall-through 双补
- H6（lowering 等价）破裂 → 否 F
- H7（现在就需要 lvalue 子语言）破裂 → 否 G（留远期 §F）
