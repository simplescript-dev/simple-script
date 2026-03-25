# 13 - Annotation Layers (注解分层)

## 设计决策

> 语言只内置机制，不内置策略。框架级注解由标准库提供，官方维护但可替换。

## 两层架构

### 语言内置 (编译器实现)

```simplescript
// 纯语言特性，编译器直接处理
@Export                          // C ABI 导出
@Builder                         // 生成 Builder 模式
@Deprecated("msg")               // 废弃标记
annotation class                 // 自定义注解的机制
```

### 官方包 (独立维护，ym new 默认带)

```
yummy/web          → @RestController, @GetMapping, @PostMapping, ...
yummy/di           → @Service, @Component, @Configuration
dev/db             → @Table, @Id, @Column, @ForeignKey, ...
encoding/json      → @JsonProperty, @JsonIgnore, @JsonFormat
yummy/validation   → @Valid, @NotBlank, @Email, @Min, @Max
yummy/cache        → @Cacheable, @CacheEvict
dev/db/tx          → @Transactional
dev/log            → @Slf4j
yummy/auth         → @RequiresRole, @RequiresPermission
yummy/schedule     → @Scheduled
```

## 用法

```simplescript
// 标准库注解和语言内置注解写法完全一样，体验无差别
import { RestController, GetMapping, PostMapping } from "yummy/web"
import { Service } from "yummy/di"
import { Table, Id } from "dev/db"

@Table("users")
class User(
    @Id id: long,
    name: string
)

@Service
class UserService(db: Database) {
    function findById(id: long): User? {
        return db.find<User>(id)
    }
}

@RestController
@RequestMapping("/api/users")
class UserController(userService: UserService) {
    @GetMapping("/:id")
    function get(@PathVariable id: long): Response {
        const user = userService.findById(id)
        return switch (user) {
            case User u -> Response.ok(u)
            default -> Response.notFound("not found")
        }
    }
}
```

## 好处

```
✓ 编译器不膨胀 — 只管注解机制，不管具体注解
✓ 统一体验 — ym new 默认带标准库，开箱即用
✓ 可替换 — 不喜欢 web 包可以用第三方 web 框架
✓ 独立更新 — web 包升版不需要升级编译器
✓ 编译期处理 — 标准库注解也是编译期生成代码，零反射
```
