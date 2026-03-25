# 60 - Validation Advanced (校验进阶)

## 设计理念

> 注解声明校验规则，编译器生成校验代码。来自 Java Bean Validation。

## 内置校验注解

```simplescript
import { Valid, NotBlank, NotNull, Email, Size, Min, Max,
         Pattern, Positive, PositiveOrZero, Past, Future } from "yummy/validation"

class CreateUserRequest(
    @NotBlank
    @Size(min: 2, max: 50)
    name: string,

    @NotBlank
    @Email
    email: string,

    @Min(0)
    @Max(150)
    age: int,

    @Size(min: 8, max: 64)
    @Pattern(regex: r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).*$",
             message: "must contain uppercase, lowercase and digit")
    password: string,

    @Past
    birthday: LocalDate?,

    @Positive
    salary: double?
)
```

## 在 Controller 中使用

```simplescript
@RestController
class UserController {

    @PostMapping("/users")
    function create(@Valid @RequestBody req: CreateUserRequest): Response {
        // @Valid 校验不通过自动返回 400:
        // {
        //   "errors": [
        //     {"field": "email", "message": "must be a valid email"},
        //     {"field": "password", "message": "must contain uppercase, lowercase and digit"}
        //   ]
        // }

        const user = userService.create(req)?
        return Response.created(user)
    }
}
```

## 自定义校验注解

```simplescript
import { Constraint, ConstraintValidator } from "yummy/validation"

// 1. 定义注解
@Constraint(validatedBy: PhoneValidator)
annotation class Phone(message: string = "invalid phone number")

// 2. 实现校验逻辑
class PhoneValidator : ConstraintValidator<Phone, string> {
    override function isValid(value: string): bool {
        return new Regex(r"^1[3-9]\d{9}$").matches(value)
    }
}

// 3. 使用
class ContactRequest(
    @Phone
    phone: string,

    @NotBlank
    name: string
)
```

## 分组校验

```simplescript
import { Group } from "yummy/validation"

// 不同场景校验不同字段
interface Create {}
interface Update {}

class UserRequest(
    @NotNull(groups: [Update])       // 更新时必填
    id: long?,

    @NotBlank(groups: [Create, Update])
    name: string,

    @NotBlank(groups: [Create])      // 创建时必填，更新时可选
    password: string?
)

@PostMapping("/users")
function create(@Valid(groups: [Create]) @RequestBody req: UserRequest): Response { }

@PutMapping("/users/:id")
function update(@Valid(groups: [Update]) @RequestBody req: UserRequest): Response { }
```

## 嵌套校验

```simplescript
class Address(
    @NotBlank city: string,
    @NotBlank street: string,
    @Pattern(regex: r"^\d{6}$") zipCode: string
)

class CreateOrderRequest(
    @NotNull userId: long,

    @Valid                        // 递归校验嵌套对象
    shippingAddress: Address,

    @Size(min: 1, message: "at least one item")
    items: List<OrderItem>
)
```

## 手动校验

```simplescript
import { Validator } from "yummy/validation"

function processData(data: SomeData): Result<void, List<ValidationError>> {
    const errors = Validator.validate(data)
    if (errors.isNotEmpty()) {
        return Result.Err(errors)
    }
    // 处理数据
    return Result.Ok(())
}
```
