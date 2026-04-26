# D135: MySQL caching_sha2_password fast-path 直发模式

**Status:** [✓] Phase 0 落盘 / [ ] Phase 1+2 待 Execute(Plan / Decision Layer)

**Depends on:**
- D134 全 Phase 收关锚(commit `e509be1`)— `lib/com/mysql/{wire,handshake,query,jdbc}.ss` driver-agnostic 实施层 + `tests/d134_mysql/` integration test 框架
- CLAUDE.md §项目本质 L7 axiom("应用层 stdlib 用纯 SS 模块实现,不引入应用层 C 库")
- CLAUDE.md §项目技术规则 §Root Cause 优先 L91-103("第一法则,无例外")
- CLAUDE.md §项目技术规则 §交互式单文档(用户对话授权 "做1" + "只兼容最新版,不必兼容那些旧的" + "自己用 / 最新最优")
- D025 Interface Dispatch
- `memory/feedback_root_cause_no_cost.md` / `memory/feedback_no_derive_workaround.md`(成本不是选次优 / 不留 fallback dead code)
- `docs/3-MNK.md` §M PSM 九问 / §N VCM 六验 / §大改档位规则

**承 D134 §6 follow-up ① 候选 + 用户授权范围简化** — 用户对话指令 2026-04-26: "我只需要兼容最新版的就行,不必兼容那些旧的" → D135 = caching_sha2_password fast-path **直发模式** + **删除 mysql_native_password 实施层**(D134 落地代码,自用语境下变 dead code)

**Date:** 2026-04-26
**Last Updated:** 2026-04-26

---

## 第一性需求

CLAUDE.md §项目本质 axiom 兑现深化 — D134 落地 mysql_native_password 实施层 + docker `--default-authentication-plugin=mysql_native_password` server-side 切换才能跑,这是为兼容 MySQL 5.x 时代 plugin 决策。

但 MySQL 8+ 默认 plugin = `caching_sha2_password`(8.0 起,2018-04-19 GA)+ 用户语境"自用 + 只兼容最新版" → mysql_native_password 路径变 dead code,**删除 fallback 走根因方案**(承 §Root Cause 优先 + memory `feedback_no_derive_workaround`)。

**单一判据**(机械,承 D134 §核心目标"axiom 不是文字,是 grep 输出"口号):

```bash
# caching_sha2 fast-path 实施(本 D Phase 1 GREEN 收敛)
grep -nE "cachingSha2Scramble|caching_sha2_password|fast_auth_success" lib/com/mysql/handshake.ss | wc -l
# 当前 = 0,目标 ≥ 5

# mysql_native_password dead code 删除(本 D Phase 2 GREEN 收敛)
grep -rnE "mysqlNativePasswordScramble|mysql_native_password" lib/com/mysql/ tests/d134_mysql/ | wc -l
# 当前 ≥ 6(handshake.ss scramble fn + plugin literal + handshake_test 4 vec + docker --default-authentication-plugin)
# 目标 = 0(全替换 + dead code 删)

# axiom 红线维持(永久)
grep -rn "libmysqlclient\|libssl\|RSA_\|EVP_PKEY" bootstrap/ lib/ build.sh | wc -l
nm bin/ss | grep -c -E "RSA_|EVP_"
# 永久 = 0

# 集成测试 e2e
bin/ss test tests/d135_caching_sha2/
bin/ss test tests/d134_mysql/
# 双绿(D134 e2e 8 case 在 caching_sha2 切换后仍绿,plugin 对 application layer 透明)
```

---

## 核心目标 (Goal)

- **为什么**:MySQL 8 默认 plugin = caching_sha2_password,D134 mysql_native 实施层是 MySQL 5.x 时代决策,用户自用语境"只兼容最新版" → 走根因 + 删 dead code,axiom 兑现度由 "需 docker plugin 切换" → "MySQL 8 默认配置开箱即用"
- **是什么**:HandshakeResponse41 直发 caching_sha2_password plugin name + 32-byte SHA-256 chained scramble + 处理 server fast-path 响应(0x01 0x03 / 0x01 0x04 / 0x00 / 0xFF / 0xFE),**删除 D134 mysqlNativePasswordScramble + scramble vec test + docker --default-authentication-plugin=mysql_native_password 配置**
- **单一判据**:三轨闭环(§第一性需求 中三个 grep / nm / test 命令)+ `./build.sh bootstrap` 三阶段固定点(Phase 1 纯 lib 改不动 bootstrap)+ D134 `tests/d134_mysql/` 8 case e2e 在 caching_sha2 切换后仍绿(plugin 对 application layer 透明)

> 口号:**只兼容最新的最优的 = 删 fallback dead code 走根因**(承用户对话指令 + Root Cause 第一法则)

---

## 核心原则 (Principles)

