# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目本质

SimpleScript 是一门自举的编译型语言。编译器用 SimpleScript 自身编写，编译到 LLVM IR 并静态链接 musl libc + mimalloc，产出原生二进制。零 C 依赖——所有运行时函数由编译器直接生成 LLVM IR。用户自定义 class 实例使用 Perceus 风格引用计数：对象头 RC@0 + TypeInfo@1，PIR 中间层做 liveness 分析自动插入 release，mimalloc 分配器支持 REUSE 优化。应用层 stdlib（HTTP/JSON/路由/sha256/base64/url）用纯 SS 模块实现（见 `lib/`），不引入应用层 C 库；只有底层基础设施（mimalloc 分配器）允许链接 C。

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

依赖：`llc-18`、`musl-gcc`、`vendor/mimalloc.o`（首次构建自动编译）。自举一次约 55 秒（三阶段固定点验证）；开工前先静态分析画完整方案、一次性改完再编译验证，避免 trial-and-error 堆编译次数。

测试文件格式：每个 `.ss` 测试是独立程序，含 `function main()`。通过条件 = 编译成功 + 运行 exit code 0。内置 `test(name, fn)` + `assertEqual`/`assertTrue` 等断言。含 `import/` 子目录的测试组只编译 `main.ss`。

## 高层架构

```
.ss → Lexer → Parser (AST) → Checker → PIR (Perceus IR) → Codegen (LLVM IR) → llc + musl-gcc → 静态二进制
                                          ↑                       ↑
                            pir_lower → pir_opt              gen_runtime.ss + gen_rt_*.ss
                            (liveness / REUSE)               生成所有 ss_* 运行时函数
```

`bootstrap/` 内编译器源码按职能分族入子目录:`lexer/`(含 `intern_pool.ss`)、`parse/`(含 `prelude.ss`)、`checker/`、`eval/`(~20,含 `eval_expr.ss` + `interp_*` + 10 条子 eval)、`pir/`(Perceus IR 层,`pir.ss`+`pir_lower.ss`+`pir_opt.ss`)、`gen/`(根下基础族 + `codegen.ss` 入口 + 子族 `class/`/`exprs/`/`stmts/`/`methods/`/`rt/`)。根目录仅保留 `main.ss`(编译器驱动入口)。**未来拆分沿用此风格**:按职能归族入子目录(不看文件数门槛,2 文件或 8 文件一视同仁)、入口文件(dispatcher)与目录同名(如 `checker/checker.ss`、`gen/exprs/exprs.ss`)、其他 .ss 一律入子目录不退回扁平根。`parse/prelude.ss` 在编译时自动注入到源码前。`main.ss` 的 `resolveImports()` 在解析前递归内联所有 `import`;解析顺序(`@/` 项目根、`./` 相对路径、`@scope/name` 走 `ss.json` dependencies、包入口 `main`/`src/index.ss`)见 `bootstrap/main.ss` `resolveImports()` 实现。详细文件清单 `ls bootstrap/ bootstrap/*/`。

## 添加新语言特性

按序修改：

1. `bootstrap/lexer/lexer.ss` — 新 token / 关键字（加入 `lexIdent()` 分发表）
2. `bootstrap/parse/parser.ss` 或 `parse/parse_stmts.ss`/`parse/parse_exprs.ss` — 新 AST 节点 kind + parse 函数 + dispatcher case
3. `bootstrap/checker/checker.ss` 或 `checker/check_stmts.ss` — `checkStmt`/`checkExpr` 加 case
4. `bootstrap/gen/stmts/stmts.ss` 或 `gen/exprs/exprs.ss` — `genStmt`/`genExpr` + `inferType` 加 case
5. `bootstrap/gen/gen_runtime.ss` 或 `gen/rt/gen_rt_*.ss` — 新 builtin 加 `emitIR("define ...")` 块
6. `bootstrap/gen/codegen.ss` `initFuncRetTypes` — 注册新内置方法返回类型

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

**Root Cause 优先（只从根因解决,不考虑成本,只要最佳）**：编译器限制是 bug，不是边界条件。当编译器限制迫使 stdlib 或用户代码使用丑陋 workaround，先修编译器。同一个 workaround 出现第二次必须停下修根因，不要记为 "Known limitation" 然后绕过。**多选路径下"根因大改 vs 浅层补丁"权衡里,成本(LOC / 工程量 / bootstrap 轮数 / 工作轮数 / linter 短期 regression / 需要先做预削减才能拿余量)不是选次优的合法理由**;最佳的判据是**根因解决度**,不是实施成本。具体:(a) 根因方案 vs workaround → 选根因(含编译器 bug 直接修 codegen / RC 逻辑,不在调用方加 strdup / copy 等 workaround);(b) 大重构 vs 小补丁 → 若根因需大重构,选大重构,即使本轮 LOC 爆炸或多 commit 分步;(c) 主线能力 vs annotation / handler 旁路 → 选主线能力补齐(参考 memory `feedback_no_derive_workaround`);(d) **多候选推荐排序**(同族下游候选 / 设计权衡 / 扩容申报取舍)按**根因解决度 + 第一性需求覆盖度**排,**禁按"工程量最小 / 最经济 / 最快上线 / LOC 最少"作排序依据**;(e) 例外极窄:仅当根因路径**物理上不可达**(需修改不可控外部依赖且无 fork 余地)才允许次优,**"太贵 / 太慢 / 本轮做不完"不算物理不可达**。

