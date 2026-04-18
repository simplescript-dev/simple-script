# D096: Class Accessors (get/set) — 响应式底层原语

**Status:** Phase 1 ✓ / Phase 2 ✓ / Phase 3 ✓(lib/reactive.ss + d096_reactive.ss PoC 通过)/ Phase 4 L1 ✓(comptime 块内 class 可在 runtime 实例化,双轨消除)/ Phase 4 L2α ✓(TypeValue 在 comptime 支持 .name/.fields/.fields(),顶层 user class 名可作 TypeValue 传递)/ Phase 4 L2β ✓(函数体内 `const W = comptime { class...; return W }` 被 checker/codegen 识别,预扫描提前注册 class 元数据避免 LLVM forward-ref)/ Phase 4 L2γ ✓(泛型函数 `f<T>` 内 T 在 comptime 作 TypeValue,monomorphize 时 genericTypeSubs[T]=Foo 绑定穿透 scope,T.name/T.fields 可用)/ Phase 4 L2δ ✓(`const R = comptime { return T }` + `new R(x:5)` 过 checker,checkerDeferredAliases 登记 type-param-dependent alias 把字段校验下放给 specialization)/ Phase 4 L2ε ✓(类型位置 `${expr}` comptime 插值,`v: ${f.type}` 编码为 `ct:<exprId>` 在 FUNC_DECL 绑定时求值;Lombok @Setter 去掉 `v: int` 硬编码,支持任意字段类型)/ Phase 4 L2ζ ✓(FieldMeta.annotations 反射,`for (a in f.annotations)` 在 @methodOf handler 里 unroll 为每条注解名字符串,`classFieldAnnotations` 全局 Map 在 registerClass 时抽 PARAM.list → ANNOTATION_LIST 存 CSV)/ Phase 4 L2η ✓(annotation 的 string 字面量 args 反射,`for (v in a.args)` 在 @methodOf 内嵌 unroll;`classFieldAnnotationArgs` 键 `Cls.field.Ann` 存 STRING_LIT arg CSV,非 string arg 自动丢弃;`.annotations` unroll 增 `${a}.__annCls/__annFld` sidecar 绑定供内层查表)/ Phase 4 L2θ ✓(class 级注解反射,`for (a in cls.annotations)` 在 @methodOf handler 内 unroll 类头部注解名,含 handler 自身;`classAnnotations`/`classAnnotationArgs` 两 Map 在 registerClass handler dispatch 同址抽取;`.args` unroll 通过 `__CLASS__` sentinel 分派 class-level vs field-level Args Map)/ Phase 4 L2ι+ 未启动
**Depends on:** D088 (Zig comptime 路线 — 字段反射), D095 (Annotation Handler API)
**Date:** 2026-04-18
**Last Updated:** 2026-04-18 (L2θ)

---

## 第一性需求

**让用户能用 stdlib 方便、强大、灵活、简洁地实现 Vue 3 `ref()` / `reactive()` / `computed()` / `watch()` 等响应式 API**。

响应式的核心机制 = 字段读写拦截（读时 `track` 当前 effect，写时 `trigger` 订阅的 effect 重跑）。SS 是静态编译语言,没有运行时 Proxy / defineProperty——拦截必须在**编译期**把 `obj.field` 的 member access 重写为 method call。

当前 SS class 的字段访问直接编译为 `getelementptr` + `load`/`store`，**没有任何拦截点**。用户想实现 `ref.value` 的读写通知、实现 `reactive(obj)` 对对象字段的 get/set 包装，都做不到——没有语言原语。

如果不落这个原语:
- 用户写不出 `class Ref<T> { _v: T; get value()/set value() }` —— ref 这个最基础的响应式容器都造不出来
- `@Getter`/`@Setter`（D095）只能生成 `get_x()`/`set_x()` 方法, 用户必须写 `p.get_x()` 丑语法,无法做到 `p.x` 自动触发拦截
- 任何"字段访问有副作用"模式（响应式、懒加载、依赖注入、脏标记、变更通知）都无从在 stdlib 层实现——要么改编译器 per-pattern 加 hack,要么用户放弃 SS

## 决策

