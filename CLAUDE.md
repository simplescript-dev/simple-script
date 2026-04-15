# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目本质

SimpleScript 是一门自举的编译型语言。编译器用 SimpleScript 自身编写，编译到 LLVM IR 并静态链接 musl libc + mimalloc，产出原生二进制。零 C 依赖——所有运行时函数由编译器直接生成 LLVM IR。用户自定义 class 实例使用 Perceus 风格引用计数：对象头 RC@0 + TypeInfo@1，PIR 中间层做 liveness 分析自动插入 release，mimalloc 分配器支持 REUSE 优化。

## 构建与测试

```bash
# 编译 .ss 文件
bin/ss build file.ss -o output
bin/ss build file.ss --release -o output    # -O2 -s
bin/ss build file.ss --emit-ir              # 输出 LLVM IR

# 运行
bin/ss run file.ss

# 测试
bin/ss test tests/
bin/ss test tests/phase2/

# 其他 CLI
bin/ss check file.ss                        # 仅类型检查
bin/ss fmt file.ss
bin/ss repl
bin/ss new myapp                            # 创建 ss.json + src/main.ss
bin/ss clean

# 自举（三阶段固定点验证）
./build.sh bootstrap
# seed→stage1→stage2→stage3，验证 stage2==stage3 后更新 bin/ss
```

依赖：`llc-18`、`musl-gcc`、`vendor/mimalloc.o`（首次构建自动编译）。

测试文件格式：每个 `.ss` 测试是独立程序，含 `function main()`。通过条件 = 编译成功 + 运行 exit code 0。内置 `test(name, fn)` + `assertEqual`/`assertTrue` 等断言。含 `import/` 子目录的测试组只编译 `main.ss`。

## 高层架构

```
.ss → Lexer → Parser (AST) → Checker → PIR (Perceus IR) → Codegen (LLVM IR) → llc + musl-gcc → 静态二进制
                                          ↑                       ↑
                            pir_lower → pir_opt              gen_runtime.ss + gen_rt_*.ss
                            (liveness / REUSE)               生成所有 ss_* 运行时函数
```

`bootstrap/` 内约 35 个 `.ss` 文件是编译器源码，按前缀命名分工：`lex_/parse_/check_/gen_/pir_/gen_rt_/`。`prelude.ss` 在编译时自动注入到源码前。`main.ss` 的 `resolveImports()` 在解析前递归内联所有 `import`；解析顺序（`@/` 项目根、`./` 相对路径、`@scope/name` 走 `ss.json` dependencies、包入口 `main`/`src/index.ss`）见 D085。详细文件清单 `ls bootstrap/`。

## 添加新语言特性

按序修改：

1. `bootstrap/lexer.ss` — 新 token / 关键字（加入 `lexIdent()` 分发表）
2. `bootstrap/parser.ss` 或 `parse_stmts.ss`/`parse_exprs.ss` — 新 AST 节点 kind + parse 函数 + dispatcher case
3. `bootstrap/checker.ss` 或 `check_stmts.ss` — `checkStmt`/`checkExpr` 加 case
4. `bootstrap/gen_stmts.ss` 或 `gen_exprs.ss` — `genStmt`/`genExpr` + `inferType` 加 case
5. `bootstrap/gen_runtime.ss` 或 `gen_rt_*.ss` — 新 builtin 加 `emitIR("define ...")` 块
6. `bootstrap/codegen.ss` `initFuncRetTypes` — 注册新内置方法返回类型

每次有意义的改动后跑 `./build.sh bootstrap` 验证固定点。

## 关键不变量

非显然约束，编辑前必须知道：

**AST 节点**：节点是 int ID，所有属性存全局 Map（`nKind`/`nStr1..3`/`nInt1..4`/`nList`/`nLine`/`nCol`）。Slot 含义见 `parser.ss` 中各 `newNode()` 调用处的注释。

**对象布局**：用户 class 实例 = `{ i32 rc, ptr TypeInfo, ...fields }`。RC@offset 0、TypeInfo@offset 1、用户字段从 offset 2。`@ClassName_type_info` 常量布局 `{drop_fn, deep_clone_fn, shallow_clone_fn, size, name}`。继承时子类 struct 前缀包含父类所有字段，方法沿 `classParents` 链查找。

