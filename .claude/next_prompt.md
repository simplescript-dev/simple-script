ultrathink Execute D132 §10 三轴自动 cover 实测验证 — N=3+ USHR + N=2 任意 M 层 nullable + generic class/method 类型参数副作用 — Phase 4 §247 第二支柱嵌套深化第十二轮(收关 vs 升根分流轮)

承上轮 commit(D132 §10 实测验证 Plan 节起立 + 8 sub-section + 锚指 4 行)+ commit e75b6ea(D132 §4.1 parser maybeNullable + pendingGtTokens guard +1 LOC + I021-requestbody-nested-deep-optional v0 9 case + spring-parity 6 fixture ship)。

下轮 Execute 单 Layer 落地 — 按 D132 §10.6 RED 命令实测 → §10.4 分流:命中(三轴全 cover)→ 加 ~3-5 case 测试 + 父档 §status reconciliation + Phase 4 §247 第二支柱嵌套深化封顶记录 + 一并 ship;不命中(任一轴破裂)→ 停手不动 codegen,改写 next_prompt 转 D133 独立 D 文档子决策起立单 Layer。

三轴 RED 命令(D132 §10.6 完整版,Execute 第一步):

```bash
# 1. /tmp/t_n3_optional.ss 5 fixture(N=3 USHR + N=2 任意 M nullable)
cat > /tmp/t_n3_optional.ss <<'EOF'
class Tag { name: string }
class OrderCubeOpt { customer: string; cube: Array<Array<Array<Tag>>>? }                       # 轴 A N=3 USHR
class OrderTriCubeOpt { customer: string; cube: Map<string, Map<string, Map<string, Tag>>>? }  # 轴 A Map N=3
class OrderTagsArrTripleOpt { customer: string; tags: Array<Array<Tag?>?>? }                   # 轴 B N=2 三 ?
class OrderArrMapTripleOpt { customer: string; entries: Array<Map<string, Tag?>>? }            # 轴 B 混合
class OrderMapArrTripleOpt { customer: string; lists: Map<string, Array<Tag?>?>? }             # 轴 B Map N=2 三 ?
function main() { let o = new OrderCubeOpt(); o.customer = "alice"; print(o.customer) }
EOF

# 2. emit-ir 验证 IR 结构(三轴 grep 阈值)
bin/ss build /tmp/t_n3_optional.ss --emit-ir > /tmp/t.ll
grep -cE '@jnIsNullOrMissing' /tmp/t.ll                # ≥ 12
grep -cE 'opt_present|opt_done' /tmp/t.ll              # ≥ 多层(三层 nullable 各自消)
grep -cE 'jnArrayLen|jnObjectKeys' /tmp/t.ll           # ≥ N=3 多层链
grep -cE '@Tag_deserialize' /tmp/t.ll                  # ≥ 5

# 3. 抽 IR body 看 N=3 + N=2 三 ? 结构(grep 数量是 lower bound,必须看结构)
sed -n "$(grep -n 'define ptr @OrderCubeOpt_deserialize' /tmp/t.ll | head -1 | cut -d: -f1),+90p" /tmp/t.ll
# 期望 N=3:字段层 alloca i64 + jnIsNullOrMissing + opt_present 内 outer arr_loop + middle arr_loop +
#   inner arr_loop + 最内 @Tag_deserialize 四层链;outer `?` 字段层归 outer 不下沉
sed -n "$(grep -n 'define ptr @OrderTagsArrTripleOpt_deserialize' /tmp/t.ll | head -1 | cut -d: -f1),+70p" /tmp/t.ll
# 期望 N=2 三 ?:字段层 outer null guard + 中层 element nullable case + 内层 element nullable case 三层

# 4. 轴 C generic 副作用 + bootstrap 固定点 + reflection
./build.sh bootstrap                                   # PASS Stage 2 == Stage 3
bin/ss test tests/phase4/                              # 27/27 PASS(承 commit e75b6ea baseline)
bin/ss test tests/phase5/                              # baseline 4 failure 与 D132 无关 confirmed
bin/ss run tools/reflection_health_linter.ss          # GATE PASS no regressions
```

