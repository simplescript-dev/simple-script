package hello;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

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

    @GetMapping("/agent")
    public String agent(@RequestHeader("User-Agent") String ua) {
        return "ua=" + ua;
    }
}
