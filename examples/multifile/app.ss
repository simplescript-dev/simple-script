import { AppConfig } from "./config"
import { info, warn, error } from "./logger"

function main() {
    const config = new AppConfig("MyApp", "1.0.0", 1)
    config.display()

    println("")
    info("Application started")
    info("Loading data...")
    warn("Cache miss, fetching from disk")
    info("Data loaded: 42 records")
    error("Connection timeout (will retry)")
    info("Retry successful")
    info("Application ready")
}
