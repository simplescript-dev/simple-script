# global_double_scalar_materialize.options — 全局非字面量 double 标量物化未支持(llc 硬失败)

> Bug 修复 Harness 轨1 前置方案对比表(MNK §字段 10)。D171 §收口验收 runtime-parity 族
> 「行为级穷举 parity 零硬失败」收口**最后一块**(全局 double 标量物化),根因家族 =
> `global_scalar_materialize` int/bool 物化的 double 扩展(materialization 侧)。
> **[⚠ 偏离 feat/d171-sema-q2 comptime 主线 — 用户授权 — I036 是 I035 轮 regression test
> 验证衍生的独立根因(materialization 侧,非 propagation 侧)]**

## RED / 现象

```
printf 'let g=1.5+2.5\nfunction main(){println(`${g}`)}\n' > /tmp/gdbl.ss
bin/ss run /tmp/gdbl.ss 2>&1 | grep -c 'error: llc'    # = 2(>0 成立)
# llc-18: error: floating point constant invalid for type
#   store ptr 0x4010000000000000, ptr @g, align 8   （0x4010..=double 4.0 的 IEEE754 位）
```

同崩:无标注全局 double 数组 array-get `let da=[1.5,2.5,3.5]; let d=da[1]`(I035 后 `d` 已
正确推为 double,`@d=global ptr null` + `store ptr <double>` 崩在**物化侧**,非推断侧)/
全局 double 函数调用 `function f():double{return 3.14}; let h=f()`。对照 GREEN:全局 int/bool
标量物化(`global_scalar_materialize` 已覆盖)、**局部** double(`function main(){let g=1.5+2.5}`
走 alloca double,正常;`let da=[1.5,..]; let d=da[1]` 局部显 "2.5")—— **仅全局 double 物化崩**。

## 根因定位(§实证 grep 证据)

| 锚 | 命令 + 输出 | 含义 |
|---|---|---|
| 物化误用 | `gen_decls.ss:294` `@${name} = global ptr null, align 8` | else 分支 realType=int/bool 已分派,**double 无分支** → 落最终 else 物化 ptr slot |
| store 误用 | `gen_decls.ss:355` `store ptr ${val}, ptr @${gname}` | emitGlobalInits gVarType=int/bool 已分派,**double 无分支** → 落 else store ptr <double> → llc 类型错 |
| 读取侧 | `exprs_simple.ss:17` `load ${ssTypeToLLVM(vType)}, ptr ${varRef(name)}` | genIdent 已按 getVarType 分派 load 类型——设 gType=double 即自动 `load double`(无需改读取侧) |
| 对齐模板 | `gen_decls.ss:260` COMPTIME_EXPR 分支 `@${name} = global double ${ceLit}, align 8` + `gType="double"` | 同函数 double 物化模板,直接复用(注意初值 `0.0` / 折叠值 `0x<hex>`) |
| 值来源合法 | `interp_value.ss:39` `return 0x${tvStringOf(id)}` + `exprs_binary.ss:127` `fadd double` | 折叠常量经 `0x<16hex>` 精确常量到达 / 算术返 double 寄存器 —— store double 操作数恒合法 |

**单一概念根** = 全局标量物化 2 站点(gen_decls.ss 声明 slot + emitGlobalInits store)对 double
类型未分派(与 int/bool 完全同构,仅类型差)。I035 把 double 元素类型已正确传播为 `Array<double>`、
`d` 推为 double,但 double 值物化侧仍落 ptr slot;`global_scalar_materialize` 修了 int/bool 同 2
站点,**double 从未覆盖**(I034/I033 前同样潜伏,但 double 局部从来走 alloca double,仅全局裸露)。

## 候选方案对比

| # | 层次 | 方案 | 假设破裂消除/绕过 | 长久/演化 |
|---|---|---|---|---|
| **A** | **数据层 patch** | 物化点 `bitcast double→i64` + `inttoptr i64→ptr` 存 ptr slot,`global ptr null` 不变;读取侧 `ptrtoint`+`bitcast i64→double` 还原 | **未消除**——slot 类型仍错(ptr 装 double 位),假设破裂仅延后到读取侧;bitcast/inttoptr/ptrtoint 污染读取全链 | N 年返工度**高**:做 B/C 时必删;违反 CLAUDE.md §Root Cause(调用方 workaround) |
| **B** ✅ | **接口层 trap** | gen_decls.ss 全局物化边界单一真相源:genGlobalVar else 分支 `realType=="double"` → `global double 0.0, align 8` + gType=realType;emitGlobalInits 对称发 `store double`。读取侧 genIdent 经 getVarType→ssTypeToLLVM 自动 `load double`(COMPTIME_EXPR double 全局 gen_decls.ss:260 + 局部 alloca double 均已验此路径) | **消除**——物化点按 realType 分派 double slot,声明+store+load 三处类型自洽;与同函数 COMPTIME_EXPR double 分支(gen_decls.ss:260)+ int/bool 物化模板(global_scalar_materialize)对齐,零新抽象 | N 年返工度**低**:double slot 是终态分派,若未来做 C 统一函数则 double 分支自然并入(迁移非返工);业界(LLVM/GCC)全局初始化均按类型分派 slot |
| **C** | **架构层 refactor** | 抽 `materializeGlobal(type, valExpr)` 统一所有全局物化(int/bool/double/string/fn/ptr/array),消除 genGlobalVar + emitGlobalInits 双站点"声明与 store 类型手动同步"的脆弱性 | **从架构消除**双站点同步破裂源(更上游),double 只是其中一个 case | 依赖未设计的统一抽象;scope 超本 finding(须迁全类型,且 global_scalar_materialize 已为 int/bool 落 B);业界演化"先按类型分派(B)后抽象统一(C)"——B 先于 C |

