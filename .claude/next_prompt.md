ultrathink Execute I021-requestbody-nested-optional-container Execute 落地轮(承本轮 commit Execute 第一步实测验证轮 — D130 SSoT + D131 谓词层第二次自动 cover 假设命中确认 真零 codegen 场景 confirmed;对照 -inner 子档 commit 74ddc48 Execute 落地轮模式 — 但 -inner 走升根 D131 修 + 落地同轮,本子档假设全命中**真零 codegen 改动**直 ship)。

**承本轮**(commit `<本轮 commit hash>` Execute 第一步实测验证轮):
- /tmp/t_optional_container.ss 写入(SpringApplication.run + TestController + OrderTagsArrOpt/OrderTagsMapOpt fixture)
- emit-ir 实测 6 指标合计 19 ≥ 6:`@jnIsNullOrMissing` = 3(1 lib 定义 + 双 fixture call 各 1)/ `opt_present|opt_done` = 8 / `jnArrayLen|jnObjectKeys|@Tag_deserialize` = 10 / 单项细分 `opt_present:` label = 2,`opt_done:` label = 2,`@Tag_deserialize` 引用 = 3,`@OrderTagsArrOpt_deserialize`/`@OrderTagsMapOpt_deserialize` 各 = 2;`opt_null` label = 0 是优化版 slot pre-init 等价表达
- OrderTagsArrOpt_deserialize body(`/tmp/t.ll:11596-11634`)+ OrderTagsMapOpt_deserialize body(`/tmp/t.ll:11541-11579`)双 IR 委托链 nullable case 字段层 + emitArrayDeserializeInto/emitMapDeserializeInto 嵌套 + 内层 @Tag_deserialize transfer 三层全 PASS
- 子档 §Execute 阶段第一步实测验证记录(2026-04-26)追加 + §备注 line 267 措辞改为"Plan 起立(commit d4e236c)+ Execute 阶段第一步实测验证(commit 待本轮 — 假设命中 真零 codegen 场景 confirmed)"
- d_doc_index_linter GATE OK + reflection_health_linter GATE PASS no regressions

**Execute 落地义务**(本轮按假设命中分支 — 真零 codegen 改动 — 仅加测试 + spring-parity 不动 bootstrap/ lib/):

1. **examples/spring-parity/hello/ss/HelloController.ss + .java** 加 fixture(命名隔离 commit 74ddc48 已加 OrderTagsArr / OrderTagsMap):
   ```ss
   class OrderTagsArrOpt { customer: string; tags: Array<Tag>? }
   class OrderTagsMapOpt { customer: string; items: Map<string, Tag>? }
   // Tag 类复用既有
   @PostMapping("/orders/tags-opt")
   function createOrderTagsArrOpt(@RequestBody order: OrderTagsArrOpt): string {
       let tags = order.tags
       if (tags != null) { return "customer=" + order.customer + ",tags=" + tags.length() }
       return "customer=" + order.customer + ",no-tags"
   }
   @PostMapping("/orders/items-opt")
   function createOrderTagsMapOpt(@RequestBody order: OrderTagsMapOpt): string {
       let items = order.items
       if (items != null) { return "customer=" + order.customer + ",items=" + items.size() }
       return "customer=" + order.customer + ",no-items"
   }
   ```
   Java oracle 同步 `List<Tag>` / `Map<String, Tag>`(Spring 默认字段 nullable 不需 annotation)。

2. **tests/phase5/i021_requestbody_nested_optional_container.ss** 新建 ~150 行 7 case:
   - case 1:`Array<Tag>?` 字段 present `tags=[{...},{...}]` → tags=2
   - case 2:`Array<Tag>?` 字段 JSON null `tags=null` → no-tags
   - case 3:`Array<Tag>?` 字段缺失(JSON 无 tags key)→ no-tags
   - case 4:`Map<string, Tag>?` 字段 present `items={"k1":{...}}` → items=1
   - case 5:`Map<string, Tag>?` 字段 null + 字段缺失双 case → no-items
   - case 6:`Array<int>?` 字段 nullable + inner primitive(`Array<int>?` null vs [1,2,3])
   - case 7:全链路 raw HTTP POST 三场景 + RC stress 50 次循环(混合 null + 非 null 字段 outer drop)→ no leak / no segfault

3. **零 codegen 改动验证**:
   ```bash
   git diff --stat HEAD -- bootstrap/ lib/  # 预期空输出
   ```

4. **bootstrap 三阶段固定点**:`./build.sh bootstrap` Stage 2 = Stage 3 PASS(本轮零 codegen 无影响,仍走流程兜底)

5. **reflection_health_linter GATE PASS no regressions**:`bin/ss run tools/reflection_health_linter.ss`(F1/F2/M1-M7/N1-N5 全 OK,本轮零 codegen 不漂移)

