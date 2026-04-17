# D095: 注解 handler 结构化 API — Lombok 风注解 = 函数

**Status:** Proposed (Plan 型, 不触发代码改动)
**Depends on:** D088 (Zig 路线 + Phase 5 obj.fields() 已落地), D094 (comptime 解释器 8/8 Zig Sema 对齐)
**Date:** 2026-04-17

## 第一性需求

**写注解 handler 应该跟写普通业务 SS 代码一样自然。**

D088 §第一性需求 解决了"给定一个对象遍历字段名/值"的运行时 + comptime 块内能力。但**用户编写注解 handler** 时仍卡在 D088 §过渡策略 第 1 条"@derive handler 内部实现可改用 fields() + bracket notation,但用户接口不变"——handler 接口是字符串拼接 (`gen_class.ss:479` `ctDerive${X}("${name}")\n` → tokenize → parse → 注入)。

否定证据：lib/spring/boot.ss 在 d1816ab 清零后 4 个月没回来 (`ls lib/spring/` → 仅 `boot/` 目录 + `data.ss` / `http.ss` / `jdbc.ss` / `web.ss`,无 boot.ss);`grep -r "function ctDerive" lib/` → 0 个用户实现。framework 级库 (spring/orm/test) 写不出来 → SS 永远停留在 toy 阶段,无法接 Java/TS 生态密度。

为什么 handler 接口必须改？字符串拼接 → 重新 tokenize/parse → 注入 AST 是双工作量;handler 内 IDE 无补全无类型检查;拼错只在编译时才发现,错误位置失真。

## 决策

**注解 = 函数。** 注解函数接收 `ClassMeta` / `MethodMeta` / `FieldMeta` / `ParamMeta`(编译期对象),在 comptime 块跑(D094 已支持),用 `@methodOf(cls)` 注解标记的嵌套函数被编译器吸收为目标 class 的方法。

模型借鉴：

| 维度 | 借鉴 | 来源 |
|---|---|---|
| 注解 = 函数,无注册表 | `@decorator class Foo` | TypeScript / Python decorator |
| 注解名直接,无 wrapper | `@ToString` / `@Data` | Lombok |
| handler 内写 def 编译器吸收 | macro body 自动注入 class | Crystal |
| 多层 Meta 树 (class/method/field/param) | `Element` / `TypeElement` / `ExecutableElement` / `VariableElement` | Java APT |
| 命名参数 | `@Column(name = "x", length = 100)` | Java annotation |

**弃用：**
- `@derive("X")` Rust 风 wrapper(违反 D088 Java/TS 优先原则)
- `annotationMapping(name, handler)` 注册表(prelude.ss:193,注解 = 函数无需注册)

**新增(编译器内部)：**
- 5 个 comptime-only 内置 class:`ClassMeta` / `FieldMeta` / `MethodMeta` / `ParamMeta` / `AnnotationMeta`
- 1 个内置注解:`@methodOf(cls)`(标记嵌套函数挂载到 cls)

**不引入：**
- 任何新关键字
- 运行时反射结构(注解全部 SOURCE retention,runtime 二进制零反射痕迹)
- D088 Phase 9 "类型作为 comptime 值"(self 类型推断仅靠 @methodOf 局部规则)

## 注解 API 总览

### 用户视角(注解使用)

```ss
import { Data, Entity, Id, Column } from "@/lib/lombok"
import { RestController, GetMapping, RequestParam } from "@/lib/spring"

@Data
@Entity
class User {
    @Id
    id: int

    @Column(name: "user_name", length: 100)
    name: string

    age: int
}

@RestController("/api")
class UserController {
    @GetMapping("/users")
    function list(@RequestParam("page") page: int): Array<User> { ... }
}
```

跟 Lombok / JPA / Spring 的 Java 写法一一对应：
- 注解名直接 (`@ToString`,不是 `@derive("ToString")`)
- 命名参数 `name: "user_id"` 对应 Java `name = "user_id"`
- positional 简化 `@RequestMapping("/api")` 对应 Spring `@RequestMapping("/api")`

