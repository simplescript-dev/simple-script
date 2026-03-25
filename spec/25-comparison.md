# 25 - Language Comparison (语言对比)

## SimpleScript vs 其他语言

### Hello World 对比

```simplescript
// SimpleScript
function main() {
    println("hello, world!")
}
```

```java
// Java
public class Main {
    public static void main(String[] args) {
        System.out.println("hello, world!");
    }
}
```

```go
// Go
package main
import "fmt"
func main() {
    fmt.Println("hello, world!")
}
```

```rust
// Rust
fn main() {
    println!("hello, world!");
}
```

### HTTP API 对比

```simplescript
// SimpleScript — 13 行
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

```java
// Java + Spring Boot — 20 行
@RestController
@RequestMapping("/api/users")
public class UserController {
    @Autowired
    private UserService userService;

    @GetMapping("/{id}")
    public ResponseEntity<?> get(@PathVariable Long id) {
        User user = userService.findById(id);
        if (user != null) {
            return ResponseEntity.ok(user);
        }
        return ResponseEntity.notFound().build();
    }
}
```

```go
// Go + Gin — 18 行
func getUser(c *gin.Context) {
    id := c.Param("id")
    user, err := userService.FindById(id)
    if err != nil {
        c.JSON(404, gin.H{"error": "not found"})
        return
    }
    c.JSON(200, user)
}

func main() {
    r := gin.Default()
    r.GET("/api/users/:id", getUser)
    r.Run(":8080")
}
```

## 量化对比

| 指标 | SimpleScript | Java | Go | Rust | Node.js |
|------|----------|------|----|------|---------|
| Hello World 二进制 | ~100KB | ~需要 JVM | ~2MB | ~300KB | ~需要 V8 |
| 启动时间 | <1ms | 100ms~几秒 | <1ms | <1ms | ~50ms |
| 内存管理 | ARC | GC | GC | 所有权 | GC |
| GC 停顿 | 无 | 有 | 有 | 无 | 有 |
| 空安全 | 编译期 | 可选注解 | 无 | 编译期 | 无 |
| 泛型 | 单态化 | 擦除 | 单态化 | 单态化 | 动态类型 |
| 并发 | 虚拟线程 | 虚拟线程 | goroutine | async | 事件循环 |
| 学习曲线 | 低 | 中 | 低 | 高 | 低 |
| Web 框架 | 语言标准库 | Spring(框架) | 标准库+框架 | 框架 | Express(框架) |

## SimpleScript 的独特优势

```
1. Java 的可读性 + Rust 的性能 + Go 的简洁
2. 框架级功能内置为标准库，开箱即用
3. 编译到单个静态二进制，FROM scratch 部署
4. 无 GC 停顿，确定性内存释放
5. 编译期消除空指针、SQL 注入、数据竞争
6. 虚拟线程: 同步写法，百万并发
7. C 库直接调用，零胶水代码
```
