# D092: SEMA 架构 — TypedValue + 共享 eval pipeline

**Status:** Accepted（架构层，实现留待后续 phase）
**Depends on:** D088（Zig 路线）
**Date:** 2026-04-15

## 背景

d1816ab 清零双轨制载体（`interp.ss` / `gen_reflect.ss` / `gen_annotations.ss` + `lib/comptime.ss` + `lib/spring/boot.ss` 共 47 tracked 文件 5197 行），`bootstrap/` 遗留 6 文件 243 处死引用（`interpEval` / `interpType` / `isCt` / `ctVal` / `comptimeDepth` 等）。

**clean slate 是有设计的半清零**：

- **删**：`interp.ss` 的 value 创建 / inspection / mutation API（`interpNewInt` / `interpType` / `interpGetField` / `interpClasses` / `interpEnumValues` / `interpFindMethod` / ...）+ `gen_reflect.ss` + `gen_annotations.ss` + `lib/comptime.ss` + `lib/spring/boot.ss`
- **留**：
  - `bootstrap/codegen.ss:21` `let comptimeDepth = 0` — mode flag
  - `bootstrap/codegen.ss:79` `let comptimeConsts = new Map()` — Phase 5 常量绑定表
  - `bootstrap/codegen.ss:118` `function ctVal(interpId: int): int` — tagged-pointer 打标签
  - `bootstrap/codegen.ss:122` `function isCt(v: int): int` — 检测 tagged
  - `bootstrap/codegen.ss:126` `function payload(v: int): int` — 脱标签
  - `bootstrap/gen_exprs.ss:431` `genValCtCall` / `:737` `genValCtNewExpr` / `:788` `genValCtMemberAccess` / `:830` `genValCtMethodCall` / `:973` `genValCtTemplateLit` / `:996` `genValCtArrayLit` / `:1029` `genValCtIndexAccess` — 7 个 comptime dispatcher
  - 所有 `if (comptimeDepth > 0)` 分支（`gen_exprs.ss` / `gen_stmts.ss` / `gen_decls.ss` / `gen_assigns.ss` 约 30+ 处）

**保留的骨架就是半 SEMA 架构的天然形态**：`genExpr` dispatcher 按 AST kind 分发，每个 case 按 mode 选路径，返回 tagged pointer（CT value 的 tvId 或 LLVM 虚拟寄存器字符串）。

D092 **不发明新架构**，只定义 value layer 的填回方式，锁死下一轮"填洞即合并"的路径，禁止再造独立 interp / sema engine。

## 决策

**一份 eval pipeline：AST → TypedValue（comptime）/ LLVM 虚拟寄存器（codegen）→ LLVM IR。**

五条硬约束：

1. **eval 函数 = 现有 `genExpr` / `genStmt`**，不新增 `semaEval` / `comptimeEval` / `constFold` 独立顶层函数
2. **value 层 = TypedValue**，存储在 `bootstrap/codegen.ss` 内部的 Map 体系（与现有 AST Map 对齐），替换被删的 `interp.ss` Map
3. **类型 / class / enum / fn 元数据**通过 AST 节点 ID **直接引用 checker 已有注册表**（`classFields` / `classMethods` / `classParents` / `funcRetTypes` / `enumValues` / ...），TypedValue **禁止**自行存 class layout / method table / function signature（消除双轨制根因）
4. **dispatcher 单一**：`genExpr` / `genStmt` 按 AST kind 分 case，每个 case 内部按 `comptimeDepth` 选 codegen 子路径或 comptime 子路径（复用现有 `genValCt*` helper 命名）
5. **未实现 case = 硬错误**：comptime 路径遇到没有 case 的 AST kind → `println` 位置 + `exit(1)`，禁止静默 `return null` 续跑（继承 D088 §Phase 8 "未知 expression 不再静默断流" 约定）

## TypedValue 结构（架构层）

架构层定义，不给 SS 语法实现，留待后续 phase。

### 字段清单

