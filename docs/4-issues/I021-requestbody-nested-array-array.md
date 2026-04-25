# I021-requestbody-nested-array-array:嵌套 `Array<Array<Class>>` / `Array<Array<int>>` / `Array<Array<string>>` / `Array<Array<double>>` / `Array<Array<bool>>` 2D 嵌套数组反序列化

> 父档:[I021-requestbody-nested-array-primitive.md](./I021-requestbody-nested-array-primitive.md)(commit a096fd0 — 单层 `Array<int|string|double|bool>` primitive 元素反序列化 + lib/json 扩 4 raw helper + codegen Array 分支 elemType 4 路分派)
> 同级父档:[I021-requestbody-nested-array.md](./I021-requestbody-nested-array.md)(commit c3361c9 — 单层 `Array<UserClass>` 元素反序列化 + lib/json array iter 扩接口 + arr[i].field 类型推断根因修)
> 祖档:[I021-requestbody-nested.md](./I021-requestbody-nested.md)(commit b79aa97 — 单层嵌套 user class scalar 字段端到端)
> 祖祖档:[I021-requestbody.md](./I021-requestbody.md)(commit 8165370 — Phase 4 §247 第二支柱端到端兑现)
> 上层 D 文档:[D123 §247 Phase 4 §第二支柱](../3-decisions/D123-spring-boot-replication.md) + [D129 §94/§130 @RequestBody V=class 域含嵌套+collection](../3-decisions/D129-request-param-class-domain.md)

## 问题

I021-requestbody-nested-array-primitive v0(commit a096fd0)端到端兑现单层 `Array<int|string|double|bool>` primitive 元素反序列化(`emitClassDeserializeFn` Array 分支按 elemType 4+1 路分派,lib/json 扩 `jnArrayGetInt` / `jnArrayGetString` / `jnArrayGetDouble` / `jnArrayGetBool` 4 raw helper)。`isArrayDeserializable` 谓词在 `bootstrap/gen/gen_deserialize.ss` 已扩 5 路 elemType(int / string / double / bool / UserClass)识别。

但本谓词**仅识别一层 elemType**:

```ss
function isArrayDeserializable(ft: string): int {
    if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
    const et = extractContainerElemType(ft)
    if (isUserClass(et) == 1) { return 1 }
    if (et == "int" || et == "string" || et == "double" || et == "bool") { return 1 }
    return 0  // ← Array<Array<X>> 走此路 fallback
}
```

故 `Array<Array<UserClass>>` / `Array<Array<int>>` / `Array<Array<string>>` / `Array<Array<double>>` / `Array<Array<bool>>` 字段——外层 et=`Array<X>` 既非 user class 也非 4 primitive 集合 → 谓词返 0 → falls through 到 `else` 默认 fallback(`bootstrap/gen/gen_deserialize.ss:184` `store ptr null`),与 Java Spring `List<List<Integer>>` / `List<List<String>>` / `List<List<Cell>>` 行为 **byte-divergence**。

a096fd0 父档 line 108 §留下下轮锚 1 已声明:"**I021-requestbody-nested-array-array** — `Array<Array<Class>>` / `Array<Array<int>>` 嵌套数组(2D matrix 类 DTO,涉 RC 双层契约累积 + 内层 array element drop 链)" — **scope 显式留本子档**。

c3361c9 同级父档 line 75 §留下下轮锚 2 同口径锚:"**I021-requestbody-nested-array-array** — `Array<Array<Class>>` 嵌套数组(2D matrix 类 DTO,涉 RC 双层契约累积)"。

enterprise REST API 真实业务 `@RequestBody { matrix: Array<Array<int>>, rows: Array<Array<Cell>>, table: Array<Array<string>> }` ——2D 表格 / 矩阵 / 二维 grid 类 DTO 是 Spring `List<List<X>>` 99% 表格业务覆盖(矩阵/网格/分组明细/层次列表)。SS 现状 codegen 检测到外层 `Array<Array<X>>` 字段静默 store null,运行时 `order.matrix.length() == 0` 即使 JSON `{"matrix":[[1,2],[3,4]]}`。

