// com.zaxxer:HikariCP:7.0 — Connection Pool (SimpleScript Implementation)
// Simplified connection pool: pre-creates N connections, reuses them.

import { Connection, DriverManager } from "@/lib/java/sql"

// ── HikariConfig ─────────────────────────────────────────────

class HikariConfig {
    jdbcUrl: string
    maximumPoolSize: int

    function getJdbcUrl(): string { return this.jdbcUrl }
    function getMaximumPoolSize(): int { return this.maximumPoolSize }
}

// ── HikariDataSource ─────────────────────────────────────────
// For SQLite (single-file DB), pooling means reusing one connection.
// For MySQL/PostgreSQL (future), would maintain actual pool.

class HikariDataSource {
    config: HikariConfig
    conn: Connection

    function getConnection(): Connection {
        return this.conn
    }

    function close() {
        this.conn.close()
    }
}

function HikariDataSource_create(config: HikariConfig): HikariDataSource {
    const conn = DriverManager.getConnection(config.getJdbcUrl())
    return new HikariDataSource(config, conn)
}
