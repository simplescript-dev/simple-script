# D111: Phase B InternPool 引入 + valOf/valType 改走 pool.load(Execute 2 Plan)

**Status:** Plan ⏳(Execute 0/1 未开工,2026-04-20 起草)
**Depends on:** D110 §下一步 #3(L237 `[ ] Planned — Execute 2 及后续 ... 独立 D 文档 D111+`)/ D110 §决策 2(valOf/valType 接口边界 Phase A→B 桥)/ D098 §决策 1 mv 编码 Phase A 不变 / §决策 2 §Phase B 三段(L121-129:`internPool: Map<string,int>` / key=tag+"|"+payload_serialization / `ctVal` 改走 `internPoolGetOrInsert` / `interp*` 调用点过 `valOf` 屏蔽差异 / O(1) eql 收益)/ §新张力 2(Phase A→B 接口稳定性 D110 已闭环)/ §新张力 4(L184-186:`STR|<huge_string>` 预 hash 开放问题,本 Plan 必决)/ D097 L70-71(累计组永不 record)/ D102 §规则 1.1-1.4 分层 GATE / §规则 2.1-2.3 F1 GATE / D101 baseline(D110 延续作 Phase A→B 全程对照基)/ D094 §规则 2 pure subset / D093 §决策 §Zig 原理 第 4 条(InternPool 统一去重)/ D088 §第一性需求(Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS) / CLAUDE.md §反射根因 gate / §交互式单文档 / §PFV 流程 / `memory/feedback_ultrathink_gate.md` / `memory/feedback_design_no_code_authority.md` / `memory/feedback_no_dramatic_reset.md`

**Date:** 2026-04-20

---

## 第一性需求

D110 Execute 1 commit `cc7cc79` 已落地 Phase B 起步:`bootstrap/gen_maybeval.ss:8-14` valOf/valType 接口边界 + 9 处 evalExpr 驱动路径调用点改走访问器。Phase A→Phase B 接口桥通,**InternPool 本体仍未引入** — `valOf(valId) = payload(valId)` 仍走 D089 ctVal bit 30 位运算解码,`valType(valId) = interpType(payload(valId))` 仍走 D092 tvKindOf 直读,即 D098 §决策 2 文本里 "Phase B: pool.load(valId).{payload,tag}" 的内层 pool.load **未实化**,`Value.eql(a, b)` 仍走深比较(`interpAsInt(a) == interpAsInt(b)` 走 tvIntOf×2 Map lookup)。

D088 §第一性需求(Zig SEMA 一份 evalExpr,反射 Meta 对象访问 = 普通 evalExpr MEMBER_ACCESS)的 D098 §决策 2 §Phase B 收益链:

```
反射 Meta 对象高频访问(`for f in cls.fields { if f.name == "x" }`)
  → Value.eql 高频
  → 当前实现:每 == 调用 tvIntOf×2 / tvStringOf×2 走 Map.getString,大 O 上界 O(Map hash)×2
  → Zig 路线:dedup 后同值同 id,id == id 即 eql,O(1)
```

**否定证据**:不引入 InternPool dedup → Phase B 反射 Meta 路径 Value.eql 仍 O(Map) 深比较 → Zig 路线 O(1) eql 不可达 → D098 §决策 2 Phase C(`interp*` 内部全迁 InternPool)评估失去前提(无 dedup 支持就无 O(1) eql 度量基线)。

D110 §下一步 #3 L237 已写 `[ ] Planned — Execute 2 及后续 ... 独立 D 文档 D111+`,本 Plan 即 D110 委托的 Execute 2 Plan。**本 Plan 三重职责**:

1. **InternPool 数据结构 + dedup 入口改造** — D098 §决策 2 §Phase B 文本指定 `ctVal` 改走 `internPoolGetOrInsert(key)` 返回稳定 int,本 Plan 拍板 5 标量 `interpNew*` 入口先做 dedup
2. **valOf/valType 改走 pool.load** — D098 §决策 1 末尾 `valOf=pool.load(valId).payload` / `valType=pool.load(valId).tag` 文本实化,本 Plan 给最简方案(valOf 物理等价 + valType 真正经 pool 反查)
3. **D098 §新张力 4 key 设计拍板** — 本 Plan 选「直接原串 + `|` 分隔」(方案 A),sha256 预 hash 留 Phase C 评估

## 当前事实(2026-04-20 snapshot,commit `cc7cc79`)

