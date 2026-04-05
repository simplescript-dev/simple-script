# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SimpleScript 是一门**自举的编译型语言**。编译器用 SimpleScript 自身编写（~10800 LOC），编译到 LLVM IR 并静态链接 musl libc + mimalloc，产出原生二进制。**零 C 依赖**——无 runtime.c，所有运行时函数由编译器直接生成为 LLVM IR。

**完全自举**：编译器能编译自己，产出字节级相同的二进制（固定点验证通过）。

**Perceus RC（Phase 1 完成）**：用户自定义 class 实例使用 Perceus 风格引用计数——对象头 RC@0 + TypeInfo@1，每类自动生成 drop/deepClone/shallowClone，PIR 中间层做 liveness 分析自动插入 release。mimalloc 分配器支持 REUSE 优化。

## 构建与测试

```bash
# 编译 .ss 文件
bin/ss build file.ss -o output
bin/ss build file.ss --release -o output    # 优化构建 (-O2 -s)
bin/ss build file.ss --emit-ir              # 输出 LLVM IR

# 运行
bin/ss run file.ss

# 测试（全部 / 单个文件）
bin/ss test tests/
bin/ss test tests/phase2/

# 其他 CLI
bin/ss check file.ss                        # 仅类型检查
bin/ss fmt file.ss                          # 格式化
bin/ss repl                                 # 交互式 REPL
bin/ss new myapp                            # 创建项目（ss.json + src/main.ss）
bin/ss clean                                # 清除构建缓存

# 自举（三阶段固定点验证）
./build.sh bootstrap
# 等价于：seed→stage1→stage2→stage3，验证 stage2==stage3 后更新 bin/ss
```

依赖：`llc-18`（LLVM）、`musl-gcc`（静态链接）、`vendor/mimalloc.o`（自动编译）。

**测试文件格式**：每个 `.ss` 测试是独立程序，包含 `function main()`。通过条件 = 编译成功 + 运行 exit code 0。无断言框架——测试靠"不崩溃"验证。含 `import/` 子目录的测试组只编译 `main.ss`。

## 编译器架构

**完全用 SimpleScript 实现**的五阶段流水线：

```
.ss 源码 → Lexer → Parser (AST) → Checker → PIR (Perceus IR) → Codegen (LLVM IR) → llc + musl-gcc → 静态二进制
                                                    ↑                    ↑
                                gen_pir.ss + pir_lower.ss + pir_opt.ss    gen_runtime.ss + gen_rt_*.ss 生成运行时
                                (lowering → liveness → rc_dec 插入)      prelude.ss 高层 SS 方法
```

### 源码结构

