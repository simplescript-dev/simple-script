# D047: Crypto Module (lib/crypto.ss)

**Status:** Accepted
**Depends on:** D035 (stdlib pattern), sha256.ss

## Decision

Add `lib/crypto.ss` — cryptographic utilities providing SHA-1 hashing, HMAC-SHA256, HMAC-SHA1, hex conversion, and constant-time comparison.

## Reasoning

- Standard library has 15 modules but no HMAC or SHA-1 support
- HMAC is essential for API authentication, webhook verification, JWT signatures, TOTP
- SHA-1 is used in Git object hashing, legacy system interoperability, TOTP/HOTP
- SHA-256 already exists in sha256.ss; crypto.ss extends it with HMAC and provides SHA-1
- Pure SS implementation, no compiler changes needed

## Key Design: Flex Hash Functions

SS strings are null-terminated (strlen-based length). HMAC's inner hash output may contain 0x00 bytes, which would corrupt string concatenation. The solution: **flex hash functions** that read bytes from multiple sources on-the-fly without constructing intermediate byte strings.

`sha1flex(data, dataHex, prefix, prefixHex, prefixXor)` and `sha256flex(...)`:
- **Standalone**: `sha256flex(data, "", "", "", 0)` — reads all bytes from `data` string
- **HMAC inner**: `sha256flex(message, "", key, "", 54)` — first 64 bytes = key XOR 0x36, rest = message
- **HMAC outer**: `sha256flex("", innerHex, key, "", 92)` — first 64 bytes = key XOR 0x5c, rest = hex-decoded inner hash

No byte string with potential null bytes is ever created. Hex decoding happens inside the hash's byte-reading loop.

## Static Methods (7)

| Method | Signature | Purpose |
|--------|-----------|---------|
| `sha1` | `(data: string): string` | SHA-1 hash, 40-char hex |
| `sha256` | `(data: string): string` | SHA-256 hash, 64-char hex |
| `hmacSHA256` | `(key: string, message: string): string` | HMAC-SHA256 (RFC 4231) |
| `hmacSHA1` | `(key: string, message: string): string` | HMAC-SHA1 (RFC 2202) |
| `hexToBytes` | `(hex: string): string` | Hex to byte string |
| `bytesToHex` | `(data: string): string` | Byte string to hex |
| `timingSafeEqual` | `(a: string, b: string): int` | Constant-time comparison |

## Internal Structure

| Function | Purpose |
|----------|---------|
| `sha1Rotl(x, n)` | Left rotate for SHA-1 |
| `sha1GetF(round, b, c, d)` | SHA-1 round function (4 variants) |
| `sha1GetK(round)` | SHA-1 round constant (4 values) |
| `cryptoHexDigit(c)` | Single hex char to int |
| `sha1flex(...)` | SHA-1 flex hash (standalone + HMAC) |
| `sha256flex(...)` | SHA-256 flex hash (standalone + HMAC) |
| `cryptoHmac256(key, msg)` | HMAC-SHA256 core |
| `cryptoHmac1(key, msg)` | HMAC-SHA1 core |
| `cryptoTimeSafe(a, b)` | Constant-time compare |

## Rejected Alternatives

1. **String-based HMAC** — Would fail ~12% of the time when inner hash contains 0x00 bytes due to null-terminated strings
2. **Array-based byte buffer** — SS array push returns new array (O(n) copy), making O(n^2) for building buffers
3. **Separate sha1.ss module** — SHA-1 standalone is less useful than having it bundled with HMAC in a crypto module

## Interfaces

```
import { Crypto } from "@/lib/crypto"

Crypto.sha1("abc")
// "a9993e364706816aba3e25717850c26c9cd0d89d"

Crypto.sha256("abc")
// "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

Crypto.hmacSHA256("Jefe", "what do ya want for nothing?")
// "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

Crypto.hmacSHA1("Jefe", "what do ya want for nothing?")
// "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"

Crypto.timingSafeEqual(hash1, hash2)  // 1 or 0
```
