package hello;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

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

    @GetMapping("/agent")
    public String agent(@RequestHeader("User-Agent") String ua) {
        return "ua=" + ua;
    }
}