| 字段 | 语义 | 与 AST / 现有机制的关系 |
|---|---|---|
| `tvId` | TypedValue 实例 ID（Map key，int） | 与 AST 节点 ID **独立编号**，使用独立分配器 `nextTvId` |
| `tvKind` | 值种类标签：`int` / `double` / `string` / `bool` / `null` / `array` / `object` / `fn` / `class` / `enum` / `type` | 替换被删 `interpType(v)` 的返回值 |
| `tvI1` / `tvI2` / `tvI3` | 整数槽（intVal / boolVal / classAstId / fnAstId / enumOrdinal / ...） | 按 `tvKind` 语义化使用，对齐 `nInt1..4` 风格 |
| `tvS1` / `tvS2` | 字符串槽（strVal / typeName / ...） | 对齐 `nStr1..3` 风格 |
| `tvD1` | double 槽 | double value 专用 |
| `tvList` | `Array<int>`（array elements 的 tvId 列表） | 替换 `interpNewArray` / `interpArrayPush` 底层 |
| `tvMap` | `Map<string, int>`（object 字段 name → field 值的 tvId） | 替换 `interpSetField` / `interpGetField` 底层 |

### 与 AST 节点 ID 的关系（关键不变量）

这是"一份 eval"的真正保证——消除双轨制根因：

- 当 `tvKind == "object"` / `"class"` / `"fn"` / `"enum"` 时，TypedValue 的"结构来源" **必须** 通过 AST 节点 ID 指向 checker / gen 已有注册表
- TypedValue **禁止** 自行存储 class layout / method table / field definition list / function signature / enum variant table
- 示例：
  - `tvKind="object"` → `tvI1=classAstNodeId` → 查 `classFields[className]` 拿字段定义 → 查 `tvMap` 拿字段值
  - `tvKind="fn"` → `tvI1=functionAstNodeId` → 查 `funcParams` / `funcRetTypes` 拿签名
  - `tvKind="enum"` → `tvI1=enumAstNodeId` + `tvI2=ordinal` → 查 `enumValues` / `enumNodes`

如果 comptime 路径用和 codegen 路径不同的 class 视图（两份 `classFields`），双轨制立即重生。此约束禁止。

## eval 函数签名

**复用现有 `genExpr(id: int): string` / `genStmt(id: int)`**。D092 不新增 eval 函数。

### 行为按 mode 分支（保留现有骨架）

- `comptimeDepth == 0` → codegen 模式
  - 返回值：LLVM 虚拟寄存器字符串（如 `%r3`）
  - 行为：发射 LLVM IR 指令，修改全局 IR buffer
- `comptimeDepth > 0` → comptime 模式
  - 返回值：tagged pointer（低位=1 表示 CT value，payload 是 tvId）
  - 行为：不发射 IR，构造 TypedValue 并返回

### 返回值编码（继承现状，不改接口）

- `ctVal(tvId)` 打 tag 得到 tagged pointer
- `isCt(v)` 检测 tag
- `payload(v)` 脱 tag 得 tvId
- 这三个 helper 的签名保持不变，只是 `payload` 返回的 id 语义从"interp 内部 value id"变为 "tvId"

### mode 不能泄漏

- dispatcher 入口判一次 `comptimeDepth` 后，下游 case body 通过 TypedValue 交换数据，不再重复判 mode
- 例外：dispatcher 顶层本身需要判 mode 决定走 codegen 子路径还是 comptime 子路径
- case body 内部如需跨 mode 复用逻辑（如字符串拼接），通过 TypedValue 读写 primitive 完成，不直接引用 `comptimeDepth`

### 错误路径

- comptime 模式遇到未实现的 AST kind → `println` 节点 kind + 行列号 + `exit(1)`
- codegen 模式保持现状（fallback 到空字符串允许，因为编译器整体测试覆盖 codegen 路径）
- 这条不对称规则反映 D088 §核心验证问 1 的路线导向：comptime 路径的完备性是路线成功的判据，必须硬报错暴露缺口

## comptime / codegen 共享入口

**入口 = 只有一个：`genExpr` / `genStmt`**。

### 外层进入 comptime 的方式（保留现状）

- `comptime { ... }` 块 → 解析后执行前 `comptimeDepth++`，执行后 `comptimeDepth--`
- 普通代码 → `comptimeDepth == 0` → 走 codegen 分支

### 禁止的入口增补

