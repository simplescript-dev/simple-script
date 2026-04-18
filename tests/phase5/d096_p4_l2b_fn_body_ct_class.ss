// D096 Phase 4 L2β RED — preScanComptimeClasses 不递归函数体
// 期望 fail:函数体内 const W = comptime { class Wrap {...}; return Wrap } 没被 checker 识别,
// new W(v: 5) 报 'is not a field of class W' 或 'undefined variable W'
function mk(): int {
    const W = comptime {
        class Wrap {
            v: int = 0
        }
        return Wrap
    }
    const w = new W(v: 5)
    return w.v
}

function main() {
    println(`v=${mk()}`)
}
