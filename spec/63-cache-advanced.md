# 63 - Cache Advanced (缓存进阶)

## 设计理念

> 注解声明缓存策略，底层可插拔（内存、Redis）。
> 来自 Spring Cache 的 @Cacheable 体验。

## 注解缓存

```simplescript
import { Cacheable, CacheEvict, CachePut, CacheConfig } from "ss/cache"
import { Service } from "ss/di"

@Service
@CacheConfig(name: "users", ttl: 3600)
class UserService(db: Database) {

    // 查询结果自动缓存，相同参数直接返回缓存
    @Cacheable
    function findById(id: long): User? {
        return db.find<User>(id)
    }

    // 更新时同步更新缓存
    @CachePut
    function update(user: User): User {
        return db.update(user)
    }

    // 删除时清除缓存
    @CacheEvict
    function deleteById(id: long) {
        db.delete<User>(id)
    }

    // 清除该缓存组的所有条目
    @CacheEvict(allEntries: true)
    function clearAll() {
        // 不需要实现
    }
}
```

## 多级缓存

```simplescript
import { Cache, LocalCache, RedisCache, MultiLevelCache } from "ss/cache"

// L1: 本地内存 (毫秒级) + L2: Redis (跨实例共享)
@Configuration
class CacheConfig {
    function cacheManager(): CacheManager {
        return new MultiLevelCache(
            l1: new LocalCache(maxSize: 1000, ttl: 60),
            l2: new RedisCache(host: "localhost", port: 6379, ttl: 3600)
        )
    }
}
```

## 手动操作缓存

```simplescript
import { CacheManager } from "ss/cache"

@Service
class ProductService(cache: CacheManager) {

    function getProduct(id: long): Product? {
        // 手动读
        const cached = cache.get<Product>("products", id.toString())
        if (cached != null) return cached

        // 查库
        const product = db.find<Product>(id)
        if (product != null) {
            // 手动写
            cache.put("products", id.toString(), product, ttl: 1800)
        }
        return product
    }

    function batchInvalidate(ids: List<long>) {
        for (id in ids) {
            cache.evict("products", id.toString())
        }
    }
}
```

## 配置

```yaml
# application.yml
cache:
  type: redis                # memory | redis
  redis:
    host: localhost
    port: 6379
    password: ""
    database: 0
    prefix: "myapp:"
  defaults:
    ttl: 3600                # 默认 1 小时
    maxSize: 10000           # 本地缓存最大条目
```
