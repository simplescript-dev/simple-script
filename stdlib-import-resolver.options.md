# Bug 修复方案对比表 — stdlib `@/lib/X` import 在外部项目断链

## 症状

```
# 外部项目 /root/code/vanengine/van-ss/crates/van-cli/src/commands/init.ss:
import { Path } from "@/lib/path"
function main() { Path.join("a", "b") }

$ ss check src/main.ss
error: undefined variable 'Path' ... did you mean 'Math'?
```

## 根因

`bootstrap/main.ss:210-211`:
```ss
if (importPath.startsWith("@/") == 1) {
    fullPath = projectRoot + "/" + importPath.substring(2, ...)
}
```

`@/` 硬编码为消费项目根 alias。SS 仓内 `@/lib/X` 等价 SS_HOME(因 SS 仓本身就是 SS_HOME),但**外部项目** `@/lib/X` 解析为外部项目根 + lib/X — 不存在。

**真正爆炸面**:`lib/crypto.ss:14` 等 stdlib 内部 cross-ref `import "@/lib/sha256"`。外部项目消费 `@/lib/crypto` 时,resolveInner 递归处理 lib/crypto.ss 的 imports,projectRoot 仍是外部项目根 → **stdlib 内部 cross-ref 全断**。

## 假设破裂

**用户描述假设**:`@/lib/path` 找不到是单点问题。
**勘察后破裂**:不是单点。300 处 `@/lib/X` 真实 import,**全在 SS 仓内**(lib/ + tests/);零外部用例。stdlib 内部相互引用同病。

## 候选方案

### 层次

- **数据**:`@/` 字面前缀解析的目标 dir
- **接口**:外部项目 import stdlib 的语义形态、`@/` 是否能继续做项目根 alias
- **架构**:stdlib 与用户代码是否同一 namespace、迁移成本与未来扩展空间

### **A**:`@/` 永远指 SS_HOME(stdlib),用户项目用 `./` `../` 相对引用

| 维度 | 内容 |
|---|---|
| 思路 | line 211 `projectRoot + "/" + path` → `SS_HOME + "/" + path`,复用 D158 `findRepoRoot()`(SS_HOME == repo root)。SS 仓内 300 处 `@/lib/X` 解析等价(SS_HOME == SS 仓根),零迁移。外部项目用 `./` `../` 表达项目内引用。 |
| 层次 | 数据 + 接口 |
| 业界对标 | Deno `@std/...` (Deno 1.x → JSR namespace) / Go `import "fmt"` 直接绑定 stdroot;TS path alias 通常通过 `tsconfig.json` 配置项目根 alias 而非 `@/` |
| 根因解决度 | 100% — 外部项目 + stdlib 内部 cross-ref 全修 |
| N 年返工度 | 中 — 用户项目失去 `@/` 当根 alias 的能力,日后若想加回需独立 alias 机制(如 `@app/` 或 ss.json 配置) |
| 实施依赖 | (1) D158 `findRepoRoot()` 复用 — 已落地;(2) line 211 一处 patch;(3) 文档新增"import 路径解析规则"一节 |
| 风险 | 用户项目内代码一律 `./` `../`,深层目录路径难看(`../../../../utils/x.ss`)— 但这是 TS/JS 标准做法 |
| 迁移成本 | 0(SS 仓内 SS_HOME == 项目根 等价) |

### **B**:`@/` 保留消费项目根,新增 stdlib alias(`@std/X` 或裸名 `lib/X`)

| 维度 | 内容 |
|---|---|
| 思路 | `@/` 不变。新增前缀 `@std/`(或裸名 `lib/X` 走 resolvePackage 优先 SS_HOME)。SS 仓内 300 处 `@/lib/X` 全迁移到 `@std/X`。tests/ 和 lib/ 全 sed。 |
| 层次 | 数据 + 接口 + 架构 |
| 业界对标 | npm `@scope/pkg` namespace / TS path alias 复合 / Deno JSR `@std/...` |
| 根因解决度 | 100% |
| N 年返工度 | 低 — alias 机制扩展性好,日后可加 `@user/` `@vendor/` 等 |
| 实施依赖 | (1) D158 findRepoRoot 复用;(2) line 211 加 `@std/` 分支;(3) **300 处 `@/lib/X` → `@std/X` 全仓 sed** + bootstrap;(4) 文档 |
| 风险 | 300 处迁移触面 + lib 内部 cross-ref `lib/crypto.ss` `lib/spring/*.ss` 等也要迁移;一次性 sed 风险低但需仔细审 |
| 迁移成本 | 高 — 300 处全仓批量改 |

### **C**:`@/` 两段查找 — 项目根优先,SS_HOME fallback

| 维度 | 内容 |
|---|---|
| 思路 | line 211 改:先 `projectRoot + "/" + path`,fileExists 命中走;否则 `SS_HOME + "/" + path` fallback。 |
| 层次 | 数据 |
| 业界对标 | Python `sys.path` 多搜索路径、CommonJS `node_modules` 上溯查找 |
| 根因解决度 | 80% — 暗坑:外部项目根下偶然有 `lib/path.ss` 时,神秘行为变化(隐式覆盖 stdlib) |
| N 年返工度 | 高 — 路径歧义导致 debug 困难,长期演化必返工拆 |
| 实施依赖 | (1) D158 findRepoRoot;(2) line 211 加 fallback 链 |
| 风险 | 用户文档:"为什么我的 lib/path.ss 没生效"—— 因为 stdlib 优先;反过来"为什么 stdlib 没生效"—— 因为本地 lib/path.ss winning。歧义 |
| 迁移成本 | 0,但暗坑长期债务 |

### **D**:`@/` 永远指 SS_HOME + ss.json `paths` 用户自定 alias(扩展 A)

| 维度 | 内容 |
|---|---|
| 思路 | A 的基础上,允许用户项目 ss.json 加 `"paths": { "@app/*": "src/*" }` 自定 alias(类似 tsconfig)。stdlib `@/` 永远 SS_HOME,用户项目根 alias 用 `@app/` 等用户自定。 |
| 层次 | 数据 + 接口 + 架构 |
| 业界对标 | tsconfig.json `compilerOptions.paths` / webpack `resolve.alias` |
| 根因解决度 | 100% + ergonomics |
| N 年返工度 | 极低 — 用户扩展能力齐全 |
| 实施依赖 | A 全部 + ss.json paths 字段解析 + alias resolution prefix-match |
| 风险 | 实施量约 3× A;ss.json paths 字段需 spec 化 |
| 迁移成本 | 0 |

## 决策

**选 A(`@/` 永远指 SS_HOME)**,**因**:
- 根因解决度 100%(外部项目 + stdlib 内部 cross-ref 全修)
- 迁移成本 0(SS 仓内 SS_HOME == 项目根,语义等价)
- 实施依赖 D158 已落地的 findRepoRoot,一处 patch
- 用户对话锁定推荐 A
- B 的迁移成本(300 处)无对应根因收益,A 已 100% 解
- C 拒绝(路径歧义,长期返工)
- D 是 A 的 ergonomics 增量,本轮不做(留 §Followup)

## 用户确认锚

用户已锁 A,直接执行。