## 第一性需求

引 [D123 §第一性需求](../3-decisions/D123-spring-boot-replication.md) + [D129 §94](../3-decisions/D129-request-param-class-domain.md)("@RequestBody | HTTP body JSON / XML / form → class 反序列化 | **任意 class(含嵌套 + collection)** + Jackson/Gson 反序列化器 | HTTP body")。

SS 用户写:

```ss
class Cell { row: int; col: int; value: string }
class Matrix {
    name: string
    grid: Array<Array<int>>
    cells: Array<Array<Cell>>
    labels: Array<Array<string>>
}

@PostMapping("/matrix")
function createMatrix(@RequestBody m: Matrix): string {
    let total = 0
    for (let i = 0; i < m.grid.length; i = i + 1) {
        for (let j = 0; j < m.grid[i].length; j = j + 1) {
            total = total + m.grid[i][j]
        }
    }
    return "name=" + m.name + ",total=" + total
}
```

行为 byte-identical Java Spring:

```java
public class Cell { int row; int col; String value; }
public class Matrix {
    String name;
    List<List<Integer>> grid;
    List<List<Cell>> cells;
    List<List<String>> labels;
}

@PostMapping("/matrix")
public String createMatrix(@RequestBody Matrix m) {
    int total = 0;
    for (List<Integer> row : m.grid) for (Integer v : row) total += v;
    return "name=" + m.name + ",total=" + total;
}
```

curl `POST /matrix -H 'Content-Type: application/json' -d '{"name":"m1","grid":[[1,2,3],[4,5,6]],"cells":[[{"row":0,"col":0,"value":"a"}]],"labels":[["x","y"],["z"]]}'` → `name=m1,total=21`。

## 候选路径(选 A)

| 候选 | 路径 | 评估 |
|---|---|---|
| **A** | **复用 nested-array v0 + nested-array-primitive v0 双层 plumbing,`isArrayDeserializable` 谓词扩第三层递归识别(et 是 `Array<X>` 时 isArrayDeserializable(et)==1 视为可反序列化外层),emitClassDeserializeFn Array 分支按 elemType 6 路分派(原 5 路 int/string/double/bool/UserClass + 新 1 路"内层 Array<X>"递归 emit)**:外层 emit `ss_newArrayPtr`(tag=5,内层 Array 是 ptr 元素)+ jnArrayLen + 循环 jnArrayGet 拿 inner array nodeId + 内层递归 emit 一组 `ss_newArray|ss_newArrayPtr` + jnArrayLen + 循环 jnArrayGet + 内层 elemType 5 路分派(原本轮 a096fd0 落地 5 路) + 外层容器 push 内层 ptr(ptrtoint i64);双层 RC 契约:外层 ss_release_arr tag=5 → 触发逐内层 ss_release_arr → 触发逐元素 ss_release(string/UserClass)/直接 free(int/double/bool) | nested-array v0 + nested-array-primitive v0 双层 plumbing 100% 复用零结构变;`ss_arrayPush(ptr, i64)` 单签家族 D013 list-append 标准化已 cover ptr 元素(ptrtoint ptr→i64);`ss_newArray` (tag=1) + `ss_newArrayPtr` (tag=5) 二分恰好对齐 inner Array (tag=1 if 内 X primitive int/double/bool / tag=5 if 内 X 是 string 或 UserClass) + outer Array (tag=5,内层是 ptr);transitive closure BFS 扩(内层 Array<UserClass> elemType 即 UserClass 仍入 deserializerTargets,与单层一致);`emitFieldReleaseLoop` 已走 Array<X> drop 路径(gen_type_ops.ss:172),内层 elem_kind 走 ptr 路径触发逐内层 array release 链;[D088 §第一性需求 alignment](../3-decisions/D088-no-runtime-reflection.md) ✅ |
| B | runtime 反射递归遍历 array 元素元数据自动 deserialize(N 任意层) | 违反 [D088 §第一性需求](../3-decisions/D088-no-runtime-reflection.md) 编译期展开消除运行时反射 ❌ |
| C | lib/json 扩 `jnArrayGetArray(arrNode, idx): int` 单层 wrap 返 inner array nodeId + codegen 知道内层 elemType 分派 | 仍需 codegen 知道内层 elemType 分派(int vs string vs UserClass),helper 层只是去 jnArrayGet 一次包装,反多一层间接 + 与 nested-array v0 raw helper 模式不对称(jnArrayGet 已返 nodeId,内层走 isArrayDeserializable 路径不是 4 raw helper 路径);拆出独立 helper 是 helper 层 vs codegen 层职责切分,不简化反多一层间接 ❌ |
| D | 仅支持 N=2 不递归(谓词写死两层) | 与 -deep 子档"任意层数 N>1 BFS"路线冲突;N=2 是 N=3+ 的 base case,根因方案应一次性支持任意层递归(本子档 v0 scope 限 N=2 但谓词递归识别已天然支持 N=3+ 由 -deep 子档承接 BFS) ❌ |

