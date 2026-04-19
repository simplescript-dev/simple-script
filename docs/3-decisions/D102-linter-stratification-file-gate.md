# D102: Linter 分层化 + F1 文件行数 GATE Plan

**Status:** Plan 阶段(未 Execute)
**Depends on:** D097(14 指标物理定义 + baseline 语义)/ D100 §坑 P(迁移结构成本八股文案例)/ D099 §坑 I-K(M7b/N3 银行余量经验)/ D093 §决策(Zig SEMA 单函数 dispatch 最终目标)
**Date:** 2026-04-19

---

## 第一性需求

D097 14 指标**统一 GATE** 把"迁移结构成本"误报为"腐败",驱动 Claude "凑余量八股文"优化:D100 Execute 1 INDEX_ACCESS 迁移实测 M2 +2 / N2 +10(新函数签名节点 + L132 `||` 链扩一 kind + 新 dispatch 行 > 删 outer wrapper),首版 GATE BLOCKED。应对是"找 inline 压缩候选"凑 M2 -2 / N2 -10,属于 D100 §坑 P 记录的方法论失败 — linter 目的是阻腐败,不是逼凑八股文。

并行问题:**无文件行数上限守护**。当前 `bootstrap/gen_exprs.ss` 1721 行 + 14 文件超 600 行(总 21102 行),D093 §决策 Zig SEMA 最终目标「evalExpr 单函数吸收所有 kind」方向下 gen_exprs.ss 应逐步降到 ≤ 600,但无量化 monotonic gate。D099/D100 的 kind 迁移(每轮从 gen_exprs.ss 搬 26-80 行到 eval_expr.ss)方向对,趋势无单调守护 = 随时可回滚。

**本 D102 根因修两项**:
1. 14 指标**分层**(结构组严格 / 累计组 ±0.5% 漂移窗口),让"迁移结构成本"不再触发 REGRESSION
2. 新增 **F1** 文件行数 GATE,per-file baseline monotonic 下降 + 新文件 ≤ 600 硬阻,最终目标全 ≤ 600

**本 Plan 不 Execute**,仅产出决策 + 方案草稿。

## 核心原则

1. **搬家不是腐败** — 从 gen_exprs.ss 迁 kind 到 eval_expr.ss 是 D093 §决策 鼓励方向,累计组 ±几节点是物理必然
2. **结构 vs 累计分层** — 新结构原子(新递归 / 新 God 入度 / 新嵌套 / 新 helper / 新深度 / 新长序列 / 新成员写入)严格;代码量 / 调用边 / 可变 state 总量允许漂移
3. **漂移窗口粗粒度先落地** — ±0.5% 是 v1 阈值,未来可按"每 kind 迁移预算"(如 M2 +5 / N2 +25 per kind)细化
4. **F1 单调下降** — 14 超标文件 per-file baseline 记录,cur 不许升;新文件硬阻 > 600 防规避"一拆二"
5. **D097 根因语义保留** — 结构组守护一个不降,G1-G5 反射 gate 不退等级;D097 L62「仅两种终态」语义 override 仅累计组
6. **linter 自身适用 F1** — 现 468 行,改后预 ~560 行,仍 ≤ 600;自己通过 F1 才有资格守护别人
7. **baseline 单数据源** — M/N + F1 合并到 `tools/linter_baseline.txt` 用 `F1:` 前缀区分,避免双文件漂移

## 当前事实(2026-04-19 snapshot)

