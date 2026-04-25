// I021-codegen-fix regression test
// 验证 module-level CONST literal 在 comptime block 内引用不喷野生 IR 到模块顶层
// 修复前:bin/ss build 报 `llc-18: error: expected 'type' after '='` (野生 `%1 = load ptr, ptr @FOO` 喷顶层)
// 修复后:bootstrap/gen/gen_decls.ss:218-244 + bootstrap/eval/ident.ss:24-32 双轨修
//   - genGlobalVar 注册 const literal 到 ctVars `:${name}`
//   - evalIdent ctVars `:${name}` fallback type 白名单放宽至任意 isCt value

const FOO = "bar"
const PI = 314
const PI2 = -42
const T = 1
const F = 0

class Sentinel { kind: string; n: int; m: int; t: int; f: int }

const SENTINELS: Array<Sentinel> = comptime {
    let arr: Array<Sentinel> = []
    arr = arr.push(new Sentinel(kind: FOO, n: PI, m: PI2, t: T, f: F))
    return arr
}

function main() {
    let count = 0
    for (s in SENTINELS) {
        if (s.kind == "bar" && s.n == 314 && s.m == -42 && s.t == 1 && s.f == 0) {
            count = count + 1
        }
    }
    if (count == 1) { exit(0) } else { exit(1) }
}