选 **A** —— nested-array v0 + nested-array-primitive v0 双层 plumbing 100% 复用 + `isArrayDeserializable` 谓词扩第三层递归识别 + emitClassDeserializeFn Array 分支扩第 6 路"内层 Array<X>"递归 emit + RC 双层契约严审。

## v0 scope 切分说明(本子档)

**落地**:

- 双层嵌套 `Array<Array<X>>` 字段(N=2),X ∈ {int / string / double / bool / UserClass} 5 路全 cover
- bootstrap/gen/gen_deserialize.ss:
  - `isArrayDeserializable` 谓词扩第三层(et 是 `Array<X>` 时递归 `isArrayDeserializable(et) == 1` 仍视为可反序列化)— 谓词天然递归终止条件:内层 et 是 X(X ∈ {int / string / double / bool / UserClass} 终止)或 X 是 `Array<Y>` 继续递归(留 -deep 子档 N>1 BFS;但本子档 v0 scope 限 N=2,谓词递归在 N=2 时停止)
  - `emitClassDeserializeFn` Array 分支扩第 6 路 elemType(elemType startsWith `Array<` 走"内层 Array 递归 emit"路径,与原 5 路 int/string/double/bool/UserClass 平级 +1 路);内层 emit 复用同 emitClassDeserializeFn Array 分支逻辑(代码侧:抽 `emitArrayDeserializeBody(arrNodeR, elemType, idxR)` helper SSoT 收敛 vs 内联递归调用 emitClassDeserializeFn — Execute 轮 simplify 阶段拍板;若内层递归循环 emit 自身 IR 太重则抽 helper)
- per-class deserializer transitive closure BFS 扩:内层 Array<UserClass> elemType=UserClass 入 deserializerTargets(b79aa97 单遍 BFS 已 cover 单层 Array<UserClass>,本子档双层确认 BFS 入口在外层 elemType=`Array<X>` 时仍递归到 X)
- 测试 IR 锚:`grep -E "ss_newArrayPtr.*ss_newArray|jnArrayLen.*jnArrayLen" /tmp/t_i021_array_array.ll` ≥ 4(外层 ss_newArrayPtr + 内层 ss_newArray|ss_newArrayPtr + 双层 jnArrayLen × 2)
- 全链路 raw HTTP POST `/matrix` byte-identical Java oracle

**留下轮**(独立 issue,本 issue Execute 收关 + simplify + commit 后立或承接):

- **I021-requestbody-nested-deep**(已起立)— N>1 任意层数嵌套(N=3 / N=4 / N=5,本子档 N=2 是 base case;-deep 子档承接 BFS 任意层数)
- **I021-requestbody-nested-map**(已起立)— `Map<K, Class>` / `Map<K, Array<X>>` 嵌套(本子档 scope collection 维度 Array,Map 维度独立子档)
- **I021-requestbody-nested-optional**(已起立)— `Array<Array<X>>?` nullable 嵌套(配合 [D067 T? narrow](../3-decisions/D067-null-safety.md))

