ultrathink D134 Phase 1 起立 — socket client 原语补齐(bootstrap 改)

承本轮 commit(待立)D134 D 文档 Phase 0 落盘 — `docs/3-decisions/D134-jdbc-mysql-wire-protocol.md` PSM 九问 + 6 Phase 序列 + 风险锚 R1-R8 + 三轨闭环 + Phase 1 详细规格已锁定(本轮通过用户审阅措辞 OK)。本轮 Layer = **Execute / Implementation**,起 D134 §3 §Phase 1。

**Why 起 Phase 1**:D134 §Stable Facts 锚"当前 client 端 TCP 原语 ✗(无 ss_tcpConnect,无精确字节读 ss_tcpReadBytes)";Phase 2 起 lib/com/mysql/wire.ss readPacket 必调 ss_tcpReadBytes(精确读 4-byte header + payload_length-byte payload),无原语 → Phase 2-6 全阻塞。**axiom 紧约束**:CLAUDE.md §项目本质 L7 + D134 §Principles 1 纯 SS 不破。

**Phase 1 范围**(承 D134 §3 §Phase 1 详细):
1. `bootstrap/gen/rt/gen_rt_system.ss` `emitRuntimeNet()` 175-255 段加:
   - **`ss_tcpConnect(host: ptr, port: i32) → i32`**:`socket(AF_INET, SOCK_STREAM, 0)` → `getaddrinfo(host, NULL, &hints, &res)` (hints `ai_family=AF_INET + ai_socktype=SOCK_STREAM`)→ `connect(fd, res->ai_addr, res->ai_addrlen)` → `freeaddrinfo(res)` → 成功返 fd,任一失败 close fd + return -1
   - **`ss_tcpReadBytes(fd: i32, buf: ptr, len: i32) → i32`**:read-loop while `read_so_far < len`:`n = read(fd, buf + read_so_far, len - read_so_far); if n <= 0 break; read_so_far += n;` 返 read_so_far(< len 表示 EOF)
2. `bootstrap/gen/gen_registry.ss`:
   - `funcRetTypes.set("ss_tcpConnect", "int")`
   - `funcRetTypes.set("ss_tcpReadBytes", "int")`
3. bootstrap 三阶段固定点验证

**调研步骤**(写代码前 ultrathink):
1. Read bootstrap/gen/rt/gen_rt_system.ss:175-255 全段 — emitRuntimeNet() 6 既有函数 IR emit 范式(socket / setsockopt / bind / listen / accept / read / write / close / htons 等 syscall 调用)
2. Read bootstrap/gen/gen_registry.ss — 找 "ss_tcp" 既有注册行(funcRetTypes.set 模式),按行序插入新注册
3. ultrathink getaddrinfo C 签名(`int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res)`)+ struct addrinfo offset(`ai_family / ai_socktype / ai_protocol / ai_addrlen / ai_addr / ai_canonname / ai_next` LLVM 类型布局)
4. ultrathink read-loop IR 实现 — 用 phi 节点 + branch label,对照 bootstrap rt 层是否有现成 loop 范式(Read gen_rt_string.ss / gen_rt_array.ss 找 loop pattern)
5. RED 命令实测 = 0(改前)
6. Edit gen_rt_system.ss 加两 builtin
7. Edit gen_registry.ss 加 funcRetTypes 注册
8. `./build.sh bootstrap` 三阶段固定点验证 stage2 == stage3 byte-identical
9. RED 命令实测 ≥ 4 + GREEN 验证

**RED**(Phase 1 起立前实测):
```bash
grep -nE "ss_tcpConnect|ss_tcpReadBytes" bootstrap/gen/rt/gen_rt_system.ss bootstrap/gen/gen_registry.ss | wc -l
# 当前 = 0,改后 ≥ 4
```