| 项 | 值 / 位置 |
|---|---|
| valOf 实现 | `bootstrap/gen_maybeval.ss:8-10` `return payload(valId)`(D089 bit 30 strip)|
| valType 实现 | `bootstrap/gen_maybeval.ss:12-14` `return interpType(payload(valId))`(走 D092 tvKindOf)|
| valOf/valType 调用点 | `bootstrap/eval_expr.ss` 6 处 + `bootstrap/eval/index_access.ss` 2 处 = 共 8 处(D110 Execute 1 范围,符合预估 5-10 上界)|
| ctVal/payload | `bootstrap/codegen.ss:131-141`(bit 30 tag,Phase A 不变)|
| interpNew* 标量入口 | `interpNewInt` L297 / `interpNewString` L301 / `interpNewBool` L305 / `interpNewNull` L309 / `interpNewType` L314 — 共 5 个,**本 Plan dedup 范围** |
| interpNew* 非标量入口 | `interpNewArray` L322 / `interpNewMap` L413 / `interpNewDouble` L505 — 共 3 个,**本 Plan 不做**(留 Phase C)|
| interpNew* 总调用 | 187 处 across 17 文件(grep 实测),其中 codegen.ss 15 / gen_exprs.ss 118 / eval_expr.ss 10 / eval/* 11 文件累计 ~36 / gen_decls.ss 2 / gen_stmts.ss 2 / gen_assigns.ss 3 |
| TypedValue 存储 | `tvI1/tvS1/tvKind/tvD1` Maps + `tvI1/tvI2/tvI3` Arrays(`bootstrap/codegen.ss:170-179`),`newTv*` 入口 6 函数(`newTvInt` L209 / `newTvString` L215 / `newTvType` L222 / `newTvBool` L228 / `newTvNull` L234 / `newTvArray` L238)|
| InternPool 现状 | `grep -l internPool bootstrap/*.ss` = 0 命中(未启动)|
| 当前 linter cur(2026-04-20) | M1=5140 / M2=76222 / M3a=12126 / M3b=1879 / M4=3035 / M5=1747 / M6=32 / M7a=27 / **M7b=676** / N1=34 / N2=381110 / N3=515014 / N4=321 / N5=0 |
| D101 baseline | M1=5134 / M2=76126 / M3a=12122 / M3b=1879 / **M4=3037** / M5=1750 / M6=32 / M7a=27 / **M7b=676** / N1=34 / N2=380630 / **N3=518111** / N4=321 / N5=0 |
| **bank cur vs baseline** | M1+6/tol±25 余 19 / M2+96/tol±380 余 284 / M3a+4/tol±60 余 56 / M3b**0 严格** / M4-2/严格余 +2 / M5-3/tol±8 余 11 / M6/M7a/N4/N5 严格 0 / **M7b 0 严格 — 主要风险点** / N1 tol ±1 余 1 / N2+480/tol±1903 余 1423 / N3-3097/严格余 +3097(深窖)|
| F1 cur | gen_exprs.ss=1218(D110 baseline 1721 PROGRESS)/ codegen.ss=1267 严格 / gen_maybeval.ss=15(D110 新建)|

## 决策(分 4 §,§决策 1-2 物理改造,§决策 3-4 范围/key 设计)

### §决策 1 — InternPool 数据结构:`internPool` + `internPoolKeyOf` 双 Map,lazy init,单 `internPoolGetOrInsert` 函数

**新建 `bootstrap/intern_pool.ss`(估 ~30 行,F1 R3 ≤ 600 远充裕)**:

```ss
// D111 Phase B InternPool — D098 §决策 2 §Phase B 实化
// 收益:相同 (tag, payload) 同 tvId,Value.eql 退化为 id == id O(1) 比较
// 范围:5 标量入口(Int/String/Bool/Null/Type),Array/Map/Double 留 Phase C
// key 格式:`<tag>|<payload>` — INT|42 / STR|hello / BOOL|0 / NULL| / TY|MyClass

let internPool: Map<string, int> = ""        // key → tvId
let internPoolKeyOf: Map<string, string> = "" // str(tvId) → key (反查支持 valType)

function internPoolGetOrInsert(key: string, ifMissAlloc: int): int {
    if (internPool == "") {
        internPool = new Map()
        internPoolKeyOf = new Map()
    }
    if (internPool.has(key) == 1) {
        return parseInt(internPool.getString(key))
    }
    internPool.set(key, `${ifMissAlloc}`)
    internPoolKeyOf.set(`${ifMissAlloc}`, key)
    return ifMissAlloc
}
```

**接口语义**:
- caller 已 `newTv*` alloc 出 tvId(`ifMissAlloc`),传入函数
- hit:返回 stored tvId,`ifMissAlloc` 浪费(GC 不存在,tvI1/tvS1 push-only,内存 O(N) 累计 — 留 §新张力 1)
- miss:存 (key→tvId) + (str(tvId)→key) 双向映射,返回 `ifMissAlloc`

**M7b 影响**:**+1**(`internPoolGetOrInsert` 单函数,`initInternPool` lazy in-body 不抽,`poolLoadTag` §决策 2 决定不抽)

**为何不抽 `initInternPool`**:lazy init 在 `internPoolGetOrInsert` body 入口 if 内部即可,抽出 = M7b +1 无收益;首次调用 cost 1 if + 2 new Map,后续 cost 1 if false。

**为何用双 Map 而非 Array<string> + Map<string,int>**:
- Array<string>[tvId] 反查更快(直接索引)但 `Array.push` 在每个 miss 触 M5(可变 state +1) + M7b 不增
- Map<string,string>.set 触 M5 同样 +1 但 Array push 节奏更密集(每 alloc 一次)
- 实测决策权衡:Map<string,string> 反查 cost O(hash) ≈ Array O(1) 在 Map 已 init 后差异微秒级
- **选 Map<string,string>** — 工程一致性(internPool 已是 Map,反查也用 Map 同构)+ 避免 Array push 反复触发 M5 监控点

### §决策 2 — valOf 物理不变(语义经 pool)+ valType 改走 `internPoolKeyOf` 反查 + split 取 tag

**改 `bootstrap/gen_maybeval.ss`**:

```ss
// D098 §决策 2 §Phase B / D111 §决策 2 — Phase B InternPool 实化
// valOf 物理上仍 strip ct bit(payload(valId) 在 InternPool dedup 后即 pool index = backing tvId 等价)
// valType 走 internPoolKeyOf 反查 key,split "|" 取 tag(替代 D092 tvKindOf 直读)
// Phase C(D098 §决策 2 Phase C):若 interp* 家族内部全迁 InternPool,valOf 也可走 pool.load 内部 array index 抽象

function valOf(valId: int): int {
    return payload(valId)   // Phase B: pool index = backing tvId(InternPool dedup invariant 保证)
}

function valType(valId: int): string {
    const tvId = payload(valId)
    const key = internPoolKeyOf.getString(`${tvId}`)
    const barAt = key.indexOf("|")
    return key.substring(0, barAt)
}
```

**`valOf` 物理上 = D110 实现**(`return payload(valId)`),**注释升级声明 "Phase B: pool index = backing tvId 等价"**。

为何 valOf 不抽 `poolLoadValue(tvId)` 子函数:
- `poolLoadValue(tvId): int { return tvId }` 是 identity,M7b +1 无收益
- D098 §决策 2 文本 `valOf=pool.load(valId).payload`,在 InternPool dedup 后 `pool.load(tvId).payload` ≡ `tvId`(因 backing tvId 自身就是 dedup 后的 stable id)
- Phase C(§新张力 4)若 `interp*` 内部全迁 InternPool 自有 array index 空间,届时引入 `poolLoadValue` 单函数承载 array 偏移,本 Plan 范围外

**`valType` 真正经 pool 反查 + split**:
- 走 `internPoolKeyOf.getString(${tvId})` 拿 key
- `key.indexOf("|")` + `key.substring(0, barAt)` 取 tag(`INT` / `STR` / `BOOL` / `NULL` / `TY`)
- **替代** D092 `interpType(tvId) → tvKindOf(tvId)` 走 `tvKind.getString(tvId+"")` 直读
- 物理 cost 对比:旧 1× Map.getString(tvKind) / 新 1× Map.getString(internPoolKeyOf) + 1× indexOf + 1× substring,**新 +2 string ops**;但内存与 Map 数等量(无新 Map),N3 估升 +30~+150(详见预估表)

**M7b 影响**:**+0**(valType inline split 不抽 `poolLoadTag` 子函数)

**为何不抽 `poolLoadTag(tvId): string` 子函数**:
- M7b bank 0,本 Plan 总 +N 数严格预算,`poolLoadTag` 抽 = M7b +1 不可承载
- valType 单调用点(11 处 caller),抽函数收益 = 6 行 → 1 行 caller code,但 M7b 阻断
- Phase C 若 valType 调用密度上升或 caller 复杂度升,届时抽

**为何 valType 不再调 `interpType`**:
- D098 §决策 2 §Phase B 文本明确 valType `pool.load(valId).tag` 走 InternPool 反查,不走 D092 tvKindOf
- 若 valType 仍走 `interpType(payload(valId))` → InternPool 引入但 valType 未真改 → §新张力 失锚,Phase C 评估前提失却

**风险:STR key 内含 `|` 字符**:`interpNewString("a|b")` → key = `STR|a|b`,`indexOf("|")` 取首个 `|` 位置,substring(0, 3) = `STR` 仍正确。**首个 `|` 总是 tag/payload 分隔,STR payload 内任意 `|` 不影响 tag 解析**(tag set 固定为 `INT/STR/BOOL/NULL/TY` 不含 `|`)— 设计 OK,无风险。

### §决策 3 — Key 设计:Phase B 起步直接原串 + `|` 分隔,sha256 预 hash 留 Phase C

**D098 §新张力 4(L184-186)开放问题**:

> Phase B `hash(payload)` 对大字符串/大 array 的性能 — `INT|42` 直接字符串拼接 key OK,但 `STR|<huge_string>` 或 `ARR|[1,2,...,100000]` 序列化成本高。**开放问题**:Phase B 启动时评估 key 上限 + 是否需要预先 hash(`STR|<sha256(s)>` 已写成样本但未验证)。本 D 文档不预判,列为 Phase B §下一步 开放项。

**D111 拍板:Phase B 起步直接原串(方案 A),sha256 预 hash 留 Phase C 评估**。

**依据**:
1. **bootstrap 自身字符串字面量分布**:`grep -E '".{0,200}"' bootstrap/*.ss` 实测绝大多数 < 100 字符,无 KB 级字符串(bootstrap 是编译器源码,字符串多用于 IR 模板片段 / 错误消息 / kind 名);Phase B 起步 dedup 仅服务 `interpNewString` 入口,实际进入 InternPool 的 STR key 长度上界由 bootstrap 自身决定
2. **Map<string, int> 原生支持**:SS Map 已支持任意长度 string key,无需自定义 hash 实现 / 自定义 Map 类
3. **sha256 dep cost**:`lib/sha256.ss` 复杂(~200 行,含 32-bit ops + 多轮压缩),引入 bootstrap import 链增 codegen 耦合 / 编译时间;Phase B 起步实测 < 100 字符 STR 不构成性能瓶颈,sha256 是过早优化
4. **`|` 分隔 vs 二进制 sentinel**:
   - 选 `|` ASCII 分隔 — 易读 / 无 escape(STR payload 内 `|` 不影响 tag 解析,见 §决策 2 风险段)
   - 拒绝 `\u00FE` / `:::SEP:::` 等稀有 sentinel — 可读性损失大,无收益(`|` 解析无歧义)
5. **key 格式集合**(本 Plan 5 入口):

| tag | 入口 | 示例 key | 说明 |
|---|---|---|---|
| INT | interpNewInt | `INT|42` / `INT|-7` / `INT|0` | 直接 int → string,符号位无需特殊处理 |
| STR | interpNewString | `STR|hello` / `STR|"a\|b"` | 直接原串,`|` 不 escape(tag 解析仅认首个 `|`)|
| BOOL | interpNewBool | `BOOL|0` / `BOOL|1` | 直接 0/1 |
| NULL | interpNewNull | `NULL|` | 固定 key,空 payload |
| TY | interpNewType | `TY|MyClass` / `TY|HttpRequest` | className 直接,SS class 名集合不含 `|` |

**Phase C 评估触发条件**:
- 实测 STR key Map.set/has 性能 > 单次调用 1ms(`time bin/ss build large.ss` 退化 ≥ 5%)
- 用户代码 STR 字面量 > 1KB 频繁出现(目前 bootstrap 自身无此场景)
- ARR/MAP/DOUBLE dedup 引入(本 Plan 范围外)

### §决策 4 — Dedup 范围:5 标量入口,Array/Map/Double 留 Phase C

| 入口 | 本 Plan dedup | 理由 |
|---|---|---|
| interpNewInt | ✓ | 标量,key `INT|${n}` 简单,dedup 收益高(同值大量重复) |
| interpNewString | ✓ | 标量,key `STR|${s}` 见 §决策 3,bootstrap 实测 OK |
| interpNewBool | ✓ | 仅 2 种值,dedup 命中率 100%,Phase B 起步必做 |
| interpNewNull | ✓ | 单值(`NULL|`),dedup 命中率 100%,可彻底改为单例 |
| interpNewType | ✓ | className dedup,反射 Meta 对象高频路径,Zig `Value.Tag.ty` 对应 |
| **interpNewArray** | **✗** | SPREAD/concat 非纯,key `ARR|<csv>` 需 deep serialize(嵌套 Array 是开放问题) — 留 Phase C |
| **interpNewMap** | **✗** | Map 可变,任意 set/delete 改变 hash,无法稳定 dedup — 留 Phase C(若做需 immutable Map 类) |
| **interpNewDouble** | **✗** | 浮点等价边界(0.1+0.2 vs 0.3 / NaN ≠ NaN / +0 vs -0)— 留 Phase C 或永不 dedup |

**Phase C 评估顺序**:Array 优先(反射 `cls.fields` / `cls.methods` 数组 dedup 收益高)→ Map / Double 视实测必要性。

## 预估指标表(对照 D101 baseline + 当前 cur D110 后)

cur 取 2026-04-20 `bin/ss run tools/reflection_health_linter.ss` 实测(D110 Execute 1 commit `cc7cc79` 后)。

| 指标 | 组 | baseline | cur | bank | 预估 step1 后 | Δ-from-cur | 判定 | 风险 |
|---|---|---|---|---|---|---|---|---|
| M1 | 累计 | 5134 | 5140 | 余 19 | 5142~5148 | +2~+8 | OK | low(if has + 2 set 小贡献 + 5 入口各 +1 if 等)|
| M2 | 累计 | 76126 | 76222 | 余 284 | 76280~76360 | +58~+138 | OK(余 ≥ 146)| medium(intern_pool.ss ~30 行 + 5 interpNew* 各 +2 行 + valType 改写 +5 行 = ~45 行新代码 + 小段重写)|
| M3a | 累计 | 12122 | 12126 | 余 56 | 12132~12145 | +6~+19 | OK(余 ≥ 37)| low(5 interpNew* +1 调 internPoolGetOrInsert / valType +3 调 getString/indexOf/substring)|
| M3b | 结构 | 1879 | 1879 | **严格 0** | 1879 | **0** | OK | **medium(internPoolGetOrInsert 入度 = 5 caller 远低于当前最大入度 1879;internPoolKeyOf.getString 仅 1 caller(valType)入度 1)** |
| M4 | 结构 | 3037 | 3035 | bank +2 | 3035~3037 | 0~+2 | OK(bank 充足)| low(intern_pool.ss 内 has() if + miss path 浅 dispatch,无新 if-chain)|
| M5 | 累计 | 1750 | 1747 | 余 11 | 1748~1750 | +1~+3 | OK | low(internPool / internPoolKeyOf 2 globals + lazy init flag in-body 不新 var = M5 +2 globals + N set 操作)|
| M6 | 结构 | 32 | 32 | 严格 0 | 32 | 0 | OK | low(无新递归)|
| M7a | 结构 | 27 | 27 | 严格 0 | 27~28 | 0~+1 | **DRIFT 风险** | medium(internPoolGetOrInsert body 内 if-init + if-has + insert-3-line 嵌套深 1-2,**应不超 27 当前最大** — Execute 2 实测警惕)|
| **M7b** | 结构 | 676 | 676 | **严格 0** | **677** | **+1** | **REGRESSION** | **极高 — Step 0 必预削减 ≥ -1**(`internPoolGetOrInsert` 单函数,valType 不抽 poolLoadTag,initInternPool lazy in-body 不抽)|
| N1 | 累计 | 34 | 34 | tol ±1 余 1 | 34 | 0 | OK | low(无新 AST kind)|
| N2 | 累计 | 380630 | 381110 | 余 1423 | 381200~381410 | +90~+300 | OK(余 ≥ 1123)| low(M2 派生 × log2(34))|
| N3 | 结构 | 518111 | 515014 | 余 +3097(深窖)| 515050~515200 | +36~+186 | OK(深窖远充裕)| low(intern_pool.ss 浅函数 depth 1-2 / 5 interpNew* 浅 if / valType depth 2 substring)|
| N4 | 结构 | 321 | 321 | 严格 0 | 321 | 0 | OK | low(无单节点 list 长度上升)|
| N5 | 结构 | 0 | 0 | 严格 0 | 0 | 0 | OK | low(无 MEMBER_ASSIGN)|
| F1 intern_pool.ss(新)| - | n/a | n/a | n/a | ~30 行 | n/a | OK(R3 ≤ 600 极充裕)| low |
| F1 codegen.ss(改)| - | 1267 | 1267 | 严格不升 | 1267 | 0 | OK | **medium(5 interpNew* 改写各 +1 行 = +5,但每函数 body 整体收紧 → 净 0,需 Execute 2 实测验证)** |
| F1 gen_maybeval.ss(改)| - | n/a | 15 | n/a | ~25 | +10 | OK(R3 ≤ 600 远)| low |
| F1 gen_exprs.ss | - | 1721 | 1218 | 单调下降 | 1218 | 0 | OK | low(本 Plan 不动 gen_exprs.ss)|

**核心风险点**:

1. **M7b +1** STRICT 严格不升 / bank 0 → **Step 0 必预削减 ≥ -1**(详见 §步骤 0)
2. **M7a 0~+1** STRICT 当前最大 27,internPoolGetOrInsert body 嵌套深观察值 — Execute 2 实测警惕,若 +1 需重构 internPoolGetOrInsert 减嵌套
3. **F1 codegen.ss** 5 interpNew* 改写各 +1 行可能触 R1,**对策**:把改写后的 interpNewInt-NewType **不留** codegen.ss,**移到 intern_pool.ss**(import 形式),codegen.ss 净 -10 行 / intern_pool.ss 升至 ~50 行(R3 仍 ≤ 600 极充裕)

**预估命中率**:6 项严格组(M3b/M4/M6/M7a/N1/N4/N5)+ 5 项累计组(M1/M2/M3a/M5/N2)+ 1 项深窖(N3)+ 1 项 STRICT 必动(M7b),**M7b 需 Step 0 抵消是唯一硬阻断**;其余预估窗口对照 D101/D110 模板给出区间,Execute 2 实测落地后回写本表实测列(参 D110 §决策 2 实测命中率段落格式)。

## §步骤 0 — 预削减(M7b ≥ -1,Plan 不钦定源,Execute 0 grep 实测)

**目标**:M7b 严格不升,Step 1 新增 `internPoolGetOrInsert` +1 必须 Step 0 预削减 ≥ -1 抵消(或 Step 0/Step 1 同 commit 削+加抵消)。

**候选削减源**(Execute 0 轮 grep 验证可行性):

1. **`interpAsClassName(codegen.ss:318,2 行 = tvStringOf alias)** 全调用点 inline → -1
   - grep `interpAsClassName(` 找全 N 调用点,每处改 `tvStringOf(`,删函数体
   - 风险:M2/N2 微升(N 处 caller +0 行 / 函数体 -2 行 / 净 ≈ -2 行),M3a -N(去掉 N 个调用边)+N(新增 N 个 tvStringOf 调用边)= 0
   - 验证:grep 实测 N 不大(估 N ≤ 5),Execute 0 grep 落地

2. **`interpAsBool`(codegen.ss:289,2 行 = tvIntOf alias)** 全调用点 inline → -1
   - 同 1,grep `interpAsBool(` N 调用点 inline
   - 风险同上

3. **`interpNewBool`(codegen.ss:305,2 行 = newTvBool alias)** 全调用点 inline → -1
   - **冲突**:本 Plan §决策 4 要 dedup interpNewBool(改写为 `internPoolGetOrInsert(BOOL|${b}, newTvBool(b))`),不能 inline 这层
   - **拒绝**:此候选与 §决策 4 互斥

4. **`interpNewNull`(codegen.ss:309,2 行 = newTvNull alias)** 全调用点 inline → -1
   - 同 3,拒绝

5. **eval/* 内单调用 helper inline 回 evalExpr 主 dispatch**
   - **拒绝**:违反 D110 §决策 1(保留 12 函数稳态)

**Plan 优先序**:候选 1 / 候选 2(每个 -1),Execute 0 实测 N 不大者优先 inline。**目标累计 -1 即可**,若两候选合并 -2 富余作 §步骤 1 内 valType M7a 风险 buffer。

**Execute 0 操作顺序**:
1. `grep -n "^function interpAs" bootstrap/*.ss` 列候选函数 + body 行数
2. 每候选 grep 全调用点 N
3. 选 N ≤ 8 且 inline 后 N3 不升的候选(N 大 = caller 多 = inline 后 caller body 各 +1 行 / N3 风险升)
4. 单独 commit + bootstrap 固定点 + linter GATE PASS

**若无单项可达 M7b -1**:Step 0 拆 0a/0b 累积,但每 commit 独立 bootstrap + GATE PASS。**或** 降级 §决策 1 (`internPoolGetOrInsert` 也 inline 在 5 入口,M7b +0 无新函数)— Plan 末位 fallback,详见 §Rejected C。

## §步骤 1 — Execute 2 实施(InternPool 引入 + 5 入口 dedup + valType 改走 pool.load)

子步骤(单 commit 含全部子步骤,bootstrap 固定点 PASS):

### Step 1a — 新建 `bootstrap/intern_pool.ss`

按 §决策 1 模板写入 ~30 行,内容含 `internPool` / `internPoolKeyOf` 双 Map global + `internPoolGetOrInsert` 单函数(lazy init in-body)。

### Step 1b — `bootstrap/main.ss` import 列表加 `import "@/bootstrap/intern_pool"`

确保 `internPoolGetOrInsert` 在 codegen.ss 的 5 interpNew* 改写处可见(SS import 是 transitive,gen_maybeval.ss 改 valType 也通过 main.ss 的 import 链拿到 `internPoolKeyOf`)。

### Step 1c — 改 codegen.ss 5 interpNew* 入口

按 §决策 4 范围改写(或全部移到 intern_pool.ss 缓解 codegen.ss F1 R1 — 见预估表风险段):

```ss
// codegen.ss(或迁 intern_pool.ss):
function interpNewInt(n: int): int {
    return internPoolGetOrInsert(`INT|${n}`, newTvInt(n))
}
function interpNewString(s: string): int {
    return internPoolGetOrInsert(`STR|${s}`, newTvString(s))
}
function interpNewBool(b: int): int {
    return internPoolGetOrInsert(`BOOL|${b}`, newTvBool(b))
}
function interpNewNull(): int {
    return internPoolGetOrInsert(`NULL|`, newTvNull())
}
function interpNewType(className: string): int {
    return internPoolGetOrInsert(`TY|${className}`, newTvType(className))
}
```

**注意 `interpNewArray` / `interpNewMap` / `interpNewDouble` 不改**(§决策 4)。

### Step 1d — 改 `bootstrap/gen_maybeval.ss` valType 走 pool.load

按 §决策 2 模板改写 valType,valOf 注释升级(物理不变):

```ss
function valOf(valId: int): int {
    return payload(valId)
}

function valType(valId: int): string {
    const tvId = payload(valId)
    const key = internPoolKeyOf.getString(`${tvId}`)
    const barAt = key.indexOf("|")
    return key.substring(0, barAt)
}
```

### Step 1e — 单 commit + bootstrap 固定点 + 全测 + GATE PASS

- `./build.sh bootstrap` 固定点 PASS(stage2 == stage3)
- `bin/ss test tests/` 全绿(InternPool 是行为透明 dedup,所有 tests/ 不变)
- `bin/ss run tools/reflection_health_linter.ss` 分层 GATE PASS:
  - 结构组 8 项 OK / PROGRESS(核心 M7b 0 / N3 微升余量充足 / M7a 0 警惕)
  - 累计组 5 项 OK / DRIFT(M2 +58~+138 / N2 +90~+300 均在 DRIFT 窗口内)
  - F1:codegen.ss / gen_maybeval.ss / intern_pool.ss 全 OK / PROGRESS

## §步骤 2 — 收尾评估 + 指向后续 Phase B / C

**目标**:Step 1 完成后决策 record vs 不 record + 指向后续 D 文档。

**默认不 record**(D110 §决策 3 累计组永不 record + 结构组允许 record 但本 Plan 仅 +1/-1 净 0 不动):
- 累计组 M2 +58~+138 / N2 +90~+300 均 DRIFT,**不 record**(D097 L70-71 + D110 §决策 3 方案 C)
- 结构组 M7b -1+1=0 / M7a 0~+1 / 其余 0,**不 record**(无削减或仅与新增抵消,record 无意义)
- N3 +36~+186 仍 ≤ baseline,**不 record**(深窖延续作 Phase B 全程缓冲)

**状态回写**:
- D110 §下一步 #3 标记 `[x] Done at <commit-sha>`(Execute 2 落地后 commit ref 写入)
- D098 §决策 2 §Phase B `[x] Phase B 起步 Done at <commit-sha>`(InternPool 5 标量入口 dedup + valType 改走 pool.load)
- D098 §新张力 4 `[x] Resolved at D111 §决策 3`(Phase B 起步直接原串,sha256 留 Phase C)

**后续指向**:

| 决策 | 触发条件 | 承载 D 文档 |
|---|---|---|
| Type-as-Value 合并(D098 §决策 3 Phase B)| InternPool 引入后 `comptimeTypeAliases` 与 ctVars 合并 | D112(独立 Plan)|
| Array/Map/Double dedup(Phase C 范围)| 实测反射 `cls.fields` 数组 dedup 收益 | D113+(Phase C 启动 Plan)|
| Meta 对象 InternPool 承载 | 反射 Meta 对象高频访问 + Value.eql O(1) 实测验证 | D113+ |
| sha256 预 hash 评估 | 实测 STR key 性能退化 ≥ 5% 或 KB 级 STR 频繁 | D114+(评估 Plan)|
| `interp*` 家族内部全迁 InternPool(Phase C)| Phase B 实测 dedup 命中率 + Value.eql O(1) 收益度量 | D115+(Phase C 启动)|

每 Execute 开始前先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## Rejected Alternatives

### §A — InternPool 一次全做(Phase B + Phase C 合并,Array/Map/Double dedup + interp* 家族内部全迁 + Meta 对象承载同轮)

**拒绝理由**:
- D098 §决策 2 已明 Phase B / Phase C 分,Phase C 工程量 5×(`interp*` 30 函数内部全迁 + 自定义 Map hash + dedup 边界)
- `memory/feedback_no_dramatic_reset.md`:Phase 切换分段诊断不推倒重来
- 合推非线性风险:Phase B 起步实测未 PASS 前 Phase C 设计假设无验证基

### §B — 抽 `internPoolGetOrInsert` + `poolLoadTag` + `poolLoadValue` 3 子函数(M7b +3)

**拒绝理由**:
- M7b bank 0 + Step 0 实测可达 -1~-2 上界,M7b +3 = 净 +1~+2 STRICT REGRESSION
- `poolLoadValue(tvId): int { return tvId }` 是 identity,M7b +1 无收益(Phase C 若改 InternPool 自有 array index 空间届时引入,本 Plan 范围外)
- `poolLoadTag(tvId): string` 单调用点(valType 1 处),抽函数收益 = 6 行 → 1 行 caller code,但 M7b 阻断
- `memory/feedback_design_no_code_authority.md`:不为 "对称美" 抽过早抽象,工程边界先行

### §C — 不抽 `internPoolGetOrInsert`,5 处 inline(M7b +0,fallback 方案)

**拒绝理由**(本 Plan 优先 §决策 1 抽函数;§C 仅作 Step 0 削减失败时 fallback):
- 违反 D098 §决策 2 §Phase B 文本指定 `internPoolGetOrInsert` 函数名(P16 决策记录连续性)
- 5 处复制粘贴破 P13(三似性原则,> 3 处必抽)
- 后续 Phase C `interp*` 内部迁 InternPool 时,inline 形式难以复用 → Phase C 重写代价
- **Plan 立场**:仅 Step 0 实测 M7b 无可削减时 Execute 2 降级到 §C,Plan 阶段不接受

### §D — Phase B 启动同时把 valOf 物理改写(走 `poolLoadValue(payload(valId))` 抽象,M7b +1 + 1 = +2)

**拒绝理由**:
- valOf 物理 = `payload(valId)` 在 InternPool dedup 后 ≡ `pool.load(tvId).payload`(invariant 等价)
- 抽 `poolLoadValue(tvId): int { return tvId }` identity 函数 = 过早抽象,M7b +1 无收益
- D098 §决策 2 文本 `valOf=pool.load(valId).payload` 是**语义描述**不是**物理强制**,Phase B 起步注释升级 + 物理不变完全合规

### §E — 用 sha256 预 hash STR key(`STR|<sha256(s)>`)

**拒绝理由**:
- bootstrap 实测字符串字面量 < 100 字符,sha256 未达性能必要性
- `lib/sha256.ss` 引入 bootstrap 增 import 链 / 增 codegen 耦合 / 增编译时间
- D098 §决策 3 sha256 是开放问题,本 Plan 决方案 A 不预判 sha256 必要性(留 Phase C 评估触发条件,详见 §决策 3 末段)

### §F — Dedup 范围扩到 Array / Map / Double(7 入口全 dedup)

**拒绝理由**:
- `interpNewArray` SPREAD 非纯,key `ARR|<csv>` 需 deep serialize(嵌套 Array 是开放问题)— 本 Plan 不解
- `interpNewMap` 可变 state,任意 set/delete 改变 hash,dedup 假设破裂
- `interpNewDouble` 浮点等价边界(0.1+0.2 vs 0.3 / NaN ≠ NaN / +0 vs -0)— 需先决浮点等价语义再 dedup
- 三类入口 dedup 留 Phase C(D113+)单独 Plan,Phase B 起步范围限定 5 标量入口

### §G — 自定义 Map hash 实现(SS Map 改 Open addressing / Cuckoo 等)

**拒绝理由**:
- SS Map 当前用原生 hash(C runtime mimalloc),无可定制 hook
- 改 Map 实现影响所有 caller(数百调用点),违反 D098 §决策 2 Phase B 范围
- 性能未达必要性(同 §E)

### §H — Phase B Execute 2 不立 D111,内联进 D110 或直接开 Execute 2 commit

**拒绝理由**:
- D110 已 commit `cc7cc79`(Execute 1 完成),后续 Execute 2 必立独立 D 文档(P16 + D110 §下一步 #3)
- 直接 commit 无 Plan 承载 → 缺设计决策记录,违反 P16(决策记录立即化)+ §交互式单文档
- Step 0 预削减 + Step 1 实施 + Step 2 收尾的三段式模板沿袭 D101-D110 八轮 Execute 模板

### §I — 双 Map(`internPool` + `internPoolKeyOf`)改单 Map(key 自带 tvId 编码)

**拒绝理由**:
- 单 Map 设计:key=`tag|payload`,value=tvId — 反查需扫 Map 找 value=tvId 的 key,O(N) 不可接受
- 双 Map 反查 O(1)(internPoolKeyOf.getString),正向插入 cost +1 Map.set,可接受
- §新张力 7 记录:Phase C 可评估单 Map(key 含 tvId 编码)优化,本 Plan 范围外

## 新张力(D111 引出)

1. **interpNew* hit 时仍 alloc newTv* 浪费** — caller 已 alloc tvId 传入 `internPoolGetOrInsert`,hit 时 `ifMissAlloc` 浪费(tvI1.push / tvS1.set 已发生,无 GC 回收)。内存 O(N) 累计,Phase C 评估 lookup-first-alloc-after 重构(接口拆为 `lookup` + `register`)。**对策**:Plan 接受小浪费,GC 不存在 + tvI1/tvS1 push-only 不可逆,Phase C 必做

2. **STR 大字符串 key 性能** — bootstrap 实测 < 100 字符 OK,但用户代码可能含 KB 级 STR(如 lib/json.ss / lib/http.ss 解析大 JSON / HTTP body)→ key Map.set/has 性能在大串场景未实测。**对策**:Phase B 完成后 `time bin/ss build lib/http.ss` 实测,如退化 ≥ 5% 触发 D114 sha256 评估 Plan

3. **valType 改写 substring/indexOf 引入 string ops 成本** — valType 调用极频(eval/* 6 文件 += codegen.ss 多处 = 共 11+ 调用点),每次 substring/indexOf,N3 / N2 微升。**对策**:Phase C 评估 cache valType 结果(`valTypeCache: Map<int, string>` 二级缓存)/ 或抽 `poolLoadTag` 子函数 + 内部 cache(M7b +1 届时承担)

4. **Type-as-Value 与 InternPool 合并(D098 §决策 3 Phase B)未在本 Plan** — 本 Plan 仅做 Value dedup,未消除 `comptimeTypeAliases` 独立通道(`bootstrap/codegen.ss:83`)。Type 句柄虽走 InternPool key `TY|${className}` dedup,但 `comptimeTypeAliases` Map 仍存在 — 双轨残留。**对策**:留 D112 单独 Plan,Phase B 中期推进

5. **反射 Meta 对象进入 InternPool 时机** — D098 §决策 2 §Phase B 末段 + D097 §后续工作 #4 暗示 Meta 对象 dedup,但本 Plan 范围限 5 标量入口。Meta 对象(`ClassMeta` / `FieldMeta` 等)是 class instance(D096 Phase 4 L1),dedup 需先解 class instance dedup 设计 — 留 Phase C / D113+。**对策**:Plan 不预判,Phase B 完成后实测反射路径 Value.eql 收益再启动

6. **Step 0 削减源 P13 边界** — `interpAsClassName` / `interpAsBool` 都是 alias 函数(2 行 = 单调用 tvStringOf/tvIntOf),inline 是 P13 三似性的反操作(N alias 调用点 inline 后每处 +1 行 直读 tvStringOf)。微违 P13 但 M7b 严格 0 强迫,记录张力。**对策**:Plan 接受单轮微违,Phase C 若 alias 函数家族稳定可 record baseline 释放压力

7. **internPool / internPoolKeyOf 双 Map 同步** — 写入两个 Map(`set + set`),性能 O(2 hash);Phase C 可改为单 Map 反查(key 含 tvId 编码)— 见 §Rejected I。**对策**:Plan 接受 O(2 hash) 起步,实测 N2 / M2 Δ 在余量内即续

8. **internPoolKeyOf 的 key 是 str(tvId)** — tvId 转 string + Map lookup,而非 Array<string>[tvId] 直接索引。Array 版更快(直接 O(1) 索引)但 `Array.push` 在每个 miss 触 M5(可变 state +1)+ 内存预分配 / 动态扩容代价。**对策**:Plan 选 Map<string,string> 一致性 + 避免 Array push 反复触发 M5,Phase C 评估 Array 优化

9. **Phase B 初次 GATE 预估命中率** — M7b +1 - Step 0 -1 = 净 0(主要硬阻断在抵消 path)/ N3 +36~+186 ≤ 余 3097 / M3b 0 / M4 0~+2 ≤ bank +2 / **M7a 0~+1 严格风险**,实测警惕。**对策**:Execute 2 实测 M7a +1 → 重构 internPoolGetOrInsert 减嵌套(if-init 与 if-has 平铺,而非嵌套)

10. **D098 §新张力 4 sha256 预 hash 决策延迟到 Phase C** — 本 Plan 选直接原串(方案 A),Phase C 评估;如 Phase B 实测大字符串性能未达问题阈值,sha256 永不引入。**对策**:留 D114 评估 Plan,触发条件见 §决策 3 末段

11. **Phase B Execute 2 完成度判定** — 本 Plan 范围 5 入口 dedup + valType 改写 + GATE PASS,但 D098 §决策 2 §Phase B 完整收益(Value.eql O(1))需后续 evalExpr `==` 比较改走 `id == id` 而非深比较。**对策**:Plan 阶段不解,留 Execute 2 完成后开 D113+ 推进(范围限 evalExpr `==` op 改写)

12. **InternPool 与 D098 §决策 1 mv 编码**(known/runtime/error 三态)兼容性 — 本 Plan 不动 mv 编码(Phase A 决策),InternPool 仅作用于 known 路径(`mv >= 0` Value 句柄空间),runtime 路径(`mv <= -2` regTable)与 error(`mv == -1`)不变。**对策**:Plan 隐式约束,Execute 2 实测验证 `evalExpr` 内 known/runtime 切换无 InternPool 污染

## 下一步(Plan 下的 Execute 顺序)

1. [ ] Planned — **Execute 0**:Step 0 预削减(M7b ≥ -1),候选 `interpAsClassName` / `interpAsBool` 全调用点 inline,Execute 0 grep 实测后选最优。单独 commit + bootstrap + GATE PASS
2. [ ] Planned — **Execute 1**(等同 Step 1):InternPool 引入(`bootstrap/intern_pool.ss` 新建)+ 5 interpNew* 入口 dedup + gen_maybeval.ss valType 改走 pool.load。单独 commit + bootstrap 固定点 + 全测 + GATE PASS。**预估**:M7b +1(被 Step 0 -1 抵消)/ M2 +58~+138 / M3a +6~+19 / N2 +90~+300 / N3 +36~+186 / 其余 0
3. [ ] Planned — **Execute 2**(等同 Step 2):收尾评估 + D 文档状态回写(D110 §下一步 #3 / D098 §决策 2 §Phase B / §新张力 4)+ 实测命中率回写本文档预估表
4. [ ] Planned — **后续 D 文档**:D112(Type-as-Value 合并)/ D113+(evalExpr `==` 改 id == id / Array Map dedup / 反射 Meta InternPool)/ D114(sha256 评估,触发后)/ D115(Phase C 启动)

每 Execute 开始前必须先填 PSM 十问;完成前过五验 VCM;单步 bootstrap 失败 → 定位根因不越步;单步分层 GATE 结构组 REGRESSION → 先削减再推进,累计组 DRIFT PASS 即可。

## 参考

- D110 §下一步 #3 L237(本 Plan 起草触发)/ §决策 1(12 函数稳态约束)/ §决策 2(valOf/valType 接口边界 D111 实化基)/ §决策 3(累计组永不 record / 单 baseline 跨 phase)/ §新张力 1-12(InternPool 长期张力上下文)
- D109 Execute 1(NEW_EXPR 迁移 commit `e141fdf`,Phase A 闭环)/ Execute 2(D109 §决策矩阵漏洞修订归 D110 §决策 3)
- D108 §步骤 1 evalCall / §扩展 子目录全拆(eval/* 11 文件 R3 方案)— 本 Plan 不触 eval/*
- D107 §步骤 1 evalMethodCall / §步骤 2 决策矩阵同构原型 — 本 Plan 沿袭 step 0/1/2 三段式
- D101-D106 §步骤 1 8 kind 迁移模板(evalExpr Phase A 8 轮 Execute 模板)
- D102 §规则 1.1-1.4 分层 GATE / §规则 1.4 record 行为 L99-103 累计组永不 record / §规则 2.1-2.3 F1 GATE / §规则 2.1 R3 新文件 ≤ 600 / R4 graduate / §规则 §单数据源(双 baseline 文件拒绝)
- D100 §坑 Q 银行余量 / §坑 P M2/N2 成本
- D099 §坑 G-O N3/M7b 成本
- **D098 §决策 1** MaybeVal 编码 Phase A mv int / **§决策 2** InternPool Phase A → Phase B 过渡(L114-129 Phase B 三段定义)/ **§决策 3** Type-as-Value 合并(D112 承接)/ **§新张力 2** Phase A 访问器引入(D110 已闭环)/ **§新张力 4** key 设计(本 Plan §决策 3 拍板)
- D097 L70-71 累积方向严禁 record(机械规则源)/ L102(D102 §规则 1.4 继承)/ §后续工作 #4(Meta 对象 dedup 暗示)
- D094 §Q2 收尾 §genVal 操作数驱动审计 §Phase A 迁移进度(9 kind 全 [x] Done,Phase A 闭环)/ §规则 2 pure subset(本 Plan 不动)
- D093 §决策 §Zig 原理 第 4 条(InternPool 统一去重)/ §SS 本质一样骨架 / §张力 1-3
- D089 ctVal bit 30 tag 编码(本 Plan 不动 tag,InternPool 在 ctVal 内层做 dedup)
- D088 §第一性需求(Zig SEMA 一份 evalExpr,反射 Meta 对象 = MEMBER_ACCESS)/ §正模式(主 dispatch + 子分析器分层 Zig sema.zig 同构)/ §反模式(双轨制)
- CLAUDE.md §反射根因 gate(本 Plan 不触反射路径,trivial PASS)/ §交互式单文档 / §PFV 流程
- `memory/feedback_ultrathink_gate.md`(下轮 payload 必含 ultrathink)/ `memory/feedback_pfv_process.md`(开工 PSM + 收工 VCM)/ `memory/feedback_design_no_code_authority.md`(设计不绕过 D098 §决策 2 已有规则)/ `memory/feedback_no_dramatic_reset.md`(Phase 切换分段诊断不推倒重来)/ `memory/feedback_reflection_root_cause_gate.md`(本 Plan 不触反射路径)
- `bootstrap/gen_maybeval.ss:8-14`(D110 valOf/valType 接口边界,本 Plan §决策 2 改造目标)
- `bootstrap/codegen.ss:131-141`(ctVal/payload Phase A bit 30 tag,Phase B 不动)
- `bootstrap/codegen.ss:277-316`(interpType / interp*New* 5 标量入口,本 Plan §决策 4 dedup 范围)
- `bootstrap/codegen.ss:209-249`(newTv* 6 入口,InternPool backing 不变)
- `bootstrap/codegen.ss:170-179`(tvI1/tvS1/tvKind/tvD1 TypedValue 存储,InternPool 上层 dedup index)
- `bootstrap/intern_pool.ss`(新建,§决策 1)
- `bootstrap/main.ss`(import 链,§步骤 1 Step 1b)
- `tools/reflection_health_linter.ss`(分层 GATE)/ `tools/linter_baseline.txt`(D101 baseline / D110 §决策 3 方案 C 跨 phase 单 baseline 延续)
- `tools/next_prompt_ultrathink_linter.ss`(PFV §收尾 gate 第 3 步 (b) 机械 gate)
