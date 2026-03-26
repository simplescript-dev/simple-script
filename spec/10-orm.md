# 10 - ORM (数据库)

## 设计理念

> JPA 的注解体验 + MyBatis 的灵活 SQL + 编译期安全。
> 不用 XML，不用反射，SQL 拼写错误编译期就报错。

## 定义实体

```simplescript
@Table("users")
class User(
    @Id @AutoIncrement
    id: long,
    name: string,
    @Column("email_address")
    email: string,
    age: int,
    @CreatedAt
    createdAt: LocalDateTime,
    @UpdatedAt
    updatedAt: LocalDateTime
)

@Table("orders")
class Order(
    @Id @AutoIncrement
    id: long,
    @ForeignKey("users")
    userId: long,
    amount: double,
    status: OrderStatus
)

enum OrderStatus { Pending, Paid, Shipped, Done }
```

## 自动建表

```simplescript
// 编译器根据 @Table 注解自动生成建表 SQL
// 开发环境自动迁移，生产环境生成迁移脚本

@Application
class MyApp {
    function main() {
        const db = Database.connect("postgres://localhost/mydb")
        db.autoMigrate()     // 自动对比 class 和表结构，生成 ALTER
    }
}
```

```bash
# 数据库迁移是第三方包，不是语言内置
ss add db-migrate
```

## 基本 CRUD

```simplescript
@Service
class UserRepository(db: Database) {

    function findById(id: long): User? {
        return db.find<User>(id)
    }

    function findAll(): List<User> {
        return db.findAll<User>()
    }

    function save(user: User): User {
        return db.insert(user)
    }

    function update(user: User): User {
        return db.update(user)
    }

    function deleteById(id: long) {
        db.delete<User>(id)
    }
}
```

## 类型安全查询

```simplescript
// 编译期检查字段名和类型，拼错字段直接报编译错误
@Service
class UserRepository(db: Database) {

    function findByName(name: string): List<User> {
        return db.query<User>()
            .where(User::name.eq(name))
            .list()
    }

    function findAdults(): List<User> {
        return db.query<User>()
            .where(User::age.gte(18))
            .orderBy(User::name.asc())
            .list()
    }

    function findByNameAndAge(name: string, minAge: int): List<User> {
        return db.query<User>()
            .where(
                User::name.like("%${name}%"),
                User::age.gte(minAge)
            )
            .limit(10)
            .list()
    }

    // 分页
    function findPage(page: int, size: int): Page<User> {
        return db.query<User>()
            .orderBy(User::createdAt.desc())
            .page(page, size)
    }

    // 聚合
    function countByAge(minAge: int): long {
        return db.query<User>()
            .where(User::age.gte(minAge))
            .count()
    }
}
```

## 原生 SQL

```simplescript
// 需要复杂 SQL 时，直接写，依然类型安全
@Service
class ReportRepository(db: Database) {

    function userOrderSummary(): List<UserOrderSummary> {
        return db.sql<UserOrderSummary>(`
            SELECT u.name, COUNT(o.id) as order_count, SUM(o.amount) as total
            FROM users u
            LEFT JOIN orders o ON u.id = o.user_id
            GROUP BY u.name
            ORDER BY total DESC
        `)
    }

    // 参数绑定，防 SQL 注入
    function searchUsers(keyword: string, minAge: int): List<User> {
        return db.sql<User>(`
            SELECT * FROM users
            WHERE name LIKE $1 AND age >= $2
        `, "%${keyword}%", minAge)
    }
}

class UserOrderSummary(
    name: string,
    @Column("order_count") orderCount: long,
    total: double
)
```

## 关联查询

```simplescript
@Table("users")
class User(
    @Id @AutoIncrement
    id: long,
    name: string,

    @HasMany(Order::userId)
    orders: List<Order>,

    @HasOne(Profile::userId)
    profile: Profile?
)

@Table("orders")
class Order(
    @Id @AutoIncrement
    id: long,
    @ForeignKey("users")
    userId: long,
    amount: double,

    @BelongsTo(User::id)
    user: User
)

// 查询时自动 JOIN
const user = db.find<User>(1)          // 懒加载，访问 orders 时才查
const orders = user.orders              // 此时执行 SELECT * FROM orders WHERE user_id = 1

// 预加载，避免 N+1
const users = db.query<User>()
    .include(User::orders)              // 一次 JOIN 查出来
    .list()
```

## 事务

```simplescript
@Service
class OrderService(db: Database, userRepo: UserRepository) {

    @Transactional
    function createOrder(userId: long, amount: double): Result<Order, Error> {
        const user = userRepo.findById(userId)?
        if (user == null) return Result.Err(new Error("user not found"))

        const order = new Order(id: 0, userId: userId, amount: amount, status: OrderStatus.Pending)
        return Result.Ok(db.insert(order))
        // 方法正常返回 → 自动 commit
        // 返回 Err 或异常 → 自动 rollback
    }
}
```

## 多数据库支持

```json
// ss.json
{
  "database": {
    "default": {
      "driver": "postgres",
      "url": "postgres://localhost/mydb"
    },
    "readonly": {
      "driver": "postgres",
      "url": "postgres://readonly-host/mydb"
    },
    "cache": {
      "driver": "sqlite",
      "url": "file:cache.db"
    }
  }
}
```

```simplescript
// 支持的数据库驱动 (编译期静态链接)
// postgres, mysql, sqlite, mariadb
```

## 完整示例

```simplescript
import { Database, Table, Id, AutoIncrement, Column } from "dev/db"
import { HttpServer, Request, Response } from "net/http"
import { RestController, RequestMapping, GetMapping, PostMapping, PutMapping, DeleteMapping, PathVariable, RequestBody } from "ss/web"

@Table("todos")
class Todo(
    @Id @AutoIncrement id: long,
    title: string,
    done: bool = false
)

@RestController
@RequestMapping("/api/todos")
@Service
class TodoController(db: Database) {

    @GetMapping
    function list(): Response {
        const todos = db.findAll<Todo>()
        return Response.ok(todos)
    }

    @GetMapping("/:id")
    function get(@PathVariable id: long): Response {
        const todo = db.find<Todo>(id)
        return switch (todo) {
            case Todo t -> Response.ok(t)
            default -> Response.notFound("todo not found")
        }
    }

    @PostMapping
    function create(@RequestBody todo: Todo): Response {
        const saved = db.insert(todo)
        return Response.created(saved)
    }

    @PutMapping("/:id")
    function update(@PathVariable id: long, @RequestBody todo: Todo): Response {
        const updated = db.update(todo)
        return Response.ok(updated)
    }

    @DeleteMapping("/:id")
    function delete(@PathVariable id: long): Response {
        db.delete<Todo>(id)
        return Response.noContent()
    }
}

@Application
class TodoApp {
    function main() {
        const app = Application.run<TodoApp>()
        app.start(port: 8080)
    }
}
```