```
bootstrap/            # 编译器源码（全部 .ss 文件，~12800 LOC，35 文件）
  lexer.ss            # 词法分析核心：状态 + tokenize API + token 访问 + 字符串/模板/数字 lexer
  lex_ops.ss          # 多字符运算符 lexer（+= -- => << >>> 等）
  parser.ss           # 语法分析核心：AST 节点系统 + parser state + 声明解析 + helpers
  parse_stmts.ss      # 语句解析：parseStmt dispatcher + 控制流 + 赋值
  parse_exprs.ss      # 表达式解析：优先级爬升 + atoms + 模板字符串 + 参数
  checker.ss          # 语义检查核心：初始化 + scope + 注册表 + 错误报告 + check() 入口
  check_stmts.ss      # 语义检查逻辑：checkStmt/checkExpr dispatcher + return path analysis
  check_suggest.ss    # 语义检查：suggestion 引擎（编辑距离 + 候选名查找）
  codegen.ss          # Codegen 状态管理/初始化/公共 API + IR builder helpers
  gen_registry.ss     # 函数/方法注册表：返回类型、参数数量、默认值、重载、builtin 映射
  gen_rc.ss           # 旧 RC 系统：字符串/数组/Map 的 ss_rc_retain/ss_rc_release
  gen_pir.ss          # Perceus IR 核心：状态 + 访问器 + 类型跟踪 + 分析入口 + schedule 发射 + REUSE 查询
  pir_lower.ss        # PIR 降低：AST→PIR 指令序列 + 表达式扫描
  pir_opt.ss          # PIR 优化：Pass 1 liveness + Pass 2 move + Pass 3 uniqueness + Pass 5 reuse
  gen_stmts.ss        # 语句代码生成：dispatcher + 控制流（if/for/while/switch/try-catch）
  gen_decls.ss        # 声明代码生成：函数声明 + 变量声明 + 全局变量 + return
  gen_assigns.ss      # 赋值代码生成：genMemberAssign + genAssign（直接赋值 + 复合赋值）
  gen_exprs.ss        # 表达式代码生成：dispatcher + binary + ternary + exprAsString
  gen_calls.ss        # 函数调用 + 模板字符串 + 数组字面量
  gen_arrows.ss       # Arrow 函数 + closure：capture analysis + codegen + drop/TypeInfo
  gen_methods.ss      # 方法调用 dispatcher + class 方法 + helpers
  gen_builtins.ss     # 内置方法 handler：string/higher-order/array/map/set
  gen_class.ss        # 类代码生成核心：状态 + 注册 + 继承 + struct/构造函数 + 方法/new/字段
  gen_iface.ss        # 接口派发：registerInterface + switch-based dispatch 函数生成
  gen_generic_class.ss # 泛型类单态化：preRegisterSpecializedClass + genGenericNewExpr + deferred codegen
  gen_type_ops.ss     # 类型操作生成：TypeInfo/drop/clone + vtable + dtor + toJson
  gen_types.ss        # 类型辅助函数
  gen_runtime.ss      # 运行时核心：dispatcher + libc 声明 + globals + helpers + RC 系统
  gen_rt_string.ss    # 运行时：字符串操作 + 类型转换
  gen_rt_array.ss     # 运行时：数组/列表操作
  gen_rt_io.ss        # 运行时：I/O + 进程 + 数学函数
  gen_rt_map.ss       # 运行时：HashMap 操作
  gen_rt_system.ss    # 运行时：文件系统 + 网络 + 异常 + SQLite
  prelude.ss          # 纯 SS 运行时方法（trim/replace/map 等）
  main.ss             # CLI 入口 + import 解析
bin/ss                # 种子编译器二进制（自举用，frozen）
vendor/mimalloc/      # mimalloc v2.2.2 源码（LIFO free-list allocator）
lib/                  # 标准库（json.ss, base64.ss, sha256.ss, http.ss）
tests/                # 测试（mvp/ phase2/ phase3/ phase4/ phase5/）
spec/                 # 语言规范文档
```

### AST 节点系统

节点是 int ID，属性存在全局 Map 中（无 struct/object）：

| Map 变量 | 用途 |
|----------|------|
| `nKind` | 节点类型字符串（`"FUNC_DECL"`, `"BINARY"`, ...） |
| `nStr1/nStr2/nStr3` | 字符串槽位（名称/类型/操作符） |
| `nInt1/nInt2/nInt3/nInt4` | 整数/子节点ID 槽位 |
| `nList` | 子节点ID 列表（逗号分隔字符串 `"3,7,12"`） |
| `nLine/nCol` | 源码位置（行号/列号），`newNode()` 自动捕获，关键节点显式覆盖 |

访问器：`nGetKind(id)`, `nGetS1(id)`, `nSetI1(id, val)`, `nGetLine(id)`, `nGetCol(id)`, `listAppend(list, id)` 等。

**关键节点 slot 约定**：
- `FUNC_DECL`: S1=名称, S2=返回类型, S3=类型参数, List=参数, I1=函数体, I3=access level (0=public, 1=private, 2=protected) (D068), I4=annotations
- `CLASS_DECL`: S1=类名, S2=父类名, List=字段, I2=方法块
- `VAR_DECL`: S1=变量名, S2=CONST/LET, S3=类型标注, I1=初始值
- `PARAM`: S1=参数名, S2=类型, S3="const"（字段级 const 标记）, I1=默认值, I2=isOptional, I3=access level (0=public, 1=private, 2=protected) (D068)
- `BINARY`: S1=操作符, I1=左, I2=右
- `CALL`: S1=被调函数, S2=显式类型参数（逗号分隔，D028）, List=参数
- `NEW_EXPR`: S1=类名, S2=显式类型参数（逗号分隔，D028）, List=参数
- `METHOD_CALL`: S1=方法名, I1=对象表达式, List=参数
- `MEMBER_ASSIGN`: S1=字段名, S2=操作符, I1=对象表达式, I2=值表达式
- `NAMED_ARG`: S1=参数名, I1=值表达式

### Codegen 状态管理

