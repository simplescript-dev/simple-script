// java.math — JDBC 4.3 numeric type class foundation (driver-agnostic)
// Mirrors: java.math.BigDecimal
//
// Used by JDBC ResultSet.getBigDecimal / updateBigDecimal as the column
// value type for SQL DECIMAL / NUMERIC. D151 setter `updateBigDecimal(col,
// val)` (≥18 method scope, JDBC §15.2.5) takes BigDecimal as `val` — this
// file is the underlying type class providing that signature.
//
// Internal representation: unscaled value (int) + scale (int).
//   Number = unscaled × 10^(-scale)
//     "19.99"   → unscaled=1999, scale=2
//     "12345"   → unscaled=12345, scale=0
//     "-3.14"   → unscaled=-314, scale=2
//
// JDK BigDecimal v9+ uses the same fast path internally (intCompact long
// + scale int) before falling back to BigInteger for precision > 18. SS
// has no BigInteger primitive yet, so this v1 covers precision ≤ 18 — the
// MySQL DECIMAL(10,2) / DECIMAL(18,4) main use case. Arbitrary-precision
// + RoundingMode-aware divide() are tracked in D152 §Followup (BigInteger
// primitive sub-D 起首 后扩 fallback path).
//
// See docs/3-decisions/D152-jdbc-type-class-foundation.md §Phase 2.

class BigDecimal {
    unscaled: int
    scale: int

    function scale(): int {
        return this.scale
    }

    function unscaledValue(): int {
        return this.unscaled
    }

    function precision(): int {
        let n = this.unscaled
        if (n < 0) { n = -n }
        if (n == 0) { return 1 }
        let p = 0
        while (n > 0) {
            n = n / 10
            p = p + 1
        }
        return p
    }

    function signum(): int {
        if (this.unscaled > 0) { return 1 }
        if (this.unscaled < 0) { return -1 }
        return 0
    }

    function add(other: BigDecimal): BigDecimal {
        let aU = this.unscaled
        let aS = this.scale
        let bU = other.unscaled
        let bS = other.scale
        if (aS < bS) {
            aU = aU * bdPow10(bS - aS)
            aS = bS
        } else if (bS < aS) {
            bU = bU * bdPow10(aS - bS)
        }
        return new BigDecimal(aU + bU, aS)
    }

    function subtract(other: BigDecimal): BigDecimal {
        let aU = this.unscaled
        let aS = this.scale
        let bU = other.unscaled
        let bS = other.scale
        if (aS < bS) {
            aU = aU * bdPow10(bS - aS)
            aS = bS
        } else if (bS < aS) {
            bU = bU * bdPow10(aS - bS)
        }
        return new BigDecimal(aU - bU, aS)
    }

    function multiply(other: BigDecimal): BigDecimal {
        return new BigDecimal(this.unscaled * other.unscaled, this.scale + other.scale)
    }

    function negate(): BigDecimal {
        return new BigDecimal(-this.unscaled, this.scale)
    }

    function abs(): BigDecimal {
        if (this.unscaled < 0) {
            return new BigDecimal(-this.unscaled, this.scale)
        }
        return new BigDecimal(this.unscaled, this.scale)
    }

    function compareTo(other: BigDecimal): int {
        let aU = this.unscaled
        let bU = other.unscaled
        if (this.scale < other.scale) {
            aU = aU * bdPow10(other.scale - this.scale)
        } else if (other.scale < this.scale) {
            bU = bU * bdPow10(this.scale - other.scale)
        }
        if (aU < bU) { return -1 }
        if (aU > bU) { return 1 }
        return 0
    }

    // JDK BigDecimal.equals: numerically equal AND same scale.
    // 1.0 != 1.00 (use compareTo for value equality).
    function equals(other: BigDecimal): int {
        if (this.scale != other.scale) { return 0 }
        if (this.unscaled != other.unscaled) { return 0 }
        return 1
    }

    function toString(): string {
        if (this.scale == 0) {
            return `${this.unscaled}`
        }
        let neg = 0
        let u = this.unscaled
        if (u < 0) {
            neg = 1
            u = -u
        }
        const pow = bdPow10(this.scale)
        const intPart = u / pow
        const fracPart = u - intPart * pow
        const fracStr = `${fracPart}`
        let padStr = ""
        let padCount = this.scale - fracStr.length()
        while (padCount > 0) {
            padStr = `${padStr}0`
            padCount = padCount - 1
        }
        let sign = ""
        if (neg == 1) { sign = "-" }
        return `${sign}${intPart}.${padStr}${fracStr}`
    }
}

// 10^n. n must be >= 0; n > 18 overflows int — caller responsibility.
function bdPow10(n: int): int {
    let r = 1
    let i = 0
    while (i < n) {
        r = r * 10
        i = i + 1
    }
    return r
}

function BigDecimal_fromInt(n: int): BigDecimal {
    return new BigDecimal(n, 0)
}

// Parse a decimal literal: optional leading '-', digits, optional '.', digits.
// No exponent ('e'/'E'), no leading '+', no underscores.
//   "19.99"  → BigDecimal(1999, 2)
//   "-3.14"  → BigDecimal(-314, 2)
//   "12345"  → BigDecimal(12345, 0)
function BigDecimal_fromString(s: string): BigDecimal {
    let neg = 0
    let i = 0
    const n = s.length()
    if (n > 0) {
        // ASCII: '-' = 45, '.' = 46, '0' = 48
        if (s.charCodeAt(0) == 45) {
            neg = 1
            i = 1
        }
    }
    let unscaled = 0
    let scale = 0
    let dotSeen = 0
    while (i < n) {
        const code = s.charCodeAt(i)
        if (code == 46) {
            dotSeen = 1
        } else {
            unscaled = unscaled * 10 + (code - 48)
            if (dotSeen == 1) {
                scale = scale + 1
            }
        }
        i = i + 1
    }
    if (neg == 1) {
        unscaled = -unscaled
    }
    return new BigDecimal(unscaled, scale)
}
