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

class OrderCell {
    row: int
    col: int
    value: string
}

class OrderMatrix {
    name: string
    grid: Array<Array<int>>
    cells: Array<Array<OrderCell>>
    labels: Array<Array<string>>
}

class DeepNest {
    name: string
    cube3i: Array<Array<Array<int>>>
    cube3s: Array<Array<Array<string>>>
    cube3c: Array<Array<Array<OrderCell>>>
    tess4s: Array<Array<Array<Array<string>>>>
    pent5i: Array<Array<Array<Array<Array<int>>>>>
}

class Tag {
    color: string
    priority: int
}

class OrderMeta {
    customer: string
    metadata: Map<string, Tag>
}

class OrderConfig {
    customer: string
    tags: Map<string, string>
    scores: Map<string, int>
    prices: Map<string, double>
    flags: Map<string, bool>
}

class BigOrder {
    customer: string
    iaGroups: Map<string, Array<int>>
    saGroups: Map<string, Array<string>>
    daGroups: Map<string, Array<double>>
    baGroups: Map<string, Array<bool>>
    caGroups: Map<string, Array<Tag>>
    iiMaps: Map<string, Map<string, int>>
    ssMaps: Map<string, Map<string, string>>
    ddMaps: Map<string, Map<string, double>>
    bbMaps: Map<string, Map<string, bool>>
    ccMaps: Map<string, Map<string, Tag>>
    iMapList: Array<Map<string, int>>
    sMapList: Array<Map<string, string>>
    cMapList: Array<Map<string, Tag>>
    deepMix: Map<string, Map<string, Array<int>>>
    deepMixR: Array<Array<Map<string, int>>>
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

    @PostMapping(path = "/matrix")
    function createMatrix(@RequestBody m: OrderMatrix): string {
        let total = 0
        let i = 0
        while (i < m.grid.length()) {
            let row = m.grid[i]
            let j = 0
            while (j < row.length()) {
                total = total + row[j]
                j = j + 1
            }
            i = i + 1
        }
        return "name=" + m.name + ",total=" + total
    }

    // parity smoke: 仅消耗 cube3i (N=3 int) + pent5i (N=5 int 极限) 两路足以验证
    // byte-identical Java 行为;全 5 elemType cover 在 tests/phase5/i021_requestbody_nested_deep.ss
    @PostMapping(path = "/deep")
    function createDeep(@RequestBody d: DeepNest): string {
        let isum = 0
        let i = 0
        while (i < d.cube3i.length()) {
            let plane = d.cube3i[i]
            let j = 0
            while (j < plane.length()) {
                let row = plane[j]
                let k = 0
                while (k < row.length()) {
                    isum = isum + row[k]
                    k = k + 1
                }
                j = j + 1
            }
            i = i + 1
        }
        let psum = 0
        let pi = 0
        while (pi < d.pent5i.length()) {
            let p4 = d.pent5i[pi]
            let pj = 0
            while (pj < p4.length()) {
                let p3 = p4[pj]
                let pk = 0
                while (pk < p3.length()) {
                    let p2 = p3[pk]
                    let pl = 0
                    while (pl < p2.length()) {
                        let p1 = p2[pl]
                        let pm = 0
                        while (pm < p1.length()) {
                            psum = psum + p1[pm]
                            pm = pm + 1
                        }
                        pl = pl + 1
                    }
                    pk = pk + 1
                }
                pj = pj + 1
            }
            pi = pi + 1
        }
        return "name=" + d.name + ",isum=" + isum + ",psum=" + psum
    }

    // I021-requestbody-nested-map(D130) — Map<string, UserClass> 反序列化:enterprise REST API
    // metadata / tags / 自定义键值对(K8s ConfigMap、Stripe metadata、AWS tags 高频形态);
    // size + total 求和顺序无关 byte-identical Java HashMap 遍历;.get("urgent") 单 key 命中
    // 直接对齐 Java Map.get。
    @PostMapping(path = "/orders/meta")
    function createOrderMeta(@RequestBody order: OrderMeta): string {
        let totalPriority = 0
        const keys = order.metadata.keys()
        let i = 0
        while (i < keys.length()) {
            const t = order.metadata.get(keys[i])
            if (t != null) {
                totalPriority = totalPriority + t.priority
            }
            i = i + 1
        }
        const urgent = order.metadata.get("urgent")
        if (urgent != null) {
            return "customer=" + order.customer + ",urgent.color=" + urgent.color + ",size=" + order.metadata.size() + ",total=" + totalPriority
        }
        return "customer=" + order.customer + ",size=" + order.metadata.size() + ",total=" + totalPriority
    }

    // I021-requestbody-nested-map-primitive(D130) — Map<string, primitive value> 4 vType
    // 反序列化 enterprise REST API 高频形态(K8s ConfigMap / Stripe metadata / AWS tags / config
    // store)。spring-parity smoke 仅消耗 string + int 二路(env / qty)维度避 double / bool 跨语言
    // ss_double_to_string vs Double.toString 格式差异;全 4 vType cover 在
    // tests/phase5/i021_requestbody_nested_map_primitive.ss(本测试 OrderConfigCtl 内闭环)。
    @PostMapping(path = "/orders/config")
    function createOrderConfig(@RequestBody order: OrderConfig): string {
        const envS = order.tags.get("env")
        const qty = order.scores.get("qty")
        return "customer=" + order.customer + ",sizes=" + order.tags.size() + "/" + order.scores.size() + "/" + order.prices.size() + "/" + order.flags.size() + ",env=" + envS + ",qty=" + qty
    }

    // I021-requestbody-nested-cartesian(D130) — 嵌套 collection 笛卡尔积 SSoT 端到端锁定
    // 15 cell 笛卡尔积:Map<string, Array<X>>×5 + Map<string, Map<string, Y>>×5 +
    //   Array<Map<string, X>>×3 + N=3 混合×2(Map→Map→Array + Array→Array→Map)。
    // spring-parity smoke 仅消耗 customer + 16 sizes 维度(避跨语言 double / bool / 嵌套
    //   toString 格式差异);full 15 cell cover 在 tests/phase5/i021_requestbody_nested_cartesian.ss
    //   (本测试 BigOrderCtl 内闭环)。
    @PostMapping(path = "/orders/cartesian")
    function createBigOrder(@RequestBody order: BigOrder): string {
        return "customer=" + order.customer + ",sizes=" + order.iaGroups.size() + "/" + order.saGroups.size() + "/" + order.daGroups.size() + "/" + order.baGroups.size() + "/" + order.caGroups.size() + "/" + order.iiMaps.size() + "/" + order.ssMaps.size() + "/" + order.ddMaps.size() + "/" + order.bbMaps.size() + "/" + order.ccMaps.size() + "/" + order.iMapList.length() + "/" + order.sMapList.length() + "/" + order.cMapList.length() + "/" + order.deepMix.size() + "/" + order.deepMixR.length()
    }

    @GetMapping(path = "/agent")
    function agent(@RequestHeader(name = "user-agent") ua: string): string {
        return "ua=" + ua
    }
}
