# build.sh 三阶段固定点校验假阳性 — 修复方案对比(MNK §轨 1)

**bug**: `build.sh:27` 用 `diff <(xxd /tmp/ss_stage2) <(xxd /tmp/ss_stage3) > /dev/null 2>&1` 做三阶段自举固定点校验。本环境 `xxd` 缺失,bash process substitution `<(xxd …)` 退化为空流,`diff` 比较两个空流恒返 0 → "Fixed point verified! Stage 2 = Stage 3" 假阳性。stage2≠stage3 的非确定 miscompilation 不会被发现。

**父约束**: `docs/1-axioms.md §C1 Self-bootstrapping` —— "The compiler compiles itself. Every change must pass 3-stage fixed-point verification (stage2 == stage3 **byte-identical**)。"

**结论**: **选 C —— `cmp -s` 直接字节比较**(见 §4 决策行)。

---

## 1. 根因机理(坐实)

`diff <(xxd a) <(xxd b)` 的设计意图是把二进制 hex-dump 成文本再 diff,使差异可读。但:

1. 整行尾随 `> /dev/null 2>&1` —— xxd 的 hex 文本输出**全被丢弃**,"可读性"收益为 0,xxd 在此自始无用。
2. `xxd` 随 `vim-common` 包发行,**非** POSIX / coreutils 基础工具,默认不保证存在(本环境 `which xxd` 实测无输出)。
3. bash process substitution `<(cmd)`:`cmd` 失败(此处 `xxd: command not found`)**不传播**到外层 `diff` —— `<(失败cmd)` 仅产出一个合法的空 FIFO 流。

→ `diff <(空流) <(空流)` 恒等 → exit 0 → `if` 取真 → "Fixed point verified!" 无条件打印 + `cp /tmp/ss_stage2 bin/ss`。校验静默降级为"恒真",且打印的是**成功**信息,无报错无警告。

## 2. 假设破裂入口

`diff <(xxd /tmp/ss_stage2) <(xxd /tmp/ss_stage3)` 隐含两个假设,**两者皆破裂**:

- **假设 A**「`xxd` 在构建环境存在」—— **破裂**:`which xxd` 无输出,xxd 属 vim 包非基础工具。
- **假设 B**「process substitution 内子命令失败会令外层命令失败」—— **破裂**:bash PS 吞掉子命令退出码,`<(失败)` = 空流,`diff` 拿到的是两个合法空流而非错误。

两假设同时破裂 → 校验从"逐字节比较"静默退化为"空流比较恒真"。

## 3. 候选方案对比

| 候选 | 层次 | 改动 | 评估 |
|---|---|---|---|
| A | 数据层 patch | 保留 `diff <(xxd …)`,其前加 `command -v xxd` 守卫,缺失则 echo 警告并降级/跳过 | 仍依赖 xxd(存在时);新增条件分支;xxd hex 输出本就 `>/dev/null` 丢弃无收益。只触假设 A 未触假设 B,且把"工具缺失"当常态降级 = 容忍 workaround 不修根因。**淘汰** |
| B | 接口层 trap | `xxd` 换成 `od -An -tx1`(coreutils)或 `hexdump`,保留 `diff <(…) <(…)` 架构 | `od` 是 coreutils 基础工具,依赖层面鲁棒、功能上可正确。但**保留 "transform→text→diff" 冗余架构** —— 为一个 `>/dev/null` 丢弃的 hex 输出维持无用中间层 + 双 process substitution,非最简。换一个工具不换架构 |
| C | 架构层 refactor | 整段 `diff <(xxd a) <(xxd b) > /dev/null 2>&1` → `cmp -s /tmp/ss_stage2 /tmp/ss_stage3` | `cmp` 直接逐字节比较二进制,无文本 transform、无 process substitution、无非必需依赖(`cmp` 是 POSIX/coreutils 基础工具,`which cmp` → `/usr/bin/cmp`)。**同时消除假设破裂 A+B**:无依赖可缺失、无 PS 吞错。`-s` 静默仅返 exit code,与 `if` 直接配合,严格更简 |
| D | 架构层 refactor | 用 SS stdlib sha256 算两 stage 二进制哈希再比较,或自研 SS 固定点校验工具 | "root 上加 root"但**过度工程**:hash 是"字节相等"的弱代理(理论碰撞面),`cmp` 已直接、精确覆盖该能力;且多一个构建步骤 / 自研工具维护面。`cmp` 已是最直接原语,hash 是 proxy 非 root |