**交互式单文档**：每轮等用户明确指定一个文档/文件，逐个问题确认方向再执行。不自动扫 `docs/3-decisions/` 找未完成决策自主挑任务，不顺带修无关文件，不批量推进类似问题。**下轮提示词 payload `.claude/next_prompt.md` 必含关键字 `ultrathink`**,§After Done §下一步提示词 写入后强制跑 `bin/ss run tools/next_prompt_ultrathink_linter.ss`,stdout 出现 `GATE BLOCKED` 即阻断 stop(机械校验,详见 `docs/3-MNK.md §After Done §4.下一步提示词`)。

**MNK 流程(强制)**:接到任意任务,第一次工具调用之前必须按 `docs/3-MNK.md §M — Before Code` 的九问 PSM 填表;任务完成宣告之前必须按 §N — After Code 六验 VCM 逐项贴证据;commit 标准改 / 大改必走 §K — After Lint 的 M-linter-K-M 问答收敛循环;`N→K→改代码` 反复 Continue NK 直到全 pass;收敛后必须走 §After Done 三步(simplify → commit → 下一步提示词),缺一条不许 stop。档位门槛、八股自检、reset 双重 gate、反射扩容协议等细节以 `docs/3-MNK.md` 为单一事实源,此处不重复。

**决策记录**：每个确认的设计决策立即写入 `docs/3-decisions/D0NN-*.md`，一个决策一个文件，不等到实现完成再补。多阶段计划的 Phase 进度只写在 D 文档里。下轮提示词收尾**自闭环**两步:(1) 对话输出(让用户审阅措辞) (2) 覆盖写入 `.claude/next_prompt.md`(单次 payload)。terman 内建 `claude-next` preset 监测 PTY 空闲 30s + 光标在 prompt 处,自动 `/clear` + bracketed paste + 30s 观察窗口 + Enter 触发下一轮(见 `docs/terman-auto-next.md`)。两处内容严格一致;用户在 30s 窗口里审阅,Ctrl+C 或键入字符即可中断。preset 读完即 `delete_file` 消费,Claude 不承载跨轮状态累积;Claude 本轮**不执行**任何触发脚本,直接 stop。

**Bug 修复 Harness（强制）**：修 bug 时必须运行 `bin/ss run .claude/harness/common/bug.ss detected <importance> <urgency>`（importance/urgency 为 1-100），读取 stdout 输出的指令并执行。修复后运行 `bin/ss run .claude/harness/common/bug.ss fixed <round> <certainty>`（round 为第几轮，certainty 为 0-100 确定性），按输出指令决定下一步。**轨 1 前置 gate**：detected 后 Execute 第一次修改性 tool call 之前必须产出 `<bug-name>.options.md` 方案对比表（候选 ≥ 3 + 层次标 + 决策行 + 假设破裂标识），跑 `bin/ss build tools/bug_options_linter.ss -o /tmp/bug_options_linter && /tmp/bug_options_linter <bug>.options.md` GATE OK 才允许 Execute。详见 `docs/3-MNK.md` §特定领域 §Bug 修复 Harness §轨 1 + §M §字段 10。

**反射根因 gate（强制）**：触碰反射路径前后必须跑 `bin/ss run tools/reflection_health_linter.ss`；任一物理指标（M1-M7 + N1-N5）高于 `budget_max` 阻断 commit。规则/baseline 2 列制/AUTO-DRIFT 软警告/`bump`+`bump-group` 扩容申报 CLI/scope-aware 判定 见 `docs/3-decisions/D097-reflection-root-cause-metrics.md`；流程层触发范围与 REGRESSION A/B 路径见 `docs/3-MNK.md` §特定领域 §反射路径根因 gate。

**D 文档治理 gate（强制）**：删/合并/重命名 `docs/3-decisions/D*.md` 或改动 bootstrap/tools/CLAUDE.md/docs/3-MNK.md 里 `D\d{3} §` 引用后必须跑 `bin/ss run tools/d_doc_index_linter.ss`；F1 死指针 BLOCK（源码注释指向已删 D 文档） / F2 孤立 D 文档 soft warn。规则见 `docs/3-MNK.md` §特定领域 §D 文档治理 gate（对称 §memory 治理 gate）。

**回复语言**：所有回复及总结使用中文。

## 外部引用

- 项目入门、语言特性 demo：`README.md`
- 详细开发指南：`docs/guide.md`
- 项目共识与原则：`docs/1-axioms.md`、`docs/2-principles.md`
- **八股流程层闸门单一事实源(MNK)**:`docs/3-MNK.md` — PSM 九问 / VCM 六验 / 档位 / 收尾 gate / 八股自检 / rule 问答收敛循环 / 反射扩容协议 / reset 双重 gate 等全部规则
- 设计决策归档（含 import 解析、enum、null safety、并发等）：`docs/3-decisions/`
- 标准库源码：`lib/`（json、base64、sha256、http）
- Terman 下轮提示词自动注入（terman `claude-next` preset 机制、`.claude/next_prompt.md` payload 协议）：`docs/terman-auto-next.md`
