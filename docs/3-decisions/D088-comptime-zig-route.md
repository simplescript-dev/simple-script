# D088: Comptime 演进路线 — 走 Zig 路线

**Status:** Accepted
**Depends on:** D087 (comptime Phase 1–4 complete)
**Date:** 2026-04-13

## 第一性需求

**给定一个对象，遍历它的字段名和值。**

toString、toJson、equals、hashCode、copy——全部是同一个需求的不同操作：拿到每个字段的名字和值，然后拼字符串 / 比较 / 算哈希 / 复制。

当前 SS 用 `@derive` + `@comptimeEmit` 字符串拼接为每个类生成专用代码，是因为 SS **没有按名称访问字段值**的能力。这是 workaround，不是解决方案。

## 决策

**实现结构化字段访问：`obj.fields()` + `obj[name]`。**

```ss
for (name in obj.fields()) {
    println(name + "=" + obj[name])
}
```

有了这个，一个通用函数就能处理所有类。不需要 per-class 代码生成，不需要 @derive（@derive 降为可选便捷层）。

### 借鉴来源

| 维度 | 借鉴 | 来源语言 |
|------|------|---------|
| 用户语法 | `Object.keys(obj)` + `obj[key]` | TypeScript/JavaScript |
| 迭代模型 | `fieldPairs(obj)` — 编译器内置，普通 for 循环 | Nim |
| 实现策略 | 编译期展开，零运行时开销 | Zig |

### 编译器行为

1. `obj.fields()` — 编译器内置方法，返回字段名列表，编译期已知
2. `obj[name]` — `name` 是编译期常量时，编译器解析 `obj["x"]` 为 `obj.x` 静态字段访问
3. for-in 迭代目标是编译期常量数组 → 编译器自动展开循环

展开后等价于手写代码：
```ss
// 用户写的：
for (name in point.fields()) {
    parts = parts + name + "=" + point[name]
}

// 编译器展开为：
parts = parts + "x" + "=" + point.x
parts = parts + "y" + "=" + point.y
```

### 设计原则检查

| SS 设计原则 | 检查结果 |
|------------|---------|
| Java/TS 优先 | TS 原生写法 `Object.keys(obj)` + `obj[key]` — 一一对应 |
| 不加新关键字 | `fields()` 是方法，`obj[name]` 是已有索引语法，for-in 已有 |
| 不自创语法 | 每个元素在 TS/JS 中都有直接对应物 |
| 编译器吸收复杂度 | 用户写普通 for 循环，编译器自动展开 |

## 背景：为什么做这个决策

### Zig 的根

Zig comptime 的所有能力源自一个架构决策：**编译器即解释器，类型是一等值。**

```
源码 → SEMA（= 完整 Zig 解释器 + 类型检查）→ 机器码
```

SS 当前是"独立解释器 + 字符串 mixin"：

```
源码 → Lexer → Parser → Checker → PIR → Codegen
                           ↓
                    interp.ss（SS 子集解释器）
                           ↓
                    @comptimeEmit(字符串) → 重新 parse → 注入 AST
```

### 根上的差距

1. **解释器覆盖度** — Zig 解释器 = 完整语言，SS interp.ss = 子集
2. **类型不是一等值** — SS 类型是字符串名称，不能传参/返回/操作

### 路线选型

**不走 D/Rust 路线**（继续堆 ct* 辅助函数 + @derive handler + 反射 API）。技术债线性增长，永远追不上 Zig。

**走 Zig 路线**：解决第一性需求（`obj.fields()` + `obj[name]`），然后逐步增强解释器覆盖度和类型系统。

## 方案对标

研究了 13 种语言的结构化字段访问方案，分三类：

### 编译期零开销

| 语言 | 机制 | 语法 |
|------|------|------|
| Zig | `@typeInfo` + `@field` + `inline for` | `@field(self, f.name)` |
| D | `__traits` + `static foreach` | `__traits(getMember, val, name)` |
| Nim | `fieldPairs` 内置迭代器 | `for name, val in fieldPairs(obj)` |
| Crystal | `@type.instance_vars` 宏 | `{% for ivar in @type.instance_vars %}` |

### 运行时反射

| 语言 | 机制 | 开销 |
|------|------|------|
| Java | `Field.get(obj)` | 2-10x |
| Go | `reflect.ValueOf` | 5-10x |
| Swift | `Mirror` | 低-中 |
| TS/JS | `Object.entries(obj)` | 极低（动态语言天然支持） |

