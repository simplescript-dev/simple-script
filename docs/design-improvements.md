# SimpleScript 编译器设计改进清单

> 基于 2026-03-30 架构审计 + 成熟编译器（Go/Rust/Zig/Swift）最佳实践对比。
> 与 design-issues.md（具体 bug）不同，本文档聚焦**架构级设计问题**。

## 总览

编译器 ~8,700 LOC，分 9 个 .ss 文件。核心问题：**单体过程式架构 + 全局状态耦合**。
当前可工作，但每加一个新特性，修改范围和出 bug 概率都在非线性增长。

---

## 🔴 P0 — 基础架构问题（阻碍后续所有改进）

### DI-1: God Functions — 巨型函数 ✅ (2026-03-30)

**现状**：6 个 100+ 行函数，最大 184 行，80+ if 分支。

| 函数 | 文件 | 行数 | 职责数 |
|------|------|------|--------|
| `genBinary()` | gen_exprs.ss | 184 | 5+（字符串拼接/比较/空合并/短路/算术） |
| `genCall()` | gen_exprs.ss | 140 | 4（重载解析/直接调用/间接调用/builtin） |
| `genMethodCall()` | gen_exprs.ss | 125 | 4（string/array/map/class 方法） |
| `genClassDecl()` | gen_class.ss | 139 | 4（vtable/构造器/析构器/字段初始化） |
| `genExpr()` | gen_exprs.ss | 107 | 30+（所有表达式类型的分发） |
| `genStmt()` | gen_stmts.ss | 114 | 20+（所有语句类型的分发） |

**问题**：无法单独理解/测试/修改任何一个子功能。改字符串拼接可能顺带搞坏算术。

**最佳实践**：
- **Go compiler**: 每个 operator 一个 handler 函数，dispatch table 只做分发
- **Rust compiler**: 每个 ExprKind variant 对应一个 `check_expr_*` 函数
- **原则**: 分发器只分发，不含业务逻辑。每个 handler ≤50 行。

**改进方案**：
1. `genBinary()` → `genBinaryArith()`, `genBinaryStringConcat()`, `genBinaryStringCmp()`, `genBinaryNullCoalesce()`, `genBinaryShortCircuit()`
2. `genCall()` → `resolveOverload()`, `genDirectCall()`, `genIndirectCall()`, `genBuiltinCall()`
3. `genClassDecl()` → `emitClassStruct()`, `emitClassConstructor()`, `emitClassVtable()`, `emitClassDestructor()`
4. `genExpr()`/`genStmt()` → 每个 case 提取为 `genXxxExpr()`/`genXxxStmt()` 独立函数

**约束**：纯重构，不改行为。每拆一个函数跑一次 bootstrap 验证。

---

### DI-2: 全局可变状态泛滥 — 55+ 个全局 let

**现状**：codegen.ss 30+, gen_exprs.ss 10+, gen_stmts.ss 10+, parser.ss 9 个 AST Map。所有函数直接读写全局状态。

**问题**：
- 改一个全局变量的结构需要 grep 所有文件找用法
- 无法对任何函数做隔离测试
- `resetCodegen()` 已经遗漏过变量重置（design-issues #13）
- 编译器不可能支持并行编译

**最佳实践**：
- **Go compiler**: `ssagen.state` struct 封装所有 codegen 状态
- **Rust compiler**: `TyCtxt` 上下文对象贯穿全程
- **Zig compiler**: `Compilation` struct 持有所有状态

**改进方案**：
> ⚠️ 目前 SS 无 struct，全局 Map 是唯一的状态聚合方式。等 struct 支持后再做大规模重构。
> **短期**: 将相关全局变量分组为 Map（如 `rcState`, `codegenCtx`），减少裸全局数量。
> **长期**: 引入 struct 后，将 Map 升级为 struct 实例。

---

### DI-3: 类型系统 = 字符串比较

**现状**：类型用裸字符串表示 `"int"`, `"string"`, `"ptr"`, `"Array<int>"`, `"Map<string,int>"`。

**问题**：
- `inferType()` 对未知变量默认返回 `"int"`（已修复为 exit，但说明类型系统脆弱）
- 泛型解析靠手写 `indexOf("<")` + `substring()` — 嵌套泛型如 `Map<string, Array<int>>` 解析困难
- 无 nullable 类型（`string?` vs `string`）
- 无联合类型
- 无类型别名
- 运行时类型（`i32`, `ptr`）和语义类型（`int`, `string`）混用

