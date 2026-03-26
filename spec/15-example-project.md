# 15 - Complete Example (完整示例项目)

## 项目: Todo REST API

> 把所有语言特性串起来的真实项目。

## 项目结构

```
todo-api/
├── ss.json
├── src/
│   ├── main.ss
│   ├── model/
│   │   └── todo.ss
│   ├── service/
│   │   └── todo_service.ss
│   ├── controller/
│   │   └── todo_controller.ss
│   └── config/
│       └── app_config.ss
├── test/
│   └── todo_service.test.ss
└── resources/
    └── application.yml
```

## ss.json

```json
{
  "name": "todo-api",
  "version": "0.1.0",
  "target": "bin",
  "dependencies": {
    "ss/web": "1.0.0",
    "ss/di": "1.0.0",
    "ss/validation": "1.0.0",
    "ss/cache": "1.0.0"
  },
  "scripts": {
    "dev": "ss run --watch",
    "prod": "ss build --release"
  }
}
```

## resources/application.yml

```yaml
server:
  port: 8080

database:
  driver: sqlite
  url: "file:todo.db"
```

## src/model/todo.ss

```simplescript
import { Table, Id, AutoIncrement, CreatedAt, UpdatedAt } from "dev/db"
import { JsonProperty, JsonIgnore } from "encoding/json"
import { NotBlank, Size } from "ss/validation"

@Table("todos")
export class Todo(
    @Id @AutoIncrement
    id: long = 0,

    @NotBlank
    @Size(min: 1, max: 200)
    title: string,

    done: bool = false,

    @CreatedAt
    createdAt: LocalDateTime = LocalDateTime.now(),

    @UpdatedAt
    updatedAt: LocalDateTime = LocalDateTime.now()
)

export enum TodoFilter { All, Active, Done }
```

## src/config/app_config.ss

```simplescript
import { Configuration } from "ss/di"
import { Database } from "dev/db"

@Configuration
export class AppConfig {
    function database(): Database {
        return Database.connect("file:todo.db")
    }
}
```

## src/service/todo_service.ss

```simplescript
import { Service } from "ss/di"
import { Database } from "dev/db"
import { Transactional } from "dev/db/tx"
import { Cacheable, CacheEvict } from "ss/cache"
import { Todo, TodoFilter } from "../model/todo"

@Service
export class TodoService(db: Database) {

    @Cacheable("todos")
    function findAll(filter: TodoFilter = TodoFilter.All): List<Todo> {
        return switch (filter) {
            case TodoFilter.All -> db.findAll<Todo>()
            case TodoFilter.Active -> db.query<Todo>()
                .where(Todo::done.eq(false))
                .list()
            case TodoFilter.Done -> db.query<Todo>()
                .where(Todo::done.eq(true))
                .list()
        }
    }

    function findById(id: long): Todo? {
        return db.find<Todo>(id)
    }

    @CacheEvict("todos")
    @Transactional
    function create(title: string): Todo {
        const todo = new Todo(title: title)
        return db.insert(todo)
    }

    @CacheEvict("todos")
    @Transactional
    function toggle(id: long): Result<Todo, string> {
        const todo = findById(id)
        if (todo == null) return Result.Err("todo not found")

        todo.done = !todo.done
        todo.updatedAt = LocalDateTime.now()
        return Result.Ok(db.update(todo))
    }

    @CacheEvict("todos")
    @Transactional
    function delete(id: long): Result<void, string> {
        if (findById(id) == null) return Result.Err("todo not found")
        db.delete<Todo>(id)
        return Result.Ok(())
    }
}
```

## src/controller/todo_controller.ss

```simplescript
import { Response } from "net/http"
import { RestController, RequestMapping, GetMapping, PostMapping, PutMapping, DeleteMapping,
         PathVariable, RequestParam, RequestBody, Valid } from "ss/web"
import { TodoService } from "../service/todo_service"
import { Todo, TodoFilter } from "../model/todo"

@RestController
@RequestMapping("/api/todos")
export class TodoController(todoService: TodoService) {

    @GetMapping
    function list(@RequestParam filter: TodoFilter = TodoFilter.All): Response {
        const todos = todoService.findAll(filter)
        return Response.ok(todos)
    }

    @GetMapping("/:id")
    function get(@PathVariable id: long): Response {
        const todo = todoService.findById(id)
        return switch (todo) {
            case Todo t -> Response.ok(t)
            default -> Response.notFound("todo not found")
        }
    }

    @PostMapping
    function create(@Valid @RequestBody body: CreateTodoRequest): Response {
        const todo = todoService.create(body.title)
        return Response.created(todo)
    }

    @PutMapping("/:id/toggle")
    function toggle(@PathVariable id: long): Response {
        const result = todoService.toggle(id)
        return switch (result) {
            case Result.Ok ok -> Response.ok(ok.value)
            case Result.Err e -> Response.notFound(e.error)
        }
    }

    @DeleteMapping("/:id")
    function delete(@PathVariable id: long): Response {
        const result = todoService.delete(id)
        return switch (result) {
            case Result.Ok _ -> Response.noContent()
            case Result.Err e -> Response.notFound(e.error)
        }
    }
}

class CreateTodoRequest(
    @NotBlank @Size(min: 1, max: 200)
    title: string
)
```

## src/main.ss

```simplescript
import { Application } from "ss/di"
import { Slf4j } from "dev/log"

@Slf4j
@Application
class TodoApp {
    function main() {
        log.info("starting todo api...")
        const app = Application.run<TodoApp>()
        app.start(port: 8080)
        log.info("listening on :8080")
    }
}
```

## test/todo_service.test.ss

```simplescript
import { test, expect, beforeEach } from "dev/test"
import { Database } from "dev/db"
import { TodoService } from "../src/service/todo_service"
import { TodoFilter } from "../src/model/todo"

let db: Database
let service: TodoService

beforeEach(() => {
    db = Database.connect("file::memory:")   // 内存数据库
    db.autoMigrate()
    service = new TodoService(db)
})

test("create todo", () => {
    const todo = service.create("buy milk")
    expect(todo.title).toBe("buy milk")
    expect(todo.done).toBe(false)
    expect(todo.id).toBeGreaterThan(0)
})

test("toggle todo", () => {
    const todo = service.create("buy milk")
    const toggled = service.toggle(todo.id)?
    expect(toggled.done).toBe(true)
})

test("filter active todos", () => {
    service.create("task 1")
    service.create("task 2")
    const todo3 = service.create("task 3")
    service.toggle(todo3.id)

    const active = service.findAll(TodoFilter.Active)
    expect(active.size()).toBe(2)
})

test("delete todo", () => {
    const todo = service.create("buy milk")
    service.delete(todo.id)
    expect(service.findById(todo.id)).toBe(null)
})

test("delete nonexistent returns error", () => {
    const result = service.delete(999)
    expect(result.isErr()).toBe(true)
})
```

## 运行

```bash
# 开发
ss run --watch

# 测试
ss test

# 构建 release
ss build --release

# 产物
ls -lh target/release/todo-api
# -rwxr-xr-x 1.2M todo-api    ← 单文件，静态链接，无依赖

# 部署: 复制到服务器直接跑
scp target/release/todo-api server:/app/
ssh server "/app/todo-api"
```

## API 测试

```bash
# 创建
curl -X POST localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "buy milk"}'

# 列表
curl localhost:8080/api/todos

# 过滤
curl "localhost:8080/api/todos?filter=Active"

# 完成
curl -X PUT localhost:8080/api/todos/1/toggle

# 删除
curl -X DELETE localhost:8080/api/todos/1
```
