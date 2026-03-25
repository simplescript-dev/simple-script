# 67 - Pagination & Sorting (分页与排序)

## 设计理念

> 分页是 API 最基本的需求。标准化分页参数和响应格式。

## 请求参数

```simplescript
import { Page, Pageable, Sort } from "dev/db"

@RestController
@RequestMapping("/api/users")
class UserController(userService: UserService) {

    // Pageable 自动从 query 参数解析
    // GET /api/users?page=1&size=20&sort=name,asc
    @GetMapping
    function list(@Pageable pageable: PageRequest): Response {
        const result = userService.findAll(pageable)
        return Response.ok(result)
    }
}
```

## Page 响应格式

```json
{
  "content": [
    {"id": 1, "name": "Alice", "age": 30},
    {"id": 2, "name": "Bob", "age": 25}
  ],
  "page": 1,
  "size": 20,
  "totalElements": 156,
  "totalPages": 8,
  "hasNext": true,
  "hasPrevious": false
}
```

## Service 层

```simplescript
@Service
class UserService(db: Database) {

    function findAll(pageable: PageRequest): Page<User> {
        return db.query<User>()
            .orderBy(pageable.sort)
            .page(pageable.page, pageable.size)
    }

    function findByAge(minAge: int, pageable: PageRequest): Page<User> {
        return db.query<User>()
            .where(User::age.gte(minAge))
            .orderBy(pageable.sort)
            .page(pageable.page, pageable.size)
    }
}
```

## 排序

```simplescript
// 单字段排序
// GET /api/users?sort=name,asc
// GET /api/users?sort=age,desc

// 多字段排序
// GET /api/users?sort=age,desc&sort=name,asc

// 代码中手动排序
const page = db.query<User>()
    .orderBy("age", Sort.DESC)
    .orderBy("name", Sort.ASC)
    .page(1, 20)
```

## 游标分页 (大数据集)

```simplescript
// 传统 offset 分页在大数据集性能差
// 游标分页用上一页最后一条的 ID 作为游标

@GetMapping
function list(
    @RequestParam cursor: long? = null,
    @RequestParam size: int = 20
): Response {
    const query = db.query<User>()
        .orderBy("id", Sort.ASC)
        .limit(size + 1)      // 多查一条判断 hasNext

    if (cursor != null) {
        query.where(User::id.gt(cursor))
    }

    const items = query.list()
    const hasNext = items.size() > size
    const content = if (hasNext) items.take(size) else items
    const nextCursor = if (hasNext) content.last()?.id else null

    return Response.ok(Map.of(
        ["content", content],
        ["nextCursor", nextCursor],
        ["hasNext", hasNext]
    ))
}
```
