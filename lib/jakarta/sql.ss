// jakarta.sql — DataSource Interface (SimpleScript Implementation)
// Mirrors: javax.sql.DataSource → jakarta.sql.DataSource (Jakarta EE 9+)

import { Connection, DriverManager } from "@/lib/java/sql"

// ── DataSource ───────────────────────────────────────────────
// Abstract database connection factory.
// Implementations: HikariDataSource, SimpleDataSource (direct)

interface DataSource {
    function getConnection(): Connection
}

// ── SimpleDataSource (no pooling, direct connection) ─────────

class SimpleDataSource : DataSource {
    url: string

    function getConnection(): Connection {
        return DriverManager.getConnection(this.url)
    }
}