1. **caching_sha2 直发不走 AuthSwitch round-trip** — HandshakeResponse41 plugin name 直填 caching_sha2_password,真 fast-path(单 round-trip),不走 D134 §A.2 提的 server-driven AuthSwitchRequest 兼容路径
2. **mysql_native_password 路径删除不留 fallback dead code** — 承 §Root Cause 优先 + memory feedback_no_derive_workaround;用户自用场景明确"只兼容最新版",MySQL 5.x 不在 scope
3. **caching_sha2 full authentication 永远不做** — RSA-OAEP 工程量爆 ≥ 1000 LOC + 数学复杂度高 + axiom 例外风险;user 缓存命中即可绕开(MySQL server 端自动缓存 fast_auth_success 状态,首次 connect cache miss 触发 0x01 0x04 → 改密码或 server cache 预热即可)
4. **TLS 永远不做** — 跨 axiom 红线 + 工程量 > 5000 LOC + 自用场景 localhost / 内网免 TLS
5. **AuthSwitchRequest (0xFE) 显式 ERR 不解析 plugin name** — server 发 AuthSwitchRequest 是 client/server 协议不匹配场景(MySQL < 5.6 / 古怪 plugin 配置),scope 控不解析,直接 errMsg 拒绝(沿 D134 Phase 3 errMsg 范式)
6. **复用 lib/crypto.ss SHA-256 不新建 lib/sha2.ss** — `sha256flex` 已存在(L239)+ `Crypto.sha256` (L504),承 D134 Phase 2 复用决策(SHA-1 同范式 sha1flex L53)
7. **D134 docker-compose retcon 而非新建** — 删 `--default-authentication-plugin=mysql_native_password` 行,MySQL 8 默认 caching_sha2 user 接管;D134 e2e tests 8 case 仍跑(plugin 对 application layer 透明)
8. **D134 §Status retcon 加 superseded 锚** — 维持 d_doc_index_linter 源码注释 `D134 §` 引用一致性(F1 死指针 = 0);D135 是 D134 实施层迭代,不是历史颠覆 — D134 全 Phase 收关 ✓ 状态保留(架构 + driver-agnostic 接口契约 + 6 Phase 范式 + 三轨闭环不动)
9. **Phase 边界 = commit 边界** — 3 Phase 各自独立 commit,禁打包(承 D134 §Principles 7)
10. **bootstrap 隔离** — 全 Phase 仅改 lib/ + tests/ + docs/,不动 bootstrap(socket client 原语 D134 Phase 1 已就绪 + sha256flex lib/crypto 既有)
11. **本 D 范围外明确清单**:caching_sha2 full auth(RSA-OAEP)/ TLS / Connection Pool(D125+ HikariCP follow-up)/ Prepared Statement / SCRAM-SHA-256 / 其他 SHA-2 plugin / utf8mb4 切换 / multi-result statement / stored procedure / replication
12. **不变量保留**(承 D134):D018 / D022 / D025 / D068 / D088 / D123 / D130-134 全不动;mimalloc C link axiom 例外保留;D134 driver 拼装架构(`lib/com/mysql/{wire,query,jdbc}` + `lib/spring` + `lib/java/sql` 接口契约)不动

---

## 1. Context Management(上下文管理)

> clear 后的 Claude 动手前 5 分钟内必须加载完本节。

### 必读清单(按顺序)

1. 本文档(D135)
2. CLAUDE.md §项目本质 + §项目技术规则 §Root Cause 优先 + §交互式单文档
3. docs/3-MNK.md §M PSM 九问 + §N VCM 六验 + §K 收敛循环 + §大改档位规则
4. docs/3-decisions/D134-jdbc-mysql-wire-protocol.md §Status §核心原则 §A.2(认证选型表)+ §Phase 3 + §Phase 6 docker-compose
5. 关键代码位置:

   | 文件 | 行号 | 角色 |
   |------|------|------|
   | `lib/com/mysql/handshake.ss` | 125-138 `mysqlNativePasswordScramble` | Phase 1 删 + 替换 `cachingSha2Scramble` |
   | `lib/com/mysql/handshake.ss` | 151-202 `sendHandshakeResponse41` | Phase 1 改 plugin name 字面值 + auth-response 20→32 byte |
   | `lib/com/mysql/handshake.ss` | 154 `pluginName = "mysql_native_password"` | Phase 1 改 `caching_sha2_password` |
   | `lib/com/mysql/handshake.ss` | 212-254 `mysqlConnect` | Phase 1 改处理 0x01 0x03 / 0x04 fast-path 响应 |
   | `lib/com/mysql/handshake.ss` | 240-245 firstByte 分支 | Phase 1 加 0x01 fast-path 解析 + 0xFE/0xFF/0x00 错误处理 |
   | `lib/crypto.ss` | 239 `sha256flex` | Phase 1 复用(走 dataHex/prefixHex 路径处理 binary intermediate) |
   | `lib/crypto.ss` | 504 `Crypto_sha256` | Phase 1 复用(SHA256(pwd) 标准接口) |
   | `tests/d134_mysql/handshake_test.ss` | 4 mysql_native vec test | Phase 1 删 + 替换 4 caching_sha2 vec |
   | `tests/d134_mysql/docker-compose.yml` | `--default-authentication-plugin=mysql_native_password` | Phase 2 删行 |
   | `tests/d134_mysql/integration_test.ss` | 全 8 case | Phase 2 不改(plugin 透明) |

