# 59 - Session & Cookie (会话与Cookie)

## 设计理念

> HTTP 是无状态的，Session 和 Cookie 是 Web 应用的基础。
> 注解注入，自动管理生命周期。

## Cookie

```simplescript
import { Request, Response } from "net/http"
import { Cookie } from "ss/web"

@RestController
class AuthController {

    @PostMapping("/login")
    function login(@RequestBody creds: LoginRequest): Response {
        const user = authService.authenticate(creds)?

        const token = generateToken(user)
        const cookie = new Cookie("token", token)
            .httpOnly(true)
            .secure(true)
            .maxAge(86400)           // 1 天
            .path("/")
            .sameSite("Strict")

        return Response.ok(user).cookie(cookie)
    }

    @PostMapping("/logout")
    function logout(): Response {
        // maxAge(0) 删除 cookie
        const cookie = new Cookie("token", "").maxAge(0).path("/")
        return Response.ok("logged out").cookie(cookie)
    }

    @GetMapping("/me")
    function me(@CookieValue("token") token: string?): Response {
        if (token == null) return Response.unauthorized("not logged in")
        const user = authService.verifyToken(token)?
        return Response.ok(user)
    }
}
```

## Session

```simplescript
import { Session } from "ss/web"

@RestController
class CartController {

    @PostMapping("/cart/add")
    function addToCart(session: Session, @RequestBody item: CartItem): Response {
        let cart = session.get<List<CartItem>>("cart") ?? List.of()
        cart = cart + item
        session.set("cart", cart)
        return Response.ok(Map.of(["cartSize", cart.size()]))
    }

    @GetMapping("/cart")
    function viewCart(session: Session): Response {
        const cart = session.get<List<CartItem>>("cart") ?? List.of()
        return Response.ok(cart)
    }

    @DeleteMapping("/cart")
    function clearCart(session: Session): Response {
        session.remove("cart")
        return Response.ok("cart cleared")
    }
}
```

## Session 存储

```yaml
# application.yml
session:
  store: memory          # memory | redis | database
  timeout: 1800          # 30 分钟
  cookieName: YMSESSID

  # Redis 存储
  # store: redis
  # redis:
  #   host: localhost
  #   port: 6379

  # 数据库存储
  # store: database
  # table: sessions
```
