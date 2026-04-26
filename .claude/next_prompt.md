ultrathink D134 Phase 2 起立 — lib/binary.ss + lib/sha1.ss + lib/com/mysql/wire.ss(纯 lib 改,不触 bootstrap)

承本轮 commit(待立)D134 §3 §Phase 1 GREEN — bootstrap socket client 原语 `ss_tcpConnect` + `ss_tcpReadBytes` 已补齐,三阶段固定点 stage2 == stage3 byte-identical 通过(二次验证),bin/ss 自我编译产物已 sync,checker.ss intFns + arg-count 注册同行(承 CLAUDE.md §添加新语言特性 step 3 + D134 §Principles 8 "Phase 1 自包含 bootstrap 改"),tests 252 pass / 4 fail = D133 §附录 B Phase 6 latent baseline 不降级。本轮 Layer = **Execute / Implementation Layer**,起 D134 §3 §Phase 2 三文件落盘。

**Why 起 Phase 2**:D134 §Stable Facts 锚 Phase 2 三文件 ✗(`lib/binary` / `lib/sha1` / `lib/com/mysql/wire` 全不存在);Phase 3 起 `lib/com/mysql/handshake.ss` 必调 `wire.readPacket / writePacket`(packet 解析)+ `sha1.sha1Hash`(`mysql_native_password` scramble 必需 SHA-1)+ `binary.byteToInt / lengthEncodedInt`(handshake v10 payload 解析),无 Phase 2 三文件 → Phase 3-6 全阻塞。**axiom 紧约束**:CLAUDE.md §项目本质 L7 + D134 §Principles 1,4 — 纯 SS,不 link `libssl` / 任何 C crypto。

**Phase 2 范围**(承 D134 §3 §Phase 2 详细):

1. **`lib/binary.ss`**(新建):
   - `function byteToInt(buf: string, offset: int, len: int): int`(little-endian 1/2/3/4/8 byte unsigned int 解析,`len ≤ 8`)
   - `function intToBytes(n: int, len: int): string`(little-endian 反向编码,`len ≤ 8`)
   - `function readLengthEncodedInt(buf: string, offset: int): int`(MySQL length-encoded int 返值)
   - `function lengthEncodedIntSize(buf: string, offset: int): int`(返字节数,因 SS 无 tuple 必拆双函数)
   - `function readLengthEncodedString(buf: string, offset: int): string`(length-prefix + raw bytes)
   - `function writeLengthEncodedInt(n: int): string`(反向编码)
   - 长度编码规则(D134 §A.4):`< 0xFB` → 1 byte / `0xFC` → 2 byte le / `0xFD` → 3 byte le / `0xFE` → 8 byte le / `0xFB` → NULL(列值)
2. **`lib/sha1.ss`**(新建,对照 `lib/sha256.ss:1-228` 风格):
   - `function sha1(input: string): string`(返 20-byte hash hex 字符串 / raw bytes,看 sha256 现风格定输出形式)
   - 内部:5 个 32-bit state H0-H4,80 round,word/chunk 解析,padding(bit length + 0x80 + zeros)
3. **`lib/com/mysql/wire.ss`**(新建):
   - `function readPacket(fd: int): string`(读 4-byte header → 解析 3-byte length + 1-byte seq → `tcpReadBytes(fd, buf, payloadLen)` 读 payload → 返 payload bytes)
   - `function writePacket(fd: int, seqId: int, payload: string): int`(写 4-byte header + payload → 调 `tcpWriteBytes`)
   - 注意:packet ≤ 16MB 简化(D134 §3 §Phase 2 续包逻辑入 sub-D)
   - **关键设计 question**:`tcpReadBytes(fd, buf, len)` 需 caller 提供 `buf: ptr`。SS 中如何 allocate raw byte buffer?candidate:① 复用 string `""`+`repeat(len)` 字面量(0 字节字符串)→ 但 string 0-terminated 不支持 binary;② 加新 builtin `bufferAlloc(len): string` 走 ss_rc_alloc;③ 借用既有 `ss_tcpRead(fd, maxlen)` 单次 read,接受短读重试。**调研 Phase 2 起立第一步**确认方案,如果 ① / ③ 不行则回头 Phase 1.5 扩 `bufferAlloc` builtin(承 D134 §Principles 8 spirit:bootstrap 触改保持 Phase 边界)
