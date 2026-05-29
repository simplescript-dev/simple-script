// D171 Phase 4: try / catch / throw 在 comptime 可捕获。
// RED(改前): `comptime error: boom` + exit(1) — comptime throw 直接 exit、genTryCatch ct 分支
//   整段忽略 catchList,catch 不捕获。§最小变量隔离实证:probe A(try 无 throw)= tryRan 正常,
//   probe B(裸 throw)= exit(1),坐实 try 执行本就 OK,断流仅在 throw→catch landing。
// GREEN(改后): comptime 无 runtime 栈/landingpad(D171 §张力 3),throw 改 raise interpThrowFlag
//   (镜像 interpReturnFlag),genBlock 语句边界经 interpShouldStop 短路,enclosing genTryCatch
//   消费 flag → 匹配 catch(untyped 全捕 / typed 走 interpResolveParent 继承链)→ bind ctVars →
//   跑 catch body;finally 始终跑(save/restore pending);未捕获在 runComptimeBlockBody 升 loud
//   comptimeError(D088 §Phase 8 不变量,见 probe B,非 passing-test 故不在本文件)。
// 走 D093 统一 evalExpr/genBlock + 现有 ctVars/interpResolveParent,不新开 ct* 异常注册表
// (D171 §拒绝准则 / D088 §反模式)。

class BaseErr { message: string = "" }
class SubErr extends BaseErr {}                 // 继承 message 字段,typed catch 走继承链匹配

function main() {
    // 1) RED canonical — throw 被 catch 捕获 + 异常值 bind 到 e(改前 exit(1) "comptime error: boom")
    const c1 = comptime {
        try { throw("boom") } catch (e) { return e }
    }
    if (c1 != "boom") { exit(1) }

    // 2) catch 绑值可在表达式里消费(e 经 ctVars `__comptime__:e` 解析,与 VAR_DECL 同 key 协议)
    const c2 = comptime {
        try { throw("x") } catch (e) { return e + "!" }
    }
    if (c2 != "x!") { exit(1) }

    // 3) try 正常完成不触发 catch(无 throw → interpThrowFlag 未 set → catch 派发跳过)
    const c3 = comptime {
        try { return "ok" } catch (e) { return "caught" }
    }
    if (c3 != "ok") { exit(1) }

    // 4) 嵌套 try — 内层 catch 捕获内层 throw(flag 在内层 genTryCatch 消费,不冒泡到外层)
    const c4 = comptime {
        try {
            try { throw("inner") } catch (e) { return "got:" + e }
        } catch (e2) {
            return "outer"
        }
    }
    if (c4 != "got:inner") { exit(1) }

    // 5) 嵌套 try — 内层 catch 再 throw,flag 重新 set 冒泡到外层 catch(re-raise 链路)
    const c5 = comptime {
        try {
            try { throw("a") } catch (e) { throw("b") }
        } catch (e2) {
            return e2
        }
    }
    if (c5 != "b") { exit(1) }

    // 6) finally 自身 return 覆盖 try 的 pending return(ctRunComptimeFinally 不恢复 pending)
    const c6 = comptime {
        try { return "try" } finally { return "finally" }
    }
    if (c6 != "finally") { exit(1) }

    // 7) finally 正常结束 — catch 的 pending return 被 save/restore 保留(finally 不吞控制流)
    const c7 = comptime {
        try { throw("e") } catch (ex) { return "C" } finally { let z = 1 }
    }
    if (c7 != "C") { exit(1) }

    // 8) typed catch 经继承链匹配 — throw SubErr,catch(e: BaseErr) 走 interpResolveParent 命中父类
    const c8 = comptime {
        try { throw(new SubErr(message: "sub")) } catch (e: BaseErr) { return e.message }
    }
    if (c8 != "sub") { exit(1) }

    // 9) typed catch 不匹配 → 落到后续 untyped catch-all(string 非 object,ctThrownMatchesType=0)
    const c9 = comptime {
        try { throw("plain") } catch (e: BaseErr) { return "typed" } catch (e) { return e }
    }
    if (c9 != "plain") { exit(1) }

    println("d171 comptime try/catch/throw: ok")
}