- 新建 `semaEval(id)` / `comptimeEval(id)` / `constFold(id)` 顶层函数
- 新建 `bootstrap/sema.ss` / `bootstrap/const_eval.ss` / `bootstrap/interp2.ss` 等文件
- 新建 "comptime-parallel dispatcher"（如 `genExpr2(id)` 绕过主 dispatcher）

任何"换名字另起炉灶"都违反 D088 §核心验证问 3 行 287。

**防漂移入口 gate**：下一轮 PR 如创建此类文件，由 PFV §字段 1 对照命令

```bash
ls bootstrap/sema*.ss bootstrap/const_eval*.ss bootstrap/interp*.ss 2>&1
```

立即截住。

### 允许的辅助函数

- `newTvInt(n)` / `newTvString(s)` / `newTvObject(classAstId)` / `newTvArray()` / ...：TypedValue 构造 primitive，**不是** eval dispatcher
- `tvKindOf(tvId)` / `tvIntOf(tvId)` / `tvFieldOf(tvId, name)` / ...：TypedValue 读取 primitive
- 现有 7 个 `genValCt*`：保留作为 dispatcher 的 comptime 分支 case body，**只能被 `genExpr` dispatcher 调用**，不能作为独立入口被其他路径直接 import

## Phase 6-8 在新架构下重定义

原 D088 Phase 6-8 描述的实现路径（基于 `interp.ss` 的 handler 表）已被 d1816ab 清零。新架构下重定义：

### Phase 6：class 在 SEMA 中 eval

- `genValCtNewExpr(id)` 改造：分配新 tvId，`tvKind="object"`，`tvI1=classAstNodeId`，`tvMap` 初始化字段值
- `genValCtMemberAccess(id)` 改造：通过 `classAstNodeId` 查 `classFields` 注册表拿字段定义，通过 `tvMap[name]` 拿字段值
- `genValCtMethodCall(id)` 改造：通过 `classAstNodeId` 查 `classMethods` 拿方法 AST 节点 ID，递归 `genStmt(methodBody)` 在 comptime 模式下求值
- method resolution state 通过新增 `comptimeMethodClassStack: Array<string>` 承载：super 调用时 push 父类名入栈，方法调用返回后 pop（替代被删的 `interpCurrentMethodClass` / `interpLastFoundMethodClass`）
- 验证：`comptime { class Foo { x: int }; const f = new Foo(x: 42); return f.x }` → 42

### Phase 7：enum / try / 闭包 在 SEMA 中 eval

- `ENUM_DECL` 进 dispatcher case：comptime 模式下注册到 checker **已有**的 `enumValues` / `enumTypes` 表（共享，不自建 enum 值表）。**注意**：`enumNodes` 注册表在 clean slate 后缺失于 `codegen.ss` 和 `gen_class.ss`（`codegen.ss:68-69` 只有 `enumValues` / `enumTypes`），下一轮 Execute 必须先新建 `let enumNodes = ""` 注册表（存储 enum AST 节点 ID 列表），然后 dispatcher case 才能通过 `enumAstNodeId` 访问 enum 定义
- `TRY` / `THROW` 进 dispatcher case：comptime 模式下用 codegen.ss 内部的 mode flag 控制异常传播（原 `interpShouldStop` 的变量定义位置从 `interp.ss` 迁到 `codegen.ss`）
- 闭包：`tvKind="fn"`，`tvI1=fnAstId`，`tvMap=捕获的 comptimeConsts 快照`

### Phase 8：解释器 = 完整语言（重新定义）

- 原目标：补完 `interp.ss` 对 SS 语言特性的覆盖度
- 新目标：**`genExpr` / `genStmt` 的每个 AST kind 都有 comptime 分支 case**，缺 case → `exit(1)` 暴露
- 路径：不是"给 `interp.ss` 抄 handler"，而是"在 `genExpr` dispatcher 里补 case"
- 原 D088 §Phase 8 缺失清单的 ✅ 标签（`ac76375` / `e54bb4d` / `9d43bd6` / `690f3f8` / `6e73ae8` / 本轮）代表的是 `interp.ss` 路径的历史实现，在 clean slate 下作废。语言特性（`ENUM_DECL` / destructuring / spread / super）仍然是待办，但实现位置从 `interp.ss` 迁到 `genExpr` dispatcher（本 D092 顺带回写这些标签为 `[-] Blocked, superseded by D092`）

