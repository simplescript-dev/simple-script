# D158: prelude 注入 + vendor mimalloc 路径 cwd-fragile 根因修

**Status:** [x] Done — bootstrap 三阶段固定点 + e2e 跨 cwd 全 GREEN
**Depends on:** None(独立 bug 修复,跨 D 无依赖)
**Date:** 2026-05-08
**Last Updated:** 2026-05-08

---

## 起首脱胎

下游 `/root/code/vanengine/van-ss/crates/van-cli/src/commands/init.ss:26-36` 留有 `substituteOnce(...)` workaround,注释明示「`@ss_replace` runtime symbol is missing in linked binaries」— 用户从任意 cwd(`/tmp/`)调用 `bin/ss build x.ss` 出现 `llc-18: error: use of undefined value '@ss_replace'`。原假设「ss_replace declare/impl/funcRetTypes 注册某一环漏」勘察后破裂(在 simple-script root 下 build/run 完整跑通)。真根因在路径解析层。

## 核心目标 (Goal)

落地后 `bin/ss` 从**任意 cwd** 调用都能完整 build + 链接 + run,不再依赖用户 cwd 在 simple-script repo 内。

**单一判据**:
```bash
cd /tmp && /<absolute>/bin/ss build /tmp/x.ss -o /tmp/y && /tmp/y
# 期望 exit 0 + 用户预期输出
```

## 根因诊断(假设破裂)

| 层 | 现象 | 真根因 |
|---|---|---|
| 用户假设 | `@ss_replace` declare/impl/funcRetTypes 注册某一环漏 | **破裂** — 在 simple-script root 下 IR 链路完整 `define ptr @_ss_replace(...)` + `call ptr @_ss_replace(...)` |
| 真根因 1 | 任意非 simple-script cwd 下 prelude 不被注入 | `bootstrap/main.ss findPrelude()` 仅查 cwd `bootstrap/parse/prelude.ss` 和 `../bootstrap/parse/prelude.ss` 两条相对路径 |
| 爆炸面 1 | **所有** prelude-only 函数全部裸名链接(`_ss_replace` / `_ss_toUpperCase` / `_ss_padStart` 等),`preludeName(...)` 因 funcRetTypes 没注册返裸名 | 不只 `ss_replace`,全部 prelude builtin 同病 |
| 真根因 2 | `vendor/mimalloc.o` 同形 cwd-relative 查找,链接缺 `mi_calloc` | `bootstrap/main.ss:614-616` 同样仅查 cwd 两条相对路径 |
| 爆炸面 2 | 任意非 simple-script cwd 下 mimalloc 缺失,所有 user binary 链接失败 | 同根因 cwd-fragile,但 C object 不能字符串 embed |

## 候选方案对比(§A.1 §M §字段 10)

| 候选 | 思路 | 根因解决度 | N 年返工度 | 决策 |
|---|---|---|---|---|
| **A** | embed prelude 内容到 ss binary(LLVM `private constant [N x i8]` + `ss_preludeContent` runtime fn) | 100%(prelude) | 极低 | 部分采纳(prelude embed 用 SS 字符串字面量包装,无需新 builtin) |
| **B** | `/proc/self/exe` readlink 反推 binary 路径 + findPrelude 加 binary-relative 搜索 | 80% | 中 | 部分采纳(用于 mimalloc 等 C object — 无法 embed 字符串) |
| **C** | 多搜索路径 fallback(SS_HOME / install dir / HOME) | 50% | 高 | 拒绝(非 root cause,fallback 堆叠) |
| **D** | A + B 复合(全局抽象 `findRepoRoot()` 同时服务 prelude / mimalloc / 未来其它 cwd-fragile 路径) | 100%+ | 极低 | **选** — 用户对话锁不接次优 / workaround;两条根因一次性根除 |

**决策选 D**,因 prelude embed(纯字符串)走 SS 字面量复用现有编译 pipeline 无需新 builtin/runtime;mimalloc 等 C object 走 `/proc/$PPID/exe` 反推 + `resolveRepoFile(rel)` 抽象;两类 cwd-fragile 路径**统一抽象**消解。**业界对标**:rustc / go(self-contained binary)+ gcc / clang(`/proc/self/exe` 推 sysroot),复合即两者最佳实践合并。

## 实施

### 文件清单

| 文件 | 类型 | 内容 |
|---|---|---|
| `tools/gen_prelude_embed.ss` | 新建 — 生成器 | 读 `bootstrap/parse/prelude.ss`、escape 成 SS 字符串字面量、写出 `bootstrap/parse/prelude_embed.ss` |
| `bootstrap/parse/prelude_embed.ss` | 新建 — auto-generated | `function ssPreludeContent(): string { return "<7099 bytes escaped prelude content>" }` |
| `bootstrap/parse/repo_paths.ss` | 新建 — path resolver helper | `findRepoRoot()` via `exec("readlink /proc/$PPID/exe")` + `resolveRepoFile(rel)` cwd-first / repo-root fallback + `stripTrailingNewline()` helper |
| `bootstrap/main.ss` | 改 | +import 2 行 / compile() 用 `ssPreludeContent()` + `resolveRepoFile()` 替换原 cwd-only 逻辑 / helper 抽到 `repo_paths.ss` 后净 +1 行(627 → 628) |

### 关键设计决策

1. **embed 走 SS 字面量而非 LLVM string + runtime fn**:`ssPreludeContent()` 是普通 SS 函数(`prelude_embed.ss` 由 generator 写出),通过 `import` 内联机制接入 — old seed 编译 NEW source 时识别普通 SS function call,无 chicken-and-egg。LLVM string + 新 builtin 路径需 old seed 不识别新 builtin,做不通。