### 编译期代码生成（SS 当前属于此类）

| 语言 | 机制 |
|------|------|
| Rust | proc_macro derive |
| C# | Roslyn Source Generator |
| SS (当前) | @derive + @comptimeEmit 字符串拼接 |

**SS 从第三类（代码生成）升级到第一类（编译期零开销）。**

## 实施路线图

优先级按第一性需求排列。`obj.fields()` + `obj[name]` 是第一优先级，其他是支撑。

### Phase 5: `obj.fields()` + `obj[name]` + 编译期循环展开

**Status:** [x] Done — 三件事均落地，验证方法代码块可直接编译运行。

**目标：** 解决第一性需求。运行时函数内可遍历对象字段并按名访问值。

**需要实现的三件事：**

1. **`obj.fields()`** — 编译器为每个 class 自动生成 `fields()` 内置方法，返回字段名数组（编译期常量）
   - **[x] Done at** `bootstrap/gen_methods.ss:467`（runtime emit）/ `bootstrap/gen_types.ss:359`（inferType 返回 `Array<string>`）/ `bootstrap/gen_exprs.ss:872`（METHOD_CALL 分发）/ `bootstrap/check_stmts.ss:482`（checker 合法化）
   - commits：`5a11642`（初次落地）/ `a5f434e`（comptime p.fields() 对称 + method-not-found 强化）

2. **`obj[name]` bracket notation** — 当 `name` 是编译期常量字符串时，`obj["x"]` 在 codegen 阶段解析为 `obj.x` 的 GEP 指令（零运行时开销）
   - **[x] Done at** `bootstrap/gen_exprs.ss:55`（INDEX_ACCESS codegen 折叠）/ `bootstrap/gen_stmts.ss:280`（INDEX_WRITE codegen 折叠）/ `bootstrap/gen_types.ss:441`（inferType）/ `bootstrap/check_stmts.ss:832`（checker 拦截 class 实例非编译期常量字段名）/ `bootstrap/codegen.ss:79`（`comptimeConsts` 常量绑定表）
   - commits：`5a11642`（初次落地）/ `f6dad10`（checker 拦截动态字段名）

3. **for-in 编译期展开** — 当 for-in 的迭代目标是编译期常量数组时，编译器展开循环，每次迭代的循环变量替换为常量
   - **[x] Done at** `bootstrap/gen_stmts.ss:586`（`genForInUnrolled` 展开核心）/ `bootstrap/gen_stmts.ss:666`（`obj.fields()` 展开入口）/ `bootstrap/gen_stmts.ss:677`（字符串字面量数组展开入口）
   - commits：`5a11642`（初次落地 `obj.fields()` 入口）/ `02f745d`（泛化到字符串字面量数组）

**验证方法：**
```ss
class Point { x: int; y: int }

function toString(p: Point): string {
    let parts = ""
    for (name in p.fields()) {
        if (parts != "") { parts = parts + ", " }
        parts = parts + name + "=" + p[name]
    }
    return "Point(" + parts + ")"
}

function main() {
    const p = new Point(x: 10, y: 20)
    assertEqual(toString(p), "Point(x=10, y=20)")
}
```

**通过标准：** 编译通过，运行输出 `Point(x=10, y=20)`，生成的 LLVM IR 中无循环（已展开为逐字段访问）。

### Phase 6: 解释器支持 class

**目标：** comptime 块内可定义 class、实例化对象、访问字段、调用方法。

**实现要点：**
- interp.ss 支持 CLASS_DECL → 注册 class
- interp.ss 支持 NEW_EXPR → 创建 object 值
- interp.ss 支持 MEMBER_ACCESS / MEMBER_ASSIGN → 字段读写
- interp.ss 支持 METHOD_CALL on object → 方法调用
- 不需要 RC/PIR — comptime 对象由解释器管理

**验证：** `comptime { class Foo { x: int }; const f = new Foo(x: 42); return f.x }` → 42

### Phase 7: 解释器支持 enum + try/catch + 闭包

**目标：** 补齐常用语言特性，comptime 覆盖日常 SS 代码。

**验证：** `comptime { try { throw("err") } catch(e) { return e } }` → "err"

### Phase 8: 解释器 = 完整语言（路线修正）