**在 class body 引入 TS 风格的 `get NAME(): T { ... }` / `set NAME(v: T) { ... }` 访问器语法**。编译期把 `obj.NAME` / `obj.NAME = v` 分别重写为 `ClassName_get_NAME(obj)` / `ClassName_set_NAME(obj, v)` 方法调用。

### 用户侧语法

```ss
class Ref<T> {
    _v: T
    new(init: T) { this._v = init }
    get value(): T { track(this, "value"); return this._v }
    set value(v: T) { this._v = v; trigger(this, "value") }
}

const r = new Ref<int>(0)
println(r.value)    // 编译为 call @Ref_get_value(r)
r.value = 42        // 编译为 call @Ref_set_value(r, 42)
```

### 借鉴来源

| 维度 | 借鉴 | 来源 |
|------|------|------|
| 语法 | `get x()/set x(v)` 在 class body 做 identifier-前缀 | TS / JS class |
| 底层 | 编译期把 member access 重写为方法调用 | C# property / Swift computed property / 编译期版 Object.defineProperty |
| 排除 | `field` 关键字做隐式 backing storage | Kotlin 风格,被项目规则排斥 |
| 排除 | 运行时 Proxy / `__get__/__set__` | 静态编译不支持,违反零运行时开销 |

### 影子字段约定

TS 路线（`get x()` 和 `x: T` 同名会冲突）要求用户手写影子字段 `_x`。SS 沿用：

```ss
class Counter {
    _count: int = 0                           // 真字段
    get count(): int { return this._count }   // 访问器,不分配存储
    set count(v: int) { this._count = v }
}
```

用户也可以只写 getter 做只读属性，setter 同理。

### 响应式应用：stdlib 蓝图

```ss
// lib/reactive.ss
let activeEffect: fn() | null = null
let depsMap = Map()

function effect(fn: fn()) { activeEffect = fn; fn(); activeEffect = null }
function track(obj: any, key: string) { ... }
function trigger(obj: any, key: string) { ... }

class Ref<T> {
    _v: T
    new(init: T) { this._v = init }
    get value(): T { track(this, "value"); return this._v }
    set value(v: T) { this._v = v; trigger(this, "value") }
}
function ref<T>(v: T): Ref<T> { return new Ref<T>(v) }

// reactive(obj) — Zig 风格 comptime 泛型生成 wrapper(依赖 D088 Phase 5 + Zig 路线 comptime 类型作为值)
comptime function Reactive<T>(): type {
    class Wrap {
        _inner: T
        new(v: T) { this._inner = v }
        comptime for (f in T.fields) {
            get [`${f.name}`](): f.type { track(this, f.name); return this._inner[f.name] }
            set [`${f.name}`](v: f.type) { this._inner[f.name] = v; trigger(this, f.name) }
        }
    }
    return Wrap
}
function reactive<T>(v: T): Reactive<T>() { return new Reactive<T>()(v) }
```

用户侧和 Vue 3 字面一致:

```ss
const count = ref(0)
effect(() => println(count.value))
count.value = 1                         // 触发

import { Counter } from "third-party"   // 第三方类无需改
const r = reactive(new Counter())
effect(() => println(r.count))
r.count = 1                              // 触发
```

### 放弃的写法

**不做 `@Reactive class { x: int }` annotation 声明式写法**。理由:
- 增加心智负担:用户要记住"加了 @Reactive 的类字段才响应"
- 第三方类不能改,annotation 无法应用
- `reactive(x)` 函数形式已能覆盖所有场景,且对第一方/第三方类写法一致

### 设计原则检查

| SS 设计原则 | 检查结果 |
|------------|---------|
| Java/TS 优先 | ✓ TS class `get x()/set x(v)` 一一对应 |
| 不加新关键字 | ✓ `get`/`set` 保持 identifier(class body 内上下文敏感) |
| 不借鉴 Kotlin | ✓ 不引入 `field` 关键字,要求显式影子 `_x` |
| 编译器吸收复杂度 | ✓ `obj.field` / `obj.field = v` 用户侧语法不变,重写发生在 codegen |
| Root Cause 优先 | ✓ 不用 workaround(运行时 dispatch / 字段命名约定)绕过,直接加访问器原语 |

## 背景:为什么做这个决策

### 调研:各家响应式机制和 SS 适配性

