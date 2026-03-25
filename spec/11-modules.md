# 11 - Module System (模块系统)

## 设计理念

> 文件即模块，目录即命名空间。来自 TypeScript 的 import/export，零配置。

## 基本规则

```
1. 一个 .ss 文件 = 一个模块
2. 目录 = 命名空间
3. export 的才能被外部访问，不 export 的是私有的
4. 没有 package 声明，文件路径就是模块路径
```

## Prelude (自动导入)

以下符号无需 import，编译器自动导入：

```
来自 io/print:
  println, print, readLine

来自 util/collections:
  List, MutableList, Map, MutableMap, Set, MutableSet, Queue, Deque, Stack

来自核心类型:
  Result, Error

其他所有模块必须显式 import。
```

## 导出

```simplescript
// src/model/user.ss

// export 的对外可见
export class User(name: string, age: int)

export function validateUser(user: User): bool {
    return user.name.length > 0 && user.age > 0
}

export const MAX_AGE = 150

// 不 export 的是模块私有
function hashPassword(pwd: string): string {
    // 外部无法调用
}
```

## 导入

```simplescript
// 按名称导入
import { User, validateUser } from "./model/user"

// 导入全部，用命名空间访问
import * as userModel from "./model/user"
const user = new userModel.User("Alice", 30)

// 导入标准库
import { HttpServer, Request, Response } from "net/http"
import { Database } from "dev/db"

// 导入第三方包
import { Redis } from "lisi/redis"

// 重命名导入
import { User as DbUser } from "./model/user"
import { User as ApiUser } from "./api/user"
```

## 目录结构 = 模块结构

```
src/
├── main.ss                          // 入口
├── controller/
│   ├── user_controller.ss           // import from "./controller/user_controller"
│   └── order_controller.ss
├── service/
│   ├── user_service.ss
│   └── order_service.ss
├── model/
│   ├── user.ss
│   └── order.ss
└── util/
    └── string_util.ss
```

```simplescript
// src/main.ss
import { UserController } from "./controller/user_controller"
import { UserService } from "./service/user_service"
import { Database } from "dev/db"
```

## 重新导出

```simplescript
// src/model/index.ss — 统一出口
export { User } from "./user"
export { Order } from "./order"
export { Product } from "./product"

// 外部只需一行导入
import { User, Order, Product } from "./model"
```

## 可见性

```simplescript
// export     → 任何人可访问
// internal   → 同包内可访问，外部包不可访问
// protected  → 子类可访问 (仅用于类成员)
// (不写)     → 私有，只有同文件/同类可访问

export class User(name: string, age: int)         // 公开
internal class UserValidator { }                   // 同包可用
class PasswordHasher { }                           // 仅本文件

// 完整的四级访问控制见 42-access-modifiers.md
```
