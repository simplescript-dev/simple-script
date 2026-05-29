// D171 finding C 残余 backlog — chained comptime double 算术精度(bit-exact 回读)。
// RED(改前): comptime { let t = 10.0/3.0; return t * 3.0 } 物化成 9.99999(应 10.0)。
//   根因: interpNumericBinop(interp_op.ss)double 回读走 parseDouble(interpToStr) 读 tvD1=%g
//   (默认 6 位有效数字,中间值 t 跨操作丢精: t 存成 "3.33333" 回读 ×3 = 9.99999)。
// FIX: 回读改 bitsToDouble(interpAsStr) 从 tvS1 IEEE754 exact-bits 重建(finding C 已让 newTvDouble
//   把 doubleBits 存入 tvS1),与物化路径(materialize/gen_types exact-bits)对称闭环。
// 判据: comptime 结果与等价 runtime 算术 **bit-exact** 一致(doubleBits 比较),消除 comptime 额外丢精;
//   IEEE754 固有 residue(如 (0.1+0.2)*10)必须**保真复现** runtime,不得伪精确。
// 走 D093 统一 interpNumericBinop(1 helper × 2 caller),不新开 ct* 注册表。

function main() {
    // 1) RED canonical: chained mul — 改前 9.99999,改后精确 10.0(round-trip 误差恰好抵消)
    const chain = comptime { let t = 10.0 / 3.0; return t * 3.0 }
    if (doubleBits(chain) != doubleBits(10.0)) { exit(1) }       // bit-exact 10.0
    let r1 = 10.0 / 3.0
    if (doubleBits(chain) != doubleBits(r1 * 3.0)) { exit(1) }   // == runtime parity

    // 2) 多级链 ((1/3)*3)*2 = 2.0 精确
    const multi = comptime { let a = 1.0 / 3.0; let b = a * 3.0; return b * 2.0 }
    if (doubleBits(multi) != doubleBits(2.0)) { exit(1) }
    let a2 = 1.0 / 3.0
    let b2 = a2 * 3.0
    if (doubleBits(multi) != doubleBits(b2 * 2.0)) { exit(1) }

    // 3) IEEE754 residue 保真: (0.1+0.2)*10 = 3.0000000000000004(非 3.0)。comptime 必须复现 runtime
    //    residue,而非伪精确成 3.0(反向断言)。证明修复 = 复现 runtime IEEE754,非"修漂亮"。
    const resid = comptime { let a = 0.1 + 0.2; return a * 10.0 }
    let ra = 0.1 + 0.2
    if (doubleBits(resid) != doubleBits(ra * 10.0)) { exit(1) }  // bit-exact parity(含 residue)
    if (doubleBits(resid) == doubleBits(3.0)) { exit(1) }        // 反向: 必非伪精确 3.0

    // 4) 混 int/double 链 7.0/2.0+1 = 4.5 精确
    const mixed = comptime { let q = 7.0 / 2.0; return q + 1 }
    if (doubleBits(mixed) != doubleBits(4.5)) { exit(1) }

    // 5) 单 op 不退化(finding C GREEN 保持): 10.0/3.0 单独折叠仍 == runtime
    const single = comptime { return 10.0 / 3.0 }
    let rs = 10.0 / 3.0
    if (doubleBits(single) != doubleBits(rs)) { exit(1) }

    println("d171 chained comptime double: all bit-exact parity OK")
}