| 机制 | 代表 | 实现层 | 运行时开销 | SS 能用? |
|---|---|---|---|---|
| `Object.defineProperty` | Vue 2 / MobX 旧版 | 运行时改属性描述符 | 实例化循环 + 访问 dispatch | ✗ SS struct 布局固定 |
| `Proxy` 对象 | Vue 3 / MobX 6 | 运行时对象代理 | 每次访问 trap | ✗ SS 访问直接 GEP+load |
| **class get/set 语法** | **C# / TS / Swift** | **编译期重写 member access** | **一次方法调用** | **✓ 完全适配** |
| `__get__`/`__set__` | Python / PHP | 运行时类级 dispatch | 方法调用 + string key 查找 | ✗ 违反静态类型 |
| 编译器 inline 重写 | Svelte 5 Runes | 编译期识别标记改 AST | 0 | ✓ 但需 get/set 打底 |
| ObjC dynamic dispatch | ObjC / Ruby | runtime | 高 | ✗ 重 |

**结论:class get/set 语法是静态编译语言的唯一合理选择**。它本质是"把 Vue 2 defineProperty 从运行时提到编译期"——编译期生成 `ClassName_get_field` 函数,所有 `.field` 访问静态重写为该函数调用。

### Vue 3 `reactive(obj)` 对第三方类的处理

Vue 3 靠 Proxy 运行时对**任意**对象套壳。SS 走不了这条。替代方案:

- `reactive<T>(v: T)` 是 **comptime 泛型函数**,编译期根据 T 的字段清单(D088 Phase 5 `T.fields`)生成具体化的 `Reactive_T` wrapper 类
- 用户侧用法与 Vue 3 一致:`const r = reactive(thirdPartyObj)`
- wrapper 类内部全是 get/set 访问器 → **需要本 D096 的机制**

即:机制 3(本决策)是 `reactive()` 实现的底层零件;`reactive()` 本身依赖 D088/D094 的 comptime 类型反射。

### 为什么不做 `@Reactive` 声明式写法

最初讨论时考虑过 `@Reactive class X { count: int }` + handler 扫字段自动生成 get/set。**被用户否决**,理由:
1. 增加心智负担——用户要记住哪个类"是响应式的"
2. 第三方类不可改,annotation 无法应用——打破范式统一
3. `reactive(obj)` 函数形式对第一方/第三方类一视同仁,心智更简洁

`@Reactive` 不写,`reactive()` 就是唯一入口,范式统一。

## 实施路线图

### Phase 1: Parser + AST — 解析 `get/set` 语法

**目标:** class body 能解析 `get NAME(): T { body }` / `set NAME(v: T) { body }`,生成 FUNC_DECL 节点,I2 slot 标记访问器类型。

**AST 约定(FUNC_DECL I2 slot)**:

| I2 值 | 含义 |
|---|---|
| 0 | regular function (默认) |
| 1 | class static method |
| 2 | class getter accessor |
| 3 | class setter accessor |

**改动点:**
- `bootstrap/parser.ss` parseClassDecl body 循环: 检测 `get`/`set` identifier + lookahead(下一个是 IDENT + LPAREN),是则标记 `isAccessor=2/3`,走 `parseAccessorDecl()`(新增,类似 parseFuncDecl 但不 expect FUNCTION token)
- `parseAccessorDecl()`: 手动 parse NAME + `(params)` + `: retType?` + `{ body }`,生成 FUNC_DECL,写入 I2 accessor 标记
- getter 必须 0 参数,setter 必须 1 参数(校验在 checker)

**RED 证据:**
```bash
cat > /tmp/d096_red.ss <<'EOF'
class Counter {
    _v: int = 0
    get value(): int { return this._v }
}
EOF
bin/ss run /tmp/d096_red.ss 2>&1 | grep "expected FUNCTION"
# → parse error at line 3: expected FUNCTION, found IDENT 'get'
```

**GREEN:** 同一代码编译通过(Phase 2 落地后运行正确)。

### Phase 2: Register + Codegen — 生成访问器函数 + 重写字段访问