关键全局变量（`codegen.ss`）：

| 变量 | 用途 |
|------|------|
| `irBuf` / `irOutFile` | IR 输出缓冲 / 文件（两种模式） |
| `strConsts` / `strCount` | 字符串常量声明 `@.str.N` |
| `regCount` / `labelCount` | SSA 寄存器 / label 计数器（每函数重置） |
| `varTypes` | `"funcName:varName"` → SS 类型 |
| `varAliases` / `globalAliases` | 局部变量 `x.42` / 全局 `@x` 名称映射 |
| `classFields` / `classFieldTypes` | `"Class"` → 字段列表 / `"Class.field"` → 类型 |
| `classMethods` / `classParents` | 方法列表 / 继承链 |
| `objClasses` | `"func.var"` → 所属类名（追踪对象类型） |
| `funcRetTypes` / `funcParamCount` | 函数返回类型 / 参数数量 |
| `currentFunc` / `currentClassName` | 当前函数 / 类上下文 |

**编译流程**：`resetCodegen()` → `emitRuntimeDefs()` → `registerAllDecls(root)`（首遍注册） → `emitGlobalsAndCode(root)`（生成 IR）

**全局变量初始化**：`let x = Map()` 等全局声明分两阶段——先 `@x = global ptr null`，再在 `main()` 开头通过 `emitGlobalInits()` 调用初始化函数。

### 类型推断

- **`resolveObjClass(nodeId)`**（gen_exprs.ss）：推断表达式的类名，用于方法派发。遍历 `IDENT→varTypes/objClasses`, `THIS→currentClassName`, `NEW_EXPR→S1`, `CALL→funcRetTypes`, `MEMBER_ACCESS→classFieldTypes`。
- **`inferType(id)`**（gen_exprs.ss）：返回 SS 类型字符串（`"int"`, `"string"`, `"double"`, 类名等），用于选择 LLVM 类型和操作。
- **`ssTypeToLLVM(t)`**：`int/bool` → `i32`, `double` → `double`, `string/class/泛型` → `ptr`, `fn` → `i64`

### 类系统内部

- **对象布局**：`{ i32 rc, ptr TypeInfo, ...fields }`。RC 在 offset 0，TypeInfo 在 offset 1，用户字段从 offset 2 开始
- **TypeInfo**：每类一个全局常量 `@ClassName_type_info = { drop_fn, deep_clone_fn, shallow_clone_fn, size, name }`
- **双 RC 系统**：旧系统 `ss_rc_retain/ss_rc_release`（字符串/数组/Map，libc calloc/free）；新系统 `ss_retain/ss_release`（class 实例，mimalloc mi_calloc/mi_free）。`emitRetainForType()`/`emitReleaseForType()` 按类型分派
- **Per-class 生成**：`ss_drop_ClassName`（释放引用字段+dealloc）、`ss_deep_clone_ClassName`（递归克隆）、`ss_shallow_clone_ClassName`（memcpy+retain）
- **Clone 分派**：用户可在 class body 定义 `deepClone()`/`shallowClone()` 覆盖自动生成版本。`classMethodHasName()` 检测用户 override
- **classConstFields Map**：`"ClassName.fieldName" → "1"`，deepClone 据此决定 share（retain）vs recursive clone
- **继承**：字段布局兼容（子类 struct 前缀包含父类所有字段），方法编译时沿 `classParents` 链查找
- **命名规则**：构造函数 `@ClassName_new`，方法 `@ClassName_methodName`
- **函数重载**：mangled 名 `@funcName_paramSig`（`i`=int, `d`=double, `s`=string, `p`=ptr）
- **Arrow 函数**：编译为顶层 `@__arrow_N`，IR 缓存在 `arrowDefs` 中，外层函数结束后 `flushArrowDefs()` 写出

### 运行时生成（gen_runtime.ss + gen_rt_*.ss）

`emitRuntimeDefs()`（gen_runtime.ss）为 dispatcher，调用各子模块生成所有 `ss_*` 函数为 LLVM IR define 块。按职责拆分为 6 个文件：

