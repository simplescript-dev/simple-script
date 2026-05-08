# D159: `@/lib/X` import 解析路径 — `@/` 永远指 SS_HOME(stdlib)

**Status:** [x] Done — bootstrap 三阶段固定点 + 外部项目 / SS 仓内 / 下游 van-cli 全 GREEN
**Depends on:** D158(`findRepoRoot()` self-exe 反推已落地,本 D 直接复用)
**Date:** 2026-05-08
**Last Updated:** 2026-05-08

---

## 起首脱胎

外部 SS 项目(`van-cli/src/commands/init.ss`)写 `import { Path } from "@/lib/path"`,`ss check` 报 `error: undefined variable 'Path' ... did you mean 'Math'?`。`@/` 解析硬编码到消费项目根,外部项目根没有 `lib/path.ss` → 断链。原假设"`@/lib/path` 单点缺失"勘察后破裂(全仓 300 个真实 `@/lib/X` 全在 SS 仓内)。真根因在 `@/` 语义层:**stdlib 与消费项目根 namespace 混用**。

## 核心目标 (Goal)

`@/` 永远指 SS_HOME(stdlib root)。SS 仓内 `@/lib/X` 解析等价(SS_HOME == 项目根),零迁移;外部项目 `@/lib/X` 直达 SS 安装目录的 stdlib。

**单一判据**:
```bash
# 外部项目从任意 cwd:
import { Path } from "@/lib/path"
function main() { println(Path.join("a", "b")) }
ss check x.ss        # check OK
ss build x.ss -o y && ./y   # 输出 a/b
```

## 根因诊断(假设破裂)

| 层 | 现象 | 真根因 |
|---|---|---|
| 用户假设 | `@/lib/path` 单点缺失 | **破裂** — 全仓 300 个真实 `@/lib/X` 全在 SS 仓内(`lib/` + `tests/`),零外部用例 |
| 真根因 | `bootstrap/main.ss:211` `@/` 解析为 `projectRoot + "/" + ...` | `@/` 硬编码消费项目根 alias,stdlib 与用户代码 namespace 混 |
| 爆炸面 | stdlib 内部 cross-ref(`lib/crypto.ss:14 import "@/lib/sha256"`)在外部项目消费时 resolveInner 递归处理 lib/crypto.ss 的 imports,projectRoot 仍是外部项目根 → **stdlib 内部 cross-ref 全断** | 不只外部项目入口,递归内联的 stdlib 之间相互引用同病 |

## 候选方案对比(§A.1 §M §字段 10)

| 候选 | 思路 | 根因解决度 | 迁移成本 | 决策 |
|---|---|---|---|---|
| **A** | `@/` 永远指 SS_HOME,用户项目用 `./` `../` 相对引用 | 100% | 0(SS 仓内等价) | **选** — 用户对话锁推荐 |
| **B** | `@/` 保留消费项目根,新增 `@std/` 或裸名 `lib/X` 作 stdlib | 100% | 高(300 处全仓 sed) | 拒绝 — 迁移成本无对应根因收益 |
| **C** | `@/` 两段查找(项目根优先 + SS_HOME fallback) | 80% | 0 | 拒绝 — 路径歧义,长期返工 |
| **D** | A + ss.json `paths` 用户自定 alias(类 tsconfig) | 100%+ergonomics | 0 | 留 §Followup |

**决策 A**:迁移成本 0(SS_HOME == SS 仓根,内部 300 处等价)+ 根因 100% + 复用 D158 `findRepoRoot()` 已落地 + 一处 line 211 patch + 业界对标 Deno `@std/` namespace。

## 实施

### 文件清单

| 文件 | 改动 |
|---|---|
| `bootstrap/parse/repo_paths.ss` | +`resolveStdlibRoot(fallback)` helper(7 行,含注释)— 复用 `findRepoRoot()` self-exe 反推 |
| `bootstrap/main.ss` | +import `resolveStdlibRoot` 1 名 + line 211 改 `resolveStdlibRoot(projectRoot) + "/" + ...`(净 +1 行 line 628 → 628 不破 F1 GATE)|

### 关键设计决策