### 库作者视角(注解定义)

```ss
// lib/lombok.ss

// 无参注解:单一 ClassMeta 参数
export function ToString(cls: ClassMeta) {
    @methodOf(cls)
    function toString(self): string {
        let parts = ""
        for (f in cls.fields) {
            if (parts != "") { parts = parts + ", " }
            parts = parts + f.name + "=" + self[f.name]
        }
        return cls.name + "(" + parts + ")"
    }
}

// 带参数注解:注解参数 = handler 第 2..n 参数
export function ToString(cls: ClassMeta, of: Array<string>) {
    @methodOf(cls)
    function toString(self): string {
        let parts = ""
        for (fname in of) {
            if (parts != "") { parts = parts + ", " }
            parts = parts + fname + "=" + self[fname]
        }
        return cls.name + "(" + parts + ")"
    }
}

// Meta 注解:组合调用其他 handler,不需要新机制
export function Data(cls: ClassMeta) {
    ToString(cls)
    EqualsAndHashCode(cls)
    Getter(cls)
    Setter(cls)
}

// Field 级注解:写 metadata
export function Column(field: FieldMeta, name: string, length: int) {
    field.metadata.set("dbName", name)
    field.metadata.set("dbLength", length)
}

// Param 级注解:写 metadata
export function RequestParam(param: ParamMeta, key: string) {
    param.metadata.set("source", "queryParam")
    param.metadata.set("key", key)
}

// Class-level handler 读 method/param 上的注解(spring 模式)
export function RestController(cls: ClassMeta, basePath: string) {
    for (m in cls.methods) {
        for (a in m.annotations) {
            if (a.name == "GetMapping") {
                const path = basePath + a.args.get(0)
                @methodOf(cls)
                function _dispatch(self, req): Response {
                    // 用 m.params 各 ParamMeta.metadata 生成参数提取
                }
            }
        }
    }
}
```

## ClassMeta API

```ss
class ClassMeta {
    name: string
    parent: string                      // "" if no parent
    fields: Array<FieldMeta>
    methods: Array<MethodMeta>
    annotations: Array<AnnotationMeta>
    metadata: Map<string, any>          // 注解间通信总线
}

class FieldMeta {
    name: string
    type: string                        // SS type name
    annotations: Array<AnnotationMeta>
    metadata: Map<string, any>
}

class MethodMeta {
    name: string
    returnType: string
    params: Array<ParamMeta>
    annotations: Array<AnnotationMeta>
    metadata: Map<string, any>
}

class ParamMeta {
    name: string
    type: string
    annotations: Array<AnnotationMeta>
    metadata: Map<string, any>
}

class AnnotationMeta {
    name: string
    args: Array<any>                    // positional
    namedArgs: Map<string, any>         // named
}
```

`metadata` 是注解之间通信的总线:`@Column` 写入 `field.metadata`,`@Entity` 读出来生成 SQL DDL;`@RequestParam` 写入 `param.metadata`,`@RestController` 读出来生成 dispatch。

## 编译器机制

### parse 阶段(无改动)

已支持:
- `parseAnnotationList()` (parser.ss:247) — parse `@xxx(args)` 序列
- `attachAnnotations(nodeId, anns)` (parser.ss:269) — 挂到 CLASS_DECL.I4 / FUNC_DECL.I4 / FIELD.I4 / PARAM.I4
- 命名参数 `name: value` 走现有 NAMED_ARG 节点

### codegen 阶段(新增)

class/field/method/param 编译时:
1. 遍历节点的 ANNOTATION_LIST
2. 对每个 ANNOTATION,按名字查找同名 export function
3. 构造对应 Meta 对象 (ClassMeta / FieldMeta / MethodMeta / ParamMeta)
4. 调 handler,把 annotation args 作为后续参数传入(comptime 求值,走 D094 已支持的外部函数调用)
5. handler 内 `@methodOf(cls) function ...` 由编译器收集到 ctFuncNodes(同 D088 Phase 5 已落地的 class-level comptime block 路径),绑定到 cls.name
6. handler 跑完,编译器把绑定的方法当作 cls 的普通方法编译(同 emitClassComptimeMethods,gen_class.ss:386)
7. 同名方法冲突:用户已定义则跳过(仿 Rust derive,silent skip)

