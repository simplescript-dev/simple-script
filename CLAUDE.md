# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SimpleScript 是一门**自举的编译型语言**。编译器用 SimpleScript 自身编写（~7400 LOC），编译到 LLVM IR 并静态链接 musl libc，产出原生二进制。**零 C 依赖**——无 runtime.c，所有运行时函数由编译器直接生成为 LLVM IR。

**完全自举**：编译器能编译自己，产出字节级相同的二进制（固定点验证通过）。

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

依赖：`llc-18`（LLVM）、`musl-gcc`（静态链接）。

**测试文件格式**：每个 `.ss` 测试是独立程序，包含 `function main()`。通过条件 = 编译成功 + 运行 exit code 0。无断言框架——测试靠"不崩溃"验证。含 `import/` 子目录的测试组只编译 `main.ss`。

## 编译器架构

**完全用 SimpleScript 实现**的四阶段流水线：

```
.ss 源码 → Lexer → Parser (AST) → Codegen (LLVM IR) → llc + musl-gcc → 静态二进制
                                      ↑
               gen_runtime.ss 生成运行时 define 块（直接调 libc）
               prelude.ss 提供高层 SS 实现（trim/replace/map 等）
```

### 源码结构

```
bootstrap/            # 编译器源码（全部 .ss 文件，~8800 LOC）
  lexer.ss            # 词法分析
  parser.ss           # 语法分析，Map-based AST
  checker.ss          # 类型检查（未定义变量、const 重赋值）
  codegen.ss          # Codegen 状态管理/初始化/公共 API
  gen_rc.ss           # 引用计数：状态/作用域追踪/释放/循环检测
  gen_stmts.ss        # 语句代码生成
  gen_exprs.ss        # 表达式代码生成 + 类型推断（inferType/resolveObjClass）
  gen_class.ss        # 类/继承代码生成
  gen_runtime.ss      # 运行时 LLVM IR 生成 — 替代 runtime.c
  prelude.ss          # 纯 SS 运行时方法（trim/replace/map 等）
  main.ss             # CLI 入口 + import 解析
bin/ss                # 种子编译器二进制（自举用）
lib/                  # 标准库（json.ss, base64.ss, sha256.ss, http.ss）
tests/                # 测试（mvp/ phase2/ phase3/ phase4/）
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

访问器：`nGetKind(id)`, `nGetS1(id)`, `nSetI1(id, val)`, `listAppend(list, id)` 等。

**关键节点 slot 约定**：
- `FUNC_DECL`: S1=名称, S2=返回类型, List=参数, I1=函数体
- `CLASS_DECL`: S1=类名, S2=父类名, List=字段, I2=方法块
- `VAR_DECL`: S1=变量名, S2=CONST/LET, S3=类型标注, I1=初始值
- `BINARY`: S1=操作符, I1=左, I2=右
- `CALL`: S1=被调函数, List=参数
- `METHOD_CALL`: S1=方法名, I1=对象表达式, List=参数

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

- **无 vtable**：继承通过字段布局兼容实现（子类 struct 前缀包含父类所有字段），方法在编译时沿 `classParents` 链查找
- **命名规则**：构造函数 `@ClassName_new`，方法 `@ClassName_methodName`
- **函数重载**：mangled 名 `@funcName_paramSig`（`i`=int, `d`=double, `s`=string, `p`=ptr）
- **Arrow 函数**：编译为顶层 `@__arrow_N`，IR 缓存在 `arrowDefs` 中，外层函数结束后 `flushArrowDefs()` 写出

### 运行时生成（gen_runtime.ss）

`emitRuntimeDefs()` 生成所有 `ss_*` 函数为 LLVM IR define 块，直接调 libc。按职责分为：`emitRuntimeStringOps`, `emitRuntimeArrayOps`, `emitRuntimeIO`, `emitRuntimeConversions`, `emitRuntimeMap`, `emitRuntimeExceptions`（setjmp/longjmp）, `emitRuntimeNet`, `emitRuntimeMath`, `emitRuntimeFS`, `emitRuntimeSQLite` 等。

运行时字符串常量用 `@.rt.` 前缀，与用户 `@.str.` 区分。

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
- **Arrow 函数**: `(x: int): int => x * 2`（编译为顶层函数+函数指针）
- **高阶方法**: `arr.map(fn)`, `arr.filter(fn)`, `arr.reduce(fn, init)`, `arr.forEach(fn)`
- **try/catch/throw**: `try { } catch (e) { }`（setjmp/longjmp 实现）
- **?? 空值合并**: `value ?? "default"`
- **Enum 带值**: `enum Color { Red = 1, Green = 2, Blue = 3 }`
- 泛型类型标注: `Array<string>`, `Map<string, int>`
- 模板字符串 `` `${expr}` ``（支持嵌套）
- switch/case, for/for-in/while/do-while, break/continue
- 位运算: &, |, ^, ~, <<, >>, >>>
- 默认参数, 短路 &&/||, 三元表达式
- import { ... } from "./module" 或 "@/lib/module"

## 开发原则

### 问题解决

- **Root Cause 优先**：从根源修复问题，不用临时方案绕过
- **技术结论必须验证**：不确定就说不确定，不编理由
- **参考最佳实践**：任何设计决策先研究 Go/Rust/Zig/Crystal 等成熟编译器的做法

### 代码质量

- **可读性优先**：不为减少行数牺牲可读性。使用模板字符串 `` `${var}` `` 代替 `+` 拼接
- **单文件不要过大**：超过 500 行考虑拆分
- **最小改动**：只做直接请求的改动
- **删除即删除**：废弃代码直接删掉
- **先读后改**：修改前先读懂现有代码
