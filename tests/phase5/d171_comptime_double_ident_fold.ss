// D171 finding C 第三物化 sink / I032 — comptime double IDENT 折叠 bit-exact。
// RED(改前): @methodOf handler 捕获外层 comptime double 绑定,rewriteIdentToLit(class_comptime.ss:48)
//   折叠 IDENT→DOUBLE_LIT 时读 tvD1=%g(6 位有效数字),getRatio() 返 400aaaa8eb463498 ≠ 精确
//   400aaaaaaaaaaaab,进数值消费(非仅显示):b.getRatio()==10.0/3.0 → false。
// FIX: fold 改 doubleToStringExact(bitsToDouble(tvStringOf(pl))) —— tvStringOf=tvS1 IEEE754 exact-bits,
//   bitsToDouble 重建精确 double,%.17g(DBL_DECIMAL_DIG)物化 round-trip S1;`.0` guard 补整数值小数点。
//   S1 单一统一契约"round-trip decimal" → 全消费点(store double / parseDouble / annArgToSrc)零改动 bit-exact。
// 判据: 折叠值与等价 runtime **bit-exact**(doubleBits 比较),含 IEEE754 residue 保真(不得伪精确)。

function WithDoubles(cls: string) {
    const ratio = 10.0 / 3.0                          // 非整数,RED canonical
    const whole = 6.0 / 2.0                           // 整数值 3.0 — 触 `.0` guard(%.17g "3")
    const chain = (1.0 / 3.0) * 3.0                   // 链式,round-trip 误差抵消
    const resid = 0.1 + 0.2                           // IEEE754 residue 3.0000000000000004(非 3.0)
    const neg   = 0.0 - 3.14                          // 负数符号位
    @methodOf(cls) function getRatio(): double { return ratio }
    @methodOf(cls) function getWhole(): double { return whole }
    @methodOf(cls) function getChain(): double { return chain }
    @methodOf(cls) function getResid(): double { return resid }
    @methodOf(cls) function getNeg(): double { return neg }
}

@WithDoubles
class Box { v: int }

function main() {
    const b = new Box(v: 1)

    // 1) RED canonical: 10.0/3.0 折叠 bit-exact(改前 400aaaa8eb463498)
    if (doubleBits(b.getRatio()) != doubleBits(10.0 / 3.0)) { exit(1) }

    // 2) 整数值 double 折叠 `.0` guard: 6.0/2.0 = 3.0 精确(改前 %.17g "3" → LLVM `global double 3` REJECT)
    if (doubleBits(b.getWhole()) != doubleBits(3.0)) { exit(1) }
    if (doubleBits(b.getWhole()) != doubleBits(6.0 / 2.0)) { exit(1) }

    // 3) 捕获算术链折叠 == runtime parity
    let rc = (1.0 / 3.0) * 3.0
    if (doubleBits(b.getChain()) != doubleBits(rc)) { exit(1) }

    // 4) IEEE754 residue 保真: comptime 复现 runtime (0.1+0.2),非伪精确成 3 折/0.3
    let rr = 0.1 + 0.2
    if (doubleBits(b.getResid()) != doubleBits(rr)) { exit(1) }    // bit-exact parity(含 residue)
    if (doubleBits(b.getResid()) == doubleBits(0.3)) { exit(1) }   // 反向: 必非伪精确 0.3

    // 5) 负数符号位往返精确
    if (doubleBits(b.getNeg()) != doubleBits(0.0 - 3.14)) { exit(1) }

    // 6) 数值消费(非仅显示)断言: == 比较走 round-trip 精确值
    if (b.getRatio() == 10.0 / 3.0) {} else { exit(1) }

    // 7) 非退化: 源码 double 字面量(parser DOUBLE_LIT，非折叠)仍精确
    let src = 3.14159
    if (doubleBits(src) != doubleBits(3.14159)) { exit(1) }

    println("d171 comptime double IDENT fold: all bit-exact parity OK")
}