**最佳实践**：
- **Go compiler**: `types.Type` interface — `*types.Basic`, `*types.Pointer`, `*types.Struct` 等
- **Rust compiler**: `ty::TyKind` enum — `Int`, `Str`, `Ref(ty)`, `Adt(def, substs)` 等
- **TypeScript compiler**: `Type` 对象，带 `flags`, `symbol`, `typeArguments`

**改进方案**：
> ⚠️ SS 没有 enum 值类型（enum 只是整数常量），无法实现 tagged union。
> **短期**: 类型仍为字符串，但统一格式和解析——引入 `TypeInfo` 概念（Map 存 kind/base/params）。
> **长期**: 等 SS 支持 enum + struct 后，改为结构化类型系统。

---

## 🟠 P1 — 高危架构问题

### DI-4: 缺少独立的语义分析阶段 — Phase 1 ✅ (2026-03-30)

**现状**：`Lexer → Parser → Checker → 直接 Codegen`

checker.ss 检查：
- 未定义变量/函数
- const 重赋值
- ✅ 函数参数数量（Phase 1, 2026-03-30）

**Phase 1 完成方案**：
- 新增 `funcParamMin`/`funcParamMax` 双 Map 追踪每个函数的最少/最多参数数
- Pass 1 注册 FUNC_DECL 时统计必选参数（无默认值且非 `?`）和总参数数
- 重载函数取并集区间 `[min(all_min), max(all_max)]`（宽松策略，避免假阳性）
- 24 个内置函数按参数数量分组注册（0/1/2 参数）
- CALL 节点检查：实际参数数量超出 `[minArgs, maxArgs]` 范围时报错
- 附带修复：补充 TRY/THROW 节点遍历（try/catch 块内代码此前不被检查）
- 检查范围：仅 CALL 节点（METHOD_CALL/NEW_EXPR 需类型推断，留给 Phase 3+）

**不检查**（由 codegen 运行时发现或静默产出错误代码）：
- 函数参数类型匹配
- 返回类型一致性
- 赋值类型兼容性
- 字段类型不匹配
- 所有控制路径是否有 return

**最佳实践**：
- **Go compiler**: `cmd/compile/internal/typecheck` — 独立 pass，前向声明两遍扫描
- **Rust compiler**: `rustc_hir_typeck` — 独立 crate，基于约束的类型推断
- **Zig compiler**: `Sema` — 语义分析是最大的模块

**后续改进方案**：
1. ~~**Phase 1**: checker.ss 增加函数参数数量检查~~ ✅
2. **Phase 2**: checker.ss 增加返回路径分析（每个非 void 函数所有路径必须 return）
3. **Phase 3**: checker.ss 增加基础类型检查（赋值、参数类型匹配 + METHOD_CALL/NEW_EXPR 参数数量）
4. **Phase 4**: 将 `inferType()` 从 gen_exprs.ss 迁移到 checker.ss，变成前置 pass

---

### DI-5: 内置方法签名硬编码为字符串列表 ✅ (2026-03-30)

**原问题**：`inferType()` 和 `callReturnType()` 中有 8 个硬编码字符串列表（intMethods/strMethods/ptrMethods/strFns/voidFns/intFns/dblFns/i64Fns），加方法要更新 3 处，漏掉一处 = silent bug。

**完成方案**：
- 35 个内置函数注册到 `funcRetTypes`（codegen.ss `initFuncRetTypes()`）
- 32 个内置方法注册到新 `methodRetTypes` Map（同一函数初始化）
- `callReturnType()` 从 19 行简化为 4 行（只查 registry + 默认值）
- `inferType()` METHOD_CALL 从 9 行硬编码简化为 3 行 registry 查询
- 新增方法只需在 `initFuncRetTypes()` 一处添加，消除分散更新风险

---

### DI-6: 错误报告极弱

**现状**：
```ss
println("parse error at line " + line + ": expected " + kind)
exit(1)  // 第一个错误就终止
```

**问题**：
- 无列号
- 无源码上下文（不显示出错的那行代码）
- 第一个错误就 exit(1)，无法收集多个错误
- 无 "did you mean ...?" 建议
- 无错误码（用户无法搜索）