**v0 scope 不做**:

- 不实现 N>2 任意层数嵌套(留 -deep)
- 不实现 `Map<K, Array<Array<X>>>` / `Array<Map<K, Array<X>>>` 异构嵌套(留 -map + -deep 复合)
- 不实现 nullable `Array<Array<X>>?`(留 -optional + D067 narrow)
- 不实现顶层 `@RequestBody matrix: Array<Array<int>>`(留 I021-requestbody-array 平级独立子档,本子档 scope 限"嵌套字段")
- 不引入新关键字 / 新语法

## 步骤(Execute 轮按序)

1. **RED 命令(必先跑,字段 3 RED)**:

   ```bash
   # RED 1: codegen 谓词不识别 Array<Array<X>>
   grep -nE "Array<Array<|isArrayDeserializable.*Array<X>|elemType.*startsWith.*\"Array<\"" bootstrap/gen/gen_deserialize.ss
   # before: 0(谓词不递归识别)  after: ≥ 1(elemType startsWith "Array<" 第 6 路分派)

   # RED 2: codegen Array 分支只识别 5 路 elemType(原 a096fd0 落地)
   grep -nE "elemType == \"int\"|elemType == \"string\"|elemType == \"double\"|elemType == \"bool\"|isUserClass\(elemType\)" bootstrap/gen/gen_deserialize.ss | wc -l
   # before: 5 路(a096fd0 已落)  after: 6 路(+ 内层 Array<X> 递归)

   # RED 3: 端到端 silent 双层数组 IR 缺
   bin/ss build tests/phase5/i021_requestbody_nested_array_array.ss -o /tmp/t_i021_array_array_red --emit-ir 2>&1 | grep -cE "double.*ss_newArray\|double.*jnArrayLen"
   # before: 0(全 fallback store null,无双层 array IR)
   # after: ≥ 4(外层 ss_newArrayPtr + 内层 ss_newArray|ss_newArrayPtr + 双层 jnArrayLen × 2)
   ```

2. **examples/spring-parity/hello/ss/HelloController.ss** 加 `class Cell { row: int; col: int; value: string }` + `class Matrix { name: string; grid: Array<Array<int>>; cells: Array<Array<Cell>>; labels: Array<Array<string>> }` + `@PostMapping("/matrix") createMatrix(@RequestBody m: Matrix)`;Java oracle 同步 `examples/spring-parity/hello/java/.../HelloController.java`(注:与 a096fd0 落地的 `class OrderPrim` / c3361c9 落地的 `class OrderList` / b79aa97 落地的 `class Order` 命名独立,不冲突)。

3. **tests/phase5/i021_requestbody_nested_array_array.ss** 新建 ~180 行 8 case:
   - case 1:`Array<Array<int>>` 2×3 grid `[[1,2,3],[4,5,6]]` 双层 length + 元素求和 = 21
   - case 2:`Array<Array<string>>` 2×2 labels `[["a","b"],["c","d"]]` 双层 length + 元素拼接 = "abcd"
   - case 3:`Array<Array<Cell>>` 2×2 cells `[[{row:0,col:0,value:"x"}],[{row:1,col:1,value:"y"}]]` 双层 length + 元素 scalar 字段访问 `cells[0][0].value == "x"`
   - case 4:外层非空内层空 `[[],[]]` length=2 但每内层 length=0 RC 契约不破裂(双层容器 free 不触发 elem release)
   - case 5:外层空数组 `[]` length=0 RC 契约不破裂(外容器 free,不触发内层链)
   - case 6:`Array<Array<double>>` 2×2 元素求和精度对齐 Java
   - case 7:`Array<Array<bool>>` 2×2 元素逻辑 `flags[0][0] == 1 && flags[1][1] == 0`
   - case 8:全链路 raw HTTP POST `/matrix -d '{"name":"m1","grid":[[1,2,3],[4,5,6]],...}'`
   - IR 锚 `grep -E "ss_newArrayPtr.*ss_newArray\|jnArrayLen" /tmp/t_i021_array_array.ll` ≥ 4(外 ptr + 内 {1|5} + 双层 jnArrayLen × 2)