**双 RC 系统**：
- 旧系统 `ss_rc_retain`/`ss_rc_release` —— 字符串、数组、Map，libc `calloc`/`free`
- 新系统 `ss_retain`/`ss_release` —— class 实例，mimalloc `mi_calloc`/`mi_free`
- `emitRetainForType()` / `emitReleaseForType()` 按 SS 类型自动分派；新增类型时必须更新两者

**Per-class 函数**：自动生成 `ss_drop_X` / `ss_deep_clone_X` / `ss_shallow_clone_X`。用户可在 class body 定义 `deepClone()` / `shallowClone()` 覆盖，`classMethodHasName()` 检测 override。`classConstFields["ClassName.fieldName"]="1"` 决定 deepClone 时 share（retain）vs recursive clone。

**PIR Map key**：所有 PIR Map（`pirKind`/`pirStr*`/`pirInt1`/`pirList`/`pirSchedule`）访问必须 `id + ""` 将 int 转 string，否则 key 错配。`pirSchedule[astStmtId]` 在 `genBlock()` 每条 `genStmt()` 后由 `pirEmitScheduled()` 发射 release。

**全局变量初始化**：`let x = new Map()` 等全局声明分两阶段——先 `@x = global ptr null`，再 `main()` 开头 `emitGlobalInits()` 调用初始化函数。

**Arrow 函数**：编译为顶层 `@__arrow_N`，IR 缓存在 `arrowDefs`，外层函数结束后 `flushArrowDefs()` 写出。

**命名空间隔离**：用户字符串常量 `@.str.N`，运行时字符串常量 `@.rt.str.name`，永不混用。

**符号 mangling**：构造函数 `@ClassName_new`，方法 `@ClassName_methodName`，重载 `@func_paramSig`（`i`=int / `d`=double / `s`=string / `p`=ptr）。

## 项目技术规则

**Java/TS 语法优先**：任何新语法必须在 TypeScript/JavaScript 或 Java 中有直接对应物。不借鉴 Kotlin/Scala（如主构造函数参数、`: Parent` 继承、`val/var` 参数）。优先复用现有关键字扩展功能，新关键字是最后手段。

**编译器吸收复杂度**：用户不应看到内存管理、类型系统等内部机制的语法暴露。

**Root Cause 优先**：编译器限制是 bug，不是边界条件。当编译器限制迫使 stdlib 或用户代码使用丑陋 workaround，先修编译器。同一个 workaround 出现第二次必须停下修根因，不要记为 "Known limitation" 然后绕过。

**交互式单文档**：每轮等用户明确指定一个文档/文件，逐个问题确认方向再执行。不自动扫 `docs/3-decisions/` 找未完成决策自主挑任务，不顺带修无关文件，不批量推进类似问题。

**PFV 流程（强制）**：接到任意任务，第一次工具调用之前必须按 `docs/2-principles.md §PFV 流程` 的十问 PSM 填表；任务完成宣告之前必须按五验 VCM 逐项贴证据；VCM 通过后必须走**收尾 gate** 的 simplify → commit → 下一步提示词三步，缺一条不许 stop。细节、层级、例外规则以该文档为准，此处不重复。

**决策记录**：每个确认的设计决策立即写入 `docs/3-decisions/D0NN-*.md`，一个决策一个文件，不等到实现完成再补。多阶段计划的 Phase 进度只写在 D 文档里，不创建 `next-prompt.md`、`handoff.md` 等"自动传递任务"文件。下一轮提示词直接输出到对话，由用户决定是否执行。

**回复语言**：所有回复及总结使用中文。

## 外部引用

- 项目入门、语言特性 demo：`README.md`
- 详细开发指南：`docs/guide.md`
- 项目共识与原则：`docs/1-axioms.md`、`docs/2-principles.md`
- 设计决策归档（含 import 解析、enum、null safety、并发等）：`docs/3-decisions/`
- 标准库源码：`lib/`（json、base64、sha256、http）