**最佳实践**：
- **Rust**: 彩色错误 + 源码片段 + `^^^` 标注 + 修复建议
- **Elm**: 友好的全段错误描述
- **Go**: 简洁但精确的 `file:line:col: error` 格式

**改进方案**：
1. **Phase 1**: AST 节点记录 line/col（parser 创建节点时存储）
2. **Phase 2**: 统一错误报告函数 `reportError(msg, line, col)`，带源码行显示
3. **Phase 3**: 错误收集模式（不立即 exit，收集后统一报告）
4. **Phase 4**: 常见错误的 "did you mean" 建议（编辑距离）

---

### DI-7: RC 逻辑散落在 codegen 各处

**现状**：RC 相关代码分布在 gen_exprs.ss (~200行)、gen_stmts.ss (6个全局变量 + ~150行)、gen_class.ss (~100行)。

**问题**：
- retain/release 调用与业务 codegen 交织，难以审查 RC 正确性
- 改 RC 策略（如加 weak ref）需要改 3 个文件 20+ 个函数
- 无法单独验证 RC 逻辑

**最佳实践**：
- **Swift compiler**: ARC 是独立的 SIL pass（`ARCOptimization/`），在 codegen 之后运行
- **Lobster**: 编译期 RC 插入是独立 pass

**改进方案**：
> ⚠️ 完全独立 pass 需要中间 IR，目前不现实。
> **短期**: 将 RC 辅助函数集中到一个文件（`gen_rc.ss`），codegen 只调接口不管实现。
> **长期**: 引入 SSA-level 中间表示后，RC 变成独立 transform pass。

---

## 🟡 P2 — 中优先级

### DI-8: AST 子节点列表用逗号分隔字符串

**现状**：`nList` Map 存 `"12,45,89"` 字符串。遍历需要 `split(",")` + 循环解析。
Parser 中手动拼接 50+ 处。

**改进方案**：已有 `listAppend()` 辅助函数。统一使用，消除手动拼接。

---

### DI-9: Parser 无运算符优先级表

**现状**：优先级硬编码在递归下降函数嵌套中：
```
parseTernary → parseNullCoalesce → parseOr → parseAnd → parseBitOr →
parseBitXor → parseBitAnd → parseEquality → parseComparison →
parseShift → parseAdditive → parseMultiplicative → parseUnary → parsePostfix
```

**改进方案**：引入 Pratt parser 或优先级表。但当前方式也能工作，优先级低。

---

### DI-10: gen_runtime.ss 2000+ 行纯 IR 文本

**现状**：手写 LLVM IR 字符串，无抽象层。

**问题**：
- 一个字符错误就产出无效 IR
- 无法复用模式（每次都手写 alloca/load/store/GEP）
- 修改一个运行时函数要读几十行 emitIR

**改进方案**：引入 IR builder 辅助函数（`emitAlloca()`, `emitLoad()`, `emitStore()`, `emitGEP()` 等），减少手写 IR。但优先级低于其他问题。

---

## 改进顺序建议

每次改进必须通过三阶段 bootstrap 固定点验证。

| 优先级 | 编号 | 改进 | 理由 |
|--------|------|------|------|
| **1** | DI-1 | 拆分 God Functions | 纯重构，零风险，为后续改进铺路 |
| **2** | DI-5 | 统一方法签名注册 | 小改动，大收益，消除 silent bug 源 |
| **3** | DI-4 | 增强 checker (Phase 1 ✅) | 渐进式，每个 phase 独立可验证 |
| **4** | DI-7 | RC 逻辑集中化 | 为 Phase 9 cycle detection 铺路 |
| **5** | DI-6 | 改进错误报告 | 用户体验，但不阻塞功能开发 |
| **6** | DI-2 | 全局状态分组 | 等 struct 支持后做 |
| **7** | DI-3 | 类型系统结构化 | 等 enum + struct 后做 |

---

## 约束与原则

1. **自举不能断**: 每步改完必须 `./build.sh bootstrap` 通过
2. **最小改动**: 一次只改一个文件的一个函数，不搞大爆炸重构
3. **行为不变**: 纯重构阶段不加新功能、不改已有行为
4. **先测后改**: 确认现有测试全通过后再动手
5. **参考最佳实践**: 改之前看 Go/Rust/Zig 怎么做的
