# I038 — inferArrayElemType 覆盖不全致 scalar 数组 join 经 fallback 段错(边缘残留)

**父决策:** D171 §下一步 finding A(runtime scalar 数组 .join 段错)修复轮 `/simplify` altitude agent 复查发现的残留入口。finding A 修了 IDENT 字面量/标注主路径,但 `inferArrayElemType` 对若干表达式形态推断不出元素类型 → join 分派 fallback `ss_join`(当 string)→ 若实为 scalar 数组**段错复活**。
**状态:** **[ ] Planned**(backlog;非阻挡 finding A 核心 RED `let a=[1,2,3]; a.join()` — 该主路径已彻底修)。
**颗粒度:** 预估标准改~大改(inferArrayElemType METHOD_CALL 分支扩 + 函数返回类型推断衔接;map/flatMap 元素类型 = callback 返回类型推断,非 trivial)。
**依赖:** 无硬依赖;与 finding A 修复(gen_methods join 分派 + gen_types ARRAY_LIT 分支)同族。
**创建:** 2026-05-29
**立项由:** `findingA_scalar_join` 轮 `/simplify` altitude agent 复查 —— 指认 fallback `jfn="ss_join"`(elemType="")的危险残留面。
**编号溯源:** 原编号 **I034**,因与 comparison/logical→bool 修复(已 Done,canonical = `I034-comparison-logical-bool.md`)撞号,2026-05-30 经 `I037` 改号为 **I038**(取当时 top+1)。本 issue 引用面小(自身 + `I035` back-ref),按 I037 §推荐「代价反转」判据迁号。

---

## 现象(altitude agent 分析,精确残留入口)

finding A 修复后,`inferArrayElemType` 推断失败(返回 "")的 scalar 数组,join 分派 fallback `ss_join`(按 string 拼接)→ scalar 元素位值当 `String*` 解引用段错:

1. **方法链 `arr.map(fn).join("-")`** — `inferArrayElemType` METHOD_CALL 分支(`gen_types.ss:136-141`)只覆盖 `split`(返 string)/`filter`/`slice`/`reverse`/`sort`(递归源元素类型),**缺 `map`/`flatMap`/`concat`/`keys`/`values`**。map 返回 Array<callback 结果类型>,若结果是 int → elemType="" → fallback ss_join → 段错。
2. **未注册返回类型的函数调用 `let a = someFunc(); a.join()`** — someFunc 返回 Array<int> 但返回类型未注册到 varTypes → getVarType("a")="" → elemType="" → fallback → 段错。
3. **嵌套数组 `[[1],[2]].join("-")`** — ARRAY_LIT 首元素是 ARRAY_LIT,`inferType` 返 "ptr" → 不匹配 int/double/bool → fallback ss_join → 元素是数组头 ptr,解引用段错(嵌套 join 语义本身亦待定)。

注:这些场景在 finding A 修复**前**同样段错(彼时所有 scalar join 段错);finding A 修了可推断的主路径(IDENT 字面量/显式标注),缩小了段错面,残留是 `inferArrayElemType` 覆盖完整性的独立局限。

## 根因

`inferArrayElemType`(`gen_types.ss:126`)对数组表达式形态的覆盖不全:METHOD_CALL 分支白名单式只列部分方法、无函数返回类型衔接、嵌套数组元素类型未递归。join 分派的 fallback `ss_join`(默认 string)对推断失败的 scalar 数组不安全。**这是元素类型推断系统的覆盖问题,影响面不限 join**(任何依赖 inferArrayElemType 的 codegen 路径——如 `a[i]` 元素访问类型——都受同一局限)。

## 候选路径(待 Execute 轮 PSM §字段 10 展开)

- **接口层(推荐)**:扩 `inferArrayElemType` METHOD_CALL 覆盖 `concat`(同 filter 递归源)+ 衔接函数返回类型(callReturnType → extractContainerElemType)。`map`/`flatMap` 需推断 callback(arrow/fn)返回类型,较深,分子步。
- **fallback 安全化**:elemType="" 且 objType 非明确 string 容器时,改 loud 编译错(而非静默段错)—— 牺牲部分合法 string 推断失败场景,需权衡。

## 为何独立(不混入 finding A)

finding A 根因 = join codegen **错置** genStringMethod(R1)+ ARRAY_LIT 元素推断缺失(R1b),已彻底修(RED `let a=[1,2,3]; a.join()` + 回归测试 11 assert 全 GREEN)。本 issue = `inferArrayElemType` **覆盖完整性**(不同 root cause,影响面广于 join),且 map 元素类型推断复杂。MNK §衍生 issue 归档:非阻挡核心 RED → 立项不混入。