> **2026-04-13 路线修正：** 原 Phase 8（comptime 参数 `@comptime`）和 Phase 9（类型作为值）暂缓。
> 原因：这两个是 Zig 的具体语法特性，不是 Zig 路线的本质。SS 已有泛型（`Array<T>`），
> 不需要用 comptime 参数当泛型用。抄手段不等于走路线。
>
> **Zig 路线的本质是：编译器即解释器，解释器 = 完整语言。**
> 任何 SS 代码都能在 `comptime {}` 里跑。每补一个解释器缺口，comptime 就能做更多事。

> **2026-04-15 实现路径修正(D093)**: 上述"补解释器缺口"在实现层的具体做法,经 D092 "半 SEMA + 填洞即合并" 尝试后证明不可达—— D092 实现层退化为"双轨 dispatch + 手工同步",详见 `docs/3-decisions/D092-sema-architecture.md` §不可靠性声明。实现路径修正为 D093 "SEMA 单函数 dispatch":一个 `evalExpr` 函数 + `?Value`(SS 里 `MaybeVal`)二元返回,comptime 与 runtime 共享同一求值路径,comptime 块只是 `comptimeMustBeKnown` flag。
>
> **Phase 8 的目标(新语法在 comptime 跑)保持有效**,但实现路径由 D093 承接;下方表格中的特性(ENUM_DECL / destructuring / spread / super)在 D093 骨架就位后按**新路径**补回,不按 D092 的 `interp*` 家族路径。

**目标：** 补齐解释器缺失的 SS 语言特性，使 `comptime {}` 能执行任意 SS 代码。

**当前解释器缺失清单：**

| 缺失特性 | 编译器对应 | 影响 | 状态 |
|----------|-----------|------|------|
| ENUM_DECL | gen_stmts.ss registerEnum | comptime 里不能定义/使用 enum | [-] Blocked at d1816ab, superseded by D092 |
| destructuring (array) | genDestructureArray | `let [a, b] = arr` 不能用 | [-] Blocked at d1816ab, superseded by D092 |
| destructuring (object) | genDestructureObject | `let {x, y} = obj` 不能用 | [-] Blocked at d1816ab, superseded by D092 |
| spread (array literal) | genValCtArrayLit | `[...a, x]` 在 comptime 里不能用 | [-] Blocked at d1816ab, superseded by D092 |
| spread (call args) | genValCtCall | `f(...a)` 在 comptime 里不能用 | [-] Blocked at d1816ab, superseded by D092 |
| super | genSuperCall | 继承方法调用不能用 | [-] Blocked at d1816ab, superseded by D092 |

> **状态回写说明（D092 本轮）**：上述 ✅ 标签对应的实现位于 d1816ab 已删的 `bootstrap/interp.ss` / `bootstrap/gen_reflect.ss` / `bootstrap/gen_annotations.ss`，D 文档标签与代码现状漂移。按 `docs/2-principles.md` §P19 + §PFV 字段 1 D 文档 grep 对照规则，回写为 Blocked。语言特性（ENUM_DECL / destructuring / spread / super）本身仍是 Phase 8 待办，但实现位置从 `interp.ss` 迁到 `genExpr` dispatcher 的 comptime case，详见 `docs/3-decisions/D092-sema-architecture.md`。

> **未知 expression 不再静默断流（本轮）**：原先 `genVal` 遇到未实现的 comptime expression 会 `println` 后返回 `null` 续跑，导致编译"成功"但生成的二进制行为错误。改为 `exit(1)` + 行列号，强制暴露缺口。
>
> **位运算赋值不属于本清单**：经核查，`&=` `|=` `^=` `<<=` `>>=` 在 lexer / parser 阶段就不存在（bootstrap 全代码库无引用），不是解释器缺口，不在 Phase 8 范围。补它要从 lexer 加 token 起，单独立项。

**验证方法：** 每轮完成后，写一段使用该特性的 SS 代码放进 `comptime {}`，确认能跑。

```ss
// 例：enum 支持完成后，这段必须能工作
comptime {
    enum Color { Red = 1, Green = 2, Blue = 3 }
    const names = Color.names()
    // names == ["Red", "Green", "Blue"]
}
```

**完成标准：** 上述所有缺失特性在 `comptime {}` 中可用。

### 原 Phase 8/9（暂缓，等有真实场景再推进）

- **comptime 参数特化** — `function foo(const n: int, s: string)` 编译期求值。SS 已有泛型，当前无驱动场景。
- **类型作为 comptime 值** — `comptime { return Pair(int, string) }`。复杂度高，等解释器完整后再评估。

