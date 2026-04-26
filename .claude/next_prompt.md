ultrathink Execute 落地 D132 §4.1 maybeNullable + pendingGtTokens guard + I021-requestbody-nested-deep-optional v0 端到端反序列化 — 承本轮 commit D132 D 文档锁定根因(parser SHR/USHR 拆分中间状态 inner maybeNullable 错位消耗 outer `?` token 致类型字符串错位 `Array<Array<Tag>?>` 而非 `Array<Array<Tag>>?`)+ 候选 A 修法选定(parser.ss:790-796 +1 LOC `if (pendingGtTokens > 0) { return baseType }` 物理 surgical 修)+ 风险锚 ≥ 6(R1 H1 实测假退路 / R2 表达式上下文副作用 0 / R3 generic 类型参数副作用 0 / R4 RC 契约不动 / R5 BFS 多层 stripNullableCG / R6 form 1+2 + 3-6 一并 ship 切分决策)。

Execute 落地步骤(单 commit 一并 ship):

1. **parser.ss maybeNullable +1 LOC guard**(D132 §4.1):
```ss
function maybeNullable(baseType: string): string {
+   if (pendingGtTokens > 0) { return baseType }    // SHR/USHR 拆分中,? 归 outer
    if (curKind() == "QUESTION") {
        pAdvance()
        return baseType + "?"
    }
    return baseType
}
```

2. **Execute 第一步实测分流 H1 物理验证**(D132 §6 + §8):
```bash
./build.sh bootstrap
bin/ss build /tmp/t_deep_optional.ss --emit-ir > /tmp/t.ll
grep -nA 50 'OrderMatrixOpt_deserialize' /tmp/t.ll | head -50
# 期望 IR: 字段 jnGetField 后 alloca + jnIsNullOrMissing + opt_present/opt_done labels
# 若 IR 仍现 outer 直 jnArrayLen / inner 误 wrap → H1 假 → 升根 D132' 候选 B codegen normalize
```

3. **新建 tests/phase5/i021_requestbody_nested_deep_optional.ss** 8-10 case(笛卡尔积 + 任意 N×M 同构剥皮形态推广):
   - case 1-2: form 1 `Array<Tag?>?` outer present + inner mixed null → tags=N,nulls=M / outer null/missing → no-tags
   - case 3-4: form 2 `Map<string, Tag?>?` 同源 outer/inner 笛卡尔积
   - case 5: form 3 `Array<Array<Tag>>?` outer present 二层嵌套 + outer null/missing 三态
   - case 6: form 4 `Map<string, Map<string, Tag>>?` outer present 二层 Map 嵌套 + outer null/missing
   - case 7: form 5/6 `Array<Map<string, Tag>>?` / `Map<string, Array<Tag>>?` 混合 + outer 三态
   - case 8: 全链路 raw HTTP POST 6 endpoint × 4 场景 byte-identical Java oracle smoke
   - case 9: RC stress 50 次循环 outer null + outer non-null + inner null + inner non-null 字段 outer drop → no leak / no segfault
   - case 10: emit-ir 锚 grep `@jnIsNullOrMissing|opt_present|opt_done|jnArrayLen|jnObjectKeys|@Tag_deserialize` ≥ 13(D132 §6 GREEN)

4. **examples/spring-parity/hello/ss/HelloController.ss + .java** 加 6 fixture(`OrderTagsArrDeepOpt` / `OrderTagsMapDeepOpt` / `OrderMatrixOpt` / `OrderGroupsOpt` / `OrderArrMapOpt` / `OrderMapArrOpt`)+ Java oracle 对称 `List<Tag>` / `Map<String, Tag>` Spring 默认 nullable;Tag 类复用既有。

5. **回头观察点验证**(D132 §9):
   - N=3 形态 `Array<Array<Array<Tag>>>?` USHR 拆分 + outer `?` 自动 cover(加 1-2 case)
   - N=2 + 中层 + 外层多 `?` `Array<Array<Tag?>?>?` 任意 M 自动 cover(加 1-2 case)
   - generic class / generic method 类型参数副作用(phase4 全套测试无 regression)

6. **VCM 六验**:bootstrap 三阶段固定点 PASS + reflection_health_linter F1 GATE PASS no regressions + phase4/5 0 regression + RC stress no leak + spring-parity byte-identical + d_doc_index_linter PASS。

7. **D132 status 同轮兑现**:`docs/3-decisions/D132-deep-optional-nesting-strip.md §9 备注 status` Edit 从 `Decided + Done at 留下下轮` → `Decided + Done at bootstrap/parse/parser.ss:790-796 maybeNullable + pendingGtTokens guard(commit <hash>)`。

8. **I021 子档 §status reconciliation 同轮兑现**:`docs/4-issues/I021-requestbody-nested-deep-optional.md §status` Edit 从 `Done at: 无` → `Done at: bootstrap/parse/parser.ss:790-796 + tests/phase5/i021_requestbody_nested_deep_optional.ss + examples/spring-parity/hello/ss/HelloController.ss(commit <hash>)`。

9. **simplify 4 agent 复审**(reuse / quality / efficiency / readability per `feedback_human_readable_code` 5 rubric a-e — readability veto)。

10. **commit message format**:`feat(I021-requestbody-nested-deep-optional,D132,D131,D130,D067,D123,D129): D132 §4.1 parser maybeNullable + pendingGtTokens guard +1 LOC 物理 surgical 修 + I021 v0 8-10 case + spring-parity 6 fixture + RC stress 50 次循环 — 任意 N×M nullable + 嵌套递归同构剥皮根因 ship — 笛卡尔积真零 codegen 场景对照 -inner 首次部分命中 + -container 首次完全命中 + -deep-optional 部分破裂转 D132 后第三次自动 cover 真零 codegen — Phase 4 §247 第二支柱嵌套深化第十一轮 D132 起立 + Execute 落地轮`。

D132 §备注 D131 §4 边界扩 vs D132 独立新档 取舍已锚选 D132 独立新档(议题尺度跨 parser/codegen + 修法物理位置跨文件 + D 文档治理避免污染 D131 history),不扩 D131。本轮决策归档锁定后 Execute 落地直接 RED→GREEN 不再 Plan(memory `feedback_execute_when_doc_locked.md`)。
