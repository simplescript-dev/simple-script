import { Log } from "@/lib/log"

function main() {
    // Test default level is INFO
    if (Log.getLevel() != 1) { exit(1) }

    // Test all log levels output (default = INFO, so debug suppressed)
    Log.debug("should not appear")
    Log.info("info message")
    Log.warn("warning message")
    Log.error("error message")
    Log.fatal("fatal message")

    // Test setLevel to DEBUG — all messages visible
    Log.setLevel(0)
    if (Log.getLevel() != 0) { exit(1) }
    Log.debug("debug visible now")

    // Test setLevel to ERROR — only ERROR and FATAL
    Log.setLevel(3)
    Log.debug("suppressed")
    Log.info("suppressed")
    Log.warn("suppressed")
    Log.error("error visible")
    Log.fatal("fatal visible")

    // Test isEnabled
    if (Log.isEnabled(3) != 1) { exit(1) }
    if (Log.isEnabled(4) != 1) { exit(1) }
    if (Log.isEnabled(2) != 0) { exit(1) }
    if (Log.isEnabled(0) != 0) { exit(1) }

    // Test level OFF — nothing logs
    Log.setLevel(5)
    Log.debug("suppressed")
    Log.info("suppressed")
    Log.warn("suppressed")
    Log.error("suppressed")
    Log.fatal("suppressed")

    // Test color disable
    Log.setLevel(0)
    Log.enableColor(0)
    Log.info("plain text info")
    Log.error("plain text error")

    // Test color re-enable
    Log.enableColor(1)
    Log.info("colored again")

    // Test generic log method
    Log.log(0, "generic debug")
    Log.log(1, "generic info")
    Log.log(2, "generic warn")
    Log.log(3, "generic error")
    Log.log(4, "generic fatal")

    // Test generic log with out-of-range level
    Log.log(99, "high level falls to fatal")

    // Reset and final check
    Log.setLevel(1)
    if (Log.getLevel() != 1) { exit(1) }
    Log.info("all tests passed")
}