4. **bootstrap fix(codegen 主路径)**:

   ```ss
   // bootstrap/gen/gen_deserialize.ss isArrayDeserializable 谓词扩第三层
   function isArrayDeserializable(ft: string): int {
       if (ft.startsWith("Array<") == 0 || ft.endsWith(">") == 0) { return 0 }
       const et = extractContainerElemType(ft)
       if (isUserClass(et) == 1) { return 1 }
       if (et == "int" || et == "string" || et == "double" || et == "bool") { return 1 }
       if (isArrayDeserializable(et) == 1) { return 1 }   // ← 新加,递归识别 Array<Array<X>>
       return 0
   }

   // emitClassDeserializeFn Array 分支扩第 6 路 elemType
   } else if (isArrayDeserializable(ft) == 1) {
       const elemType = extractContainerElemType(ft)
       const arrNodeR = nextReg()
       emitIR(`  ${arrNodeR} = call i32 @jnGetField(i32 %nodeId.arg, ptr ${keyConst})`)
       const arrLenR = nextReg()
       emitIR(`  ${arrLenR} = call i32 @jnArrayLen(i32 ${arrNodeR})`)
       const initArrR = nextReg()
       // tag=1 if elemType primitive(int/double/bool 不 retain)
       // tag=5 if elemType ptr-bearing(string / UserClass / Array<X>)
       const isPtrElem = (elemType == "string" || isUserClass(elemType) == 1 || elemType.startsWith("Array<") == 1)
       const newArrFn = isPtrElem ? "ss_newArrayPtr" : "ss_newArray"
       emitIR(`  ${initArrR} = call ptr @${newArrFn}(i32 0)`)
       // ... loop head ...
       // body: 按 elemType 分派 6 路(原 5 路 + 新 1 路 "Array<X>" 内层递归 emit)
       if (isUserClass(elemType) == 1) {
           // c3361c9 落地路径(<Class>_deserialize → ptrtoint → ss_arrayPush)
       } else if (elemType == "int") { /* a096fd0 sext + ss_arrayPush */ }
         else if (elemType == "double") { /* a096fd0 bitcast + ss_arrayPush */ }
         else if (elemType == "string") { /* a096fd0 retain + ptrtoint + ss_arrayPush */ }
         else if (elemType == "bool") { /* a096fd0 zext + ss_arrayPush */ }
         else if (elemType.startsWith("Array<") == 1) {
           // 新加:内层 Array 递归 emit
           // arrNodeR2 = jnArrayGet(arrNodeR, idxR)  // 拿 inner array nodeId
           // 内层 elemType2 = extractContainerElemType(elemType)
           // 内层 emit 一组 ss_newArray|ss_newArrayPtr + jnArrayLen + loop + 内层 elemType2 5 路分派
           // 内层 ptrR = inner array ptr
           // 外层 push:val64R = ptrtoint ptr ${innerPtrR} to i64; ss_arrayPush(curArrR, val64R)
           emitArrayDeserializeBody(arrNodeR2, elemType, idxR)  // SSoT 抽函数 vs 内联,simplify 拍板
       }
       // ... loop end + final store ...
   }
   ```

   `emitArrayDeserializeBody(arrNodeR, elemType, idxR)` helper:抽出 Array 分支 emit 逻辑成单一函数,允许 emitClassDeserializeFn Array 分支递归调用自身处理内层 Array(SSoT 收敛);若内联 6 路全展开 IR 重则简化 ROI 高 → simplify 抽函数;Execute 轮先跑 simplify reuse agent grep `emitClassDeserializeFn` Array 分支 LOC 现状(a096fd0 ~ 60 LOC)+ 第 6 路新增 ~ 30 LOC,合 ~ 90 LOC 单函数仍可读则不抽;> 100 LOC 抽 helper。