4. **`tests/d134_mysql/`**(新建目录)+ `tests/d134_mysql/wire_test.ss`(新):
   - 单元测试 `binary.byteToInt` / `binary.readLengthEncodedInt` / `binary.intToBytes` / `binary.writeLengthEncodedInt` 边界(0xFB / 0xFC / 0xFD / 0xFE 分支)
   - 单元测试 `sha1.sha1` 对照 NIST FIPS 180-4 已知向量(空字符串 / "abc" / 等)
   - **不依赖网络**(纯字节计算 + assertEqual)

**调研步骤**(写代码前 ultrathink):
1. Read lib/sha256.ss 全文 1-228 — sha256 风格(state init / round 数 / pad / 输出格式)+ 注意 SS int 是 i64,处理 32-bit overflow 用 `& 0xFFFFFFFF` mask
2. Read lib/sha256.ss 测试文件(tests/.../sha256_*.ss) — 测试范式参考
3. ultrathink Phase 2 关键设计 question(`tcpReadBytes` 的 buf 来源)— 调研:
   - grep `ss_rc_alloc` lib/ — 看是否有用户层包装
   - grep `repeat\|fromCharCode` lib/ — 看 string 构造 raw bytes 模式
   - 评估 ① / ② / ③ 方案的可行性 + 各自工程量
   - 决策记录:本轮选哪个,记入 §附录 B Phase 2 实施日志
4. ultrathink SHA-1 算法:`H0=0x67452301 / H1=0xEFCDAB89 / H2=0x98BADCFE / H3=0x10325476 / H4=0xC3D2E1F0` 初始化;message padding(append 0x80 + 0 padding + 64-bit length);80 round per chunk;F1 = (B AND C) OR ((NOT B) AND D)(round 0-19) / F2 = B XOR C XOR D(20-39 + 60-79) / F3 = (B AND C) OR (B AND D) OR (C AND D)(40-59);K constants: 0x5A827999 / 0x6ED9EBA1 / 0x8F1BBCDC / 0xCA62C1D6
5. ultrathink length-encoded int 边界:`0xFB` 是 NULL 标记不是数据(SS 中如何返"NULL"?int -1 sentinel?需 readLengthEncodedIntOrNull 双函数?)
6. RED 命令实测(Phase 2 起立前 = 0)
7. Write lib/binary.ss + lib/sha1.ss + lib/com/mysql/wire.ss
8. Write tests/d134_mysql/wire_test.ss
9. `bin/ss test tests/d134_mysql/wire_test.ss` 全绿(GREEN 收敛)
10. `./build.sh bootstrap` 三阶段固定点确认零冲击(承 D134 §Principles 8 — Phase 2 不应触 bootstrap,但 build.sh bootstrap 跑一次确认无意外耦合)

**RED**(Phase 2 起立前实测):
```bash
ls lib/binary.ss lib/sha1.ss lib/com/mysql/wire.ss tests/d134_mysql/wire_test.ss 2>&1 | grep -c "No such" 
# 当前 = 4(全不存在),改后 = 0
```

**GREEN**(Phase 2 收敛):
- 四文件全在(lib/binary.ss + lib/sha1.ss + lib/com/mysql/wire.ss + tests/d134_mysql/wire_test.ss)
- `bin/ss test tests/d134_mysql/wire_test.ss` 全绿
- `./build.sh bootstrap` 三阶段固定点 stage2 == stage3 byte-identical 通过(无意外 bootstrap 触)
- `bin/ss test tests/` 不降级(承 D133 §附录 B Phase 6 latent 4 fail 基线 + Phase 1 252/256 实测)

