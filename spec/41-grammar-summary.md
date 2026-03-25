# 41 - Grammar Summary (语法速查表)

## 关键字

```
// 声明
const let function class interface enum abstract open
annotation export import type new

// 控制流
if else switch case default for while do break continue return
try                                // 仅用于 try-with-resources

// 类型
byte short int long ubyte ushort uint ulong float double
bool char string void any null true false

// 修饰符
override static export internal protected weak

// 错误处理
panic assert recover catch

// 并发
spawn select scope parallel from

// 编译期
comptime typeof

// 其他
this super in is as
```

## 保留字 (不使用但预留)

```
async await yield          // 不使用虚拟线程替代
throw finally              // 不使用 (catch 已用于 recover/catch)
var val fun when           // 不使用
struct union               // 不使用
sealed                     // 不使用
macro                      // 未来可能使用
```

## 操作符

```
// 算术
+  -  *  /  %

// 比较
==  !=  >  <  >=  <=

// 逻辑
&&  ||  !

// 位运算
&  |  ^  ~  <<  >>  >>>

// 赋值
=  +=  -=  *=  /=  %=
&=  |=  ^=  <<=  >>=

// 自增自减
++  --

// 空安全与错误传播
?.   // 安全访问: user?.name
??   // 默认值: value ?? fallback (对 null 和 Result.Err 都生效)
!    // 强制解包: user!.name (null 则 panic), result! (Err 则 panic)
?    // Result 传播: readFile()? (后缀, 仅用于 Result<T,E> 返回值)

// 注意: ? 和 ?. 不冲突
//   expr?     → Result 传播 (后缀, 表达式结尾)
//   expr?.x   → 空安全访问 (中缀, 后面跟成员)

// 类型
is   // 类型检查: x is User
as   // 类型转换: x as User (失败 panic)

// 属性引用
::   // 成员引用: User::name (编译期属性描述符, 用于 ORM 查询等)

// 模板字符串
`${expr}`

// 箭头
=>   // 箭头函数: (x) => x * 2
->   // switch case: case 1 -> "one"
->   // select case: case msg from ch -> handle(msg)
```

## 语句语法

```simplescript
// 变量
const name = value
let name = value
const name: Type = value

// 函数
function name(param: Type): ReturnType { }
function name(param: Type): ReturnType = expr
export function name(param: Type): ReturnType { }

// 箭头函数
const fn = (param: Type): ReturnType => expr
const fn = (param: Type): ReturnType => { ... }

// 类
class Name(param: Type) { }
class Name(param: Type) : Parent(args), Interface1, Interface2 { }

// 接口
interface Name { }
interface Name<T> { }

// 枚举
enum Name { Value1, Value2 }
enum Name<T> { Value1(field: T), Value2(field: T) }

// 注解
annotation class Name(param: Type)
@AnnotationName(args)

// 导入导出
import { Name } from "module/path"
import * as alias from "module/path"
export class Name { }
export function name() { }
```

## 控制流语法

```simplescript
// if (是表达式)
if (condition) { } else { }
const x = if (condition) a else b

// switch (是表达式)
switch (value) {
    case Pattern -> expr
    case Pattern -> { if (guard) expr else other }
    default -> expr
}

// for
for (let i = 0; i < n; i++) { }
for (item in collection) { }
for ((key, value) in map) { }

// while
while (condition) { }
do { } while (condition)

// try-with-resources
try (const resource = new Resource()) { }
```

## 文件结构

```simplescript
// 导入 (文件顶部)
import { A, B } from "module/path"

// 声明
export class MyClass { }
export function myFunction() { }
const MY_CONSTANT = 42

// 入口 (可执行项目)
function main() { }
```