5. **per-class deserializer transitive closure BFS 验**:
   - 内层 Array<UserClass> elemType=UserClass 应入 deserializerTargets(b79aa97 单遍 BFS 已 cover 单层 Array<UserClass>);本子档双层 `Array<Array<UserClass>>` 外层 elemType=`Array<UserClass>`,extractContainerElemType 返 `Array<UserClass>`,需 BFS 在 `Array<UserClass>` 时**继续 unwrap** 拿 UserClass 入队(否则内层 UserClass 不 emit deserialize fn → undefined symbol link error)
   - Execute 轮诊断:grep BFS unwrap 路径(`bootstrap/gen/codegen.ss emitDeserializeClosure` 或 `gen_deserialize.ss collectDeserializerTargets`),若 BFS 仅 unwrap 一层 Array → 补递归 unwrap

6. **simplify 4 agent 复审**:reuse / quality / efficiency / readability(按 [feedback_human_readable_code](../../.claude/projects/-root-code-simplescript-dev-simple-script/memory/feedback_human_readable_code.md) 5 rubric a-e)。重点:
   - reuse:`emitArrayDeserializeBody` helper 抽 vs 内联拍板(LOC 阈值 ~ 100;a096fd0 5 路 ~ 60 LOC + 第 6 路 ~ 30 LOC ≈ 90 LOC,临界值)
   - quality:RC 双层契约严审 — 外层 push 内层 ptr 时是否 retain(对照 a096fd0 string 元素 push 前 retain 模式;内层 Array 是新分配 mimalloc ptr 持新 RC,与 string jnStr 内部 ptr 不同,**不需要 retain**,直接 transfer ownership)
   - efficiency:编译期已固定 6 路分派 elemType,无运行时分支
   - readability:双层 emit 顺序对齐(outer call → inner emit body → outer push),IR 顺序严按 `outer.ss_newArrayPtr → outer.jnArrayLen → outer.loop_head → outer.jnArrayGet(inner_node_id) → inner.ss_newArray|Ptr → inner.jnArrayLen → inner.loop_head → inner.jnArrayGet*(elem) → inner.push → inner.loop_end → outer.push(inner_ptr) → outer.loop_end`

7. **commit + push**:format `feat(I021-requestbody-nested-array-array,D123,D129): Array<Array<X>> 2D 嵌套数组反序列化 + 谓词递归识别 + emitClassDeserializeFn Array 分支递归 + RC 双层契约 — Phase 4 §247 第二支柱嵌套深化第四轮`。

## 反向 / 备选

(同上候选 A 评估表 — B/C/D 否决)

## 验收 RED 命令

- **本轮起立 RED**:`ls docs/4-issues/I021-requestbody-nested-array-array.md 2>&1 | grep -c "No such"` = 1(本轮 Write 后 = 0)
- **Execute 轮 RED before**:见 §步骤 §1 RED 命令(3 条)
- **Execute 轮 after**:`bin/ss test tests/phase5/i021_requestbody_nested_array_array.ss` exit 0,8 case 全绿
- **Execute 轮 after**:parity 端到端 curl POST `/matrix -d '{"name":"m1","grid":[[1,2,3],[4,5,6]],...}'` 返 byte-identical Java oracle(`name=m1,total=21`)
- **Execute 轮 after**:`grep -E "ss_newArrayPtr.*ss_newArray|jnArrayLen" /tmp/t_i021_array_array.ll` ≥ 4(外层 ss_newArrayPtr + 内层 ss_newArray|ss_newArrayPtr + 双层 jnArrayLen × 2)
- **Execute 轮 after**:bootstrap 三阶段固定点 PASS Stage 2 = Stage 3 + reflection_health_linter PASS(predict no F1 regression — gen_deserialize.ss 当前在 baseline 容量内,第 6 路递归分派 ~ 30 LOC 增量;若超 baseline 走反射路径根因 gate B 路径申报扩容)

## 风险 / 表面 / 下轮升根路径