1. **fallback 到 projectRoot**:`resolveStdlibRoot(fallback)` 当 `/proc/$PPID/exe` 不可用(极端环境 / 非 Linux)时兜底到原行为(projectRoot)。SS 仓内场景 SS_HOME == projectRoot,fallback 等价。
2. **不修改 SS 仓内 300 处 `@/lib/X`**:SS_HOME == SS 仓根,语义等价。
3. **`./` `../` 相对引用为外部项目唯一选项**:外部项目失去 `@/` 当根 alias 能力,留 §Followup D 提供 ss.json `paths` 自定 alias(tsconfig 风格)。
4. **复用 D158 self-exe 反推**:`findRepoRoot()` 已 cache 单次 readlink,本 D 零额外 syscall 开销。

## 验收(VCM 六验)

| | 项 | 结果 |
|---|---|---|
| V1 | 外部项目 `cd /tmp/stdlib_test && ss check stdlib_test.ss` | check OK ✓ |
| V2 | 外部项目 `ss build x.ss -o y && ./y`(`@/lib/path` Path.join)| `a/b` exit=0 ✓ |
| V3 | 下游 van-cli `init.ss` 改回 `import { Path } from "@/lib/path"` + `Path.join` / `Path.dirname` 调用 → `ss check src/main.ss` | check OK ✓ |
| V4 | 下游 van-cli `ss build src/main.ss -o /tmp/van && /tmp/van init demo-app` | 产出 `data/` `package.json` `src/` 三脚手架 ✓ |
| V5 | `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 | Fixed point verified ✓ |
| V6 | `bin/ss test tests/` 与 baseline 完全一致(SS 仓内 300 处 `@/lib/X` 解析等价)| 301/14/315 ✓ |
| V7 | `tools/reflection_health_linter.ss` F1 GATE | PASS(main.ss 628 == bv,DRIFT 0)✓ |
| V8 | `tools/d_doc_index_linter.ss` | OK ✓ |

## §A.2 隐藏假设挑战

- **H1**:SS 仓内 300 处 `@/lib/X` 在策略 A 之后是否解析等价?
  - 验证:SS 仓内编译时 `findRepoRoot()` 通过 self-exe 反推得到 SS 仓根,projectRoot 也是 SS 仓根(via `findProjectRoot(filePath)` 找 ss.json 上溯)— 两值相等。300 处全等价,bootstrap 三阶段固定点 + tests baseline 完全一致 ✓
- **H2**:`findRepoRoot()` 失败时(`/proc/$PPID/exe` 不可用),`@/` 解析行为?
  - 验证:`resolveStdlibRoot(fallback)` 返 projectRoot,与原 `@/ → projectRoot` 行为完全等价 — **零退化**
- **H3**:外部项目内若有同名 `lib/path.ss`,会怎样?
  - 影响:策略 A 永远指 SS_HOME,用户项目同名文件**不会**winning(C 方案的暗坑被消除)。如果用户想引用项目内的同名文件,用 `./lib/path` 或 `../lib/path` 显式路径
- **H4**:嵌套 import(stdlib lib/crypto.ss `import "@/lib/sha256"`)在外部项目消费链中如何解析?
  - 验证:`resolveInner` 递归调用,每次 import 都重新走 `@/` 解析路径,`findRepoRoot()` 每次返同 SS_HOME(cached)— stdlib 内部 cross-ref 一致解析到 SS_HOME ✓

## §Followup

- **F1**(ss.json `paths` 用户自定 alias):tsconfig 风格 `"paths": {"@app/*": "src/*"}` 用户项目根 alias,补回失去的 `@/` 项目根能力。本轮不做。
- **F2**(stdlib 路径解析规则文档化):`README.md` 或 `docs/guide.md` 加"import 路径解析规则"一节,说明 `@/` `./` `../` `<package>` 四种形态。本轮不做(D 文档已记录,`docs/guide.md` 长期更新由用户决定)。
- **F3**(non-Linux portability):D158 §F2 同源 — `/proc/$PPID/exe` 不可用时 macOS / Windows 抽象,与 D158 共享 fix 时机。

## §Status 时间线

| Phase | Date | Commit | 内容 |
|---|---|---|---|
| 收关 | 2026-05-08 | `<commit-hash>` | bug options.md GATE 产出 + D159 文档落档 + bootstrap/parse/repo_paths.ss 加 resolveStdlibRoot helper + main.ss line 211 改用 resolveStdlibRoot + bootstrap 三阶段固定点 PASS + 外部 stdlib_test e2e PASS + 下游 van-cli `Path.join` / `Path.dirname` + init demo-app e2e PASS + reflection_health F1 GATE PASS(main.ss 628 == bv DRIFT 0)+ d_doc_index GATE PASS + tests baseline 完全一致(301/14/315)|
