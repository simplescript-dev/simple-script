# SS-LIM-3 Multi-line import — 修法方案对比

## 现象

```
import {
    Foo,
    Bar,
    Baz
} from "./mod"
function main() { println("ok") }
```

`bin/ss check` 报：`parse error at line 1: expected newline or '}', found COMMA`（行号错位 — 非真实 import 块行号）。等价单行 `import { Foo, Bar, Baz } from "./mod"` 通过。

## 根因 trace（双层不变量同时破裂）

1. **接口层 trap**：`bootstrap/main.ss:188-230 resolveInner` 用 `line.startsWith("import ")` **逐行字符串扫描**识别 import。多行 import 时只命中 line 1（`import {`）;`extractImportPath(line)` 找不到同行 `from`,该行被吞;line 2-5(`Foo,` / `Bar,` / `Baz` / `} from "./mod"`) 被当作普通代码累积进 `mainCode`,丢给 parser。**parser 永远收不到 IMPORT token 开头的多行块**,所以候选 A 单修无效。

2. **数据层不变量**：即便 resolveImports 修好,`bootstrap/parse/parser.ss:622-652 parseImport` 内 `while` 循环也没在 LBRACE 后 / COMMA 后 / RBRACE 前调 `skipNL()`,与同文件 `parseEnumDecl` line 612 / `parseSwitch` line 144 同模式不一致 — parser 自身 robustness 缺角。

## 候选对比

| 候选 | 层次 | 描述 | 优 | 劣 | 假设破裂 | 决策 |
|---|---|---|---|---|---|---|
| **A** | 数据层 patch | 仅改 parser.ss parseImport 加 skipNL（LBRACE 后 / COMMA 后 / RBRACE 前各一处） | LOC 最小 ~3 行 | **完全无效** — resolveImports 上游字符串扫描已吞掉多行块,parser 永远收不到 IMPORT token 开头的多行内容 | 假设 H1「parser 是唯一拦点」破裂 — 实测上游 resolveImports line-scan 才是首拦点（main.ss:206 `line.startsWith("import ")` + extractImportPath 同行查 from） | ✗ |
| **B** | 接口层 trap | 仅改 main.ss resolveImports 多行 import 块累积:`startsWith("import ")` 命中后若同行无 `from `,继续累积下行直到含 `from "..."` 闭合,整段调 `extractImportPath` 提取 path,整段不进 mainCode | LOC ~15 行；当前 RED 立刻 GREEN（用户问题表层修复） | parser invariant 仍残缺；将来若有其他路径喂 parser（prelude / @ct 求值产物 / @derive 输出代码块）多行 IMPORT token 流,parser 仍报错。Robustness 不一致 | 假设 H2「resolveImports 是唯一入口」破裂 — parser 应是 robust 的下游 invariant,不应假设上游 100% 过滤 | ✗（半根） |
| **C** | 接口层 trap + 数据层一致性补强 | A + B 双修：(1) main.ss resolveImports 多行块累积消除"字符串 line-scan 假设单行 import"破裂入口；(2) parser.ss parseImport 加 skipNL 与 parseEnumDecl / parseSwitch 同模式补齐数据层不变量 | 双层都 robust；与编译器既有"上下游各自负责自己 invariant"哲学一致；与 parseEnumDecl line 612 同模式（局部一致性补齐而非新增抽象）；下轮切 token-based AST 模块图时 parser skipNL 修法可直接继承（零返工） | LOC ~18 行 + 2 文件 | 假设 H3「双修是过度工程」破裂 — parser robustness 是独立 invariant,resolveImports 改写不能替代;两层各自的破裂入口客观存在(grep parser.ss:622 / main.ss:206 同时锚到) | ✓ |
| **D** | 架构层 refactor | 把 resolveImports 切到 token-based AST 模块图：先 tokenize 顶层文件,parser 识别真正的 IMPORT 节点 list,再递归 import 每个文件;消除 line-by-line 字符串扫描机制 | 架构最干净;长远视野 N+1 工程目标;消除"字符串扫描 vs token 解析"双轨制 | 本轮 scope 爆炸 ~200 LOC + 多文件;**且依赖未落地基础**:lexer 当前不可重入(单全局 `src` / `pos` 状态),需先做 lexer 状态隔离才能多文件 tokenize → 候选 D 依赖更基础候选 E(lexer 重入) — **底层依赖链未达**,本阶段做不到 | 假设 H4「现在就需要 token-based AST 模块图」破裂 — TS 演化顺序: TS 1.x line-scan two-pass → 2.0 ModuleResolver AST diff,业界先字符串后 AST 渐进路径;SS 当前在字符串阶段,跨阶段 N+1 工程超 SS-LIM-3 issue scope | ✗（远期） |

## 决策

**选 C 因 当前阶段双层都是不变量,单修一层留 robustness 缺口。** A 完全无效（上游拦死）；B 半根（parser invariant 仍缺）；D 跨阶段 N+1 工程依赖未落地基础（lexer 重入）。C 是**当前阶段最深可达根因**。

### ladder 追问

ladder 还能上推一格吗？yes — 候选 D 比 C 深一层。但 ladder 上推即出本阶段编译器 scope:

- **底层依赖链**：D 依赖 lexer 重入,SS 当前 lexer 单全局状态,候选 E 必先于 D 起首 — 物理边界
- **业界演化对标**：TS 1.x line-scan + 2.0 AST 模块图 — 演化顺序客观判据,SS 当前在字符串阶段,跨阶段直接做 D 违反业界渐进路径
- **N 年返工度**：C 内 parser skipNL 修法在 D 落地后**可直接继承零返工**（parser 仍需 robust 多行 IMPORT 解析）；C 内 resolveImports 多行累积修法在 D 落地后会被替换,但**返工幅度小**（语义可迁移）

C 锁定为**本阶段最深可达根因**。下轮 issue 锚：起 D 文档"切 token-based AST 模块图"远期 — lexer 重入 + 模块图同步推进。

## 假设破裂总览

- H1（parser 是唯一拦点）破裂 → 否 A
- H2（resolveImports 是唯一入口）破裂 → 否 B
- H3（双修是过度工程）破裂 → 选 C
- H4（现在就需要 AST 模块图）破裂 → 否 D（远期 + 依赖未落地）

## 跨候选联动

C 内 A + B 互不耦合：B 修上游入口让 parser 收到 IMPORT token 流；A 修下游 parser 让 NEWLINE 正确忽略。两层各自的破裂入口客观存在,不可互相吸收。spike 验证可分别独立验证（A 改 parser 单测;B 改 resolveImports 端到端测）。
