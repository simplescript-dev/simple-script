// spring-boot-starter-data-jpa — Auto-configuration
// Provides convenient repository creation with default SQLite backend.

import { JpaRepository, JpaRepositoryFactory } from "@/lib/spring/data"

let defaultDbUrl = "sqlite:./data.db"

function setDatabaseUrl(url: string) {
    defaultDbUrl = url
}

function createRepository(tableName: string, columns: string): JpaRepository {
    return JpaRepositoryFactory.create(defaultDbUrl, tableName, columns)
}
