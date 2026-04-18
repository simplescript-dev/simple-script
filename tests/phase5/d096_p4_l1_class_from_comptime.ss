// D096 Phase 4 L1 — comptime 里声明的 class 能被 runtime 实例化
// 根因：genClassDecl comptimeDepth>0 原本 return 掉,class 消失在 runtime;
// 改为 register 到 interpClasses + 排队待主 codegen 发射。
// checker 侧 preScanComptimeClasses 识别 `const T = comptime { class X; return X }`
// 形态并建立 T→X 字段表,allow `new T(...)` 在 runtime 成立。
class Count { val: int = 0 }

const W = comptime {
    class Wrap { _inner: Count = new Count(); label: int = 0 }
    return Wrap
}

function main() {
    const r = new W(_inner: new Count(val: 99), label: 5)
    println(`label=${r.label}`)
    println(`inner=${r._inner.val}`)
}
