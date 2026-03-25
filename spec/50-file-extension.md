# 50 - File Extension & MIME (文件扩展名与约定)

## 文件扩展名

```
.ss             SimpleScript 源代码文件
.test.ss        测试文件
.ss.json        ss.json 项目配置 (实际文件名就是 ss.json)
.ss.lock        依赖锁文件 (实际文件名就是 ss.lock)
```

## 文件命名

```
snake_case.ss            普通源文件
user_service.ss          按类名命名
user_controller.ss       按角色命名
user_service.test.ss     测试文件跟随源文件命名
```

## 项目约定

```
src/                     源代码目录
test/                    测试目录
resources/               配置和静态资源
target/                  构建产物 (自动生成)
ss.json                  项目配置
ss.lock                  依赖锁 (自动生成)
```

## 一个文件可以包含

```simplescript
// 一个文件可以有多个 class、function、常量
// 但建议: 一个 export class 一个文件

export class User(name: string, age: int) {
    function greet(): string = `hello, ${name}`
}

// 同文件的辅助类型 (不 export)
enum UserStatus { Active, Inactive, Banned }

// 同文件的辅助函数 (不 export)
function validateName(name: string): bool {
    return name.length > 0 && name.length <= 50
}
```

## 入口文件

```
可执行项目:   src/main.ss 中必须有 function main()
库项目:       无 main 函数，通过 export 暴露 API
```
