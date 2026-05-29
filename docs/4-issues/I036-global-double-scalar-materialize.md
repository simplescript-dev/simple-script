# I036 — 全局非字面量 double 标量物化未支持致 llc 硬失败

**父决策:** D171 §收口验收 finding 链衍生。`global_scalar_materialize` 轮修了全局非字面量
**int/bool** 标量物化（genGlobalVar else 分支 `global i32 0` + emitGlobalInits `store i32`），
但 **double 从未覆盖**；I035 轮（无标注全局数组元素类型传播）验证时实测暴露:double 元素类型
已正确传播，但物化侧仍崩 —— 独立根因。
**状态:** **[ ] Planned**（backlog；非阻挡 I035 核心 RED int/string/bool array-get — 该主路径已彻底修）。
**颗粒度:** 预估微改（genGlobalVar else + emitGlobalInits 各补 double 分支，对齐 int/bool 2 站点对称模式）。
**依赖:** 无硬依赖；与 `global_scalar_materialize`（int/bool 物化）、I035（元素类型传播）同函数
`gen_decls.ss genGlobalVar`/`emitGlobalInits`，**不同根因**:I036 = 标量物化 double 扩展（materialization 侧），
I035 = 元素类型传播（propagation 侧），二者正交。`comptime` double 物化 = 独立既有 [[I011]]（comptime 侧，本 I036 是 runtime 全局侧）。
**创建:** 2026-05-29
**立项由:** I035 轮 regression test 验证 —— 无标注全局 double 数组 `let da=[1.5,2.5,3.5]; let d=da[1]`
实测 `@d=global ptr null` + `store ptr %11`（%11 是 double）llc 硬失败；且 `let g=1.5+2.5`（非数组的
全局 double 算术）**同崩** → 确认是 general 全局 double 物化 gap（非 array-get 专属），属
global_scalar_materialize int/bool 家族的 double 未扩展。

---

## 现象（最小变量隔离实证）

```
# 全局 double 算术 — RED（与数组无关，证 general gap）
let g = 1.5 + 2.5      # @g = global ptr null + emitGlobalInits store ptr <double> → llc error

# 无标注全局 double 数组 array-get — RED（I035 已传播 Array<double>，崩在物化）
let da = [1.5, 2.5, 3.5]
let d = da[1]          # IR: @d=global ptr null + store ptr %N(%N 是 double）→ llc error

# 对照局部 — GREEN（local var decl double 物化走 alloca double，正常）
function main(){ let g = 1.5 + 2.5 }   # ✓
```

## 根因（global_scalar_materialize int/bool 家族未扩 double）

`gen_decls.ss` 全局标量物化接口边界 2 站点对 double 缺分支:
- **站点 A** `genGlobalVar` else 分支:`realType=="int"||"bool"` → `global i32 0`；`realType=="double"`
  **无分支** → 落 else `@x = global ptr null`（ptr slot,但值是 double）。
- **站点 B** `emitGlobalInits`:`gVarType=="int"||"bool"` → `store i32`；double **无分支** → 落 else
  `store ptr <val>`,而 `genExpr`/`emitI64ToValue(_, "double")` 产出 double 寄存器 → `store ptr <double>` → llc 类型错。

**单一概念根** = 全局标量物化 2 站点对 double 类型未分派（与 int/bool 完全同构,仅类型差）。
与 I035（propagation 侧:元素类型是否传播）正交 —— I035 后 double 元素类型已正确传播为 `Array<double>`、
`d` 推为 `double`,但 double 值无处物化。

## 候选路径（待 Execute 轮 PSM §字段 10 展开）

- **接口层（推荐）**:genGlobalVar else 补 `else if (realType=="double") → @x=global double 0.0, align 8`
  + emitGlobalInits 补 `else if (gVarType=="double") → store double <val>, align 8`,对齐 int/bool
  2 站点对称模式（global_scalar_materialize 同模式扩 double）。**注意** LLVM `global double 3`（整数值）
  REJECT,初值用 `0.0`；存储值若 comptime 折叠须 `.0` guard（参考 D171:163 comptime double 物化 `.0` 补点）。
- **数据层（次优）**:物化点 `bitcast double→i64` 存 ptr slot 再读取侧还原 —— slot 类型仍错,污染读取链,违反 §Root Cause。

## GREEN 判据（立项目标，非本轮）

全局非字面量 double（算术 `let g=1.5+2.5` / 无标注 double 数组 array-get / double-fn-call）编译通过 +
值正确 + comptime==runtime parity；全局 int/bool/double 标量物化 3 类型对称。