### 各 Phase 解锁的能力

| 能力 | 当前 | Ph5 | Ph6 | Ph7 | Ph8 |
|------|------|-----|-----|-----|-----|
| **obj.fields()** | ❌ | ✅ | | | |
| **obj[name] bracket READ/WRITE** | ❌ | ✅ | | | |
| **for-in 编译期展开** | ❌ | ✅ | | | |
| comptime class 实例化 | ❌ | | ✅ | | |
| comptime try-catch/闭包 | ❌ | | | ✅ | |
| comptime enum | ❌ | | | | ✅ |
| comptime destructuring | ❌ | | | | ✅ |
| comptime spread (array lit) | ❌ | | | | ✅ |
| comptime super | ❌ | | | | ✅ |
| comptime 块 | ✅ | | | | |
| comptime 表达式 | ✅ | | | | |
| @derive 注解 | ✅ | | | | |
| @typeInfo / 类型发现 | ✅ | | | | |
| 文件 I/O / Shell | ✅ | | | | |
| 条件编译 | ✅ | | | | |
| 字符串 mixin | ✅ | | | | |

## 过渡策略

1. **@derive 保留为便捷层** — `@derive("ToString")` 继续可用。Phase 5 完成后，@derive handler 内部实现可改用 fields() + bracket notation，但用户接口不变
2. **@comptimeEmit 保留但冻结** — 已有的字符串 mixin 继续工作，不再扩展
3. **ct* 辅助函数冻结** — ctMap/ctZip/ctRange 等保留，不再新增
4. **渐进替换** — Phase 5 完成后，新功能优先用 fields() + obj[name] 实现

## 不做的事

- 不实现运行时反射（Java/Go 模式）— SS 是编译型语言，编译期展开零开销
- 不加 `inline` 关键字 — 编译器自动检测编译期常量迭代目标并展开
- 不加 `@field` 内建函数 — 用 TS 风格 bracket notation `obj[name]`
- 不照搬 Zig/D/Nim 语法 — 用 TS/Java 风格表达
- 不取消现有泛型语法 — `Array<T>` 保留
- 不限制 comptime I/O — readFile/shellOutput 是 SS 优势，保留

## 验证标准（每轮必检）

### 核心验证（最重要的三条）

> **(1) 这轮完成后，有新的 SS 语法能在 `comptime {}` 里跑了吗？**
> - 是 → 在路线上。
> - 不是 → **偏了。停下来重新审视方向。**
>
> **(2) 这轮是从根儿上走 Zig 路线吗？不是假装解决，不是从表面解决？**
> - 对 §反模式 双轨制两问必须清零：(a) 这是双轨制（codegen / interp.ss 两份 SS 实现）根因吗？(b) 本轮补丁会维持双轨制吗？
> - 两问任一为"是" → **表面解决。** 禁止纳入本轮清单，必须先给出非补丁路径（共享层抽取 / 统一 SEMA / 合并 pipeline）再启动。
> - 两问都为"否" → 根路径，继续。
> - Zig 路线的本质是"编译器即解释器，一份实现"。每给 interp.ss 抄一个 codegen 已有的 handler，都是在加深双轨制，而不是在走向 Zig。"逐步补解释器覆盖度"必须同时回答"怎么走向合并"，否则就是假装走 Zig。
>
> **(3) 这轮是 Zig 式 SEMA 架构吗？**
> - "Zig 式 SEMA" 定义：**一份 eval 函数**同时做 comptime 执行 + 类型检查 + codegen 前端。pipeline 是 **AST → TypedValue → LLVM IR**，TypedValue 既是 comptime 值也是 codegen 输入，**不存在独立的 interp / compile-time eval engine / typeInfo API / 字符串 mixin**。
> - 本轮检验：(a) 产出的代码是否消费或产生 TypedValue？(b) 同一 eval 路径是否同时服务 comptime 和 codegen？(c) 有没有写任何"comptime 专用"的独立分支 / 独立文件 / 独立注册表？
> - 任何"comptime 专用"独立路径 → 即使不叫 interp.ss，也是**新名字的第二份执行器**，禁止纳入本轮清单。
> - 和问 2 配套：问 2 防"继续给 interp.ss 补 handler"，问 3 防"换个名字另起炉灶写独立 eval 路径"。两个入口堵死，才能逼出真正的 SEMA 合并架构。
>
> **2026-04-15 现状注记(按 P19 回写)**: Q3 的定义"不存在独立 interp / compile-time eval engine / typeInfo API"是**目标状态**,不是**当前状态**。2026-04-15 对 `bootstrap/` grep 发现:
> - **40 处** `if (comptimeDepth > 0)` 分岔横跨 5 文件(gen_exprs.ss:18 / gen_stmts.ss:15 / gen_decls.ss:4 / gen_assigns.ss:2 / codegen.ss:1)
> - **7 个** `genValCt*` 函数(`genValCtCall` / `NewExpr` / `MemberAccess` / `MethodCall` / `TemplateLit` / `ArrayLit` / `IndexAccess`)是独立的第二份 dispatch 表
> - **`TypedValue` storage**(`tvKind` / `tvI1` / `tvS1` / `tvD1` / `tvList` / `tvMap`)是 Kind-tagged Value 混存层,未达成 Zig Value 的无类型语义
>
> 即 Q3 断言与代码现状**相反**。Q3 的 (a)(b)(c) 三问在代码现状下答案全为"否",作为 **[ ] Planned** 目标保留。路径修正见 `docs/3-decisions/D093-sema-single-dispatch.md` "SEMA 单函数 dispatch — Zig 本质一样路径"。