### Stable Facts

| 项 | 值 |
|---|---|
| D134 全 Phase 收关锚 | commit `e509be1`(2026-04-26) |
| 当前 driver auth plugin | `mysql_native_password`(D134 Phase 3,Phase 1 替换 caching_sha2_password) |
| 当前 SHA-256 实现 | ✓ `lib/sha256.ss` + `lib/crypto.ss:239 sha256flex` / `:504 Crypto_sha256` |
| 当前 SHA-1 实现 | ✓ `lib/crypto.ss:53 sha1flex` / `:500 Crypto_sha1`(D134 mysql_native 用,Phase 1 后变 unused 但不删除 — D134 之外用途) |
| 当前 RSA / ASN.1 / DER | ✗(永远不做) |
| 当前 caching_sha2 实现 | ✗(本 D 落地) |
| 当前 socket client TCP 原语 | ✓(D134 Phase 1 ss_tcpConnect / ss_tcpReadBytes / ss_tcpWriteBytes 全就绪) |
| 测试基线(D134 §Status) | `bin/ss test tests/` 256 pass / 4 pre-existing fail / 260 total |
| docker-compose 当前 plugin | `--default-authentication-plugin=mysql_native_password`(Phase 2 删) |
| 自举状态 | 自举完成,固定点验证通过(D134 commit `e509be1`) |

### 禁止的 Context 操作

- ❌ 不读 RSA-OAEP / ASN.1 / PKCS / DER 协议规范(范围外)
- ❌ 不读 TLS / SSL 协议(范围外)
- ❌ 不读 caching_sha2 full auth path(范围外永远不做)
- ❌ 不试图保留 mysql_native_password fallback(用户授权删 dead code)
- ❌ 不试图实现 server-driven AuthSwitchRequest 兼容路径(范围外,§Principles 1)

---

## 2. Tool System

### 必备工具(已在环境中)

| 类别 | 工具 | 用途 |
|---|---|---|
| Claude 内置 | Read / Edit / Write / Bash | 文件操作 |
| 项目专属 | `./build.sh bootstrap` | 三阶段固定点(本 D 纯 lib 改,Phase 1+2 后建议跑确认零冲击) |
| 项目专属 | `bin/ss test tests/` | 全测试集 |
| 项目专属 | `bin/ss test tests/d134_mysql/` | D134 既有 e2e(Phase 2 docker-compose retcon 后仍绿) |
| 项目专属 | `bin/ss test tests/d135_caching_sha2/` | D135 新 e2e(Phase 2 加) |
| 项目专属 | `nm bin/ss \| grep -c -E "RSA_\|EVP_"` | axiom 红线扫描(永久 = 0) |
| 项目专属 | `docker compose -f tests/d134_mysql/docker-compose.yml up -d --wait` | MySQL 8 实例(Phase 2 retcon 后默认 caching_sha2) |
| linter | `bin/ss run tools/d_doc_index_linter.ss` | D 文档治理 gate(F1 死指针 = 0) |
| linter | `bin/ss run tools/reflection_health_linter.ss` | 反射 baseline(本 D 不触反射,baseline 不动) |
| linter | `bin/ss run tools/next_prompt_ultrathink_linter.ss` | next_prompt.md 必含 ultrathink |

### 禁止引入

- ❌ 任何新 C 库(libmysqlclient / libssl / libcrypto / libasn1 等)
- ❌ 任何新 build flag(本 D 不改 build.sh / bootstrap/main.ss link 段)
- ❌ 新 lib/sha2.ss(复用 lib/crypto.ss sha256flex,§Principles 6)
- ❌ TLS 握手层 / RSA-OAEP 实现(永远不做)

---

## 3. Execution Orchestration

### 总体节奏

- 3 Phase 各自独立 commit + Phase 1 后必跑 bootstrap 三阶段固定点 + Phase 2 必跑 docker mysql 真 e2e
- 禁"边删 mysql_native scramble 边写 caching_sha2 边改 docker"打包 commit

### Phase 详细

#### Phase 0: 本文档落盘(本轮 Plan)

- D135 文档骨架 + PSM 九问 + 3 Phase 序列 + 风险锚 + 三轨闭环
- 改动:`docs/3-decisions/D135-mysql-caching-sha2-fast-path.md`(新)+ `.claude/next_prompt.md`(改 — Phase 1 起立)
- **不动代码**:`git diff --stat bootstrap/ lib/ tools/ = 0`
- **不动 D134**:Phase 0 只落 D135 文档骨架,D134 §Status retcon 留 Phase 2 实施完成 + commit hash known 时回填(承 §Principles 8)
- **验证**:用户审阅 OK 后下轮 Execute Phase 1

#### Phase 1: caching_sha2_password 实施替换(纯 lib 改)