## 死引用洞的填回策略

`bootstrap/` 6 文件 243 处死引用的替换映射：

| 死引用 | 替换策略 |
|---|---|
| `interpNewInt/Double/String/Bool/Null/Val/Array/Map(...)` | 新 TypedValue 构造 primitive `newTvXxx(...)`，实现在 `codegen.ss` |
| `interpType(id)` | `tvKind.getString(id + "")` |
| `interpAsInt/Str/Bool(id)` | `tvI1/tvS1.getXxx(id + "")` |
| `interpGetField/SetField(id, name, val)` | 读写 `tvMap.get(id + "").{get/set}(name, ...)` |
| `interpCollectFields` / `interpCtFieldsArray` | 通过 `classAstNodeId` 查 checker `classFields` 注册表 |
| `interpClasses` / `interpClassParents` / `interpEnumValues` / `interpEnumTypes` / `interpEnumNodes` | **删除**，直接读 checker 的 `classFields` / `classParents` / `enumValues` / `enumTypes` / `enumNodes`（消除双轨制根因）。**`enumNodes` 例外**：clean slate 后 `codegen.ss:68-69` 只有 `enumValues` / `enumTypes`，无 `enumNodes`，下一轮 Execute 必须先在 `codegen.ss` 或 `gen_class.ss` 新建 `let enumNodes = ""` 注册表（存储 enum AST 节点 ID 列表），然后才能替换 `interpEnumNodes` |
| `interpFindMethod` | 通过 `classAstNodeId` 查 `classMethods` 注册表 |
| `interpCompoundOp` / `interpDoubleOp` / `interpIntOp` | `codegen.ss` 内部纯函数（无 state） |
| `interpValEquals` / `interpTruthy` / `interpToStr` | 同上 |
| `interpShouldStop` / `interpBreakFlag` / `interpContinueFlag` | `codegen.ss` 的 comptime mode flag（变量定义位置迁移） |
| `interpGetComptimeIR` / `interpClearComptimeIR` / `interpGetComptimeSS` / `interpClearComptimeSS` | 接口名保留（@comptimeEmit 是 D088 §过渡策略"保留但冻结"），实现搬到 `codegen.ss`，不扩展新语义 |
| `interpVars` / `interpFindScopeKey` / `interpEnsureComptimeRoot` | `comptimeConsts` 承载 top-level 常量；comptime 执行栈的局部变量用新增 `comptimeScopeStack: Array<Map>` 承载；`interpFindScopeKey` 的作用域查找走栈顶向下；`interpEnsureComptimeRoot` 对应栈初始化 |
| `interpReturnFlag` / `interpReturnVal` / `interpCheckLoopExit` | `codegen.ss` 的 `comptimeReturnFlag` / `comptimeReturnVal` / `comptimeLoopExitFlag`，和 `comptimeDepth` 同层定义，控制 comptime 中 return / 循环早退传播 |
| `interpThisVal` | `codegen.ss` 的 comptime this 栈 |
| `interpCurrentMethodClass` / `interpLastFoundMethodClass` | `codegen.ss` 的 `comptimeMethodClassStack: Array<string>`，super 调用时 push 父类名入栈，方法调用返回后 pop |
| `interpBuildTypeInfo` | 通过 AST 节点 ID 查 checker 类型元数据，返回 `tvKind="type"` 的 TypedValue |
| `interpMapSet` / `interpMapGet` / `interpMapHas` / `interpMapDelete` / `interpMapGetKeys` / `interpMapGetSize` | 在 `genValCtMethodCall` 当 `tvKind="object"` 且 `classId` 对应 Map 时 dispatch 到 `tvMap` 读写，返回 `tvKind="array"`（keys）/ `"int"`（size）/ `"bool"`（has）的新 TypedValue |

### 填洞顺序

高阶大纲。详细 Phase 清单 + LOC 估算 + bootstrap 可验证状态见下 `## Q1 跨线路径`。