### 假设破裂入口

> **"genGlobalVar else 分支对 realType=double 落最终 else 物化 `global ptr null` 的假设,在
> double 值物化时破裂"** —— genExpr 对 double 算术(`fadd/fmul double` 寄存器)/ 折叠常量
> (`0x<16hex>` 精确位,interp_value.ss:39)/ array-get(`bitcast i64→double` 寄存器)/
> double-call(`call double` 寄存器)产出 **double 操作数**,存入 ptr slot → llc
> "floating point constant invalid for type" 硬失败。
>
> - 候选 A 用 bitcast/inttoptr **绕过**(假设破裂仍在,slot 类型错,延后到读取侧)
> - 候选 B 在物化点按 realType 分派 double slot **消除**该破裂(本 finding 可达最深根)
> - 候选 C 用统一物化函数从架构**消除**"双站点手动同步"这一更上游破裂源(scope 超本 finding)

## 决策行

**选 B 因** 接口层(gen_decls 全局物化边界)是全局声明+store 的单一真相源,realType==double
走 double 物化模板即让声明/store/读取三处类型自洽、消除根因,与同函数 COMPTIME_EXPR double 分支
(gen_decls.ss:260)既有 double 模板 + `global_scalar_materialize` int/bool 2 站点对称模式完全对齐
(零新抽象),与 I033/I034/I035「接口层根因」同族。**不选 A** 因数据层 bitcast/inttoptr 强转
slot 类型仍错(假设破裂未消除)+ 污染读取全链,违反 §Root Cause 第一法则。**不选 C** 因架构层
统一物化函数 scope 超本 finding(string/fn/array 全迁移)、违反 commit 半径,且业界演化 B 先于 C;
C 留独立 refactor issue(B 落地后 double 分支自然并入,非返工)。根因解决度排序:B(消除,终态
分派)> C(消除但越界)> A(绕过)。

## §实证

### grep 证据(根因定位)

见上「根因定位」表 5 锚:物化误用 `gen_decls.ss:294`(else 缺 double 分支)/ store 误用
`gen_decls.ss:355`(emitGlobalInits 缺 double 分支)/ 读取侧自动分派 `exprs_simple.ss:17` /
对齐模板 `gen_decls.ss:260`(COMPTIME_EXPR double 已存)/ 值来源合法 `interp_value.ss:39` +
`exprs_binary.ss:127`(0x<hex> 精确常量 / fadd double 寄存器)。

### 最危险假设 + 最小 spike(已实证,不改编译器)

- **最危险假设**:genExpr 对所有非字面量 double 全局初值返**合法 LLVM double 操作数**
  (`0x<16hex>` 精确常量 / `%reg`),故 `store double ${val}` 类型安全、无需额外 `.0` guard。
- **最小 spike(RED IR + 局部 working-reference 试切)**:
  - RED 实测 IR `store ptr 0x4010000000000000, ptr @g`(1.5+2.5 折叠经 interp_value.ss:39
    `0x${tvStringOf}` 到达,与 gen_types.ss:312 COMPTIME 同源 exact-bits)→ 证折叠值是 `0x<hex>`
    合法 double 常量(非裸整数 `4`,故无需 `.0` guard;`.0` guard 已在 constVal 源头由 `0x` 前缀承担)。
  - 局部 `function main(){let da=[1.5,2.5,3.5]; let d=da[1]; println(\`${d}\`)}` → 输出 **2.5**
    (局部 alloca double + array-get `bitcast i64→double` 寄存器 → 证 array-get 返 double 寄存器)。
  - 局部 `let g=1.5+2.5` → alloca double + `fadd double`(exprs_binary.ss:127)寄存器,均合法 store double 操作数。
- **spike 结论**:double 值来源(折叠 0x<hex> / array-get bitcast 寄存器 / fadd 寄存器 / call double
  寄存器)恒是合法 LLVM double 操作数,全局只需复用同 double 物化模板(候选 B),`store double ${val}`
  无需额外转换安全网。本改 <20 LOC + 1 编译器文件,未触发 §字段 12 大规模 spike 门槛,
  RED IR + 局部 working-reference 即充分 de-risk。

## GREEN 验收判据

- 全局非字面量 double(算术 `let g=1.5+2.5` / 无标注 double 数组 array-get / double-fn-call)全编译通过
- 值正确 + 显示 parity(`${d}` → "2.5") + comptime==runtime(oracle 一致)
- 全局 int/bool/**double** 标量物化 3 类型对称
- bootstrap 三阶段固定点 + 全测 baseline 持平(3 pre-existing 不变,+1 新 regression test)
- reflection_health(F1 gen_decls bump 走 §扩容申报-I036)/ sunset / bugfix / d_doc / derived_issue gate 全 PASS
