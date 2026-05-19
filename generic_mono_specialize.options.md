# generic_mono_specialize — 泛型单态化非确定性漏特化 bug 方案对比

## 摘要(大白话)

编译器把"泛型函数"翻译成具体版本时,有一行代码用错了比较方式:它想问"这次调用有没有传参数",却把一个"列表"直接拿去跟"空文字"比。列表在内存里的地址末位碰巧是不是 0,纯看运气 —— 末位是 0 时,比较被误判成"没传参数",于是编译器跳过了"把类型参 T 换成真实类型 Hero"这一步,产出一个残缺的半成品函数,运行时断言就挂。换台机器、或编译器自身被加了别的代码,内存布局一变,这个 bug 就时有时无。修法:把那行"拿列表比空文字"改成"拿真正的参数文字比空文字"。

## 根因 (Root Cause)

`bootstrap/gen/gen_calls.ss` `genGenericCall()` 步骤 1(类型参推断):

```
const aParts = argList != "" ? argList.split(",") : ""   // line 354 — aParts 类型 = Array<string> | string 联合
...
if (aParts != "") {                                      // line 360 — Array 与 "" 做 != 比较(类型混淆)
```

`aParts` 是联合类型(`argList.split(",")` 给 `Array<string>`,`""` 给 `string`)。`if (aParts != "")` 把运行时为 Array 的 `aParts` 与字符串 `""` 比 —— codegen 发射 `ss_string_ne(aPartsPtr, "")`。`%Array` 与 `%String` header 同布局 `{i64,ptr,ptr,i64,i64}`,`ss_string_ne` 把 Array header 当 String 解读、strcmp Array 的 `data` 指针(当 cstr):

- `data` 指针低字节 == 0x00 → strcmp 判"相等" → `aParts != ""` 为假 → 步骤 1 推断整段被跳过 → `subs` Map 空 → mangledName = `funcName_T`(裸类型参)而非 `funcName_Hero` → emit `define @fullInfo_T` + `; TODO: method call` 残桩。
- `data` 指针低字节 != 0x00 → `aParts != ""` 为真 → 正常特化。

mimalloc 16 字节对齐 → `data` 指针低字节 == 0x00 概率约 1/16,且随进程布局(ASLR / 工作树死代码致编译器自身布局漂移)漂移 → 非确定性、布局敏感、潜伏于 clean 编译器。

## §实证

**根因定位 grep 证据:**

```
$ grep -rn '? .*\.split(.*: ""' bootstrap/
bootstrap/gen/gen_calls.ss:354:    const aParts = argList != "" ? argList.split(",") : ""
```
→ `cond ? split : ""` 联合类型反模式全 bootstrap 仅此一处(非弥散反模式,单点根因)。

```
$ grep -n 'aParts' bootstrap/gen/gen_calls.ss
354 / 360 / 367
```
→ `aParts` 仅 3 处:声明(联合类型三元)、`!= ""`(类型混淆比较)、`for-in`(数组迭代)。读 `bootstrap/gen/rt/gen_rt_map.ss` 确认 `%Array`/`%String` header 同布局,`ss_string_ne` 对入参按 `%String` GEP `data`/`buf` 指针。

**最小 spike(最危险假设实证):**

最危险假设:"非确定性偏差源于 `genGenericCall` 步骤 1,定位后改之必消除"。spike = 仪器化 `genGenericCall` 打印步骤 1 各输入 + `aParts != ""` 求值;单阶段 build 仪器编译器 `/tmp/ss_inst`;500 路并行 `build tests//phase5/generic_multi_constraint.ss`:

```
buggy=500/500
XGGCa pId=714 pType=[T] apNE=0          ← aParts != "" 求值 = 0(假)
XGGC  fullInfo fn=715 dP=[714] tps=[T] expl=[] aL=[785] subs: T#has=0
XGGC2 fullInfo mangledSig=[T] mangledName=[fullInfo_T]
```

→ `aL=[785]`(argList 非空)但 `apNE=0`(`aParts != ""` 求假)—— 直接实锤 `aParts != ""` 是唯一偏差点,其余输入(funcNodeId/declParams/typeParamStr/explicitTypes/argList)全对;clean 对照 run 同探针 `subs: T#has=1` → `fullInfo_Hero`。由此最危险假设证实:guard 改为基于类型干净的 `argList`(string,非空)→ guard 必真 → 步骤 1 推断必执行 → `subs` 必含 T。**选定候选 B 的 spike 验证**(应用 B 后 500 路并行 = 0 buggy + 三阶段固定点 stage2==stage3 + `bin/ss test tests/` ×N = 325/4)在 Execute 阶段落地。

## 候选方案对比

**假设破裂入口**:`!=`(BINARY_OP)的 codegen 假设两侧操作数 SS 类型一致;当 LHS 为 `Array`、RHS 为 `string` 时静默发射 `ss_string_ne`,把 Array header 重解读为 `%String`。该假设在联合类型变量持 Array 值时**破裂**。

| 候选 | 层次 | 含 | 不含 | 在哪层消除/绕过假设破裂 | 决策 |
|---|---|---|---|---|---|
| A | 数据层 patch | `if (aParts != "")` → `if (argList != "")`(line 360 单 token) | `aParts` 联合类型仍保留 | 绕过:不再把 Array 喂进 `!=`,改比类型干净的 `argList`(string);破裂入口仍在,仅本路径不触发 | 不选 |
| B | 接口层 trap | A + `const aParts = argList.split(",")`(line 354 去三元) | 编译器 checker 不动 | 消除:`aParts` 类型契约收敛为纯 `Array<string>`,联合类型根除 → 任何 codegen 路径都不可能再把 `aParts` 重解读为 string | **选** |
| C | 架构层 refactor | 修 checker 拒绝 mixed-type `!=`(`Array != string` 报类型错) | 单态化代码本身仍需改 | 消除(全局):破裂入口在 check 阶段被 gate,全编译器/stdlib 同类隐患一网打尽 | 不选 |

**决策行**:选 B 因 B 在单态化 scope 内根除结构性病根(`Array<string> | string` 联合类型三元),`aParts` 类型契约收敛为纯数组、N 年返工度低;A 是 B 的真子集(留联合类型,下个改这块的人仍可能踩同坑),根因解决度不足;C 最深但 scope = 整个 type checker(D164 §核心原则 9 范式:单 bug scope 不引入全局 type-system 重写),且 C 落地后这行代码仍须改(checker 报错 ≠ 代码自动正确)→ C 不替代 B,列废案。

**长久/演化**:B 无底层依赖、自洽,落地即终态;C(业界对标 TS/Rust:强类型 checker 即拒 mixed-type 比较)是更基础能力,但属独立 compiler-wide 工程,非 B 的前置依赖 → 不阻塞 B;未来若要做全编译器 type-confusion gate 再独立起,届时 B 已正确、无返工。