1. 在 `codegen.ss` 新增 TypedValue Map 体系（`tvKind` / `tvI1..3` / `tvS1..2` / `tvD1` / `tvList` / `tvMap` / `nextTvId`）+ `newTvXxx` 构造 primitive
2. 逐文件替换 `interpXxx` 调用（建议顺序：`codegen.ss` → `gen_exprs.ss` → `gen_stmts.ss` → `gen_decls.ss` → `gen_assigns.ss` → `gen_types.ss`），每批次后 `./build.sh bootstrap` 固定点验证
3. Phase 6 验证例子跑通 → Phase 7 → Phase 8 case 完备性巡检

## Q1 跨线路径

D088 §核心验证 Q1（"有新 SS 语法能在 comptime 里跑了吗"）对应的具体 Phase 清单与 LOC 估算。`feat/d092-sema-q1` 分支多 commit PR 的完整时间线：整体跨 Q1 前不合并 `dev`，Phase 之间每个 commit 独立过 PFV。

### 基线数据（2026-04-15 feat HEAD 90133f2 采样）

- **56 个独立 interp\* 函数名**散落在 `bootstrap/` 7 文件（`grep -roE "interp[A-Z][A-Za-z]+" bootstrap/ | sort -u`）
- **492 次 interp\* 调用点**（同 grep，不去重）
- bootstrap baseline = `aborting due to 448 errors` "undefined function"（d1816ab clean slate 遗产）
- D092 `§死引用洞的填回策略` 表覆盖 **51 函数** → **缺 5 个未覆盖**：`interpArrayPush` / `interpGetReturnFlag` / `interpGetReturnVal` / `interpId` / `interpValId`（Phase 7 或 Phase 2 合并补表）

### Phase 清单

| # | Phase | 内容概要 | LOC 估算 | bootstrap 状态 | 跨 Q1 |
|---|---|---|---|---|---|
| **0** | TypedValue 存储层 | 11 全局 + `initTypedValue` + `allocTv` + 6 构造 primitive | ~74（**已落** 90133f2） | ❌ baseline 448 RED | ❌ |
| 1 | TypedValue getter/accessor primitive | `tvKindOf` / `tvIntOf` / `tvStringOf` / `tvBoolOf` / `tvFieldGet` / `tvFieldSet` / `tvArrayPush` / `tvArrayAt` / `tvArrayLen` / `tvKeys` / `tvHas` / `tvSize` | ~80 | ❌ baseline 仍 RED（accessor 不接 callers） | ❌ |
| 2 | 填洞批 A（纯函数 + 控制 flag） | `interpType` / `AsInt` / `AsStr` / `AsBool` / `Truthy` / `ToStr` / `ValEquals` / `IntOp` / `DoubleOp` / `CompoundOp` + `Break` / `Continue` / `Return` / `CheckLoopExit` / `ShouldStop` flag → codegen.ss 内部函数/全局 + 跨文件 callsite 替换 | ~120 迁移 + ~200 callsite | ❓ 部分文件 GREEN（按 `codegen.ss → gen_exprs.ss → gen_stmts.ss → gen_decls.ss → gen_assigns.ss → gen_types.ss` 批次验证，看错误总数是否下降） | ❌ |
| 3 | 填洞批 B（value 构造/读写） | `interpNewInt` / `Double` / `String` / `Bool` / `Null` / `Val` / `Array` / `Map` + `interpGetField` / `SetField` → 直接转到 Phase 0+1 primitive | ~300 callsite | ❓ | ❌ |
| 4 | 填洞批 C（checker 注册表直读） | `interpClasses` / `ClassParents` / `EnumValues` / `EnumTypes` / `EnumNodes` / `CollectFields` / `CtFieldsArray` / `FindMethod` → 改读 `classFields` / `classParents` / `enumValues` / `enumTypes` / `classMethods`；**新建 `enumNodes` 注册表** | ~80 新 `enumNodes` + ~150 callsite | ❓ | ❌ |
| 5 | 填洞批 D（作用域/栈/this） | `interpVars` / `FindScopeKey` / `EnsureComptimeRoot` → `comptimeScopeStack`；`interpThisVal` → comptime this 栈；`interpCurrentMethodClass` / `LastFoundMethodClass` → `comptimeMethodClassStack` | ~100 + ~120 callsite | ❓ | ❌ |
| 6 | 填洞批 E（@comptimeEmit + Map builtin） | `interpGetComptimeIR` / `ClearComptimeIR` / `GetComptimeSS` / `ClearComptimeSS` → codegen.ss 函数（接口冻结）；Map builtin dispatch 在 `genValCtMethodCall` | ~60 + ~60 callsite | ❓ | ❌ |
| 7 | 未覆盖 5 函数补填 | `interpArrayPush` / `GetReturnFlag` / `GetReturnVal` / `Id` / `ValId` 补填洞策略表 + callsite 替换 | ~40 + ~40 callsite | ❓ | ❌ |
| 8 | `genExpr` / `genStmt` comptime dispatcher case 完备化 | LIT / IDENT / BINOP / UNOP / CALL / FIELD_GET / FIELD_SET / NEW / ARRAY / IF / WHILE / FOR / BLOCK / RETURN 各加 comptime case 分支，确保 `tvKind=*` 可正确产出 | ~200（分布到 `genExpr` / `genStmt`） | ✅ **baseline GREEN**（填洞完成 + dispatcher 到位，首次跑完整 `./build.sh bootstrap` 固定点） | ❌ |
| 9 | Q1 最小例子 + 测试 | `tests/comptime/hello.ss`：`@comptime const x = 1 + 2; print(x)` + 断言 + 可能少量 dispatcher bug 修复 | ~30 测试 + ~50 修 bug | ✅ 固定点 GREEN + test pass | ✅ **跨 Q1** |

