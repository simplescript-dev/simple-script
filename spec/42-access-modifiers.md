# 42 - Access Modifiers (访问修饰符)

## 设计理念

> 默认私有，显式公开。来自 Java 的四级访问控制，但默认值不同。
> Java 默认包可见，SimpleScript 默认私有 — 更安全。
>
> `export` 关键字含义统一：无论用在模块顶层（class/function）还是类成员上，
> 都表示"对外部可见"。模块级 export = 外部模块可 import，成员级 export = 外部代码可访问。

## 四级访问

| 修饰符 | 本文件 | 子类 | 同包 | 外部 |
|--------|--------|------|------|------|
| (默认) | ✓ | ✗ | ✗ | ✗ |
| `protected` | ✓ | ✓ | ✗ | ✗ |
| `internal` | ✓ | ✓ | ✓ | ✗ |
| `export` | ✓ | ✓ | ✓ | ✓ |

## 用在哪

```simplescript
// class 级别
export class UserService { }         // 外部可用
internal class UserValidator { }     // 同包可用
class PasswordHasher { }             // 仅本文件

// 成员级别
export class User(name: string, age: int) {
    export function getName(): string = name     // 外部可调
    protected function validate() { }            // 子类可调
    internal function serialize() { }            // 同包可调
    function hashPassword() { }                  // 仅本类
}

// 函数级别
export function publicApi() { }
internal function packageHelper() { }
function privateHelper() { }

// 常量级别
export const VERSION = "1.0.0"
const SECRET_KEY = "xxx"             // 仅本文件
```

## 构造参数访问性

```simplescript
// 构造参数默认与 class 访问级别一致
export class User(name: string, age: int)
// name 和 age 对外可读可写 (因为 class 是 export 的)

// 限制某个字段
export class User(
    name: string,                      // export (跟随 class)
    internal age: int,                 // 同包可访问
    password: string                   // 显式私有? 不，跟随 class
)
```

## 最佳实践

```
1. class 的字段尽量不对外暴露，用方法访问
2. 工具函数不需要 export 就不 export
3. 接口的方法自动是 export 的（接口本身就是契约）
4. 测试代码可以访问 internal 成员（同包）
```