### 与现有 comptime 解释器复用

- handler body 在 comptime 块跑 → 走 D094 已对齐的 8/8 Zig Sema 求值路径
- handler 内 `for (f in cls.fields)` → 走 D088 Phase 5 已落地的编译期循环展开 (gen_stmts.ss:586)
- handler 内 `self[f.name]` → 走 D088 Phase 5 已落地的 bracket notation 折叠 (gen_exprs.ss:55)
- ClassMeta 存活于 comptime 解释器的 ctVars / ctScopeStack,runtime 不可见

零新求值器,零运行时反射结构。

## @methodOf(cls) 的语义

`@methodOf(cls)` 是 D095 引入的内置注解,编译器特殊识别:

- 标注在 handler 内嵌套函数声明上
- 编译器把该函数收集到 ctFuncNodes,绑定 className = cls.name
- self 参数类型自动推断为 cls 实例化的 class(仅靠 @methodOf 上下文,不依赖 D088 Phase 9)
- handler 跑完,编译器把绑定的函数走 emitClassComptimeMethods 注入到 class

命名暂用 `@methodOf(cls)`(Java reflection `Method.getDeclaringClass` 风格),后续可改名(用户保留改名权)。

## 设计原则检查(对照 D088)

| D088 原则 | D095 检查 |
|---|---|
| Java/TS 优先 | 注解 = 函数同 TS decorator,参数语法同 Java annotation |
| 不加新关键字 | @methodOf 是注解(已有 @ 语法),不是关键字 |
| 不自创语法 | Lombok / Spring / JPA 一一对应 |
| 编译器吸收复杂度 | handler 内写普通 SS,编译器吸收为 method |
| 不运行时反射 | ClassMeta 仅 comptime;runtime 二进制零痕迹 |
| 不抄 Zig 具体语法 | 借鉴 Crystal / Lombok / TS decorator,非 `@compileLog` / `usingnamespace` |

## 与现状的差距清单(每项标 P19 状态)

1. **[ ] Planned** — ClassMeta / FieldMeta / MethodMeta / ParamMeta / AnnotationMeta 5 个内置 class 定义
   现状:不存在。目标:comptime-only class,编译器在调 handler 前构造

2. **[ ] Planned** — 内置注解 `@methodOf(cls)` 实现
   现状:parser 已支持任意 @xxx 语法;`gen_class.ss:466` 仅特殊识别 @derive。目标:编译器特殊识别 @methodOf,吸收嵌套函数到 cls

3. **[ ] Planned** — codegen 阶段 dispatch 注解到同名 function
   现状:仅 @derive 走 ctDerive{X} 字符串拼接路径 (gen_class.ss:479)。目标:通用机制——任意注解名 → 查找同名 function → 调用,annotations 透明

4. **[ ] Planned** — `metadata: Map<string, any>` 在 5 个 Meta class 上落地
   现状:D088 Phase 5 落地的 fields() 仅返回 string 数组 (gen_methods.ss:482)。目标:构造完整 Meta 对象时初始化 metadata Map

5. **[ ] Planned** — 弃用 @derive 字符串拼接路径
   现状:`gen_class.ss:466-490` 仍处理 @derive。目标:保留 parser 兼容(不破现有测试),但 codegen 路径改走通用 dispatch;@derive 文档标记为 deprecated

6. **[ ] Planned** — 同名注解 overload 走 SS 现有 paramSig 机制
   现状:注解调用站点未走 overload。目标:注解参数数量/类型选 overload,复用 funcRetTypes overload 机制

## 实施路线图(粒度仅至阶段,不指定时间)

