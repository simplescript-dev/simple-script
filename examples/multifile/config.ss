class AppConfig(name: string, version: string, debug: int) {
    function display() {
        println(this.name + " v" + this.version)
        if (this.debug == 1) {
            println("  [debug mode]")
        }
    }
}
