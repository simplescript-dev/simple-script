# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SimpleScript 是一门**自举的编译型语言**。编译器用 SimpleScript 自身编写（~6200 LOC），编译到 LLVM IR 并静态链接 musl libc，产出原生二进制。**零 C 依赖**——无 runtime.c，所有运行时函数由编译器直接生成为 LLVM IR。

**完全自举**：编译器能编译自己，产出字节级相同的二进制（固定点验证通过）。

## 构建与测试

```bash
# 编译 .ss 文件
bin/ss build file.ss -o output
bin/ss build file.ss --release -o output    # 优化构建 (-O2 -s)
bin/ss build file.ss --emit-ir              # 输出 LLVM IR

# 运行
bin/ss run file.ss

# 测试
bin/ss test tests/

# 自举（用编译器编译自己）
bin/ss build bootstrap/main.ss -o /tmp/ss_new
/tmp/ss_new build bootstrap/main.ss -o /tmp/ss_stage2
# 验证固定点: md5sum /tmp/ss_new == md5sum /tmp/ss_stage2
```

依赖：`llc-18`（LLVM）、`musl-gcc`（静态链接）。

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
bootstrap/            # 编译器源码（全部 .ss 文件，~6200 LOC）
  lexer.ss            # 词法分析 (481 LOC)
  parser.ss           # 语法分析，Map-based AST (1149 LOC)
  checker.ss          # 类型检查 (349 LOC)
  codegen.ss          # 状态/初始化/API (250 LOC)
  gen_stmts.ss        # 语句代码生成 (701 LOC)
  gen_exprs.ss        # 表达式代码生成 (1020 LOC)
  gen_class.ss        # 类/继承代码生成 (298 LOC)
  gen_runtime.ss      # 运行时 LLVM IR 生成 (1411 LOC) — 替代 runtime.c
  prelude.ss          # 纯 SS 运行时方法 (153 LOC)
  main.ss             # CLI 入口 + import 解析 (361 LOC)
bin/ss                # 种子编译器二进制（自举用）
lib/                  # 标准库
  json.ss             # JSON 解析/序列化
  base64.ss           # Base64 编解码
  sha256.ss           # SHA-256 哈希
```

### 关键设计

- **AST**: Map-based（每个节点一个 int ID，属性存在全局 Map 中）
- **Codegen**: 直接生成 LLVM IR 文本（.ll 格式）
- **运行时**: gen_runtime.ss 生成所有 ss_* 函数为 LLVM IR define 块，直接调 libc（无 C 文件）
- **Prelude**: 高层方法（trim/replace/toUpperCase 等）用纯 SS 实现，编译时自动包含
- **Import**: 递归内联导入文件，`@/` 支持项目根路径
- **自举**: bin/ss → 编译 bootstrap/ → 新 bin/ss（固定点验证）

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
