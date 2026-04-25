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

class Item {
    name: string
    price: int
}

class OrderList {
    customer: string
    items: Array<Item>
}

class OrderPrim {
    customer: string
    tags: Array<string>
    scores: Array<int>
    prices: Array<double>
    flags: Array<bool>
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

    @PostMapping(path = "/orders-list")
    function createOrderList(@RequestBody order: OrderList): string {
        let total = 0
        let i = 0
        while (i < order.items.length()) {
            total = total + order.items[i].price
            i = i + 1
        }
        return "customer=" + order.customer + ",total=" + total
    }

    @PostMapping(path = "/orders-prim")
    function createOrderPrim(@RequestBody order: OrderPrim): string {
        let tagSum = ""
        let i = 0
        while (i < order.tags.length()) {
            tagSum = tagSum + order.tags[i]
            i = i + 1
        }
        let scoreSum = 0
        let j = 0
        while (j < order.scores.length()) {
            scoreSum = scoreSum + order.scores[j]
            j = j + 1
        }
        return "customer=" + order.customer + ",tags=" + tagSum + ",scores=" + scoreSum
    }

    @GetMapping(path = "/agent")
    function agent(@RequestHeader(name = "user-agent") ua: string): string {
        return "ua=" + ua
    }
}
