// Test: const field — mutable field operations only
// (const field compile error is verified manually with ss check)
class Config(name: string, value: int, enabled: int)

function toggle(c: Config) {
    if (c.enabled == 1) {
        c.enabled = 0
    } else {
        c.enabled = 1
    }
}

function main() {
    let cfg = new Config("debug", 42, 1)
    if (cfg.name != "debug") { exit(1) }
    if (cfg.value != 42) { exit(1) }
    if (cfg.enabled != 1) { exit(1) }
    // Mutable field assignment
    cfg.value = 100
    if (cfg.value != 100) { exit(1) }
    // Function mutation through shared ref
    toggle(cfg)
    if (cfg.enabled != 0) { exit(1) }
    toggle(cfg)
    if (cfg.enabled != 1) { exit(1) }
    println("const_field: all passed")
}
