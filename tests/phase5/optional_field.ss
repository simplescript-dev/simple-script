// Test: optional field chaining (obj?.field)

class Config(host: string, port: int)

function getConfig(useNull: int): Config {
    if (useNull == 1) { return null }
    return new Config("localhost", 8080)
}

function main() {
    // Normal access via ?.
    const cfg = getConfig(0)
    const host = cfg?.host
    if (host != "localhost") { throw("normal optional field failed") }
    const port = cfg?.port
    if (port != 8080) { throw("normal optional port failed") }

    // Null access via ?. — returns "" for ptr, 0 for int
    const nullCfg = getConfig(1)
    const nullHost = nullCfg?.host
    if (nullHost != "") { throw("null optional field should be empty") }
    const nullPort = nullCfg?.port
    if (nullPort != 0) { throw("null optional int should be 0") }

    println("optional_field: all passed")
}