**总增量估算**：~1600 行代码修改（~950 新代码 + ~650 callsite 替换）+ ~30 行测试。

### 设计原则

1. **每 Phase 一个 commit**，独立过 PFV（开工 PSM + 收工 VCM + simplify），commit 信息标明 `feat: D092 Phase N — ...`
2. **Phase 0-7 允许 baseline RED**（填洞未完，bootstrap 无法 GREEN），仅用 grep 间接证据：
   - "零新错误"（Phase 增量符号不出现在 error 输出）
   - "错误总数单调下降"（每 Phase 完成后 `aborting due to N errors` 的 N 必须严格小于上一 Phase）
3. **Phase 8 是 GREEN 转折点**：dispatcher case 完成后 baseline 必须 GREEN，首次跑完整 bootstrap 固定点验证
4. **Phase 9 是 Q1 跨线**：包含最小 comptime 测试例，测试 pass = Q1 通过 = feat 分支 merge `dev`
5. **偏差处理**：某 Phase 实际 LOC 超估算 50% 以上 → 停下回 `## Q1 跨线路径` 章节校准，不硬推
6. **错误总数单调下降保证**：若某 Phase 结束 `grep "aborting due to"` 的数字未下降，视为 Phase 失败，回滚 commit

### 前置假设

- 56 独立函数 / 492 refs 是 2026-04-15 feat HEAD 90133f2 的采样值，实施时需在 PSM 字段 3 RED 重新采样
- `§死引用洞的填回策略` 表需 Phase 7 补 5 个未覆盖函数映射（或在 Phase 2 合并补入相应批次）
- Phase 2-7 的 "bootstrap 部分 GREEN" 取决于 callsite 替换的文件粒度——每完成一个文件跑一次 bootstrap，看错误数下降
- Phase 8 dispatcher case 完备化可能触发 checker 注册表不一致 bug（如 `tvKind="fn"` 需 `funcParams` / `funcRetTypes` 但 checker 未锁 fn AST ID）——若发现，回 Plan 插入 Phase 8.5
- 若 Phase 5（作用域栈）与 Phase 6（@comptimeEmit）涉及已删除的控制流不变量（`interpShouldStop` → `comptimeDepth` 联动），实施时需回 D088 §过渡策略核对

### Q1 定义锚定

D088 §核心验证 Q1 原文："有新 SS 语法能在 comptime 里跑了吗"。本 Plan 的"最小例子"取：

```ss
@comptime const x = 1 + 2
function main() {
    print(x)
}
```

覆盖维度：
- comptime 常量折叠（`1 + 2`）→ TypedValue `tvKind="int"` + `tvIntOf` 读取
- comptime 结果写入 codegen 全局常量（`x`）→ CT value 降级为 LLVM i32 字面量 `3`
- 运行期无计算 → 二进制 printf 输出 `3\n`