1. **RC 双层契约累积严审**(承接 nested.md line 124-128 + nested-array.md line 163-168 + nested-array-primitive.md line 240-249 父档 / 同级父档 / 祖父档已锚契约):
   - **外层容器**:`ss_newArrayPtr`(tag=5)— 内层 Array 是 ptr 元素;`ss_drop_<Outer>` 链遍历外层 Array 字段 → emit `ss_array_release_with_drop(arr, elem_kind=ptr)` → 内部 tag=5 触发逐内层 ss_release_arr
   - **内层容器**:`ss_newArray`(tag=1)if 内 X primitive int/double/bool;`ss_newArrayPtr`(tag=5)if 内 X 是 string 或 UserClass — 内 X primitive 时内层 release 仅 free 容器(elem_kind 走 primitive 路径,无 elem release);内 X = string/UserClass 时内层 release 触发逐元素 ss_release_str / ss_release(UserClass)
   - **push 前是否 retain**:外层 push 内层 ptr — **不 retain**(内层 Array 是新分配 mimalloc ptr 已持新 RC=1,直接 transfer ownership;对照 a096fd0 string 元素 push 前 retain 是因为 jnStr 内部 ptr 未持新 RC,语义不同;UserClass 元素同模式不 retain — c3361c9 已落地);内层 push 元素若 elemType=string 仍 retain(jnStr 内部 ptr 未持新 RC,与 a096fd0 单层 string elem 同模式)
   - **若契约破裂**(外层 push 时 retain 内层 ptr → 内层 RC=2,外层 drop 后内层 RC=1 leaked;或内层 string elem push 时漏 retain → 内层 drop 时 free jnStr 仍持 ptr → use-after-free)→ Execute 必须严审 `emitRetainForType` 调用条件 + 双层 push 模式分立(外层 transfer / 内层 string elem retain)
   - **drop 链严审**:`ss_drop_<Outer>` 遍历外层 Array 字段路径 → `ss_array_release_with_drop(outer_arr, ptr)` → 内部 tag=5 + elem_kind=ptr → 逐外层元素调 `ss_release_arr(inner_arr, inner_elem_kind)` → 内部 tag={1|5} + inner_elem_kind={int|double|bool|string|user_class} → 内 X primitive 仅 free 容器;内 X = string 触发逐元素 ss_release_str;内 X = UserClass 触发逐元素 ss_release(UserClass);**链路 elem_kind 传递严审**:`emitFieldReleaseLoop` Array<Array<X>> 字段 release 路径 elem_kind 必须传 ptr(外层),内层 release 时 inner_elem_kind 由 inner array struct meta 持有(SS Array 结构必含 elem_kind 字段),**禁止编译期烧死内层 elem_kind 到外层 release call**

2. **`isArrayDeserializable` 谓词递归终止条件**:
   - 谓词扩 `if (isArrayDeserializable(et) == 1) { return 1 }` 后,N=2 时内层 et=`Array<X>`,X ∈ {int/string/double/bool/UserClass} 终止;N=3 时内层 et=`Array<Array<X>>`,递归一次得 X 终止;**N 任意层 N>1 谓词天然递归终止**
   - **本子档 v0 scope 限 N=2** — 谓词递归识别天然支持任意层,但 emit 路径 emitClassDeserializeFn Array 分支第 6 路递归调用自身仅在 simplify 抽函数后才支持 N>2;v0 内联 emit 仅 cover N=2 一层(若直接调用 emitClassDeserializeFn 自身则 v0 已支持 N>2,但 RC 契约 N>2 累积复杂度未严审 → 留 -deep 子档严审)
   - **升根路径**:N>1 任意层数 → `I021-requestbody-nested-deep` 子档承接 BFS