**GREEN**(Phase 1 收敛):
- RED 改后 ≥ 4 命中
- `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical 通过
- bootstrap 二进制可正常自编译 + bin/ss test tests/ 不降级(承 D133 §附录 B Phase 6 latent 4 fail 基线)

**MNK §M PSM 九问填表**(本轮第一次工具调用之前必须落):
- 字段 1 总体:服务 D134 §3 Phase 1 Execute 实施 — 实测 D134 §Status `Plan` 落盘 ✓ + Phase 1 详细规格 §3 Execution Orchestration §Phase 1 ✓ + .claude/next_prompt.md ultrathink ✓
- 字段 2 第一性需求:无 ss_tcpConnect = lib/com/mysql/wire.ss readPacket 不可编译 = Phase 2 起立 RED 永远阻塞;不做 → D134 全 Phase 全瘫
- 字段 3 核心目标:RED `grep -nE "ss_tcpConnect|ss_tcpReadBytes" bootstrap/gen/rt/gen_rt_system.ss bootstrap/gen/gen_registry.ss \| wc -l = 0` → 改后 ≥ 4;`./build.sh bootstrap` stage2 == stage3 byte-identical
- 字段 4 规则:CLAUDE.md §构建与测试 §自举固定点 + D134 §Principles 3,8 + docs/3-MNK.md §M PSM 九问
- 字段 5 界定:**做** — bootstrap/gen/rt/gen_rt_system.ss + bootstrap/gen/gen_registry.ss 两文件;**不做** — lib/ / build.sh / 任何 lib/com/mysql 实现(Phase 2 起);**不做** — TCP server 端原语既有 6 函数(emitRuntimeNet 全段保留)
- 字段 6 步骤:见上调研步骤 1-9
- 字段 7 对照实验:不做 → Phase 2 起 lib/com/mysql/wire.ss readPacket 调 ss_tcpReadBytes 编译错 → D134 全 Phase 阻塞 ✓ 卡
- 字段 8 Plan vs Execute + Layer:**Execute / Implementation Layer**(承 D134 §Phase 1);本轮 Layer 引用上层 D134 §3 = 同 Layer 不跨层
- 字段 9 表面 vs 根:**根**(socket client 原语物理空缺,补齐是结构性根因;非 workaround / mock / 旁路)
- 字段 10 bug 修复:不适用(新 builtin 添加,非 bug 修复)

**档位**:**大改**(LOC ~30-50 + 2 文件 + 新增 builtin 函数签名变 → 升档大改 — 承 docs/3-MNK.md §改动分层 §函数签名变升档至 ≥ 标准改 + 新 builtin 加注册触发大改门槛)

**不变量保留**:D018(对象布局)/ D022(clone 语义)/ D025(interface dispatch)/ D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;**TCP server 端原语(emitRuntimeNet 既有 ss_tcpListen/Accept/Read/Write/WriteBytes/Close 6 函数)不动**;ss_tcpRead 既有字符串 0-terminated 单次 read 语义保留(供既有 server 端 lib/http.ss 等调用),Phase 1 仅追加 ss_tcpReadBytes 精确字节读,**不替换**既有 ss_tcpRead

**git stale state 处理**(承 D133 范式):仅 stage 本轮真实改动:`git add bootstrap/gen/rt/gen_rt_system.ss bootstrap/gen/gen_registry.ss .claude/next_prompt.md`。其他 stale D 文档删除 + 现有 untracked 不触(违反 §交互式单文档)。

**收尾**:Phase 1 GREEN(socket 原语补齐 + bootstrap 固定点 stage2 == stage3) → /simplify(承 §After Done §1) → commit "feat(D134): Phase 1 socket client 原语 ss_tcpConnect + ss_tcpReadBytes 补齐 — emitRuntimeNet 既有 6 server 函数 + 2 client 函数追加 + funcRetTypes 双注册 — bootstrap 三阶段固定点 stage2==stage3 byte-identical 通过 — D134 §3 §Phase 1 全 GREEN,Phase 2 (lib/binary + lib/sha1 + lib/com/mysql/wire) 待起立" → 写下轮 next_prompt(ultrathink + Phase 2 起立 = lib/binary.ss 字节序原语 + lib/sha1.ss + lib/com/mysql/wire.ss packet read/write) → stop

**Layer**:Execute / Implementation Layer。本轮在 D134 §3 §Phase 1 范围内不跨层。

下轮 Execute / Implementation 流程,**ultrathink** 模式下深度调研 ss_tcpListen IR emit 范式 + getaddrinfo addrinfo struct LLVM 类型布局 + read-loop phi 节点设计 + 改两文件 + bootstrap 三阶段固定点 + commit。
