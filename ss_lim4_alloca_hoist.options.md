# SS-LIM-4 Alloca-not-dominate-all-uses verifier crash — 修法方案对比

## 现象

- 用户原始 repro: `function recurseHard(n: Node)` with 嵌套 while + 多 if instanceof + as cast + 多 const + 递归,LOC > 40 → `llc: error: input module cannot be verified` + `Instruction does not dominate all uses! %ce.470 = alloca ptr, ... %34 = load ptr, ptr %ce.470`
- 本轮 spike `tests/phase5/ss_lim4_alloca_hoist_test.ss` 编译过(我未完美复刻原始 trigger 形态),**但结构性 RED 仍命中**:`awk 'BEGIN{e=0;n=0} /^entry:/{e=1;next} /^[a-z][a-z._0-9]*:[[:space:]]*$/{e=0;next} e==0 && / = alloca /{n++} END{print n}' /tmp/lim4_red.ll` = **48**(48 个 alloca 在非 entry BB,跨 spike + 标准库)
- 根因:`bootstrap/gen/{gen_decls.ss,stmts/stmts_loop_forin.ss,stmts/stmts_exc.ss,exprs/exprs_binary.ss,gen_arrows.ss,...}` 共 12+ 处 `emitIR(\`%${name} = alloca ...\`)` 调用直接在"当前 BB"emit alloca,**没有"alloca 必在 entry block"不变量**;一旦 alloca 落到嵌套 BB(if.then / cast.ok / while.body / if.merge / nc.then / sc.rhs / catch BB),use 路径若不经过 alloca BB → LLVM dominator analysis reject

## 假设破裂入口(共同根)

`bootstrap/gen/gen_emit.ss:emitIR` 是平面流式 append,**没有 BB-aware insertion point**;凡 codegen 子族(gen_decls / stmts_loop_forin / stmts_exc / exprs_binary / gen_arrows / 等) 调用 `emitIR(`  %X = alloca ...`)` 时假设"当前 emit 位置 = 当前 BB",而当前 BB 是函数体不断切换的(`emitIR("if.then.N:")` / `emitIR("cast.ok.N:")` / `emitIR("while.body.N:")` 等会切 BB)→ alloca 被困在切换后的 BB → use 路径不经过该 BB 时 dominate 失败 → verifier reject

## 候选对比

