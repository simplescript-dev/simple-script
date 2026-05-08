# Bug 修复方案对比表 — prelude 注入路径 cwd 解析坏

## 症状(用户原报)

```
ss build /tmp/x.ss -o /tmp/x
→ llc-18: error: use of undefined value '@ss_replace'
   %51 = call ptr @ss_replace(ptr %49, ptr @.str.25, ptr %50)
```

## 误诊 vs 真根因(假设破裂入口)

**用户报告时假设**:`@ss_replace` 这一条 string op 路径里 declare/impl/funcRetTypes 注册某一环漏了。

**该假设在勘察后破裂**:`bin/ss build /tmp/x.ss` 在 `/root/code/simplescript-dev/simple-script` cwd 下能正常 build + run、IR 链路完整 `define ptr @_ss_replace(...)` + `call ptr @_ss_replace(...)`,prelude 注册和 emit 都齐全。

**真根因**:`bootstrap/main.ss:623-627` 的 `findPrelude()`:

```ss
function findPrelude(): string {
    if (fileExists("bootstrap/parse/prelude.ss") == 1) { return "bootstrap/parse/prelude.ss" }
    if (fileExists("../bootstrap/parse/prelude.ss") == 1) { return "../bootstrap/parse/prelude.ss" }
    return ""
}
```

仅查 cwd 下两个相对路径,**完全靠 cwd**。在任意非 simple-script 仓库 cwd(比如 `/tmp/`)下,prelude 找不到 → 不被注入 → `_ss_replace` / `_ss_toUpperCase` / `_ss_padStart` 等**所有 prelude 函数**全部缺失 → `preludeName("ss_replace")` 因 funcRetTypes 没注册返回**裸名 `ss_replace`** → llc 报 undefined value。

**复现确认**(在 `/tmp/` cwd 下):
```
$ cd /tmp && /root/code/simplescript-dev/simple-script/bin/ss build /tmp/replace_test.ss -o /tmp/rt
llc-18: error: use of undefined value '@ss_replace'
  %4 = call ptr @ss_replace(ptr @.str.1, ptr @.str.2, ptr @.str.3)
```

**爆炸面**:不只 `ss_replace`,任何 prelude-only string op 都中招(已实测 `toUpperCase` 同病)。

## 候选方案

### 层次

- **数据**:prelude.ss 内容如何定位/承载 → embed vs 文件路径
- **接口**:findPrelude 是否暴露给 SS 用户、binary 是否 self-contained
- **架构**:bootstrap stage 的依赖关系、SS binary 的 portability 模型

### **A**:embed prelude 内容到 ss binary(self-contained,业界标杆)

| 维度 | 内容 |
|------|------|
| 思路 | build.sh bootstrap 阶段把 `bootstrap/parse/prelude.ss` 读出转义成 LLVM `private constant [N x i8]`,emit 进 binary 自身。`findPrelude()` 不再 readFile,直接从内存读 `@ss_prelude_content`。 |
| 层次 | 数据(prelude 不再是文件)+ 架构(binary 完全 self-contained) |
| 业界对标 | rustc(libcore embed in sysroot binary)、go(runtime embed)、tcc(`tcc_set_lib_path` 但默认 self-contained) |
| 根因解决度 | 100% — 完全消除路径依赖 |
| N 年返工度 | 极低 — install / portability / docker 一次性消解 |
| 实施依赖 | (1) codegen 加 emit prelude string blob;(2) main.ss 用新 API 取 prelude 内容;(3) bootstrap 链 stage0(seed)是否需特殊处理 — seed 时 cwd 必在仓根所以仍能 readFile,stage1+ 的 ss 自带 embed |
| 风险 | 转义实现:prelude.ss 含反引号/双引号/换行,LLVM `[N x i8]` 字面量需逐字节 escape;开发期改 prelude.ss 必须重 bootstrap 才生效(失去文件 reload 的 ergonomics) |

### **B**:`/proc/self/exe` 反推 binary 路径(gcc/clang 风格)