| 文件 | 职责 |
|------|------|
| `gen_runtime.ss` | dispatcher + libc 声明 + globals + helpers + 双 RC 系统 |
| `gen_rt_string.ss` | 字符串操作（concat/split/indexOf 等）+ 类型转换 |
| `gen_rt_array.ss` | 数组/列表操作（push/slice/concat/sort 等） |
| `gen_rt_io.ss` | I/O（println/readFile 等）+ 进程 + 数学函数 |
| `gen_rt_map.ss` | HashMap（set/get/delete/keys） |
| `gen_rt_system.ss` | 文件系统 + 网络 + 异常（setjmp/longjmp）+ SQLite |

运行时字符串常量用 `@.rt.` 前缀，与用户 `@.str.` 区分。

### Perceus IR (PIR)

PIR 是 AST 与 LLVM IR 之间的中间层，专用于 class 实例的 RC 分析。

- **PIR 节点**：Map-based（与 AST 同架构），`pirKind/pirStr1/pirStr2/pirStr3/pirInt1/pirList`
- **指令集**：`ALLOC`, `RC_INC`, `RC_DEC`, `FIELD_SET`, `FIELD_GET`, `USE`, `CALL`, `MOVE`
- **Opt-in**：`pirAnalyzeFunc()` 检测函数是否含 class 操作，无则跳过
- **Pass 1 Liveness**：反向扫描找 last-use → 在该语句后插入 RC_DEC
- **Schedule 机制**：`pirSchedule[astStmtId] → "var1:type1|var2:type2"`，`genBlock()` 每条 `genStmt()` 后调 `pirEmitScheduled()` 发射 release
- **PIR Map key**：所有 PIR Map 访问用 `id + ""` 将 int 转 string（CRITICAL）

### Import 系统

`resolveImports(filePath)`（main.ss）在解析前递归内联所有导入，生成一个合并的源码字符串。`@/` 解析为项目根路径（向上查找 `ss.json` 或 `bootstrap/`）。prelude.ss 在编译时自动注入到源码前部。

## 添加新语言特性

需要按序修改以下文件：

1. **lexer.ss** — 新 token 类型 / 关键字（加入 `lexIdent()` 分发表）
2. **parser.ss** — `parseXxx()` 函数 + 在 `parseStmt()` 或表达式解析器中加 case + 定义新 AST 节点 kind
3. **checker.ss** — `checkStmt()` / `checkExpr()` 加 case
4. **gen_stmts.ss** 或 **gen_exprs.ss** — `genStmt()` / `genExpr()` + `inferType()` 加 case
5. **gen_runtime.ss** — 若需要新 builtin 函数，添加 `emitIR("define ...")` 块
6. **codegen.ss** `initFuncRetTypes` — 注册新内置方法返回类型

## 命名约定

| 类别 | 模式 | 示例 |
|------|------|------|
| 运行时函数 | `ss_functionName` | `ss_println`, `ss_mapNew` |
| Perceus RC 函数 | `ss_retain/ss_release/ss_alloc/ss_dealloc` | class 实例专用（mimalloc） |
| 旧 RC 函数 | `ss_rc_retain/ss_rc_release` | 字符串/数组/Map 专用（libc） |
| Per-class drop | `ss_drop_ClassName` | `ss_drop_Player` |
| Per-class clone | `ss_deep_clone_ClassName` | `ss_deep_clone_Player` |
| TypeInfo 常量 | `@ClassName_type_info` | `@Player_type_info` |
| Prelude 函数 | `_ss_functionName` | `_ss_trim`, `_ss_replace` |
| 类构造函数 | `@ClassName_new` | `@Dog_new` |
| 类方法 | `@ClassName_methodName` | `@Dog_speak` |
| 重载签名 | `@func_paramSig` | `@add_i_i`, `@process_Node` |
| Arrow 函数 | `@__arrow_N` | `@__arrow_0` |
| 用户字符串常量 | `@.str.N` | `@.str.5` |
| 运行时字符串常量 | `@.rt.str.name` | `@.rt.str.null` |
| Label | `prefix.N` | `if.then.5`, `for.cond.12` |

## 语言特性

