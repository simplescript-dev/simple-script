package hello;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

class User {
    public String name;
    public int age;
}

class Address {
    public String city;
    public String zip;
}

class Customer {
    public String name;
    public int age;
}

class Order {
    public Customer customer;
    public Address addr;
}

class Item {
    public String name;
    public int price;
}

class OrderList {
    public String customer;
    public List<Item> items;
}

class OrderPrim {
    public String customer;
    public List<String> tags;
    public List<Integer> scores;
    public List<Double> prices;
    public List<Boolean> flags;
}

class OrderCell {
    public int row;
    public int col;
    public String value;
}

class OrderMatrix {
    public String name;
    public List<List<Integer>> grid;
    public List<List<OrderCell>> cells;
    public List<List<String>> labels;
}

class DeepNest {
    public String name;
    public List<List<List<Integer>>> cube3i;
    public List<List<List<String>>> cube3s;
    public List<List<List<OrderCell>>> cube3c;
    public List<List<List<List<String>>>> tess4s;
    public List<List<List<List<List<Integer>>>>> pent5i;
}

class Tag {
    public String color;
    public int priority;
}

class OrderMeta {
    public String customer;
    public Map<String, Tag> metadata;
}

class OrderConfig {
    public String customer;
    public Map<String, String> tags;
    public Map<String, Integer> scores;
    public Map<String, Double> prices;
    public Map<String, Boolean> flags;
}

class BigOrder {
    public String customer;
    public Map<String, List<Integer>> iaGroups;
    public Map<String, List<String>> saGroups;
    public Map<String, List<Double>> daGroups;
    public Map<String, List<Boolean>> baGroups;
    public Map<String, List<Tag>> caGroups;
    public Map<String, Map<String, Integer>> iiMaps;
    public Map<String, Map<String, String>> ssMaps;
    public Map<String, Map<String, Double>> ddMaps;
    public Map<String, Map<String, Boolean>> bbMaps;
    public Map<String, Map<String, Tag>> ccMaps;
    public List<Map<String, Integer>> iMapList;
    public List<Map<String, String>> sMapList;
    public List<Map<String, Tag>> cMapList;
    public Map<String, Map<String, List<Integer>>> deepMix;
    public List<List<Map<String, Integer>>> deepMixR;
}

@RestController
public class HelloController {
    @GetMapping("/hello")
    public String hello(@RequestParam(name = "name") String name) {
        return "Hello, " + name + "!";
    }

    @GetMapping("/age")
    public String age(@RequestParam(name = "n") int n) {
        return "n=" + n;
    }

    @GetMapping("/calc")
    public String calc(@RequestParam(name = "x") double x) {
        return "x=" + x;
    }

    @GetMapping("/add")
    public String add(@RequestParam(name = "x") int x, @RequestParam(name = "y") int y) {
        return "sum=" + (x + y);
    }

    @GetMapping("/users/{id}")
    public String show(@PathVariable("id") Integer id) {
        return "user=" + id;
    }

    @PostMapping("/users")
    public String createUser(@RequestBody User user) {
        return "user=" + user.name + ",age=" + user.age;
    }

    @PostMapping("/orders")
    public String createOrder(@RequestBody Order order) {
        return "customer=" + order.customer.name + ",city=" + order.addr.city;
    }

    @PostMapping("/orders-list")
    public String createOrderList(@RequestBody OrderList order) {
        int total = 0;
        for (Item it : order.items) total += it.price;
        return "customer=" + order.customer + ",total=" + total;
    }

    @PostMapping("/orders-prim")
    public String createOrderPrim(@RequestBody OrderPrim order) {
        String tagSum = "";
        for (String t : order.tags) tagSum += t;
        int scoreSum = 0;
        for (Integer s : order.scores) scoreSum += s;
        return "customer=" + order.customer + ",tags=" + tagSum + ",scores=" + scoreSum;
    }

    @PostMapping("/matrix")
    public String createMatrix(@RequestBody OrderMatrix m) {
        int total = 0;
        for (List<Integer> row : m.grid) for (Integer v : row) total += v;
        return "name=" + m.name + ",total=" + total;
    }

    // parity smoke: only cube3i (N=3 int) + pent5i (N=5 int) suffice for byte-identical;
    // full 5-elemType coverage in tests/phase5/i021_requestbody_nested_deep.ss
    @PostMapping("/deep")
    public String createDeep(@RequestBody DeepNest d) {
        int isum = 0;
        for (List<List<Integer>> plane : d.cube3i)
            for (List<Integer> row : plane)
                for (Integer v : row) isum += v;
        int psum = 0;
        for (List<List<List<List<Integer>>>> p4 : d.pent5i)
            for (List<List<List<Integer>>> p3 : p4)
                for (List<List<Integer>> p2 : p3)
                    for (List<Integer> p1 : p2)
                        for (Integer v : p1) psum += v;
        return "name=" + d.name + ",isum=" + isum + ",psum=" + psum;
    }

    @PostMapping("/orders/meta")
    public String createOrderMeta(@RequestBody OrderMeta order) {
        int totalPriority = 0;
        for (Tag t : order.metadata.values()) totalPriority += t.priority;
        Tag urgent = order.metadata.get("urgent");
        if (urgent != null) {
            return "customer=" + order.customer + ",urgent.color=" + urgent.color + ",size=" + order.metadata.size() + ",total=" + totalPriority;
        }
        return "customer=" + order.customer + ",size=" + order.metadata.size() + ",total=" + totalPriority;
    }

    // I021-requestbody-nested-map-primitive(D130) — Map<string, primitive value> 4 vType
    // 反序列化 enterprise REST API 高频形态(K8s ConfigMap / Stripe metadata / AWS tags / config
    // store)。spring-parity smoke 仅消耗 string + int 二路(env / qty)维度,避 double / bool 跨语言
    // 格式差异;full 4-vType coverage 在 tests/phase5/i021_requestbody_nested_map_primitive.ss。
    @PostMapping("/orders/config")
    public String createOrderConfig(@RequestBody OrderConfig order) {
        String envS = order.tags.getOrDefault("env", "");
        Integer qty = order.scores.getOrDefault("qty", 0);
        return "customer=" + order.customer + ",sizes=" + order.tags.size() + "/" + order.scores.size() + "/" + order.prices.size() + "/" + order.flags.size() + ",env=" + envS + ",qty=" + qty;
    }

    // I021-requestbody-nested-cartesian(D130) — 嵌套 collection 笛卡尔积 SSoT 端到端锁定
    // spring-parity smoke 仅消耗 customer + 16 sizes 维度(避跨语言 double / bool / 嵌套 toString
    //   格式差异);full 15 cell cover 在 tests/phase5/i021_requestbody_nested_cartesian.ss。
    @PostMapping("/orders/cartesian")
    public String createBigOrder(@RequestBody BigOrder order) {
        return "customer=" + order.customer + ",sizes=" + order.iaGroups.size() + "/" + order.saGroups.size() + "/" + order.daGroups.size() + "/" + order.baGroups.size() + "/" + order.caGroups.size() + "/" + order.iiMaps.size() + "/" + order.ssMaps.size() + "/" + order.ddMaps.size() + "/" + order.bbMaps.size() + "/" + order.ccMaps.size() + "/" + order.iMapList.size() + "/" + order.sMapList.size() + "/" + order.cMapList.size() + "/" + order.deepMix.size() + "/" + order.deepMixR.size();
    }

    @GetMapping("/agent")
    public String agent(@RequestHeader("User-Agent") String ua) {
        return "ua=" + ua;
    }
}