风险锚 ≥ 6(承 D132 §10.3 R1-R6 — 详 D132 §10.3 行号):
- R1 N=3+ USHR pendingGtTokens=2 拆分 + 中层 maybeNullable guard 同源 cover(轴 A §10.2 推证 6 步;实测命中预期 ≥ 99%;破裂 → 升根 D133-N3-USHR-strip)
- R2 任意 M 层 nullable 笛卡尔积 cover(轴 B §10.2 推证 5 步;破裂 → 升根 D133-M-layer-nullable-strip)
- R3 generic class/method 类型参数副作用(轴 C §10.2 推证;phase4 全套测试 baseline e75b6ea PASS,regression 概率 < 1%;破裂 → 升根 maybeNullable guard scope 缩窄)
- R4 D131 谓词层多层递归 stripNullableCG(N=3+ 谓词三级递归;破裂 → 升根 D131 §4 边界扩)
- R5 BFS emitPendingDeserializers 多层 stripNullableCG(N=3+ transitive closure;破裂 → 升根 D131 §4.4 BFS 多层 stripNullableCG 边界扩)
- R6 决策预审 — Phase 4 §247 第二支柱嵌套深化封顶 vs 留观察(三轴全 cover → §10.5 选 A 收关 / 任一轴破裂 → 选 B 推迟)

不变量保留(承 D132 §10.7):D018 ObjectLayout(RC@0 + TypeInfo@1) + D022 clone 语义 + D088 编译期反射禁 + D130 emitDeserializeForType SSoT 单点解码 + D131 谓词层 stripNullableCG inner + D067 null safety T? 概念锚 + D132 maybeNullable + pendingGtTokens guard 全形态自动 cover + commit e75b6ea 9 case + 6 fixture spring-parity ship。

Layer:Execute(下轮)单 Layer 落地 — 按 §10.6 RED 命令实测 → §10.4 分流;命中加测试 ship 收关 / 不命中升根 D133 起立(分流锚)。

下轮 Execute 落地预期 commit message:
- 命中(三轴全 cover):`feat(I021-requestbody-nested-deep-optional-N3,D132,D131,D130,D067,D123,D129): D132 §10 修法 generality 三轴自动 cover 实测验证 — N=3+ USHR + N=2 任意 M 层 nullable + generic 类型参数副作用三轴 ship — 第四次自动 cover 真零 codegen 场景 — Phase 4 §247 第二支柱嵌套深化第十二轮收关轮`
- 不命中(任一轴破裂):`feat(D133-<破裂轴>,D132): D132 §10 三轴实测 <破裂轴> 破裂 — D133-<破裂轴> 起立锁定根因 + 候选修法选定 + 风险锚 ≥ 6 — Phase 4 §247 第二支柱嵌套深化第十二轮升根 D 文档子决策起立轮`

D132 §10 单一事实源:
- §10.1 三轴 RED 命令 scope
- §10.2 假设链推证(轴 A N=3+ USHR 6 步 + 轴 B M 层 nullable 5 步 + 轴 C generic 副作用 4 步)
- §10.3 风险锚 ≥ 6(R1-R6)
- §10.4 Execute 落地分流锚(命中 / 不命中)
- §10.5 决策预审(Phase 4 §247 收关 vs 留观察)
- §10.6 RED 命令完整版(下轮 Execute 第一步)
- §10.7 不变量保留
- §10.8 Layer 跨越 / Plan vs Execute

I021-requestbody-nested-deep-optional 子档 §status 已 Done at commit e75b6ea(parser.ss:790-800 + 9 case + 6 fixture);下轮 Execute 命中 → 子档 §status reconciliation 加 "§10 N=3+ USHR + N=2 任意 M nullable + generic 类型参数副作用三轴自动 cover ship at <test 文件 line>";D132 §status 加 "§10 三轴自动 cover 实测验证 Done at <test 文件 + emit-ir 锚>";D123 §247 加 "第十二轮 D132 §10 三轴自动 cover 验证 — Phase 4 §第二支柱嵌套深化收关"。