**通过条件**：编译成功 + 运行 exit 0 + stdout 匹配 `3\n` + `./build.sh bootstrap` 固定点通过。

### 与 D088 §核心验证的对应

| D088 问 | Q1 跨线后答案 |
|---|---|
| Q1 "有新 SS 语法能在 comptime 里跑了吗" | **是**（Phase 9 最小例子通过） |
| Q2 "根 vs 表面" | **根**（TypedValue 是 Zig Sema `Value` 的同构物，不是 shim） |
| Q3 "是 Zig 式 SEMA 架构吗" | **是**（单一 `genExpr`/`genStmt` + TypedValue + checker 共享注册表，由 Phase 8 的 dispatcher case 统一落实） |

## 拒绝方案对比

| 方案 | 通过 §核心验证问 3 | 通过 §反模式 | 拒绝理由 |
|---|---|---|---|
| (a) 复活 `interp.ss` + 共享接口层 | No | No | 两份 value 存储（`interp.ss` Map + checker Map）= 双轨制根因；等于回到 d1816ab 之前 |
| (b) 新建 `bootstrap/sema.ss` 独立 engine | No | No | "换名字另起炉灶"，§核心验证问 3 行 287 明确禁止 |
| (c) AST 直接 eval，不要 TypedValue 中间层 | No | — | 没有 value 结构 → comptime 返回值无载体 → 复合值（object / array / fn / enum）无法表达 → Phase 6-8 无法推进 |
| (d) 另写 const-folder（限定 const 表达式） | No | — | Phase 6-8 要求 comptime 执行**任意** SS 代码；const folder 是真子集，不是替代 |
| **(e) Zig 式统一 eval（本方案）** | **Yes** | **Yes** | 一份 eval（`genExpr` / `genStmt`），一份 value（TypedValue），和 checker 共享 class / fn / enum 注册表 |

## 隐藏假设挑战

### (i) TypedValue 能同时承载 comptime 值和 codegen 输入吗？

**答：是。** 现有 `ctVal` / `isCt` / `payload` 的 tagged pointer 编码已经证明"同一返回值既可以是 CT value 也可以是 LLVM 寄存器字符串"，两者通过低位 tag 区分。TypedValue 是 CT value 的新存储载体，codegen 路径仍然返回寄存器字符串。这不是"同一值承载两种语义"，而是"同一函数的两种返回模式"，和 Zig Sema 的 comptime-known 值内联 vs AIR 指令引用同构。**假设成立，有现成机制支撑。**

### (ii) 一份函数双 mode 的复杂度会不会超过维护能力？

**答：风险真实，但可控。** 现状 `gen_exprs.ss` 约 1300 行，comptime 分支占约 1/3。SEMA 架构下 Phase 6-8 会增加 case，可能再加 30-50%。缓解策略：

- `genExpr` dispatcher 只分发，每个 case body delegate 到 helper（现有 `genValCt*` 命名保留）
- 每个 helper ≤ 50 行，遵守 principles.md §P6 "分发器只分发"
- 超限立即触发 DI 风格二次拆分（参考 DI-1 / DI-5 经验）

**假设在 P6 约束下成立。** 若下一轮实际落地时 `gen_exprs.ss` 单文件超 2000 行，D092 允许按 case 类别拆子文件（如 `gen_exprs_class.ss` / `gen_exprs_enum.ss`），但**必须**保证所有子文件的 comptime / codegen 双路径由主 `genExpr` dispatcher 统一调度，不允许子文件有独立入口。

### (iii) Zig SEMA 是否 Zig 特有产物？"类型一等值"是 SS 可以不要的前提吗？

**答：Zig SEMA 的核心是"comptime 和 codegen 走同一份 eval"，不依赖"类型一等值"。** "类型一等值"是 Zig 在 SEMA 上构建的**具体语言特性**，不是 SEMA 的必要条件。D088 §Phase 8 路线修正（行 228-232）已明确：原 Phase 9 "类型作为 comptime 值"暂缓，SS 不承诺此特性。

D092 **锁架构不锁语言特性**。Zig 的根（一份 eval）可以抄，Zig 的具体语法特性（`@Type` / `@typeInfo` / comptime 参数）不必抄。**假设成立。**