**目标:**
1. class 注册时扫描 accessor,填 `classAccessorGetters[ClassName.field]` / `classAccessorSetters[ClassName.field]` 表,注册 funcRetTypes
2. getter/setter 像普通方法一样 codegen(发射 `@ClassName_get_NAME` / `@ClassName_set_NAME` 函数)
3. MEMBER_ACCESS 在 codegen / checker 检测到 accessor 时,发射 `call ClassName_get_NAME(obj)` 而非 GEP+load
4. ASSIGN 到 MEMBER_ACCESS 时,若是 accessor field,发射 `call ClassName_set_NAME(obj, v)` 而非 GEP+store

**改动点:**
- `bootstrap/gen_class.ss` registerClass: 扫 classMethods 里 FUNC_DECL I2=2/3,填 classAccessorGetters/Setters Maps
- `bootstrap/gen_exprs.ss` MEMBER_ACCESS case: 先查 classAccessorGetters, 有就发 method call
- `bootstrap/gen_stmts.ss` ASSIGN 分支(target 是 MEMBER_ACCESS): 先查 classAccessorSetters, 有就发 method call
- `bootstrap/gen_types.ss` inferType for MEMBER_ACCESS: accessor 字段的类型 = getter 返回类型
- checker 拦截: field name 和 accessor name 冲突 → 报错

**GREEN:**
```ss
class Ref {
    _v: int = 0
    get value(): int { return this._v }
    set value(v: int) { this._v = v }
}
function main() {
    const r = new Ref(_v: 0)
    println(r.value)        // 0 (走 getter)
    r.value = 42             // 走 setter
    println(r.value)        // 42
}
```

输出:
```
0
42
```

### Phase 3: stdlib `ref()` + `effect()` + `track/trigger` PoC

**目标:** 基于 Phase 2 落地的 class get/set,在 `lib/reactive.ss` 写出最小响应式 stdlib(`ref` + `effect` + `track/trigger`),用户测试通过。

**不含:** `reactive(obj)` 泛型 wrapper(需要 D088 Phase 6+ comptime 类型作为值,属于更大话题,分 Phase 4 以后)。

### Phase 4+(未启动): `reactive<T>(v)` 泛型 wrapper

**依赖:** D088 Phase 6(comptime class 实例化)+ comptime 类型作为值(Zig `comptime T: type → type`)。

**形态:** `comptime function Reactive<T>(): type { class Wrap { ... } return Wrap }`。

本 phase 是 Zig 路线主线任务,不在 D096 第一版范围。

## 不变量

- **访问器生成函数命名:** `@ClassName_get_FIELD` / `@ClassName_set_FIELD`(和现有 method mangling 一致)
- **访问器与字段不能同名:** TS 规则,字段声明 `field: T` 与 `get field()` 同名 → 编译期报错
- **getter 必须 0 参数,setter 必须 1 参数:** 否则 checker 报错
- **static 访问器不支持(第一版):** `static get NAME()` 直接拒绝,后续 phase 扩展
- **getter 若不配 setter → 只读属性:** `obj.field = v` 对只读属性编译期报错
- **setter 若不配 getter → 只写属性:** `println(obj.field)` 对只写属性编译期报错
- **L2θ cls.annotations 包含 handler 自身:** 反射能看到当前正在运行的 handler,顺序按源码声明序(Java `Class.getAnnotations()` 同语义)。例:`@Scan @Deprecated class C` 的 `cls.annotations` 迭代出 `[Scan, Deprecated]`。handler 若需过滤自身需自行判断 ann 名

## 验证标准

每轮完成后:
1. `./build.sh bootstrap` 固定点验证(stage2 == stage3)
2. `tests/phase5/d096_*.ss` 覆盖:基础 get/set、只读、只写、字段-访问器同名检测、getter/setter 参数数校验
3. `tests/phase5/d095_*.ss` + 全 phase5 回归无新 FAIL
4. 最终 stdlib lib/reactive.ss `ref + effect + track + trigger` 最小 PoC 跑通

## 参考

- TS class accessor: https://www.typescriptlang.org/docs/handbook/classes.html#accessors
- C# property: https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/properties
- Vue 3 reactivity: https://vuejs.org/guide/extras/reactivity-in-depth.html
- D088 §Phase 5 fields() + bracket notation(响应式 reactive wrapper 的字段反射依赖)
- D095 @methodOf + Lombok handler(和本决策互补: D095 做声明时 annotation, D096 做 class body 访问器)