2. **`/proc/$PPID/exe` 而非 `/proc/self/exe`**:`exec()` 走 popen,popen 启动 sh 子进程跑 `readlink`。`/proc/self/exe` 在 readlink 视角解析为 readlink binary;`/proc/$PPID/exe` `$PPID` 由 sh 解释为 sh 父进程 = ss binary。**critical pitfall**,代码注释中已明示。

3. **resolveRepoFile cwd-first**:开发期 / in-repo build 走 cwd-relative fast-path 避免 readlink syscall 开销;repo-root fallback 仅在 cwd-relative miss 时触发(用户从外部调用)。

4. **cachedRepoRoot 单次 readlink**:每次 compile() 调用至多一次 readlink,后续命中 cache。

5. **prelude 加载兜底链**:`ssPreludeContent()` → 空(cold-start 极端) → `resolveRepoFile("bootstrap/parse/prelude.ss")` + readFile。embed 是主路径,fallback 仅防御性兜底(实测永不触发)。

### Generator 转义规则(SS 字符串字面量)

| 字符 | 转义 |
|---|---|
| `\` | `\\` |
| `"` | `\"` |
| `\n` (LF) | `\n` |
| `\r` (CR) | `\r` |
| `\t` (TAB) | `\t` |
| `` ` `` | `` \` `` |
| `$` | `\$`(防 template substitution)|

## 验收(VCM 六验)

| | 项 | 结果 |
|---|---|---|
| V1 | `cd /tmp && bin/ss build /tmp/replace_test.ss -o /tmp/rt && /tmp/rt` | `hello SS` exit=0 ✓ |
| V2 | `cd /tmp && bin/ss build /tmp/upper.ss && ./out`(对称同根因)| `toUpperCase` 也修 ✓ |
| V3 | 下游 van-cli `substituteOnce(...)` → `contents[i].replace(...)` `ss check src/main.ss` | check OK ✓ |
| V4 | 下游 van-cli `ss build src/main.ss -o /tmp/van_cli`(mimalloc 测试)| compiled ✓ |
| V5 | `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 | Fixed point verified ✓ |
| V6 | `bin/ss test tests/` 与 baseline 完全一致(14 fail 全 pre-existing docker integration)| 301/14/315 ✓ |
| V7 | `tools/reflection_health_linter.ss` F1 GATE | PASS(main.ss 628 < bm 630)✓ |
| V8 | `tools/d_doc_index_linter.ss` D 文档引用 GATE | OK ✓ |

## 维护协议

- 每次修改 `bootstrap/parse/prelude.ss` 后**必须**跑 `bin/ss run tools/gen_prelude_embed.ss` 重新生成 `bootstrap/parse/prelude_embed.ss`,然后重 bootstrap。
- 未跑 generator 直接 bootstrap → 新 binary 仍带旧 prelude(可能与 source 不一致)。
- 长期可加 git pre-commit hook 自动 gen + commit prelude_embed.ss(本轮不做,留 §Followup)。

## §A.2 隐藏假设挑战

- **H1**:embed 走 SS 字面量是否会被 prelude 注入流程二次处理?
  - 验证:prelude_embed.ss 中 `ssPreludeContent()` 是普通 SS 函数,通过 `import` 内联;`compile()` 调用 `ssPreludeContent()` 拿 string,然后 string 被用作 prelude content 注入到 user source 前。**embed 字符串内容不被 lexer 二次解析作为 prelude_embed.ss 内容**,而是作为下次 lexer 输入(用户编译时的 prelude)— 一切正常。
- **H2**:`exec("readlink /proc/$PPID/exe")` 在 popen 调 sh 失败时会怎样?
  - 验证:`exitCode != 0` 时 findRepoRoot 返 ""(短路),resolveRepoFile 退回到 cwd-relative;cwd 也找不到则返 "" — compile 失败有 error message。**有兜底链**。
- **H3**:`bin/ss` 在 `/usr/local/bin/ss` 这种 system install 路径下,反推 root 会得到 `/usr/local`,但 `/usr/local/vendor/mimalloc.o` 不存在。
  - 影响:install 场景 mimalloc 路径仍坏,但本轮 ss 没有 install 流程,**install 路径治理留 §Followup**。当前 `bin/ss` 走 in-repo `<root>/bin/ss` 范式,反推有效。
- **H4**:macOS / Windows 不识别 `/proc/$PPID/exe`。
  - 影响:本轮限 Linux(SS 整套 toolchain musl-gcc + llc-18 已限 Linux,一致)。

## §Followup

- **F1**(install 路径治理):未来 `ss` 加 install 流程时,`vendor/mimalloc.o` 应随 ss binary 一同 install,resolveRepoFile 加 `<install-prefix>/lib/simplescript/` 搜索分支。
- **F2**(macOS / Windows portability):`/proc/$PPID/exe` 不可用,需 `_NSGetExecutablePath`(macOS)/ `GetModuleFileName`(Windows)抽象 — 待 SS toolchain 支持非 Linux 时再做。
- **F3**(git pre-commit hook 自动 gen prelude_embed):防开发者忘记跑 generator 导致 embed drift。

## §Status 时间线

| Phase | Date | Commit | 内容 |
|---|---|---|---|
| 收关 | 2026-05-08 | `<commit-hash>` | bug options.md GATE 产出 + D158 文档落档 + tools/gen_prelude_embed.ss + bootstrap/parse/prelude_embed.ss(auto-gen)+ bootstrap/parse/repo_paths.ss + main.ss prelude/mimalloc 加载切换 + bootstrap 三阶段固定点 PASS + /tmp e2e PASS(prelude + mimalloc 双根因)+ van-cli 下游验收 PASS + reflection_health F1 GATE PASS(main.ss 628<630)+ d_doc_index GATE PASS + tests baseline 完全一致(301/14/315)|