每阶段独立 D 文档(D095-A / D095-B / ...),本 D 仅列阶段。

- **Stage A**:5 个 Meta class + ClassMeta 构造 + codegen dispatch 框架
  最小可工作 = `@MyAnnotation class Foo {}` 能调用 MyAnnotation handler
- **Stage B**:`@methodOf(cls)` 内置注解 + handler 内嵌套函数吸收
  最小可工作 = `@ToString class Point {x: int; y: int}` 自动生成 toString 方法
- **Stage C**:FieldMeta / ParamMeta + 嵌套 annotations 树
  最小可工作 = `@Column(name: "x")` field 注解能写入 metadata
- **Stage D**:MethodMeta + class-level handler 扫嵌套注解
  最小可工作 = `@RestController` 能扫 method 上的 `@GetMapping`
- **Stage E**:lib/lombok.ss + lib/spring/boot.ss 用新 API 实现
  验证标准 = `tests/phase5/spring_web_params.ss` 测试通过

## Rejected Alternatives

- **A: 保留 @derive("X") + 字符串拼接 handler**(D088 §过渡策略 第 1 条) — 用户判定丑且 handler 写不出复杂逻辑(拼源码无 IDE 支持),lib/spring/boot 4 个月未恢复即证据
- **B: handler 调 cls.addMethod(funcAst) 显式注册**(Java APT / Roslyn 模式) — funcAst 怎么造?JavaPoet 那套 builder API 表面积巨大,SS 阶段做不起且违反"handler 写起来像普通 SS"目标
- **C: handler 返回 Array\<FuncAst\>**(Nim macro 模式) — FuncAst 同 B 的难点;返回值 + 显式注册的双重负担
- **D: 全局变量 `__currentClass: ClassMeta`,handler 零参数** — 隐式上下文 = 魔法,嵌套触发乱套
- **E: 注解 = 类**(Java/Kotlin annotation class) — SS 没有 annotation class 概念,引入即新关键字
- **F: 用 @annotation 标记区分注解 vs 普通函数** — TS / Python decorator 都不需要标记(签名匹配即可),多余

## 张力

1. **`metadata: Map<string, any>` 的 any 类型** — SS 无 union type,any 实际上是 ptr。注解之间约定 key 含义,无类型检查。**接受** — Java APT 同样依赖约定 (`Element.getAnnotation(X.class)` 取出后 cast)
2. **同名注解 overload 的 dispatch 时机** — 注解参数数量/类型必须在 codegen 阶段已知,否则 overload 无法 resolve。本设计要求注解参数全部 comptime constant(D094 规则 1 已保证 comptime 块内全部 known)。**天然满足**
3. **handler 内 `@methodOf(cls)` 函数的 self 推断** — 仅靠 @methodOf 上下文规则,不引入"类型即值"。如果未来出现 `@methodOf(cls) function equals(self, other: cls)` 这种 other 也是 cls 类型的场景,需扩展推断规则。**当前 D095 范围内仅支持 self 推断;其他参数为 cls 类型走未来 D 文档**
4. **注解定义文件加载顺序** — `import { ToString } from "@/lib/lombok"` 必须先于使用 @ToString 的 class 定义。SS resolveImports 已先内联所有 import (D085),天然满足。**天然满足**
5. **handler 同名方法冲突的 silent skip vs error** — Rust derive 走 silent skip。SS 暂走 silent skip,未来可加 `@override` 注解显式声明覆盖意图

## 下一步

本 D 文档不触发任何 .ss 代码改动,不跑 bootstrap。

- **[ ] Planned** — 起 D095-A,定义 5 个 Meta class 的精确 SS 形态 + 编译器构造时机
- **[ ] Planned** — 验证 SS 现有 import 系统能否支持"注解函数 import 后 @注解名 直接使用"(grep `parseAnnotationList` + import resolution 路径)
- **[ ] Planned** — 验证 SS 现有 `funcRetTypes` overload 机制能否覆盖注解参数 overload

代码改动从 D095-A 之后的 Execute 轮开始。