- **`lib/com/mysql/handshake.ss`** 改:
  - 删 `mysqlNativePasswordScramble` (15 LOC)
  - 加 `cachingSha2Scramble(password: string, scrambleHex: string): string` (~18 LOC) — `SHA256(pwd) XOR SHA256(SHA256(SHA256(pwd)) ‖ nonce)`,32-byte 输出 64 hex chars,走 sha256flex dataHex/prefixHex 路径处理 binary intermediate
  - 改 `sendHandshakeResponse41` plugin name 字面值 `mysql_native_password` → `caching_sha2_password` + auth-response length 20 → 32 + payloadLen 计算更新
  - 改 `mysqlConnect` 处理 server fast-path 响应:
    - `firstByte == 0x00` → OK 直接 — 返 fd ≥ 0(罕见,server 直接 OK)
    - `firstByte == 0x01` → 读 secondByte:`0x03` fast_auth_success → 等下一 OK packet → 返 fd ≥ 0;`0x04` perform_full_authentication → ERR(显式拒绝,§Principles 3)
    - `firstByte == 0xFE` → ERR "server requested AuthSwitch (caching_sha2 fast-path direct mode)" — §Principles 5
    - `firstByte == 0xFF` → ERR "auth failed (ERR packet)" — wrong password / user not found
- **`tests/d134_mysql/handshake_test.ss`** 改:
  - 删 4 `mysqlNativePasswordScramble` vec test(Python hashlib SHA-1 离线算)
  - 加 4 `cachingSha2Scramble` vec test(Python hashlib SHA-256 离线算 — 本 Phase 调研步骤产出)
