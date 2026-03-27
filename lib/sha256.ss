// SHA-256 in pure SimpleScript — no C dependency
// Uses bitwise operators: & | ^ >>> <<

function rotr(x: int, n: int): int {
    return (x >>> n) | (x << (32 - n))
}

function ch(x: int, y: int, z: int): int {
    return (x & y) ^ ((~x) & z)
}

function maj(x: int, y: int, z: int): int {
    return (x & y) ^ (x & z) ^ (y & z)
}

function sigma0(x: int): int {
    return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22)
}

function sigma1(x: int): int {
    return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25)
}

function gamma0(x: int): int {
    return rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3)
}

function gamma1(x: int): int {
    return rotr(x, 17) ^ rotr(x, 19) ^ (x >>> 10)
}

function getKConst(i: int): int {
    const k = "1116352408,1899447441,-1245643825,-373957723,961987163,1508970993,-1841331548,-1424204075,-670586216,310598401,607225278,1426881987,1925078388,-2132889090,-1680079193,-1046744716,-459576895,-272742522,264347078,604807628,770255983,1249150122,1555081692,1996064986,-1740746414,-1473132947,-1341970488,-1084653625,-958395405,-710438585,113926993,338241895,666307205,773529912,1294757372,1396182291,1695183700,1986661051,-2117940946,-1838011259,-1564481375,-1474664885,-1035236496,-949202525,-778901479,-694614492,-200395387,275423344,430227734,506948616,659060556,883997877,958139571,1322822218,1537002063,1747873779,1955562222,2024104815,-2067236844,-1933114872,-1866530822,-1538233109,-1090935817,-965641998"
    const parts = k.split(",")
    let idx = 0
    for (p in parts) {
        if (idx == i) { return parseInt(p) }
        idx = idx + 1
    }
    return 0
}

function hexByte(v: int): string {
    const hex = "0123456789abcdef"
    return hex.charAt((v >>> 4) & 15) + hex.charAt(v & 15)
}

function hexWord(v: int): string {
    return hexByte((v >>> 24) & 255) + hexByte((v >>> 16) & 255) + hexByte((v >>> 8) & 255) + hexByte(v & 255)
}

function sha256pure(data: string): string {
    let h0 = 1779033703
    let h1 = -1150833019
    let h2 = 1013904242
    let h3 = -1521486534
    let h4 = 1359893119
    let h5 = -1694144372
    let h6 = 528734635
    let h7 = 1541459225

    const dataLen = data.length()
    const bitLen = dataLen * 8

    // Calculate padded length
    let padLen = dataLen + 1
    while (padLen % 64 != 56) {
        padLen = padLen + 1
    }
    padLen = padLen + 8

    // Process each 64-byte block
    let blockStart = 0
    while (blockStart < padLen) {
        // Read 16 words from padded message
        let w0 = 0
        let w1 = 0
        let w2 = 0
        let w3 = 0
        let w4 = 0
        let w5 = 0
        let w6 = 0
        let w7 = 0
        let w8 = 0
        let w9 = 0
        let w10 = 0
        let w11 = 0
        let w12 = 0
        let w13 = 0
        let w14 = 0
        let w15 = 0

        let wi = 0
        while (wi < 16) {
            let word = 0
            let bi = 0
            while (bi < 4) {
                const byteIdx = blockStart + wi * 4 + bi
                let byteVal = 0
                if (byteIdx < dataLen) {
                    byteVal = data.charCodeAt(byteIdx)
                } else if (byteIdx == dataLen) {
                    byteVal = 128
                } else if (byteIdx >= padLen - 4) {
                    const lbp = byteIdx - (padLen - 4)
                    if (lbp == 0) { byteVal = (bitLen >>> 24) & 255 }
                    if (lbp == 1) { byteVal = (bitLen >>> 16) & 255 }
                    if (lbp == 2) { byteVal = (bitLen >>> 8) & 255 }
                    if (lbp == 3) { byteVal = bitLen & 255 }
                }
                word = (word << 8) | byteVal
                bi = bi + 1
            }
            if (wi == 0) { w0 = word }
            if (wi == 1) { w1 = word }
            if (wi == 2) { w2 = word }
            if (wi == 3) { w3 = word }
            if (wi == 4) { w4 = word }
            if (wi == 5) { w5 = word }
            if (wi == 6) { w6 = word }
            if (wi == 7) { w7 = word }
            if (wi == 8) { w8 = word }
            if (wi == 9) { w9 = word }
            if (wi == 10) { w10 = word }
            if (wi == 11) { w11 = word }
            if (wi == 12) { w12 = word }
            if (wi == 13) { w13 = word }
            if (wi == 14) { w14 = word }
            if (wi == 15) { w15 = word }
            wi = wi + 1
        }

        // Message schedule expansion (rounds 16..63)
        // w[i] = gamma1(w[i-2]) + w[i-7] + gamma0(w[i-15]) + w[i-16]
        // Using a sliding window of 16 variables
        let ri = 16
        let a = h0
        let b = h1
        let c = h2
        let d = h3
        let e = h4
        let f = h5
        let g = h6
        let h = h7

        // First 16 rounds use w0..w15 directly
        let round = 0
        while (round < 16) {
            let wVal = 0
            if (round == 0) { wVal = w0 }
            if (round == 1) { wVal = w1 }
            if (round == 2) { wVal = w2 }
            if (round == 3) { wVal = w3 }
            if (round == 4) { wVal = w4 }
            if (round == 5) { wVal = w5 }
            if (round == 6) { wVal = w6 }
            if (round == 7) { wVal = w7 }
            if (round == 8) { wVal = w8 }
            if (round == 9) { wVal = w9 }
            if (round == 10) { wVal = w10 }
            if (round == 11) { wVal = w11 }
            if (round == 12) { wVal = w12 }
            if (round == 13) { wVal = w13 }
            if (round == 14) { wVal = w14 }
            if (round == 15) { wVal = w15 }

            const t1 = h + sigma1(e) + ch(e, f, g) + getKConst(round) + wVal
            const t2 = sigma0(a) + maj(a, b, c)
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
            round = round + 1
        }

        // Rounds 16..63: expand and compress
        while (round < 64) {
            // Expand: new_w = gamma1(w14) + w9 + gamma0(w1) + w0
            const new_w = gamma1(w14) + w9 + gamma0(w1) + w0
            // Shift window
            w0 = w1
            w1 = w2
            w2 = w3
            w3 = w4
            w4 = w5
            w5 = w6
            w6 = w7
            w7 = w8
            w8 = w9
            w9 = w10
            w10 = w11
            w11 = w12
            w12 = w13
            w13 = w14
            w14 = w15
            w15 = new_w

            const t1 = h + sigma1(e) + ch(e, f, g) + getKConst(round) + new_w
            const t2 = sigma0(a) + maj(a, b, c)
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
            round = round + 1
        }

        h0 = h0 + a
        h1 = h1 + b
        h2 = h2 + c
        h3 = h3 + d
        h4 = h4 + e
        h5 = h5 + f
        h6 = h6 + g
        h7 = h7 + h

        blockStart = blockStart + 64
    }

    return hexWord(h0) + hexWord(h1) + hexWord(h2) + hexWord(h3) + hexWord(h4) + hexWord(h5) + hexWord(h6) + hexWord(h7)
}