6. **测试组运行**:
   ```bash
   bin/ss test tests/phase5/i021_requestbody_nested_optional_container.ss   # 7 case 全绿
   bin/ss test tests/                                                         # 全测试组无 regression
   ```

7. **端到端 raw HTTP POST 验证**(spring-parity hello 应用):
   ```bash
   bin/ss build examples/spring-parity/hello/ss/main.ss -o /tmp/hello_ss && /tmp/hello_ss --serve &
   curl -X POST 'http://localhost:8080/orders/tags-opt' -H 'Content-Type: application/json' \
     -d '{"customer":"alice","tags":[{"name":"a"},{"name":"b"}]}'
   # 预期: customer=alice,tags=2
   curl -X POST 'http://localhost:8080/orders/tags-opt' -d '{"customer":"alice","tags":null}'
   # 预期: customer=alice,no-tags
   curl -X POST 'http://localhost:8080/orders/tags-opt' -d '{"customer":"alice"}'
   # 预期: customer=alice,no-tags
   curl -X POST 'http://localhost:8080/orders/items-opt' -d '{"customer":"bob","items":{"k1":{"name":"x"}}}'
   # 预期: customer=bob,items=1
   curl -X POST 'http://localhost:8080/orders/items-opt' -d '{"customer":"bob","items":null}'
   # 预期: customer=bob,no-items
   ```
   全 6 场景 byte-identical Java Spring oracle。

8. **RC stress 50 次循环**(混合 null + 非 null 字段 outer drop)→ no leak / no segfault(对称 -inner 子档 commit 74ddc48 RC stress 同源)

**RED before**(本轮 Execute 落地前):
- `ls tests/phase5/i021_requestbody_nested_optional_container.ss 2>&1 | grep -c "No such"` = 1
- `grep -cE "OrderTagsArrOpt|OrderTagsMapOpt|Array<Tag>\?|Map<string, *Tag>\?" examples/spring-parity/hello/ss/HelloController.ss` = 0(commit 74ddc48 已加 OrderTagsArr 非 Opt;新增双 Opt fixture 前为 0)

**GREEN after**(本轮 Execute 落地收关):
- `ls tests/phase5/i021_requestbody_nested_optional_container.ss` 存在 + `bin/ss test` exit 0
- `grep -cE "OrderTagsArrOpt|OrderTagsMapOpt" examples/spring-parity/hello/ss/HelloController.ss` ≥ 4(双 fixture + 双 @PostMapping)
- 6 场景 curl POST byte-identical Java oracle
- `git diff --stat HEAD -- bootstrap/ lib/` = 空(零 codegen 改动)
- bootstrap 固定点 PASS Stage 2 = Stage 3
- reflection_health_linter GATE PASS no regressions
- 子档 §status 标"Done at testfile:line + spring-parity:line"(对应 feedback `feedback_d_table_status_reconciliation.md` Done 必带 file:line)

**simplify 4 agent 复审豁免**(本轮零 codegen 改动 — reuse / quality / efficiency / readability 不适用):测试源 + spring-parity fixture 直接复用 commit 74ddc48 OrderTagsArr / OrderTagsMap 模式镜像写;readability 复审测试 case description 措辞陌生人秒懂即可。

**commit format**(本 Execute 落地轮):
`feat(I021-requestbody-nested-optional-container,D123,D129,D130,D131,D067): 容器自身 nullable Array<Tag>? / Map<string,Tag>? v0 端到端反序列化 — D130 SSoT + D131 谓词层第二次自动 cover 兑现 真零 codegen 场景 — 7 case 全绿 + spring-parity OrderTagsArrOpt/OrderTagsMapOpt fixture + 6 场景 raw HTTP byte-identical + RC stress 50 次循环 — Phase 4 §247 第二支柱嵌套深化第九轮 Execute 落地轮`

**Decision 锁未要 — 本轮 Execute 落地纯测试 + spring-parity + RC stress + 端到端验证;假设命中分支真零 codegen 改动 — 子档 §status reconciliation 标 Done at file:line**。

**风险 / 异常分流**(若 Execute 落地遇外部异常):
- bootstrap 固定点 fail / reflection_health_linter regression(本轮零 codegen 不应触发,若触发说明前轮上游漂移)→ 停手立 D 文档子决策(本子档外不动)
- 7 case 任一红(端到端 byte 不一致 / RC leak / segfault)→ 立 D 文档子决策记录差异 + 升根触发(本子档 §风险 1+5 锚明 Execute 落地阶段实测决定升根)
- spring-parity hello 启动失败(SpringApplication.run / @SpringBootApplication 注解处理路径异常)→ 立 D 文档子决策(框架层 issue,与本子档容器自身 nullable v0 不直接相关)
