# Round 126

## Role
Senior technical architect. Project: SimpleScript (self-bootstrapping compiled language, ~16700 LOC).

## Language
Persistent files in English. Discussion in Chinese, terms in English inline.

## Read These Files
- docs/3-decisions/D087-comptime.md (comptime 完整设计 + 实现路径 + 设计细节)
- bootstrap/gen_annotations.ss (当前注解处理，comptime 完成后删除)

## Last Round (max 3 sentences)
确定 comptime（编译期执行）为 SimpleScript 元编程方案，淘汰插件系统和外部工具方案。D087 记录了完整选型决策、4 Phase 实现路径（含 16 个子步骤和完成标准）、解释器设计细节。同时完成了 D086 v2 注解分发重构（annotationMapping + handler dispatch），作为 comptime 前的工作实现。

## Task
**D087 Phase 1a：解释器骨架**

实现 SimpleScript AST 解释器的基础：
- 文件：`bootstrap/interp.ss`
- 值表示：int/string/double/bool/null（用 Map 存储）
- 环境/作用域栈
- 表达式求值：算术、比较、逻辑、字符串拼接、模板字符串
- **完成标准：** 写测试验证 `comptime { const x = 1 + 2 }` 能执行并产出值

详细设计见 D087 "设计细节" 章节。

### Open Issues (by priority)
1. **I001 — Global mutable state explosion** [BLOCKED]: 55+ globals. Needs struct support.
2. **I002 — String-based type system** [BLOCKED]: Types compared as raw strings. Needs enum/struct.
3. **I005 — AST list as string** [PARTIAL]: Has helpers, perf issues need proper array type.
4. **I006 — Runtime raw IR** [LOW]: Mostly converted, 401 raw emitIR remaining.
5. **I008 — Parser no precedence table** [LOW]: Works, recursive descent is standard.

### Project Status
- **D087 planned**: Comptime — 编译期执行用户代码，Zig 模型
- **D086 v2 done**: annotationMapping + handler dispatch（comptime 前的工作实现）
- **Spring Boot DI**: @Component/@Service/@Repository → springAnnotationHandler in lib
- **D085 done**: Package system
- **D082 Phase 1-4 done**: ref/watch, Thread, Channel<T>
- **Bootstrap**: 40 files, ~16700 LOC, 180 tests (all passing).

## Watch Out For
- **D087 是唯一真相**：每轮开头读 D087，不重新讨论选型
- **Phase 编号跟踪**：当前步骤写在 handoff Task 中（如 "D087 Phase 1a"），完成后更新到下一步
- **Bootstrap works**: After any source change, run `bin/ss test tests/` then verify bootstrap fixed-point.
- **Runtime cache**: After changing gen_runtime.ss or gen_rt_*.ss, run `rm -f /tmp/ss_rt_cache.*` before testing.
- **interp.ss 自举安全**: 解释器是普通 SS 代码，seed 能编译。解释器不使用 comptime 自身。
- **FUNC_DECL I4 conflict**: I4 is used for both annotations and isAbstract. Known issue.
- **Rejected features**: Range syntax, pattern matching type patterns, Result<T,E> + ? operator, FFI via dlopen, Kotlin/Scala syntax. Do not propose.

## When Done
**P18: One task per context. When done or context runs low, update handoff and stop.**
1. Write tests for new features
2. Verify against axioms and principles
3. Run `/simplify` to review code quality before commit
4. Self-review for contradictions
5. Commit and push to remote
6. Generate next docs/5-handoff/next-prompt.md (include "Next Direction" summary)
7. List files created/modified + brief next direction
8. **Stop.**