| 项 | 值 |
|---|---|
| D097 规则版本 | v2(2026-04-18 commit 9e20f26) |
| linter 代码 | `tools/reflection_health_linter.ss` **468 行** |
| M/N baseline | M1=5135, M2=76153, M3a=12133, M3b=1879, M4=3038, M5=1750, M6=32, M7a=27, M7b=678, N1=34, N2=380765, N3=518387, N4=321, N5=0(Execute 6b) |
| bootstrap 总行 | 21102 |
| > 600 文件数 | **14** |
| 最大超标 | gen_exprs.ss **1721**(距 600 超 1121) |
| 最小超标 | parse_stmts.ss **617**(距 600 超 17) |
| lib/*.ss 最大 | json.ss 580(已 ≤ 600,F1 无 lib 相关 pending) |

## 决策 1:14 指标分层

### §规则 1.1 分组表

| 指标 | 组 | 分类依据 | 搬家影响(D100 Execute 1 实测) |
|---|---|---|---|
| M3b 最大入度 | **结构** | God 函数 新增即规避 | 0 |
| M4 dispatch 深度和 | **结构** | 新 else-chain 即问题 | 0 |
| M6 递归函数数 | **结构** | 新递归入口是质变 | 0 |
| M7a 最大 IF 嵌套深 | **结构** | 新深度即规避 | 0 |
| M7b 函数总数 | **结构** | 拆 helper 规避(D097 v1 伪造路径) | -1 |
| N3 AST 深度总和 | **结构** | 藏深嵌套规避,削减 = 目标 | -157 |
| N4 最大节点出度 | **结构** | 压长序列规避 | 0 |
| N5 成员写入数 | **结构** | Map 搬 class 字段规避 | 0 |
| M1 CC 总和 | 累计 | 代码量派生 | 0 |
| M2 节点总数 | 累计 | 搬家 ±几节点 | **+2** |
| M3a 调用边数 | 累计 | 调用总量(与 M2 对齐) | 0 |
| M5 可变 state 点数 | 累计 | 总量级 | 0 |
| N1 kind 基数 | 累计 | 新 kind 经性 +1 可接受 | 0 |
| N2 Halstead 体积 | 累计 | M2 × log2(N1) 派生 | **+10** |

**结构组 8 项 / 累计组 6 项**。用户原提示词列表未含 M3a,本 D102 补入**累计组**(语义接近 M2:调用总量级 ≈ 代码量级,搬家=0 但每 call +1 累计)。

### §规则 1.2 漂移窗口阈值

公式: `tol = max(baseline / 200, floor_for_label(label))`

- 累计组 6 项:`tol = baseline / 200`(±0.5%)
- 结构组 8 项:`tol = 0`(严格)
- N1 保底: `baseline / 200 = 0`,N1 设 `floor = 1`(引入新 kind 必 +1,保底避免一 kind 就炸)

| 指标 | baseline | ±0.5% | 实际 vs 窗口 |
|---|---|---|---|
| M1 | 5135 | ±25 | 0 / 25 |
| M2 | 76153 | ±380 | +2 / 380(190× 充裕) |
| M3a | 12133 | ±60 | 0 / 60 |
| M5 | 1750 | ±8 | 0 / 8 |
| N1 | 34 | ±0 → **±1**(保底) | 0 / 1 |
| N2 | 380765 | ±1903 | +10 / 1903(190× 充裕) |

### §规则 1.3 三终态扩展

D097 L62 原定义:「仅此两种终态(PASS / BLOCKED),无中间分级」。D102 分层后引入 DRIFT 第三态:

| 终态 | 条件 | GATE |
|---|---|---|
| PROGRESS | `cur < baseline` | PASS |
| OK | `cur == baseline` | PASS |
| **DRIFT** | **累计组**:`baseline < cur <= baseline + tol` | **PASS**(新增态) |
| REGRESSION | 结构组:`cur > baseline`;累计组:`cur > baseline + tol` | BLOCKED |

**D097 L62 修订**:「仅两种终态」语义仅适用结构组。累计组 DRIFT 表示「漂移窗口内物理波动」,不阻断但也不 record(§规则 1.4)。

### §规则 1.4 record 行为

D097 L102「累积方向严禁更新 baseline」规则**不变**但分层化:

- **结构组**:任一 cur > baseline → record 拒绝(同 D097 v2)
- **累计组**:任一 cur > baseline → record 拒绝(即使在 DRIFT 窗口内也不 record,避免 baseline 慢慢被漂移蚕食)
- **全部指标不升时才 record**:与 D097 一致

## 决策 2:F1 文件行数 GATE

### §规则 2.1 F1 规则集

- **R1**:已知 > 600 文件: per-file baseline 记录当前值,cur > baseline → REGRESSION 阻断;cur < baseline → PROGRESS;cur == baseline → OK
- **R2**:已知 ≤ 600 文件: cur > 600 → REGRESSION 阻断
- **R3**:新文件(baseline 无): cur > 600 → REGRESSION 阻断;否则 record 时入库
- **R4**:record 规则: 文件行数下降时 baseline 更新;降到 ≤ 600 时该文件 baseline **删除**(变成 R2 状态,不允许再升至 > 600)
- **R5**:文件被删除时, record 时该 baseline 条目删除

**最终目标**:所有 bootstrap/*.ss ≤ 600,F1 baseline 全清空。

### §规则 2.2 首次 record baseline 内容

```
F1:bootstrap/gen_exprs.ss=1721
F1:bootstrap/checker.ss=1299
F1:bootstrap/gen_class.ss=1286
F1:bootstrap/codegen.ss=1277
F1:bootstrap/gen_stmts.ss=1125
F1:bootstrap/check_stmts.ss=1083
F1:bootstrap/parser.ss=813
F1:bootstrap/gen_types.ss=738
F1:bootstrap/gen_methods.ss=709
F1:bootstrap/gen_calls.ss=695
F1:bootstrap/gen_decls.ss=691
F1:bootstrap/main.ss=630
F1:bootstrap/gen_runtime.ss=621
F1:bootstrap/parse_stmts.ss=617
```

### §规则 2.3 F1 与 D099/D100 kind 迁移同方向性论证

| 轮次 | gen_exprs.ss 行数变化 | 迁移项 |
|---|---|---|
| D099 Pre | ~1810 | — |
| D099 首批 1a 5 kind | -90 左右 | BINARY/UNARY/TERNARY/SHORT_CIRCUIT/COMPTIME_EXPR |
| **D100 1b INDEX_ACCESS** | **-26(当前 1721)** | INDEX_ACCESS inline body 删 |
| D100 1b 剩余 4 kind(TEMPLATE_LIT/ARRAY_LIT/IDENT/MEMBER_ACCESS) | -150~-250 | 按 D100 L19-23 估 42 + 63 + 40 + 123 行 |
| 1b 完成预期 | ~1500 | 仍 > 600,但方向单调 |
| Zig SEMA D093 最终态 | < 600 | evalExpr 完全吸收 |

F1 GATE 提供 Zig 路线**量化终态**:达成 F1 全绿 ≈ gen_exprs.ss 解构完成 ≈ D093 §决策「evalExpr 单函数 dispatch」落地。F1 既守护单调性也量化 Zig 路线进度。

### §规则 2.4 防规避

- **一拆二**:把 1721 行 gen_exprs.ss 拆成两个 861 行文件,R3 硬阻(新文件 > 600)—— 必须真实削减
- **换位置**:把代码从 gen_exprs.ss 搬到 gen_stmts.ss(已超标),R1 对目标文件阻断 cur > baseline —— 必须走新的 ≤ 600 文件或既有 ≤ 600 文件
- **分裂伪移**:把 gen_exprs.ss 从 1721 降到 900 然后新建 eval_xyz.ss 821 行,R3 阻(新文件 > 600)—— 强制走 ≤ 600 小文件

三种规避手法全在 R1-R3 覆盖范围。

## 决策 3:linter 代码层改动草案(Phase 2 Execute,本 Plan 不落地)

### §方案 3.1 改动位置表

| # | 位置 | 改动 | 函数增量 |
|---|---|---|---|
| 1 | L403-415 `reportDelta` | 加 DRIFT 分级 + `tol` 参数,lookup inline | 0 |
| 2 | L65 常量区 | 加 `F1_LIMIT = 600` / `fileLineCounts` Map | 0 |
| 3 | L291-303 `processFile` | 首行加 line count 计算 inline(`for c in source { if c=='\n'... }`) | 0 |
| 4 | main L417 后 | 新增 `checkF1` 独立函数(F1 baseline 比对 + report) | **+1** |
| 5 | L323-344 `writeBaseline` | 写入尾部追加 F1 条目(inline,不新函数) | 0 |
| 6 | L346-401 `compareAndReport` | 末尾调 `checkF1()` 合计 regressions | 0 |
| 7 | L310-321 `readBaselineVal` | 支持 `F1:<path>=` 前缀查询(改签名) | 0 |
| 8 | main L418 | 打印 F1 结果段 inline | 0 |

**M7b 净增量 +1**(checkF1)。

### §方案 3.2 M7b 余量策略

M7b 当前 baseline 678 / 679 cur(D099 Execute 6b 后 record 678,之后未再 record;实时 M7b 需 Phase 2 重跑 linter 确认)。

**选项 A**(优先):分层落地后 M7b 变结构组严格,checkF1 +1 必须同步削减 1 个现有 helper 来抵消。候选:
- `mapSetInt`(L73-75,3 行):2 处调用(L105, L323 附近),inline 到调用点可消
- `funcTop`(L89-93,5 行):1 处调用 `countEdge`,inline 可消
- `popFunc`(L80-87,8 行):1 处调用,逻辑可搬进 visit FUNC_DECL 出栈处

**选项 B**:接受 Execute 0 预削减轮(类似 D100 §步骤 0),单 commit 先削 1-2 函数腾余量,再 Execute 1 新增 checkF1。

**选项 C**:利用银行余量(若 Execute 1 后实际 M7b < 678,有隐余量)—— 不可靠,不走。

**推荐选项 A + 选项 B 结合**:Plan 阶段明确 Execute 1 同一 commit 里 (+checkF1 -1 helper) 净 0,无需预削减轮。

### §方案 3.3 linter 自身行数影响

改动预估 LOC:+80~100(新 checkF1 ~40 行 + 各位置扩展 ~40-60 行)。

当前 468 行 → 预计 ~560 行,**仍 ≤ 600,自己通过 F1**。关键:checkF1 逻辑紧凑(30-40 行 per-file 循环 + baseline diff),不能膨胀到 580+ 导致 F1 自阻。

### §方案 3.4 代码骨架示意(不 Execute)

**toleranceFor inline 到 reportDelta**:
```ss
function reportDelta(label: string, cur: int, baseline: int): int {
    if (baseline < 0) { println(`  ${label} cur=${cur} baseline=(missing)`); return 0 }
    // 分层阈值 inline lookup
    let tol = 0
    if (label == "M1 " || label == "M2 " || label == "M3a" || label == "M5 " || label == "N1 " || label == "N2 ") {
        tol = baseline / 200
        if (label == "N1 " && tol == 0) { tol = 1 }
    }
    const delta = cur - baseline
    let tag = "OK"
    let isReg = 0
    if (cur > baseline + tol) { tag = "REGRESSION"; isReg = 1 }
    else if (cur > baseline) { tag = "DRIFT" }
    else if (cur < baseline) { tag = "PROGRESS" }
    println(`  ${label} cur=${cur} baseline=${baseline} delta=${delta} tol=±${tol} → ${tag}`)
    return isReg
}
```

**checkF1 新增函数**:
```ss
function checkF1(): int {
    let regs = 0
    const text = fileExists(BASELINE_PATH) == 1 ? readFile(BASELINE_PATH) : ""
    let fi = 0
    while (fi < files.length()) {
        const path = files[fi]
        const cur = parseInt(fileLineCounts.getString(path))
        const bKey = `F1:${path}=`
        let base = -1
        for (line in text.split("\n")) {
            if (line.startsWith(bKey) == 1) { base = parseInt(line.substring(bKey.length(), line.length() - bKey.length())) }
        }
        let tag = "OK"
        if (base >= 0) {
            if (cur > base) { tag = "REGRESSION"; regs = regs + 1 }
            else if (cur < base) { tag = "PROGRESS" }
        } else {
            if (cur > F1_LIMIT) { tag = "REGRESSION (> 600)"; regs = regs + 1 }
        }
        if (base >= 0 || cur > F1_LIMIT) { println(`  F1 ${path} cur=${cur} baseline=${base} → ${tag}`) }
        fi = fi + 1
    }
    return regs
}
```

**processFile inline line count**:
```ss
function processFile(path: string) {
    const source = readFile(path)
    let lc = 1
    let sp = 0
    while (sp < source.length()) { if (source.charAt(sp) == "\n") { lc = lc + 1 }; sp = sp + 1 }
    fileLineCounts.set(path, `${lc}`)
    tokenize(source)
    const rootId = parse("done")
    visit(rootId, 0, 0)
    const topList = nGetList(rootId)
    if (topList == "") { return }
    for (p in topList.split(",")) {
        if (p == "") { continue }
        const sid = parseInt(p)
        if (sid > 0 && nGetKind(sid) == "VAR_DECL") { m5 = m5 + 1 }
    }
}
```

**writeBaseline 扩展(尾部追加 F1)**:
```ss
function writeBaseline() {
    // ... 原 M/N 累积方向检查逻辑不变 ...
    let text = `# auto-generated by tools/reflection_health_linter.ss — do not edit\nM1=${m1}\n...\nN5=${n5}\n`
    let fi = 0
    while (fi < files.length()) {
        const path = files[fi]
        const cur = parseInt(fileLineCounts.getString(path))
        if (cur > F1_LIMIT) { text = `${text}F1:${path}=${cur}\n` }
        fi = fi + 1
    }
    writeFile(BASELINE_PATH, text)
}
```

## Phase 划分(不 Execute)

### Phase 1:Plan ✅(本轮)

- D102 决策文落地
- 分层规则 §规则 1.1-1.4
- F1 规则 §规则 2.1-2.4
- linter 代码改动草案 §方案 3.1-3.4

### Phase 2:Execute linter 分层化 ⏳(下轮)

按 §方案 3.1-3.4 落地 linter 代码。步骤:

1. `Step 0`(可选):若 M7b 银行余量 < 1,先 commit 削 1 helper(mapSetInt/funcTop/popFunc 三选一)
2. `Step 1`:改 reportDelta 加 DRIFT 分层(选项 A +checkF1 同 commit)
3. `Step 2`:processFile 加 line count + writeBaseline 加 F1 条目 + main 加 checkF1 调用
4. `Step 3`:`bin/ss run tools/reflection_health_linter.ss record` 首次写入 F1 baseline(14 条)
5. `Step 4`:负例测试 — 手工 append 10 行到 gen_exprs.ss 验证 R1 阻断,手工新建 601 行文件验证 R3 阻断,撤销
6. `Step 5`:`./build.sh bootstrap` 固定点 PASS
7. `Step 6`:commit(linter 代码 + baseline 首次 F1 record)

### Phase 3:回放 D100 §坑 P 验证 ⏳(可选)

手工制造 M2 +2 / N2 +10 scenario 跑 linter,验证 DRIFT 分级 + PASS。

### Phase 4:驱动 1b 剩余 kind 迁移 ⏳

D101(TEMPLATE_LIT)→ D103-D105(ARRAY_LIT / IDENT / MEMBER_ACCESS)依次迁移,每轮验证:
- 结构组无 REGRESSION(净削减或 OK)
- 累计组允许 DRIFT 不阻断
- F1 gen_exprs.ss 单调下降

## 风险 + 反模式

### ❌ 反模式

- **"凑余量"八股文**(D100 §坑 P):为累计组 +2 强行搜 -2 凑齐,破坏 no_workaround
- **文件一拆二**:1721 行拆成两个 861 行,R3 未覆盖时易漏 — 本 D102 §规则 2.4 已覆盖
- **N5 归累计**:破坏"Map 搬 class 字段"规避守护,D097 v2 核心防线
- **结构组放宽**:任一结构指标加 tol 即 D097 v2 退化成 v1,可被伪造
- **linter 自膨胀**:改动后 linter > 600,F1 自阻 = 笑话

### ⚠ 风险

| 风险 | 缓解 |
|---|---|
| ±0.5% 对小基数指标失效 | N1 保底 ±1;未来考虑 M6(32) / M7a(27) 加保底 |
| ±0.5% 对大基数过宽(M2 380 / N2 1903) | v1 接受粗粒度;Phase 4 按 kind 迁移预算细化 |
| M3a 归类争议 | 累计组(本 D102 决策);若 Phase 4 观测到 M3a 搬家影响 > 0 则重审 |
| N1 归类争议 | 累计组(引入新 kind 本应走单独 D 审批,linter 保底 ±1 不破坏根因) |
| F1 per-file baseline 解析膨胀 readBaselineVal | readBaselineVal 签名改(支持 `F1:<path>=` 前缀),最坏 checkF1 独立 O(N_files × N_lines) 循环 |
| `./build.sh bootstrap` 耗时 2-3 分钟 × linter Execute 多次 | Plan 已把改动合并到最少 commit(2-3 个)降低成本 |

### ✅ 正模式

- **结构组 8 项严格守护**:D097 根因 gate 不退
- **累计组 DRIFT 窗口**:合法迁移期物理成本显式承认
- **F1 单调下降 + 新文件硬阻**:规避路径全覆盖
- **linter 自身 ≤ 600**:自举一致性,守护者自己先达标

## 参考

- D097(指标定义 + L62 「仅两种终态」原语义 + L102 累积严禁 record)
- D100 §坑 P(迁移结构成本八股文案例)/ §坑 Q(银行余量)
- D099 §坑 I-K(M7b 银行余量 / N3 body 深度经验)
- D093 §决策(Zig SEMA 单函数 dispatch 最终目标)
- D094 §规则 2(pure subset 白名单,1b 迁移范围)
- CLAUDE.md §反射根因 gate(强制条款)
- `tools/reflection_health_linter.ss` L403-415(reportDelta 当前)/ L323-344(writeBaseline 当前)/ L291-303(processFile 当前)
- `tools/linter_baseline.txt`(Execute 6b baseline)
- `bootstrap/*.ss` 14 文件 > 600(本 D102 §规则 2.2 首次 record 清单)
