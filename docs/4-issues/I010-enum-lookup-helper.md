# I010 — Enum 双 map + typed 分派 helper 抽取

**父决策:** D127 §A.1 第 4 项衍生(I004 simplify 审阅发现)
**状态:** Draft
**颗粒度:** ~2-3 万 token
**依赖:** 无(跨文件 refactor)
**创建:** 2026-04-22

## 上下文

I004 落地后,simplify reuse 审阅发现**三处**重复双 map + typed 分派:

| 文件:行 | 函数 | typed 分支 | untyped 分支 |
|---|---|---|---|
| `bootstrap/eval/member_access.ss:10-17` | `evalMemberAccess` | string(backing) | **int(ordinal)** |
| `bootstrap/eval/interp_obj.ss:163-173` | `evalAnnotationArg` | string(backing) | **string(symbol name)** |
| `bootstrap/gen/exprs/exprs_ct_enum.ss:33-36` | `ctEnumValueOfMethod` | string(backing) | **int(ordinal)** |

三处**共性**:
- 查找双 map `interpEnumValues` (comptimeDepth>0) / `enumValues` (=0,受 `enumReady` gate)
- 判定 typed `interpEnumTypes.has(eName)` / `enumTypes.has(eName)`

三处**差异**(untyped 语义):
- `evalMemberAccess`:untyped → `interpNewInt(parseInt(ordinal))`(enum expr 参与算术/比较)
- `evalAnnotationArg`:untyped → `interpNewString(memberName)`(Java `.name()` 语义,annotation 读回)
- `ctEnumValueOfMethod`:untyped → `interpNewInt(parseInt(ordinal))`(enum method valueof)

共性部分(双 map + enumReady gate + typed 返 backing value)可抽:

```ss
// 返 "" miss / backing value hit,typed enum 的 string backing value 查找
function lookupEnumBackingValue(eName: string, eKey: string): string {
    if (interpEnumValues.has(eKey) == 1 && interpEnumTypes.has(eName) == 1) {
        return interpEnumValues.getString(eKey)
    }
    if (enumReady == 1 && enumValues.has(eKey) == 1 && enumTypes.has(eName) == 1) {
        return enumValues.getString(eKey)
    }
    return ""
}

// 返 -1 miss / ordinal hit,untyped enum 的 ordinal 查找
function lookupEnumOrdinal(eName: string, eKey: string): int {
    if (interpEnumValues.has(eKey) == 1 && interpEnumTypes.has(eName) == 0) {
        return parseInt(interpEnumValues.getString(eKey))
    }
    if (enumReady == 1 && enumValues.has(eKey) == 1 && enumTypes.has(eName) == 0) {
        return parseInt(enumValues.getString(eKey))
    }
    return -1
}
```

## 范围

- 新增两个 helper 到 `bootstrap/eval/interp_obj.ss`(或 interp_core.ss)
- 三个调用点改用 helper,按各自 untyped 语义组装 tv
- bootstrap 固定点验证
- 无行为变化,纯 refactor

## 步骤

1. 选 helper 归属文件(interp_core.ss 更合适,是底层 enum 访问)
2. 抽 `lookupEnumBackingValue` + `lookupEnumOrdinal`
3. 改 3 个调用点
4. bootstrap + 全量测试

## 反向

不做 → 每新增 enum 分派点都重抄 4-8 行双 map gate;D127 §A.1 第 5 项(I005 array lit)若含 enum 元素时再次要抄 → 第 **4** 处重复触发 `feedback_no_workaround` 第二次 root cause 义务。

## 验收 RED 命令

```bash
# 本身是 refactor,无行为变化,RED 是"调用点存在重复"的证据
grep -c "interpEnumValues.has.*interpEnumTypes" bootstrap/eval/member_access.ss bootstrap/eval/interp_obj.ss bootstrap/gen/exprs/exprs_ct_enum.ss
# 期望:0(每文件 0 次直接双 map gate,全部通过 helper)
./build.sh bootstrap
```

## 备注

- simplify 审阅共识:本 diff 先合(I004 范围优先),refactor 独立立项
- feedback_no_workaround 触发点:**已到第三处**,不再抽下一次到第四处(I005/I006 任何 enum 分支)就违反"第二次必修根因"
- 归属候选:`interp_core.ss` 底层工具 vs `interp_obj.ss` eval helper;按调用者分布(member_access + interp_obj + exprs_ct_enum)跨 2 个顶级子族 → `interp_core.ss` 更中性