**MNK §M PSM 九问填表**(本轮第一次工具调用之前必须落):
- 字段 1 总体:服务 D134 §3 Phase 2 Execute 实施 — 实测 §Status `Plan` ✓ + Phase 1 §3 Execution Orchestration §Phase 1 GREEN 收关 ✓ + Phase 2 三文件起立锚 D134 §3 §Phase 2
- 字段 2 第一性需求:无 lib/binary + lib/sha1 + lib/com/mysql/wire = handshake v10 解析 + scramble 计算 + packet read/write 全瘫;不做 → Phase 3-6 全 Phase 阻塞
- 字段 3 核心目标:RED `ls lib/binary.ss lib/sha1.ss lib/com/mysql/wire.ss tests/d134_mysql/wire_test.ss = 4 缺` → 改后 = 0 缺;`bin/ss test tests/d134_mysql/wire_test.ss` 全绿;`./build.sh bootstrap` stage2 == stage3
- 字段 4 规则:CLAUDE.md §项目本质 L7(纯 SS) + D134 §Principles 1,4(纯 SS axiom + packet 纯 SS) + docs/3-MNK.md §M PSM 九问
- 字段 5 界定:**做** — lib/binary.ss(新)+ lib/sha1.ss(新)+ lib/com/mysql/wire.ss(新)+ tests/d134_mysql/wire_test.ss(新);**不做** — bootstrap/ 任何文件(若 `tcpReadBytes` 的 buf 设计 question 必须回头扩 builtin,则 Phase 1.5 单独 D 文档 + commit,不偷渡入 Phase 2 commit);**不做** — lib/sha2 / RSA / TLS / lib/com/mysql/handshake / query / jdbc(Phase 3-5 起);**不做** — 任何 docker-compose 或集成测试(Phase 6 起)
- 字段 6 步骤:见上调研步骤 1-10
- 字段 7 对照实验:不做 → Phase 3 起 lib/com/mysql/handshake.ss 调 sha1 / readPacket / parseLengthEncoded 全 undefined function → 编译永久失败 ✓ 卡
- 字段 8 Plan vs Execute + Layer:**Execute / Implementation Layer**(承 D134 §Phase 2);本轮 Layer 引用上层 D134 §3 = 同 Layer 不跨层
- 字段 9 表面 vs 根:**根**(三 lib 文件物理空缺,补齐是结构性根因;非 workaround / mock / 旁路;若 buf 设计 question 触回头改 bootstrap,亦是结构性根因不接受 SS-side workaround)
- 字段 10 bug 修复:不适用(新功能起立,非 bug 修复)

**档位**:**大改**(LOC ~400-600:binary ~80 + sha1 ~200 + wire ~100 + wire_test ~150;新建 4 文件;承 docs/3-MNK.md §改动分层 §新建 ≥ 100 LOC 升档大改门槛)

**不变量保留**:D018(对象布局)/ D022(clone 语义)/ D025(interface dispatch)/ D088 / D123 / D130-133 全不动;mimalloc C link axiom 例外保留;**Phase 1 加的 socket client 原语接口不动**(sha1 / wire 直调 `tcpConnect` / `tcpReadBytes` / `tcpWriteBytes` / `tcpClose`);**lib/sha256.ss 不动**(sha1 是平行新建,不复用 sha256 内部 state)

**git stale state 处理**(承 D133 范式):仅 stage 本轮真实改动:`git add lib/binary.ss lib/sha1.ss lib/com/mysql/wire.ss tests/d134_mysql/wire_test.ss .claude/next_prompt.md`(若 Phase 1.5 触 bootstrap 则单 commit 隔离)。其他 stale D 文档删除 + 现有 untracked 不触(违反 §交互式单文档)。

**收尾**:Phase 2 GREEN(三 lib 文件 + wire 单测 + bootstrap 固定点零冲击) → /simplify(承 §After Done §1) → commit "feat(D134): Phase 2 lib/binary + lib/sha1 + lib/com/mysql/wire 落盘 — byteToInt + lengthEncodedInt 字节序原语 + SHA-1 hash(80 round / 5 state, FIPS 180-4 兼容)+ packet readPacket/writePacket(3-byte length + 1-byte seq header)+ wire_test.ss 单元测试全绿 — Phase 3 (handshake v10 + mysql_native_password scramble + mysqlConnect flow) 待起立" → 写下轮 next_prompt(ultrathink + Phase 3 起立 = lib/com/mysql/handshake.ss + parseHandshakeV10 + buildHandshakeResponse41 + mysqlNativePasswordScramble + mysqlConnect flow) → stop

**Layer**:Execute / Implementation Layer。本轮在 D134 §3 §Phase 2 范围内不跨层。

下轮 Execute / Implementation 流程,**ultrathink** 模式下深度调研 lib/sha256.ss 范式 + SHA-1 算法 80 round / 5 state / F1/F2/F3 函数 / K 常量 + length-encoded int 边界(0xFB NULL 标记)+ tcpReadBytes buf 来源设计 question(① string repeat ② bufferAlloc builtin 新增 ③ tcpRead 短读重试)三方案评估 + 决策落记 §附录 B Phase 2 + 写四文件 + bin/ss test 全绿 + commit。
