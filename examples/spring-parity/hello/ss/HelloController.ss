class User {
    name: string
    age: int
}

class Address {
    city: string
    zip: string
}

class Customer {
    name: string
    age: int
}

class Order {
    customer: Customer
    addr: Address
}

@RestController
class HelloController {
    @GetMapping(path = "/hello")
    function hello(@RequestParam(name = "name") name: string): string {
        return "Hello, " + name + "!"
    }

    @GetMapping(path = "/age")
    function age(@RequestParam(name = "n") n: int): string {
        return "n=" + n
    }

    @GetMapping(path = "/calc")
    function calc(@RequestParam(name = "x") x: double): string {
        return "x=" + x
    }

    @GetMapping(path = "/add")
    function add(@RequestParam(name = "x") x: int, @RequestParam(name = "y") y: int): string {
        return "sum=" + (x + y)
    }

    @GetMapping(path = "/users/{id}")
    function show(@PathVariable(name = "id") id: int): string {
        return "user=" + id
    }

    @PostMapping(path = "/users")
    function createUser(@RequestBody user: User): string {
        return "user=" + user.name + ",age=" + user.age
    }

    @PostMapping(path = "/orders")
    function createOrder(@RequestBody order: Order): string {
        return "customer=" + order.customer.name + ",city=" + order.addr.city
    }

    @GetMapping(path = "/agent")
    function agent(@RequestHeader(name = "user-agent") ua: string): string {
        return "ua=" + ua
    }
}