## 4. 决策行

**选 C 因** `cmp -s` 是 byte-identical 文件比较的 POSIX 规范直接原语,是 4 候选中根因解决度最高项 —— 同时消除假设破裂 A(无外部非必需依赖可缺失)与 B(无 process substitution 吞错);A 仅触假设 A 且容忍 workaround;B 功能可正确但保留 "transform→text→diff" 冗余架构(为已丢弃输出维持中间层);D 是 `cmp` 已直接覆盖能力的弱代理 + 多构建步骤 = 过度工程。**不选更深的 D** 因 `cmp` 已是字节比较最直接原语,再"加深"是引入 proxy 而非消除根因。排序依据为根因解决度,非工程量。

## 5. 长久评估

`cmp` 是 POSIX 标准工具(coreutils),40+ 年稳定,无演化返工风险。业界对标:GCC / Clang / Rust 自举与可复现构建(reproducible build)的固定点验证均用 `cmp` / 直接字节比较,而非 hex-dump-then-diff。N 年返工度 ≈ 0。底层依赖链:C 不依赖任何未落地的更基础候选(`cmp` 即时可用),无"先做基础候选"前置。

## 6. §实证(MNK §字段 12)

**根因定位 grep 证据**:

```
$ which xxd
（无输出 —— xxd 缺失)
$ grep -n 'xxd' build.sh
27:    if diff <(xxd /tmp/ss_stage2) <(xxd /tmp/ss_stage3) > /dev/null 2>&1; then
$ which cmp
/usr/bin/cmp
$ grep -rnI 'xxd' . --exclude-dir=vendor --exclude-dir=.git
build.sh:27:    if diff <(xxd /tmp/ss_stage2) <(xxd /tmp/ss_stage3) > /dev/null 2>&1; then
docs/4-issues/I024-double-comptime-annotation-codegen-segfault.md:63:
  ... bootstrap 三阶段 Stage2=Stage3(`xxd` 缺失须 `cmp /tmp/ss_stage2 /tmp/ss_stage3` 自验)...
```

→ 代码层 bug 实例**唯一**:`build.sh:27`。`I024:63` 是该 bug 的**文档记述** + 手工 workaround 注记("xxd 缺失须手动 cmp 自验")—— 正是 CLAUDE.md §Root Cause 警告的"同一 workaround 出现第二次必须停下修根因";本修复把该 workaround 从手工注记升级为 build.sh 原生行为。code same-pattern 残留 = 0。

**最危险假设最小 spike(试切)** —— 假设「`cmp -s` 能正确区分不同文件 / 识别相同文件」:

```
$ printf 'STAGE2-BINARY-A' >a; printf 'STAGE3-DIFFERENT' >b; printf 'STAGE2-BINARY-A' >c
$ cmp -s a b; echo $?      → 1   (不同文件,正确检出 != 0)
$ cmp -s a c; echo $?      → 0   (相同文件,正确识别 0)
$ diff <(xxd a) <(xxd b) > /dev/null 2>&1; echo $?
  xxd: command not found   (×2)
  → 0                       (旧逻辑对不同文件假阳性,实证坐实)
```

最危险假设 spike **实证成立**;旧逻辑假阳性 **实证坐实**。完整 bootstrap 实证(三阶段固定点 + 全测)见 `tools/bugfix_reports/2026-05-19-build-xxd-fixed-point.bugfix` §verify。