- const/let（TypeScript 风格），类型后置 `name: Type`
- function, class/new/this/extends（继承，父类字段/方法链查找）
- **`super` keyword**: `super.method(args)` calls parent class method directly, bypassing vtable (D069)
- **Access modifiers**: `private` (class-only) and `protected` (class + subclasses) keywords for class fields/methods — compile-time access control (D068)
- **Field-level const**: `class Player(const name: string, health: int)` — const 字段构造后不可赋值
- **Field assignment**: `obj.field = value`, `obj.field += value`, 支持嵌套 `a.b.c = v`
- **Named params**: `new Player(name: "Alice", health: 100)`
- **deepClone/shallowClone**: 自动生成，支持用户 override
- **Perceus RC**: class 实例自动引用计数，PIR liveness 分析优化
- **List\<T\>**: Array 的用户侧别名（`List<string>` 等价于 `Array<string>`）
- **Set\<T\>**: Map wrapper（`add`, `has`, `remove`, `size`, `values`）
- **Arrow 函数**: `(x: int): int => x * 2`（编译为顶层函数+函数指针）
- **高阶方法**: `arr.map(fn)`, `arr.filter(fn)`, `arr.reduce(fn, init)`, `arr.forEach(fn)`
- **try/catch/throw**: `try { } catch (e) { }`（setjmp/longjmp 实现）
- **?? 空值合并**: `value ?? "default"`
- **Enum 带值**: `enum Color { Red = 1, Green = 2, Blue = 3 }`
- **泛型类型约束**: `<T extends Interface>`、多约束 `<T extends A & B>`（编译期验证，D031）
- 泛型类型标注: `Array<string>`, `Map<string, int>`, `List<int>`, `Set<string>`
- 模板字符串 `` `${expr}` ``（支持嵌套）
- switch/case, for/for-in/while/do-while, break/continue
- 位运算: &, |, ^, ~, <<, >>, >>>
- 默认参数, 短路 &&/||, 三元表达式
- import { ... } from "./module" 或 "@/lib/module"

## 开发原则

### 第一性原理

- **从原始需求和问题本质出发**，不从惯例或模板出发
- **不要假设用户清楚自己想要什么**：动机或目标不清晰时，停下来讨论
- **目标清晰但路径不是最短的**，直接告知并建议更好的办法
- **遇到问题追根因，不打补丁**：每个决策都要能回答"为什么"
- **输出说重点**，砍掉一切不改变决策的信息

### 语法设计

- **Java/TS 优先**：语法设计优先借鉴 Java 和 TypeScript/JavaScript，不借鉴 Kotlin/Scala 语法（如主构造函数参数、`: Parent` 继承、`val/var` 参数）。任何新语法必须在 TS/JS 或 Java 中有直接对应物，不自创语法形式
- **不加新关键字**：优先复用现有关键字扩展功能，只有现有语法完全无法表达时才考虑新关键字
- **编译器吸收复杂度**：用户不应看到内存管理、类型系统等内部机制的语法暴露

### 问题解决

- **Root Cause 优先**：从根源修复问题，不用临时方案绕过
- **编译器限制是 bug，不是边界条件**：当编译器限制迫使 stdlib 或用户代码使用丑陋 workaround 时，先修编译器。不要记为 "Known limitation" 然后绕过。同一个 workaround 出现第二次就该停下来修根因
- **技术结论必须验证**：不确定就说不确定，不编理由
- **参考最佳实践**：任何设计决策先研究 Go/Rust/Zig/Crystal 等成熟编译器的做法

### 优先级

- **先修后加**：`docs/4-issues/1-open/` 中的 open issues 优先于新功能和 stdlib 模块。不在已知问题（静默产出错误代码、崩溃、强制 workaround）未修复时添加新功能
- **每轮开始先审 open issues**：读 handoff 后先检查 `docs/4-issues/1-open/`，优先处理未被语言能力阻塞的 issue
- **单上下文单任务**：每个对话上下文只处理一个任务（一个 issue fix、一个 feature、一个 refactor）。完成或上下文不足时，更新 handoff 并停止。外部自动化会 clear + `/next` 接力下一轮

### 决策记录与上下文管理

- **设计讨论产出决策 → 立即创建 D 文档**：每个确认的设计决策写入 `docs/3-decisions/D0XX-*.md`，一个决策一个文件。不等到实现完成再补
- **handoff 随时可用**：每完成一个里程碑立即更新 `docs/5-handoff/next-prompt.md`，确保任何时刻被中断都能无缝续接

### 代码质量

- **可读性优先**：不为减少行数牺牲可读性。使用模板字符串 `` `${var}` `` 代替 `+` 拼接
- **单文件不要过大**：超过 500 行考虑拆分
- **最小改动**：只做直接请求的改动
- **删除即删除**：废弃代码直接删掉
- **先读后改**：修改前先读懂现有代码