- **RED**:`grep -nE "cachingSha2Scramble|caching_sha2_password|fast_auth_success" lib/com/mysql/handshake.ss = 0` 改前 / `grep -rnE "mysqlNativePasswordScramble|mysql_native_password" lib/com/mysql/ tests/d134_mysql/ ≥ 6` 改前
- **GREEN**:改后 RED 命令翻转 — caching_sha2 ≥ 5 / mysql_native ≥ 0(handshake_test.ss vec 删 + handshake.ss scramble fn 删 + plugin literal 改 = lib/+test 接近 0,docker-compose Phase 2 处理) + `bin/ss test tests/d134_mysql/handshake_test.ss` 4 vec 全绿 + `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical(纯 lib 不动 bootstrap)

#### Phase 2: docker retcon + tests/d135_caching_sha2/ e2e + D134 retcon

- **`tests/d134_mysql/docker-compose.yml`** 改:
  - 删 `command: --default-authentication-plugin=mysql_native_password` 行(MySQL 8 默认 caching_sha2 接管)
- **`tests/d135_caching_sha2/integration_test.ss`** 新建 ~150 LOC:
  - test 1: connect + isClosed + close(基础 caching_sha2 fast-path 通)
  - test 2: 第二次 connect 验 server cache hit fast_auth_success 路径(无 0x01 0x04 触发)
  - test 3: wrong password → 0xFF ERR(SS errMsg "auth failed (ERR packet)")
  - test 4: server perform_full_authentication 0x01 0x04 拒绝路径 — 测试需先清 server cache(`FLUSH PRIVILEGES`),若 docker 不允许 RESET 则降级"创建临时 user 验首次 connect 0x01 0x04" 或 unit mock
- **D134 §Status retcon**(Phase 2 commit hash known 时回填):
  - 加 superseded 锚 `**D135 superseded mysql_native_password 实施层** at commit <D135 Phase 2 hash> (2026-04-26)`
  - §Phase 3 + §Phase 6 docker-compose 段加 superseded 注脚(指向 D135)
  - 维持 d_doc_index_linter F1 死指针 = 0
- **GREEN**:`bin/ss test tests/d135_caching_sha2/` 全绿 + `bin/ss test tests/d134_mysql/` e2e 8 case 全绿(plugin 对 application layer 透明) + 三轨 RED 闭环 + axiom 红线 grep / nm = 0

### 反模式

- ❌ 边删 mysql_native scramble 边写 caching_sha2 边改 docker(打包 commit,违反 §Principles 9)
- ❌ 保留 mysql_native_password fallback dead code(违反 §Principles 2 + 用户对话授权删)
- ❌ 实现 caching_sha2 full auth(RSA-OAEP)(违反 §Principles 3,永远不做)
- ❌ 实现 AuthSwitchRequest 兼容路径(违反 §Principles 1 / 5)
- ❌ link libssl / libcrypto(违反 axiom L7 + §Principles 4)
- ❌ 新建 lib/sha2.ss(违反 §Principles 6,复用 lib/crypto.ss sha256flex)
- ❌ 新建 tests/d135_caching_sha2/docker-compose.yml(单 docker 实例最简,§Principles 7 retcon)
- ❌ Phase 0 retcon D134 §Status(D134 retcon 留 Phase 2,因 commit hash 未 known)

---

## 4. State & Memory

### 编译时 state

| 变量 | 文件 | 角色 |
|---|---|---|
| 无新增编译时 state | — | Phase 1 纯 lib 替换,bootstrap funcRetTypes 不动 |

### 运行时 state(driver 内部)

- 同 D134(`MysqlConnection.fd / autoCommit / closed`,`MysqlResultSet` 等)
- caching_sha2 协议无新 state,scramble 计算是 stateless 函数
- server-side cache 状态(server 内部维护,client 无感知 — fast_auth_success 命中 / perform_full_auth 触发由 server 决定)

### 中间产物

- Phase 1: 4 `cachingSha2Scramble` reference vector(Python hashlib SHA-256 离线算 + MySQL `sha2_password_common.cc generate_auth_string_sha256()` 反查 stage2/nonce 串接顺序确认 — 本 D 实施过程产出 + 入 handshake_test.ss)

### 会话间持久化

- git log — Phase 0/1/2 commit 边界 = 进度锚
- 本文档 — 唯一 D135 状态记录
- D134 §Status superseded 锚(Phase 2 回填) — 跨轮引用一致性

### 禁止 state 操作

- ❌ 把跨 Phase 进度写到 .claude/next_prompt.md 累积
- ❌ amend 已 push commit
- ❌ 写 caching_sha2_protocol_log.md / wire_analysis_caching_sha2.md 类分析文件入仓
- ❌ 把 mysql credentials 硬编码进 tests/d135_caching_sha2/(用 docker-compose 环境变量传递,密码默认 `test` 沿 D134 范式)

---

## 5. Evaluation & Observation

### 判据(每 Phase 完成必跑)

| # | 类型 | 命令 | 通过条件 |
|---|---|---|---|
| 1 | 工程 | `./build.sh bootstrap` | Phase 1 后跑确认零冲击(纯 lib 改);Phase 2 commit 时再跑 |
| 2 | 测试 | `bin/ss test tests/` | 256+/260 不降(D134 baseline) |
| 3 | D134 e2e 兼容 | `bin/ss test tests/d134_mysql/` | Phase 2 docker retcon 后仍 4 file pass / 0 fail / 29 sub-test 全绿 |
| 4 | D135 e2e | `bin/ss test tests/d135_caching_sha2/` | Phase 2 加 + 全绿(4 case) |
| 5 | RED 收敛 caching_sha2 | `grep -nE "cachingSha2Scramble\|caching_sha2_password\|fast_auth_success" lib/com/mysql/handshake.ss \| wc -l` | Phase 1 后 ≥ 5 |
| 6 | RED 收敛 mysql_native 删 | `grep -rnE "mysqlNativePasswordScramble\|mysql_native_password" lib/com/mysql/ tests/d134_mysql/ \| wc -l` | Phase 2 后 = 0 |
| 7 | axiom 红线 | `grep -rn "libmysqlclient\|libssl\|RSA_\|EVP_PKEY" bootstrap/ lib/ build.sh \| wc -l` + `nm bin/ss \| grep -c -E "RSA_\|EVP_"` | 永久 = 0 |
| 8 | D 治理 | `bin/ss run tools/d_doc_index_linter.ss` | F1 死指针 = 0(D134 §Status retcon superseded 锚维持引用) |
| 9 | 反射 baseline | `bin/ss run tools/reflection_health_linter.ss` | 不升(本 D 不触反射) |

### 回归信号(任一出现 = 立即停下)

- ⚠ Phase 1 后 stage2 ≠ stage3(纯 lib 改不该出现 bootstrap 字节差,若出现说明不慎触 bootstrap)
- ⚠ Phase 2 后 D134 e2e 测试任一红(caching_sha2 切换破坏既有 application layer 透明性)
- ⚠ tests/d135_caching_sha2/integration_test.ss test 2 fast_auth_success 不命中(server cache 行为与协议描述不一致)
- ⚠ axiom 红线 grep / nm 命中(libssl / RSA_ 误链)
- ⚠ Phase 2 D134 §Status retcon 后 d_doc_index_linter F1 BLOCK(死指针 — 修锚点引用)

---

## 6. Constraints & Recovery

### 硬约束

- **不允许 axiom 例外** — feedback_root_cause_no_cost,纯 SS 实现到底
- **不允许跨层** — TLS / RSA-OAEP / Pool / Prepared Statement 全留 sub-D 或永远不做
- **不允许打包 commit** — 3 Phase 各自独立 commit
- **不允许接口签名变** — D025 interface(Connection / Statement / ResultSet)签名本 D 不动
- **不允许保留 mysql_native_password fallback** — 用户对话授权删 dead code

### 风险锚(R1-R5)

| # | 风险 | 触发场景 | 处置 |
|---|---|---|---|
| R1 | caching_sha2 vec 算错 | Python hashlib 与 MySQL server 实现 string concat 顺序不一致(stage2‖nonce vs nonce‖stage2) | Phase 1 用 MySQL `sha2_password_common.cc generate_auth_string_sha256()` 反向验证 — 源码确认 stage2 在前 nonce 在后(与 mysql_native 相反顺序);Python hashlib reference 4 vec 离线算 + e2e 实测交叉验证 |
| R2 | server cache 行为差异 | MySQL 8 server fast_auth cache 用 LRU / connection state,test 2 fast_auth_success 难复现 | Phase 2 test 2 用"先 connect 一次预热 cache,再 connect 验 fast-path"模式;若 cache miss 视为 0x01 0x04 被 server 视为正常 → e2e test 4 拒绝路径 |
| R3 | docker config retcon 影响 D134 | `--default-authentication-plugin=mysql_native_password` 删后 D134 e2e 8 case 走 caching_sha2 → 若 caching_sha2 实现未就绪 → D134 e2e 全红 | **Phase 顺序锁定**:Phase 1 caching_sha2 实施 GREEN 后才 Phase 2 docker retcon;不允许颠倒 |
| R4 | sha256flex 调用 boundary | `sha256flex(data, dataHex, prefix, prefixHex, prefixXor)` 5 参数顺序 + binary intermediate 边界(stage2 = SHA256(stage1) 的 stage1 是 64 hex chars,pass dataHex 路径) | Phase 1 调研步骤跑 MIN reference test:`Crypto.sha256("abc")` 与 Python hashlib SHA256("abc") 比 + `sha256flex("", "<stage1Hex>", "", "", 0)` 与 SHA256(SHA256("abc")) 比 |
| R5 | full_auth 0x01 0x04 路径 e2e 难触发 | server cache miss 导致 full_auth 需要清空 cache 或新建 user — docker e2e 难自动化 | Phase 2 test 4 用 `FLUSH PRIVILEGES + ALTER USER` 清 cache,验 0x01 0x04 → ERR;若 docker 不允许 RESET 则降级"创建临时 user 验首次 connect" 或纯 unit mock(写死 server 响应 0x01 0x04 byte sequence + 验 SS 错误返 -1) |

### 失败模式 + 恢复表

| 信号 | 恢复 |
|---|---|
| Phase 1 cachingSha2Scramble vec 错 | Python hashlib `sha2_password_common.cc generate_auth_string_sha256()` 源码反查 stage2/nonce 串接顺序;参考 PyMySQL / mysql-connector-python 同步实现交叉验证 |
| Phase 2 docker retcon 后 D134 e2e 红 | git revert Phase 2 docker-compose 改 — Phase 1 caching_sha2 实施层未跑通,先回 Phase 1 排查 |
| Phase 2 fast_auth_success cache 未命中 | MySQL doc 反查 cache LRU 容量 / 行为;test 2 改"先 connect 预热"模式;或视 0x01 0x04 + cache miss 为正常 |
| sha256flex 调用结果异常 | 跑 Phase 1 调研 MIN reference vec(`Crypto.sha256` + `sha256flex` 双向比 Python hashlib);确认 dataHex 路径 binary intermediate 处理与 sha1flex 同范式 |
| Phase 2 D134 §Status retcon F1 死指针 BLOCK | 检查 `D134 §Phase 3` / `D134 §Phase 6` 等源码注释引用 — 若 D134 文件 § 段被 retcon 而引用未更新 → 修引用 |

### 回滚策略

- 任一 Phase 失败 → `git reset --soft HEAD^` 回上一 Phase
- Phase 0 落盘后允许下轮 Execute Phase 1 起立时 git stash + 重 plan(D 文档措辞调整)
- 跨 Phase 回滚需先和用户确认(Phase 边界 = 稳定锚点,承 D134 §6 §回滚策略)

---

# 附录 A: 决策细节

## A.1 协议路径选型 — HandshakeResponse41 直发 vs server-driven AuthSwitch

候选(D134 §A.2 已述,D135 简化版):

| 候选 | 描述 | 优 | 劣 | 选/不选 |
|---|---|---|---|---|
| ① **直发 caching_sha2 plugin name** | client 一开始就发 caching_sha2_password + 32-byte SHA-256 scramble | 单 round-trip 真 fast-path / 自用语境最优 / 删 mysql_native dead code 走根因 | 当 server 配置 mysql_native(MySQL 5.x)时反触发 AuthSwitch,显式 ERR(范围外) | **✓ 选**(用户对话授权 "只兼容最新版") |
| ② AuthSwitch 兼容路径 | client 发 mysql_native,server 主动发 0xFE → client 切 SHA-256 | 双向兼容(server 是 mysql_native 时 Phase 3 范式不变) | 多 1 round-trip / 保留 mysql_native fallback dead code(违反 §Principles 2) | ✗ 不选 |
| ③ 双路径 client opt-in | url query param `?authPlugin=...` 显式 | 用户控 | 复杂度 / dead code | ✗ 不选 |

**选 ①**,理由:
- 用户语境"自用 + 只兼容最新版" → MySQL 8 默认 caching_sha2 是唯一 target
- 单 round-trip = 真 fast-path,符合 sub-D 命名"fast-path"语义
- 删 mysql_native fallback = 走根因 + 不留 dead code(承 §Root Cause 优先 + memory feedback_no_derive_workaround)

## A.2 caching_sha2 scramble 算法

```
stage1 = SHA256(password)              // 32 bytes
stage2 = SHA256(stage1)                // 32 bytes  
stage3 = SHA256(stage2 ‖ nonce)        // 32 bytes (注意 stage2‖nonce 顺序!)
reply  = stage1 XOR stage3             // 32 bytes
```

**关键差异**(对偶 D134 §A.2 mysql_native_password):

| 维度 | mysql_native_password | caching_sha2_password |
|---|---|---|
| Hash | SHA-1 | SHA-256 |
| 输出长度 | 20 bytes (40 hex) | 32 bytes (64 hex) |
| stage3 拼接 | nonce ‖ stage2(scramble 在前) | **stage2 ‖ nonce(stage2 在前)** |
| MySQL 默认版本 | 5.x | 8.x |

**算法源**:MySQL 源码 `auth/sha2_password_common.cc generate_auth_string_sha256()`:
```c
SHA256(stage1, stage1_hash);          // hash1
SHA256(hash1, hash2);                 // hash2
SHA256(hash2 || scramble, hash3);     // hash3 = SHA256(hash2 ‖ nonce)
reply = hash1 XOR hash3
```

**SS 实现**(走 `sha256flex` dataHex 路径,binary-safe):

```ss
function cachingSha2Scramble(password: string, scrambleHex: string): string {
    const stage1Hex = Crypto.sha256(password)
    const stage2Hex = sha256flex("", stage1Hex, "", "", 0)
    const stage3Hex = sha256flex("", stage2Hex + scrambleHex, "", "", 0)
    let replyHex = ""
    let i = 0
    while (i < 32) {
        const b1 = cryptoHexDigit(stage1Hex.charAt(i*2)) * 16 + cryptoHexDigit(stage1Hex.charAt(i*2+1))
        const b3 = cryptoHexDigit(stage3Hex.charAt(i*2)) * 16 + cryptoHexDigit(stage3Hex.charAt(i*2+1))
        replyHex = replyHex + hexByte(b1 ^ b3)
        i = i + 1
    }
    return replyHex
}
```

## A.3 server fast-path 响应解析

server 收到 32-byte SHA-256 scramble 后回 packet:

| firstByte | secondByte | 含义 | 处理 |
|---|---|---|---|
| `0x00` | OK packet payload | 直接 OK(罕见) | 返 fd ≥ 0 |
| `0x01` | `0x03` | fast_auth_success(server cache 命中) | 等下一 OK packet → 返 fd ≥ 0 |
| `0x01` | `0x04` | perform_full_authentication(server cache miss) | ERR "full auth not supported (RSA-OAEP scope-out)" → 返 -1 |
| `0xFF` | (ERR packet payload) | 标准 ERR(认证失败 / wrong password / user not found) | errMsg "auth failed (ERR packet)" → 返 -1 |
| `0xFE` | (AuthSwitchRequest payload) | server 不接受 caching_sha2 plugin(MySQL < 5.6 / 古怪配置) | errMsg "server requested AuthSwitch (caching_sha2 fast-path direct mode)" → 返 -1 |

**§Principles 5 锚**:0xFE 显式 ERR 不解析 plugin name,scope 控。用户语境"自用 + MySQL 8" 不该触发。

## A.4 D134 retcon 处理(Phase 2 实施)

D134 §Status 当前:

```
**Status:** ✓ 全 Phase 收关(Phase 0/1/1.5/2/3/4/5/6 全绿;axiom 兑现度 100%)
```

Phase 2 commit 落地后回填 superseded 锚:

```
**Status:** ✓ 全 Phase 收关(Phase 0/1/1.5/2/3/4/5/6 全绿)+ **D135 superseded mysql_native_password 实施层** at commit `<D135 Phase 2 hash>` (2026-04-26)
```

D134 §Phase 3 + §Phase 6 docker-compose 段加 superseded 注脚:

```markdown
> **2026-04-26 D135 supersedes**: mysql_native_password 实施层删除,driver 走 caching_sha2_password fast-path 直发模式;docker `--default-authentication-plugin=mysql_native_password` 行删除,MySQL 8 默认 caching_sha2 接管。详见 `docs/3-decisions/D135-mysql-caching-sha2-fast-path.md`
```

**理由**:
- 维持 d_doc_index_linter F1 死指针 = 0(源码注释 `D134 §Phase 3` 引用仍命中实活段)
- D135 是 D134 实施层迭代,不是历史颠覆
- D134 全 Phase 收关 ✓ 状态保留(架构 + driver-agnostic 接口契约 + 6 Phase 范式 + 三轨闭环不动)
- Phase 0 不动 D134 文件,Phase 2 commit hash known 时回填(承 §Principles 8)

## A.5 与 D134 axiom 范式的对偶

D134 §A.7:
- TCP socket syscall(`connect` / `read` / `write` / `getaddrinfo`)= OS / libc 边界,axiom 例外允许(底层基础设施)
- libmysqlclient.so / libmariadb.so = 应用层 client 库,axiom 不允许 link
- mysql wire protocol 实现纯 SS = 应用层 stdlib

本 D 同范式延伸:
- caching_sha2 SHA-256 chained scramble = 纯 SS 协议层(复用 lib/crypto.ss sha256flex)
- 永远不做 RSA-OAEP / TLS = 跨 axiom 红线 + 工程量爆,自用语境免

## A.6 PSM 九问填表(Phase 0 — 对话正文已述,本节归档完整版)

| # | 字段 | 内容 |
|---|---|---|
| 1 | 总体 | D134 §6 follow-up ① 候选起立 + 用户授权范围简化"只兼容最新版"(2026-04-26 对话指令 "做1" + "看不懂 / 自用 / 最新最优");D134 §Status 全 Phase 收关 ✓ at commit `e509be1`;现 lib/com/mysql/handshake.ss 实施层 mysql_native_password — D135 替换为 caching_sha2_password fast-path |
| 2 | 第一性需求 | MySQL 8 默认 plugin = caching_sha2_password,D134 docker `--default-authentication-plugin=mysql_native_password` server-side workaround 才能跑 → user 体验差;Why 链 ① user 必须 server-side 切换 plugin / docker config;Why 链 ② "MySQL 8 默认开箱即用" axiom 兑现度差;末层断言 docker run mysql:8 + SS connect → handshake.ss:244 errMsg AuthSwitch unsupported |
| 3 | 核心目标 | 三轨闭环:① caching_sha2 path 实施 grep ≥ 5 ② mysql_native 删 grep = 0 ③ tests/d135_caching_sha2/ e2e 全绿 + D134 e2e 8 case 仍绿 |
| 4 | 规则 | CLAUDE.md §项目本质 L7 + §Root Cause 第一法则 + §交互式单文档 + D134 §Principles 5 + D025 interface |
| 5 | 界定 | 做:caching_sha2 直发 + scramble + fast-path 响应 + 删 mysql_native + docker retcon + e2e + D134 §Status retcon;不做:RSA-OAEP / TLS / AuthSwitch / SCRAM-SHA-256 / fallback dead code |
| 6 | 步骤 | 3 Phase: 0 D 文档 / 1 lib 替换 / 2 docker + e2e + D134 retcon |
| 7 | 对照实验 | 不做 → MySQL 8 默认 caching_sha2 user 直接连不上 / user 必须 server-side 切换 plugin / docker config workaround → axiom 兑现差 ✓ 卡 |
| 8 | Plan vs Execute + Layer | Phase 0 = Plan / Decision Layer(D 文档落盘);Phase 1-2 = Execute / Implementation Layer |
| 9 | 表面 vs 根 | 根:caching_sha2 fast-path 协议层根因 + 删 mysql_native dead code 走根因(§Root Cause + memory feedback_no_derive_workaround)+ RSA-OAEP 永远不做 是 §Principles 3 锚定 scope 控,非表面 |
| 10 | bug 修复方案对比 | 不适用(新功能起立) |

---

# 附录 B: 实施日志

### Phase 0: D 文档落盘 [✓] Done at commit `571e54d` (2026-04-26)

- ✓ PSM 九问填表(响应正文 + §A.6)
- ✓ D135 文档骨架完成(此文件)
- ✓ 改动:`docs/3-decisions/D135-mysql-caching-sha2-fast-path.md`(新)
- ✓ 用户对话授权:2026-04-26 "做1" + "只需要兼容最新版,不必兼容那些旧的" + "看不懂 / 自用 / 最新最优"
- ✓ 不动 D134 文件(retcon 留 Phase 2 commit hash known 时回填,承 §Principles 8)
- 用户审阅 OK 后下轮起 Phase 1

### Phase 1: caching_sha2_password 实施替换 [ ] Planned

- [ ] `lib/com/mysql/handshake.ss`:删 `mysqlNativePasswordScramble` + 加 `cachingSha2Scramble` + 改 `sendHandshakeResponse41` plugin name + 改 `mysqlConnect` fast-path 响应处理
- [ ] `tests/d134_mysql/handshake_test.ss`:删 4 mysql_native vec + 加 4 caching_sha2 vec(Python hashlib SHA-256 reference)
- [ ] `bin/ss test tests/d134_mysql/handshake_test.ss` 全绿
- [ ] `./build.sh bootstrap` 三阶段固定点 stage2 == stage3
- [ ] commit "feat(D135): Phase 1 ..."

### Phase 2: docker retcon + tests/d135_caching_sha2/ e2e + D134 retcon [ ] Planned

- [ ] `tests/d134_mysql/docker-compose.yml`:删 `--default-authentication-plugin=mysql_native_password`
- [ ] `tests/d135_caching_sha2/integration_test.ss`(新)~150 LOC / 4 e2e
- [ ] `D134 §Status` 加 superseded 锚 + §Phase 3 / §Phase 6 docker-compose 注脚
- [ ] `bin/ss test tests/d135_caching_sha2/` + `tests/d134_mysql/` 全绿
- [ ] `bin/ss run tools/d_doc_index_linter.ss` F1 死指针 = 0
- [ ] axiom 红线 grep / nm = 0 永久维持
- [ ] commit "feat(D135): Phase 2 ..."

---