这三条规则能过滤掉所有偏离：打磨 @derive 过不了 (1)（没让新语法在 comptime 工作），
抄 Zig 语法特性也过不了 (1)（添加的是编译期语法，不是解释器覆盖度）；
给 interp.ss 直接补 class / enum / method handler 过不了 (2)（维持双轨制，是表面 — 必须先设计共享层）；
另起炉灶写一个 compile-time eval engine / 独立的 const-folder 也过不了 (3)（新名字的双轨制，架构不是 SEMA）。

### 方向性检查（开始前）

1. **这轮在补解释器的缺口吗？**（enum / destructuring / super / spread / 其他缺失语法）
   - 是 → 继续
   - 不是 → 在解决第一性需求吗？（fields() + obj[name] + 循环展开）
   - 都不是 → **停。偏了。**

2. **是在打磨 @derive / 便捷层 / 过渡方案吗？**
   - 是 → **不做。** 便捷层不是主线。

3. **是在加 ct* 辅助函数吗？**
   - 是 → **不做。** ct* 已冻结。

### 实现检查（完成后）

4. **写一段用到新特性的 SS 代码放进 `comptime {}`，能跑吗？**
   - 能 → 符合方向
   - 不能 → 没有真正缩小差距

5. **新代码是拼字符串还是操作值？**
   - 拼字符串 → 过渡方案，标记为技术债
   - 操作值 → 符合方向

### 反模式（出现即偏离）

- ❌ 新增 ct* 辅助函数
- ❌ 新增 @derive handler 用字符串拼接实现
- ❌ 增强 @comptimeEmit
- ❌ 给字符串模板加新占位符
- ❌ 在 lib/comptime.ss 中加大量新函数
- ❌ 打磨 @derive 便捷层（已够用，不是主线）
- ❌ 抄 Zig 的具体语法特性而不是架构本质
- ❌ 见症状直接打补丁，未先问「双轨制（codegen / interp 两份实现）是否是根因」。每个识别为"缺口/待办"的项必须答两问：(a) 这是双轨制根因吗？(b) 补丁会维持双轨制吗？两问都"是" → **表面解决**，必须先给非补丁路径才能纳入清单
- ❌ 把 Phase 8（解释器补缺口）当成 Phase 5（核心目标 fields()/bracket/循环展开）的前置。Phase 5 是 codegen 阶段事，不依赖任何 comptime 解释器覆盖度。先做 Phase 5

### 正模式（应该做的事）

- ✅ 补解释器缺失的 SS 语言特性（enum / destructuring / super / spread）
- ✅ 让更多 SS 代码能在 comptime {} 中执行
- ✅ 用户用普通 SS 写法搞定编译期任务
- ✅ 减少"这段代码在 comptime 里跑不了"的场景

## 参考

- Zig comptime: https://ziglang.org/documentation/master/#comptime
- Nim fieldPairs: https://nim-lang.org/docs/iterators.html
- D 语言 CTFE: https://dlang.org/ctfe.html
- Rust proc-macro: https://doc.rust-lang.org/reference/procedural-macros.html
- D087 决策文档: docs/3-decisions/D087-comptime.md