| 候选 | 层次 | 描述 | 优 | 劣 | 假设破裂消除点 | 长久 / 演化对标 | 决策 |
|---|---|---|---|---|---|---|---|
| **A** | 数据层 patch | 函数 IR emit 完后,文本后处理(awk / regex)把所有 `  %X = alloca ...` 行移到 `entry:` 之后 | emit 路径不动;最少 LOC | post-process 字符级 fragile;IR 文本格式微变(空格 / 注释 / 多行 alloca)即破;alloca 后紧跟的 store 不能跟着移(store 仍在原 BB 是对的);跨函数边界识别脆弱(define ... { 嵌套 } 解析) | 部分消除(alloca 物理位置改 entry,但接口层未 trap → 未来新加 emit 点仍按错误模式写) | LLVM 演化 0% 用 post-process(LLVM 早期就是 IRBuilder 显式 BB);N 年返工度 100% — 任何 emit 模板小变就必返工 | ✗ |
| **B** | 接口层 trap + 数据层 hoist 双轨 | (1) `bootstrap/gen/gen_emit.ss` 加 `funcEntryAllocas: string` 累积缓冲 + `emitEntryAlloca(name, llType, align): string` API + `flushFuncEntryAllocas()` + `resetFuncEntryAllocas()`; (2) 12+ 处直接 `emitIR(`  %X = alloca ...`)` 改为 `emitEntryAlloca(name, llType, align)`; (3) `ir_builder.ss:irAlloca` 改为路由到同一 buffer; (4) 函数 emit 入口(`genFunc` / `genArrow` / `genConstructor` / `genMethodBody` / class drop_fn / deep_clone_fn / shallow_clone_fn / global init wrapper / runtime emit 处)在 emit `entry:` 后立即 `flushFuncEntryAllocas()`;退出函数前 `resetFuncEntryAllocas()` | 真根因 — 接口层 trap 让未来 emit 点必走 API(违则一望可见,新 emit 点不能再"忘记 hoist");数据层 hoist 真把 alloca 物理放到 entry block 顶部;LLVM 标准做法(IRBuilder 的 GetEntryBlock + insertBefore 或 alloca-in-entry-only convention);**编译器吸收复杂度,应用代码无需配合**;一刀切覆盖 12+ 现有 emit 点 + 未来新 emit 点 | 函数边界 8+ 处入口要插 flush hook;funcEntryAllocas 是 string 缓冲不是 BB-aware IRBuilder(限于 alloca + entry,不解决一般 BB 切换问题但本轮 scope 不需要) | 完全消除 — alloca 物理位置改 entry(数据轨)+ API trap 让"在嵌套 BB emit alloca"成为编译时不可表达(接口轨) | LLVM 演化客观顺序:**先 entry-alloca-convention(LLVM 1.x 时代约定)→ 后 IRBuilder API(LLVM 3.x+)**;SS 当前阶段先做 convention 是业界客观顺序;N 年返工度 0%(IRBuilder 演化时此 API 是 trivial migrate target,buffer 直接退役) | **✓** |
| **C** | 架构层 refactor — 全 codegen 改 BB-aware IRBuilder | 重写 codegen 为带 BB 引用 + insertion point 的 IRBuilder 模式(类似 LLVM C++ API):每个 BB 是对象,emit 时用 `builder.SetInsertPoint(bb)` 切换插入点,alloca 走 `builder.CreateAlloca(.., insertBefore=entry.firstInst)` | 长期视野最干净;一次性消除所有 BB 管理 ad-hoc;一切 emit 强制带 BB 上下文 | scope 爆炸(改全部 codegen 子族 ~ 30 文件);本轮 LOC 估 800+ + N 个 phase 才能落定;违反 §改动分层"大改"档位上限可接受范围(>5 文件 + > 100 LOC 但 30 文件 + 800 LOC 是另一量级);依赖 B 候选作为前置(IRBuilder 内部仍需"alloca 必入 entry"约定) | 完全消除 + 引入新 IR 抽象层 | LLVM 演化客观顺序里 IRBuilder 是 entry-alloca-convention **之后** 的 phase;**先做 C 跳过 B 违反业界对标**;且 C 依赖 B(IRBuilder 内部仍约定 alloca 入 entry) — 违反 §字段 10 (d) "底层依赖链:候选 A 依赖未落地的更基础候选 B,B 必先于 A 起首" | ✗(留远期 phase,本轮先做 B 作为基础;C 在 B 落定后再起独立 D 文档评估) |
| **D** | PIR 层 alloca normalization pass | 在 PIR optimizer(`bootstrap/pir/pir_opt.ss`)加一个 "alloca normalization" pass:遍历 PIR,把所有 alloca op 提到 entry block | 复用 PIR pass 框架 | PIR 当前不操心 alloca 物理位置(只管 RC liveness);PIR 是 IR-to-IR pass,但 SS 的 codegen **直接到 LLVM 文本** 不经过 PIR rewrite framework — alloca 在 codegen 阶段已是文本,PIR 看不见;扩 PIR 覆盖 alloca 是 scope 错位(PIR 是语义 IR 不是 LLVM IR) | 假设破裂消除点错位 — 错位放到 PIR 不能 trap codegen 直接 emit `alloca` 文本 | PIR 设计目标是 RC liveness + REUSE 优化,不是 alloca location normalization;N 年返工度 100% — 后续若 PIR 退役/重构 此 pass 无家可归 | ✗ |
| **E** | 编译末端调 LLVM `opt -mem2reg` | bin/ss build pipeline 末端 IR 跑 `opt -mem2reg` pass,LLVM 自动把 alloca 转 SSA 寄存器 | 零 codegen 改;一行命令调 opt | 引入新工具链依赖(`opt-18`,当前 SS 只依赖 `llc-18` + `musl-gcc`);**mem2reg ≠ alloca-hoist** — mem2reg 把 alloca-load-store pattern 转 phi node,即"消除 alloca",而本 bug 在 mem2reg 跑前 verifier 已 reject 输入 IR(verifier 在 opt 之前必跑) | 假设破裂消除点错位 — opt 跑前 verifier 已 reject,mem2reg 救不了 | LLVM opt pass chain 客观顺序:verifier → mem2reg → ...;opt 不能跑在 verifier reject 的 IR 上;N 年返工度 100% — verifier 永远在前 | ✗ |

## 决策行

**选 B(接口层 trap + 数据层 hoist 双轨)因根因解决度 9/10:接口轨 trap 未来 emit 点(新加 var-decl 必走 emitEntryAlloca,违则一望可见)+ 数据轨 alloca 物理放到 entry block(verifier 不再有 dominate-related reject 入口)。**

