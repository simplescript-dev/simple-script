# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SimpleScript 是一门**自举的编译型语言**。编译器用 SimpleScript 自身编写（~3900 LOC），编译到 LLVM IR 并静态链接 musl libc，产出原生二进制。

**完全自举**：编译器能编译自己，产出字节级相同的二进制（固定点验证通过）。

## 构建与测试

```bash
# 编译 .ss 文件
bin/ss file.ss -o output
bin/ss --release file.ss -o output    # 优化构建 (-O2 -s)
bin/ss --emit-ir file.ss              # 输出 LLVM IR

# 自举（用编译器编译自己）
./build.sh bootstrap

# 运行测试
for f in tests/**/*.ss; do bin/ss "$f" -o /tmp/test && /tmp/test; done
```

依赖：`llc-18`（LLVM）、`musl-gcc`（静态链接）。

## 编译器架构

**完全用 SimpleScript 实现**的四阶段流水线：

```
.ss 源码 → Lexer → Parser (AST) → Codegen (LLVM IR text) → llc + musl-gcc → 静态二进制
```

### 源码结构

```
bootstrap/          # 编译器源码（全部 .ss 文件）
  lexer.ss          # 词法分析 (427 LOC)
  parser.ss         # 语法分析，Map-based AST (964 LOC)
  checker.ss        # 类型检查 (349 LOC)
  codegen.ss        # 状态/初始化/运行时声明/API (293 LOC)
  gen_stmts.ss      # 语句代码生成 (570 LOC)
  gen_exprs.ss      # 表达式代码生成 (834 LOC)
  gen_class.ss      # 类/继承代码生成 (286 LOC)
  main.ss           # CLI 入口 + import 解析 (168 LOC)
bin/ss              # 种子编译器二进制（自举用）
runtime/runtime.c   # C 运行时 (~800 LOC)
```

### 关键设计

- **AST**: Map-based（每个节点一个 int ID，属性存在全局 Map 中）
- **Codegen**: 直接生成 LLVM IR 文本（.ll 格式），不用 inkwell
- **Import**: 递归内联导入文件，去重全局变量和函数
- **自举**: bin/ss → 编译 bootstrap/ → 新的 bin/ss（固定点）

### 运行时 (runtime/runtime.c)

纯 C + POSIX，通过 musl-gcc 静态链接：
- I/O: ss_println/ss_readFile/ss_writeFile/ss_appendFile
- 字符串: 20+ 方法 (concat/split/join/trim/replace/indexOf...)
- 数组: 堆分配 i64 槽 (ss_newArray/ss_arrayPush/ss_arraySort...)
- HashMap: ss_mapNew/ss_mapSet/ss_mapGet/ss_mapKeys
- 网络: ss_tcpListen/ss_tcpAccept/ss_tcpRead/ss_tcpWrite
- 文件系统: ss_mkdir/ss_fileExists/ss_listDir/ss_sha256
- 加密: ss_sha256/ss_base64Encode/ss_base64Decode
- 数学: ss_sqrt/ss_abs/ss_pow/ss_random...

## 语言特性

- const/let（TypeScript 风格），类型后置 (name: Type)
- function, class/new/this/extends（继承，父类字段/方法链查找）
- 泛型类型标注: Array<string>, Map<string, int>
- 模板字符串 `` `${expr}` ``（支持嵌套）
- switch/case, for/for-in/while/do-while, break/continue
- 默认参数, 短路 &&/||, 三元表达式
- import { ... } from "./module"

## 开发原则

### 问题解决

- **Root Cause 优先**：从根源修复问题，不用临时方案绕过
- **技术结论必须验证**：不确定就说不确定，不编理由
- **逐步确认不想当然**：每一步修复后验证结果

### 代码质量

- **单文件不要过大**：超过 500 行考虑拆分
- **最小改动**：只做直接请求的改动
- **删除即删除**：废弃代码直接删掉
- **先读后改**：修改前先读懂现有代码
- **融入项目风格**：保持现有代码风格一致
