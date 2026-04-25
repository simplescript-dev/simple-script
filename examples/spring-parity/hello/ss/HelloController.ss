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
}
