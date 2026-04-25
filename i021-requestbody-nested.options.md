# I021-requestbody-nested 嵌套 class 反序列化 bug 修复方案对比

## 问题

`tests/phase5/i021_requestbody_nested.ss` RED 命令实测:

```bash
bin/ss build tests/phase5/i021_requestbody_nested.ss -o /tmp/t --emit-ir 2>&1 | grep -cE "@Customer_deserialize|@Address_deserialize"
# 输出:0(预期:2)
```

IR 物理证据:`Order_deserialize` 嵌套字段 `customer` / `addr` fallback 到 `store ptr null`(`bootstrap/gen/gen_type_ops.ss:437-451`),且 `Customer_deserialize` / `Address_deserialize` 函数完全未 emit。

## 假设破裂入口(2 项)

1. **假设**「`deserializerTargets` 由 invoke sentinel 一一注册即可」在嵌套场景下**假设破裂** — 因为嵌套 user class(`Customer` / `Address`)不被 invoke sentinel 直接引用,只通过 outer class(`Order`)字段间接引用,注册路径漏 transitive closure → 嵌套 deserializer 永不 emit → undefined symbol link error 或 store null。

2. **假设**「`jnGetInt/Double/String/Bool` primitive helpers 足够覆盖所有字段」在嵌套场景下**假设破裂** — 嵌套字段类型是 user class 而非 primitive,需要 `jnGetField` 拿子 nodeId + 递归调 `<NestedClass>_deserialize` 才能反序列化嵌套对象。

## 候选方案对比

| 候选 | 方案 | 层次 | 优 | 缺 |
|---|---|---|---|---|
| **A** | **`emitClassDeserializeFn` 嵌套 user class 字段 case 加递归调 + `emitPendingDeserializers` 用 work-list 算法做 transitive closure**(emit 前迭代扩展 `deserializerTargets`,直到不动点) | **数据**(`deserializerTargets` Map 内容由直接引用扩为传递闭包)+ **接口**(`emitClassDeserializeFn` 嵌套字段 case 加 jnGetField + `<NestedClass>_deserialize` 递归调)+ **架构**(延迟 emit 模式不变,closure 计算时机移到 `emitPendingDeserializers` 入口) | 改动局限两函数(`emitClassDeserializeFn` + `emitPendingDeserializers`)/ 不动 invoke sentinel 注册路径 / 闭包计算 emit 前一次性算完不污染 method_call.ss / 与 ss_drop_X / ss_deep_clone_X 全 class 自动生成模式对称(嵌套 class 一并 emit drop/clone)/ jnGetField 已存在(lib/json.ss:263)零新 helper | 工作集小约 30-40 LOC,但需正确处理无穷递归(`A → B → A` 自引用)— work-list visited Map 兜底 |
| **B** | invoke sentinel 注册 `deserializerTargets` 时直接做 transitive closure(`method_call.ss:178` 注册 outer class 同时递归注册嵌套 class) | **数据**(同 A,Map 内容传递闭包)+ **接口**(method_call.ss 注册路径加递归)+ **架构**(closure 计算时机前移到 invoke sentinel 注册时,与 emit 解耦) | 注册时一次性算完,emit 入口无需 work-list | invoke sentinel 是 eval 层(method_call.ss),却要看 codegen 层数据(classFields / classFieldTypes)— 跨层耦合违反 D015 func registry isolation;闭包计算混在 invoke sentinel 处理路径里降低可读性 |
| **C** | 弃延迟 emit,所有 class 都自动生成 `<ClassName>_deserialize`(回到 emitClassTypeInfo 全 class emit) | **架构**(放弃 v0 延迟 emit 的隔离设计) | 实现最简 | 违反 v0 §200-205 注释明确说的「延迟 emit 防 jnGet* runtime symbol 污染未 import lib/json.ss 的程序」— 若程序未 import lib/json.ss,deserializer 内部 jnGetInt/Double/String 调用会 link 失败;**直接撞 v0 设计原则,否决** |
| **D** | 在 codegen.ss generateToFile 末尾加单独预处理 pass 计算 closure,然后调 emitPendingDeserializers | **架构**(closure 计算独立成 pass) | 概念上分离 closure 计算与 emit | 多 pass 实质上和 A 的 work-list-then-emit 等价,但拆成两个函数额外增加 codegen 入口复杂度 — A 把闭包计算内嵌 emitPendingDeserializers 入口更内聚;无独立 pass 必要 |

## 决策

**选 A** 因:

1. **根因解决度最高**(第一法则):嵌套字段递归 + transitive closure 同时修,既补 emit 路径(接口层缺 user class case)又补 emit 范围(数据层缺嵌套 class targets);两处缺口同源(v0 注释 line 392-393 明确锚「嵌套 user class / Array / Map 字段报 codegen 编译错(留 I021-requestbody-nested 子档完善)」),A 是兑现该锚的最直接路径。

2. **改动局部 + 不破坏现有架构**:`emitClassDeserializeFn` + `emitPendingDeserializers` 两函数局部修,不动 invoke sentinel 注册路径(method_call.ss),不动 v0 延迟 emit 设计(防 jnGet* runtime symbol 污染未 import lib/json.ss 的程序);与 ss_drop_X / ss_deep_clone_X 全 class 自动生成对称 — 嵌套 class 在 transitive closure 扩展时一并被 emit,与既有 per-class 函数自动生成模式一致。

3. **B 否决**:eval 层(method_call.ss)调 codegen 层数据(classFields / classFieldTypes)= 跨层耦合,违反 D015 func registry isolation 隔离原则;closure 计算混在 invoke sentinel 处理路径里降低可读性。

4. **C 否决**:违反 v0 §200-205 延迟 emit 设计原则,直接撞 jnGet* runtime symbol 污染未 import lib/json.ss 程序的 link error,根本不可行。

5. **D 否决**:多 pass 等价 A 但额外增加 codegen 入口函数;A 的 work-list-then-emit 内聚在 emitPendingDeserializers 入口更简。

## 落地步骤

1. `bootstrap/gen/gen_type_ops.ss:emitClassDeserializeFn` 嵌套字段 fallback case(line 437-451)替换为:
   - 若 `isUserClass(ft) == 1`:emit `jnGetField(nodeId.arg, key)` 拿子 nodeId(int)+ emit `<ft>_deserialize(子 nodeId)` 拿子 ptr + emit `store ptr <子 ptr>` 到字段 gep(无 retain — 子 deserialize 已返 rc=1 新对象,直接 transfer ownership;父 ss_drop_<Outer> 链 emit `ss_release` 自动级联触发子 drop)
   - Array / Map 字段保留 fallback null(留 nested-array / nested-map 子档)
2. `bootstrap/gen/gen_type_ops.ss:emitPendingDeserializers` 入口加 work-list transitive closure:
   - `let workList = deserializerTargets.keys()`
   - `let visited: Map<string, int> = new Map()`
   - 循环 pop workList,若 cn 未 visited:visited.set(cn, 1),遍历 classFields[cn] 字段,若字段类型是 user class 且未 visited → `deserializerTargets.set(ft, 1) + workList.push(ft)`
   - 闭包计算完后,for cn in deserializerTargets.keys() 调 emitClassDeserializeFn(同既有逻辑)
3. ./build.sh bootstrap 固定点 PASS + RED grep ≥ 2 + 5 case test exit 0
