// SimpleScript Log Library — structured logging with levels and colors
//
// Usage:
//   import { Log } from "@/lib/log"
//
//   Log.info("server started")           // [INFO ] server started
//   Log.error("connection failed")       // [ERROR] connection failed
//   Log.setLevel(2)                      // only WARN and above
//   Log.debug("skipped")                 // (suppressed)
//   Log.enableColor(0)                   // disable ANSI colors
//
// Levels: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL, 5=OFF
// Default level: INFO (1). Default colors: on.

class Log()

// ── Internal state ───────────────────────────────────────────

let logLevel = 1
let logColorOn = 1

// ── Internal helpers ─────────────────────────────────────────

function logOutput(level: int, label: string, colorCode: int, msg: string) {
    if (level < logLevel) { return }
    if (logColorOn == 1) {
        const esc = fromCharCode(27)
        println(`${esc}[${colorCode}m[${label}]${esc}[0m ${msg}`)
    } else {
        println(`[${label}] ${msg}`)
    }
}

// ── Log level methods ────────────────────────────────────────

// Debug level (0) — detailed diagnostic info, cyan
function Log_debug(msg: string) {
    logOutput(0, "DEBUG", 36, msg)
}

// Info level (1) — general informational messages, green
function Log_info(msg: string) {
    logOutput(1, "INFO ", 32, msg)
}

// Warn level (2) — potential issues, yellow
function Log_warn(msg: string) {
    logOutput(2, "WARN ", 33, msg)
}

// Error level (3) — error conditions, red
function Log_error(msg: string) {
    logOutput(3, "ERROR", 31, msg)
}

// Fatal level (4) — critical failures, bright red
function Log_fatal(msg: string) {
    logOutput(4, "FATAL", 91, msg)
}

// ── Generic log ──────────────────────────────────────────────

// Log at a given level (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL)
function Log_log(level: int, msg: string) {
    if (level == 0) {
        Log_debug(msg)
    } else if (level == 1) {
        Log_info(msg)
    } else if (level == 2) {
        Log_warn(msg)
    } else if (level == 3) {
        Log_error(msg)
    } else {
        Log_fatal(msg)
    }
}

// ── Configuration ────────────────────────────────────────────

// Set minimum log level (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=FATAL, 5=OFF)
function Log_setLevel(level: int) {
    logLevel = level
}

// Get current minimum log level
function Log_getLevel(): int {
    return logLevel
}

// Enable (1) or disable (0) ANSI color output
function Log_enableColor(on: int) {
    logColorOn = on
}

// Check if a given level would produce output at current settings
function Log_isEnabled(level: int): int {
    if (level >= logLevel) {
        return 1
    }
    return 0
}