### (iv) d1816ab 的"半清零"留下的骨架是否足够作为回填基础？

**答：grep 已确认骨架完整。**

- `codegen.ss:118/122/126` (`ctVal` / `isCt` / `payload`) — tagged-pointer 编码层
- `codegen.ss:21/79/483/496` (`comptimeDepth` / `comptimeConsts` + 初始化) — mode flag + 常量绑定
- `gen_exprs.ss:431/737/788/830/973/996/1029` — 7 个 `genValCt*` dispatcher 函数
- 30+ 处 `if (comptimeDepth > 0)` 分支散布在 `gen_*.ss`

骨架完整，只缺 value layer 实现。d1816ab commit message 明确 "bin/ss 保留，跑旧测试可验证语言身份部分未损伤"，证明 clean slate 是**设计过的半清零**，不是误删。**假设成立。**

## 不做的事

- 不在本 D092 写 SS 代码（Plan 型，Q2=a 架构层）
- 不实现 TypedValue Map 体系（留给下一轮）
- 不承诺"类型一等值"作为 SS 语言特性
- 不修改 D088 §第一性需求 / §决策 / §Phase 5 / §核心验证问 1-3 / §反模式 / §正模式（D088 这些段落仍然权威）
- 不修改 D001-D091 其他 D 文档
- 不恢复 d1816ab 删除的文件
- 不触碰 `CLAUDE.md` / `principles.md` / `axioms.md`

## 与 D088 的同步（本轮顺带回写）

按本轮 Q1=A，顺带回写 D088 §Phase 8 缺失清单（行 202-210）：

| 原标签（interp.ss 实现历史） | 回写为 |
|---|---|
| ✅ ac76375（ENUM_DECL） | `[-] Blocked at d1816ab, superseded by D092` |
| ✅ e54bb4d（destructuring array） | `[-] Blocked at d1816ab, superseded by D092` |
| ✅ 9d43bd6（destructuring object） | `[-] Blocked at d1816ab, superseded by D092` |
| ✅ 690f3f8（spread array lit） | `[-] Blocked at d1816ab, superseded by D092` |
| ✅ 6e73ae8（spread call args） | `[-] Blocked at d1816ab, superseded by D092` |
| ✅ 本轮（super） | `[-] Blocked at d1816ab, superseded by D092` |

理由：这些 commit 的实现位于 d1816ab 已删的 `interp.ss` 等文件，D088 标签当前与代码现状漂移。按 principles.md §P19 + §PFV 字段 1 D 文档 grep 对照规则，必须回写。

D088 §第一性需求 / §决策 / §Phase 5 `[x] Done` / §路线修正段落 / §借鉴来源 / §方案对标 / §不做的事 / §参考 不变。

## 验证标准

D092 本身的验证 = 下一轮填死引用洞时能否通过 D088 §核心验证三问：

1. **"有新 SS 语法能在 `comptime {}` 里跑了吗"** → 填 Phase 6 case 后跑 `comptime { class Foo { x: int }; const f = new Foo(x: 42); return f.x }` → 能跑 → 通过
2. **"是从根儿上走 Zig 路线吗"** → 不新建 `interp*.ss` / `sema.ss` / `const_eval.ss` 文件，在保留的 `genValCt*` 骨架里填 → 通过
3. **"是 Zig 式 SEMA 架构吗"** → 一份 `genExpr` + 一份 TypedValue + 共享 checker 注册表 → 通过

下一轮 PR 如无法逐条回答"是"，D092 约束失效，必须回到 D092 修订。

## 参考

- `docs/3-decisions/D088-comptime-zig-route.md:284-288` — §核心验证问 3（Zig 式 SEMA 定义）
- d1816ab commit — "reset: 删除双轨制 comptime 遗产 — clean slate for Zig 路线"
- `CLAUDE.md` §关键不变量 — "AST 节点是 int ID，所有属性存全局 Map"
- `docs/2-principles.md` §P6 分发器只分发 / §P19 D 文档状态标注 / §PFV 流程 §字段 1 D 文档 grep 对照
- Zig `src/Sema.zig`（架构参考，不抄具体语法）