| 维度 | 内容 |
|------|------|
| 思路 | 加 `ss_selfExe()` runtime function 走 readlink syscall,拿到 binary 绝对路径 → dirname 推 simple-script 仓根 → 加 `<repoRoot>/bootstrap/parse/prelude.ss`。`findPrelude()` 增加这一搜索层。 |
| 层次 | 数据(用 syscall 找文件)+ 接口(暴露 selfExe runtime) |
| 业界对标 | gcc(driver 用 `/proc/self/exe` 找 sysroot)、clang(同) |
| 根因解决度 | 80% — 仍依赖 prelude.ss 物理存在;用户单独 copy `bin/ss` 一个文件出去仍坏 |
| N 年返工度 | 中 — install 流程不规范时仍可能踩坑;ss 的 packaging 长期演化必走 embed,这是过渡方案 |
| 实施依赖 | (1) `gen_rt_io.ss` 加 `ss_selfExe`;(2) `main.ss` `findPrelude` 加 selfExe-relative 搜索 |
| 风险 | 仅 Linux 友好(macOS 是 `_NSGetExecutablePath`,Windows 是 `GetModuleFileName`);portability 层留尾巴 |

### **C**:扩展 findPrelude 多搜索路径(ad-hoc 兜底)

| 维度 | 内容 |
|------|------|
| 思路 | `findPrelude()` 加 fallback 链:cwd → cwd/.. → `arg(0)` 推 binary dir → `SS_HOME` env → `/usr/local/lib/simplescript/prelude.ss` → `$HOME/.simple-script/prelude.ss`。 |
| 层次 | 数据(多文件路径搜索) |
| 业界对标 | python sys.path 风格 — 但 python 自身更靠 `sys.prefix` 推路径,纯多搜索路径少见 |
| 根因解决度 | 50% — 仍是文件路径问题,只是 fallback 多了 |
| N 年返工度 | 高 — 每加一种 install 形态又要回来动一次 |
| 实施依赖 | (1) main.ss findPrelude 加 fallback;(2) 文档说明每个 fallback |
| 风险 | 多 fallback 增加 debug 难度;不同环境表现不一致 |

### **D**:A + B 复合(embed primary + DEV mode 兜底)

| 维度 | 内容 |
|------|------|
| 思路 | 默认走 embed(方案 A);加环境变量 `SS_PRELUDE_DEV=1` 时走 `/proc/self/exe` 推 simple-script 仓根读 `bootstrap/parse/prelude.ss`(方案 B)。开发期改 prelude.ss 不必重 bootstrap 也能见效。 |
| 层次 | 数据 + 接口 + 架构 三层全覆盖 |
| 业界对标 | rustc(`RUSTC_BOOTSTRAP=1` DEV mode + 默认 sysroot embed) |
| 根因解决度 | 100% + DEV ergonomics |
| N 年返工度 | 极低 |
| 实施依赖 | A 的全部 + B 的 selfExe runtime |
| 风险 | 实施量比 A 大 ~30%;两路径需 cycle test 防 drift |

## 决策

**选 A(embed prelude 到 ss binary)**,**因**根因解决度最高(100%)、业界标杆对标 rustc/go(都是 self-contained binary)、N 年返工度最低(install/docker/portability 一次性消解)。CLAUDE.md "Root Cause 优先" + "长久/演化维度"两条原则共同指向:任何文件路径方案(B/C)在长期 packaging 演化中都会被 embed 覆盖致返工,不是"最佳"是"短期权宜"。

**B 是次优兜底**,实施成本最低但根因覆盖度只有 80%;若用户因单一改动门槛(prelude.ss 改一处需重 bootstrap)拒绝接受 A 的 ergonomics 损失,可考虑 D(A+B 复合)— 实施量比 A 大但开发期 ergonomics 不退步。

**C 拒绝**,因不是 root cause 解,只是 fallback 堆叠,不符合"根因优先"。

## 用户确认锚

下一步需用户在 A / B / D 三选一。建议 **A**,理由如上。如选 D,会一并实施 selfExe runtime 作为 DEV mode 后门(实施量约 +30% LOC,~一次性增量)。