**为何不选 deeper layer C:** C(IRBuilder 重写)依赖 B(entry-alloca-convention)作为前置 — LLVM 演化客观顺序 entry-alloca-convention → IRBuilder API,SS 当前先做 B 是业界对标客观判据(§字段 10 (d) 长久演化维度);C 自身 scope 爆炸(30 文件 + 800 LOC + N phase)且违反 "底层依赖链 — 上层必依赖下层落地" 不变量。本轮不选 C 是基于 §字段 10 (d) 横向时间维度,不是基于"工程量大"(违反 `feedback_root_cause_no_cost` §7 禁工程量排序)。C 留 next_prompt 起独立 D 文档评估。

## 假设破裂总览

- H1(post-process 字符级可靠):破裂 → 否 A(IR 文本格式微变即破;store 跟随逻辑错位)
- H2(emit 平面流式 = alloca 必和 use 同 BB):破裂 → 选 B(API + buffer 双轨,emit 平面但缓冲分流)
- H3(IRBuilder 不依赖 entry-alloca-convention):破裂 → 否 C(LLVM 演化客观顺序 convention 先于 IRBuilder)
- H4(PIR 能 trap codegen 直接 emit alloca 文本):破裂 → 否 D(PIR 是语义 IR,看不见 codegen 文本输出)
- H5(opt -mem2reg 能在 verifier reject 后跑):破裂 → 否 E(verifier 在 opt chain 之前)

## 实施明细(B)

**新增**(gen_emit.ss):
- `let funcEntryAllocas = ""` (全局 string 缓冲)
- `function emitEntryAlloca(name: string, llType: string, align: int): string` — append `  %${name} = alloca ${llType}, align ${align}\n` 到 funcEntryAllocas,return `%${name}`
- `function flushFuncEntryAllocas()` — emit funcEntryAllocas 内容(若非空) 到 irBuf
- `function resetFuncEntryAllocas()` — funcEntryAllocas = ""

**改 ir_builder.ss `irAlloca`**:把内部 `emitIR` 改为路由到 `funcEntryAllocas`(append into buffer 不直接 emit)

**改 12+ 处直接 emitIR alloca**:每处 `emitIR(\`  %${llName} = alloca ${llType}, align ${align}\`)` 改为 `emitEntryAlloca(llName, llType, align)`(返回 `%${llName}` 是 alloca 寄存器,store 仍在原 BB 走 emitIR)

**函数边界 flush + reset hook**(8+ 处 emit `entry:` 之后):
- `gen_decls.ss:118` (genFunc) — 在 emit `entry:` 后 + body emit 前不 flush(因为 alloca 在 body emit 中累积);**body emit 完才 flush** — 但此时位置错了。**正确做法**:body 用单独 buffer 累积,body 完成后 emit `entry:` + flush funcEntryAllocas + emit body buffer + emit closing brace
- 即:`emitFuncBody(...)` 改为先把 body emit 到 `bodyBuf`,完成后:
  ```
  emitIR("entry:")
  emitIR(funcEntryAllocas)  // flush
  emitIR(bodyBuf)            // body content (不含 entry: 标签)
  ```
- 这种"三段式"是 entry-hoist 的标准实现

**测试**:`tests/phase5/ss_lim4_alloca_hoist_test.ss` 已写;新加 case 包含 try/catch + nested loop + 多 const + 递归。

**RED → GREEN 命令**:
```bash
bin/ss build tests/phase5/ss_lim4_alloca_hoist_test.ss -o /tmp/lim4 --emit-ir 2>&1 > /dev/null
awk 'BEGIN{e=0;n=0} /^entry:/{e=1;next} /^[a-z][a-z._0-9]*:[[:space:]]*$/{e=0;next} e==0 && / = alloca /{n++} END{print n}' /tmp/lim4.ll
# RED: 48 (现状)
# GREEN: 0 (alloca 全部 hoist 到 entry)
```

## 联动确认

A+B 互斥(B 是接口 trap A 是 post-process,选 B 即弃 A),B 与 C/D/E 互斥。本轮单选 B。

## 跨族 / 长久演化判据(§字段 10 (d))

- **底层依赖链**:B 是 C 的前置(IRBuilder 内部仍需 entry-alloca-convention)→ B 必先做
- **业界演化对标**:LLVM 1.x → 3.x 是 entry-alloca-convention → IRBuilder,SS 现阶段照此顺序做 B
- **N 年返工度**:B 0%(IRBuilder 演化时 emitEntryAlloca API 是 trivial migrate target,funcEntryAllocas buffer 直接退役);C/D/E 100%