3. **lib/json.ss 内部 Array 表示嵌套 nodeId 链**:
   - lib/json.ss 当前 `jnArrayLen` 接 nodeId 返 length;`jnArrayGet(arrNode, idx)` 接 nodeId 返子 nodeId(子 nodeId 仍可作为 jnArrayLen / jnArrayGet 入参 — 嵌套 nodeId 天然支持任意层数)
   - 双层 array nodeId 链:外层 `jnArrayGet(outerArrNode, i)` 返 inner array nodeId,内层调 `jnArrayLen(inner_array_nodeId)` + `jnArrayGet(inner_array_nodeId, j)` 拿 element nodeId;**内层 Array 走 isArrayDeserializable 路径** — 不调 jnArrayGet*Int/String/Double/Bool 4 raw helper(那 4 raw helper 仅在内层 elem 是 primitive 时调,N=2 内层 X=primitive 时内层 elem nodeId 走 jnInt.getString/jnStr.getString)
   - **lib/json 现状无缺口**:嵌套 nodeId 已支持,本子档不动 lib/json

4. **内层 emit 时 SSA register 命名冲突**:
   - 外层 idxR / outerArrR / outerLenR 与内层 idxR / innerArrR / innerLenR 嵌套
   - 同一 emitClassDeserializeFn 编译器代码侧用 `nextLabel()` / `nextReg()` 自然累加 — `%idx_outer_N` / `%idx_inner_M` 自然不冲突(N / M 是全局自增计数器);**风险点**:若 emit 抽 helper `emitArrayDeserializeBody` 共享 `idxR` 局部变量名 → 外层 / 内层调用 helper 时 helper 内部 `nextReg()` 仍生成不同 reg,无字面冲突;但**调试 IR 可读性**下降(外层 / 内层 idx 区分仅靠数字下标),Execute 轮 emit 命名前缀 `%outer_idx_N` / `%inner_idx_M` 可选(simplify readability 拍板)

**Plan 阶段 plumbing 完整**:本子档 Execute 轮无表面遗留,RC 双层契约严审(外层 transfer / 内层 string retain / 内层 UserClass transfer)+ tag 选择对齐(外层 tag=5 / 内层 tag={1|5} 按内 X primitive vs ptr-bearing)+ 谓词递归识别 + emit 第 6 路递归分派 + transitive closure BFS 内层 UserClass 入队验证 + lib/json 嵌套 nodeId 链天然支持。

## 触发场景

- 接到 enterprise REST API 业务实现含 2D matrix / 表格 / 二维数据字段(`@RequestBody { matrix: Array<Array<int>>, rows: Array<Array<Cell>> }`)
- D129 §94 "@RequestBody | 任意 class(含嵌套 + collection)" 域语义 collection 维度 N=2 双层兑现
- I021-requestbody-nested-array.md line 75 §留下下轮锚 2 + I021-requestbody-nested-array-primitive.md line 108 §留下下轮锚 1 双锚承接(c3361c9 / a096fd0 双父档锚)
- I021-requestbody.md line 116 父档父档显式 backlog 部分承接(本子档处理嵌套 N=2,顶层 `@RequestBody matrix: Array<Array<int>>` 留 I021-requestbody-array 平级独立子档)

## 备注

- 本子档**纯文档起立轮**,Execute 留下下轮(按 §交互式单文档:每轮一目标)
- nested-array-primitive.md line 108 §留下下轮锚 1 + nested-array.md line 75 §留下下轮锚 2 父档 / 同级父档已锚 RC 双层契约 / lib/json 嵌套 nodeId / 留下轮锚配伍,本子档承接
- D123 §247 Phase 4 §第二支柱 V=class 域辨析锁(D129 §5)已 Decided,本子档执行不再辨析
- Phase 4 主流注解清单封顶(I021-requestbody-nested.md line 153 锚),本子档为 Phase 4 §第二支柱嵌套深化第四轮(深化 = collection 维度 N=2 双层;首轮 nested.md = 单层 user class 字段维度 / 第二轮 nested-array.md = 单层 Array<UserClass> elem / 第三轮 nested-array-primitive.md = 单层 Array<primitive> elem / 第四轮本子档 = N=2 双层 Array<Array<X>>)
- 本子档 LOC ~ 250(单子档完整),与同级 nested-array-primitive.md (~ 282) / nested-array.md (~ 200) / nested-deep.md / nested-map.md / nested-optional.md 量级对齐
