# 51 - Template Engine (模板引擎)

## 设计理念

> 内置模板引擎，支持 HTML 模板渲染。来自 Thymeleaf 的思路，但更简洁。
> 模板语法用 `${}` 插值，和 SimpleScript 模板字符串一致。

## 基本用法

```simplescript
import { Template } from "ss/template"

function main() {
    const tmpl = Template.load("templates/hello.html")
    const html = tmpl.render(Map.of(
        ["name", "Alice"],
        ["age", 30]
    ))
    println(html)
}
```

## 模板语法

```html
<!-- templates/hello.html -->
<!DOCTYPE html>
<html>
<head><title>${title}</title></head>
<body>
    <h1>Hello, ${name}!</h1>
    <p>You are ${age} years old.</p>
</body>
</html>
```

## 条件

```html
<!-- if -->
<div ss-if="${user != null}">
    <p>Welcome, ${user.name}</p>
</div>
<div ss-else>
    <p>Please login</p>
</div>
```

## 循环

```html
<!-- for -->
<ul>
    <li ss-for="${item in items}">
        ${item.name} - ${item.price}
    </li>
</ul>

<!-- 带索引 -->
<table>
    <tr ss-for="${(index, user) in users}">
        <td>${index + 1}</td>
        <td>${user.name}</td>
        <td>${user.email}</td>
    </tr>
</table>
```

## 布局与组件

```html
<!-- templates/layout.html -->
<!DOCTYPE html>
<html>
<head><title>${title}</title></head>
<body>
    <header ss-include="components/header.html"></header>
    <main>
        ${content}
    </main>
    <footer ss-include="components/footer.html"></footer>
</body>
</html>
```

```html
<!-- templates/pages/home.html -->
<div ss-layout="layout.html" ss-title="Home">
    <h1>Welcome</h1>
    <p>This is the home page.</p>
</div>
```

## 与 Web 框架集成

```simplescript
import { RestController, GetMapping } from "ss/web"
import { Template } from "ss/template"
import { Response } from "net/http"

@RestController
class PageController {

    @GetMapping("/")
    function home(): Response {
        return Response.html(Template.render("pages/home.html", Map.of(
            ["title", "Home"],
            ["users", userService.findAll()]
        )))
    }

    @GetMapping("/users/:id")
    function userProfile(@PathVariable id: long): Response {
        const user = userService.findById(id)
        if (user == null) return Response.notFound("user not found")

        return Response.html(Template.render("pages/profile.html", Map.of(
            ["user", user],
            ["orders", orderService.findByUser(id)]
        )))
    }
}
```

## 模板编译

```
模板在首次使用时编译为 SimpleScript 函数，后续调用直接执行。
不是运行时字符串替换，是编译后的原生代码。
```
