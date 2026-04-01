# D042: URL Module (lib/url.ss)

**Status:** Accepted
**Depends-on:** D035 (standard library pattern)

## Decision

Add `lib/url.ss` — a URL parsing, formatting, and query string handling library. Pure SS implementation, no compiler changes.

## API

### Static Methods (7)

| Method | Signature | Description |
|--------|-----------|-------------|
| `URL.parse` | `(input: string): UrlParts` | Parse URL string into components |
| `URL.format` | `(parts: UrlParts): string` | Format UrlParts back to URL string |
| `URL.resolve` | `(base: string, ref: string): string` | Resolve relative URL against base |
| `URL.parseQuery` | `(qs: string): Map<string, string>` | Parse query string to Map |
| `URL.encodeQuery` | `(keys: Array<string>, values: Array<string>): string` | Encode parallel arrays to query string |
| `URL.encodeComponent` | `(str: string): string` | Percent-encode string (RFC 3986) |
| `URL.decodeComponent` | `(str: string): string` | Decode percent-encoded string |

### UrlParts Instance Methods (11)

| Method | Returns | Description |
|--------|---------|-------------|
| `protocol()` | `string` | Scheme without colon ("https") |
| `username()` | `string` | Userinfo username |
| `password()` | `string` | Userinfo password |
| `hostname()` | `string` | Host name (includes brackets for IPv6) |
| `port()` | `string` | Port number or empty string |
| `pathname()` | `string` | Path component |
| `search()` | `string` | Query string without leading ? |
| `hash()` | `string` | Fragment without leading # |
| `host()` | `string` | hostname:port (or just hostname) |
| `origin()` | `string` | protocol://host |
| `href()` | `string` | Full reconstructed URL |

## Architecture

- **Storage**: Map-based (like json.ss/csv.ss). Global `urlData` Map keyed by `"id.field"`.
- **Parsing**: Multi-pass extraction: fragment → query → scheme → authority/path.
- **Authority**: Handles userinfo@, IPv6 brackets, port detection.
- **Percent encoding**: RFC 3986 unreserved set (A-Z, a-z, 0-9, `-._~`).
- **Decode**: Supports both `%XX` sequences and `+` as space.
- **encodeQuery**: Accepts parallel arrays (not Map) due to SS Map parameter limitation with `.keys()`.

## Reasoning

- URL parsing is a natural complement to the existing http.ss module.
- Every major language has a URL parsing utility (Go `net/url`, Python `urllib.parse`, Node.js `URL`).
- Component values returned without delimiters (Go/Python style) for practical programmatic use.
- Protocol is auto-lowercased per RFC 3986; hostname and path case preserved.

## Rejected Alternatives

- **WHATWG-style with delimiters** (protocol returns "https:", search returns "?q=1"): Less practical for programmatic use. Go/Python convention preferred.
- **Map parameter for encodeQuery**: `Map.keys()` unreliable on function-parameter Maps in SS. Parallel arrays are a clean workaround.
- **Regex-based parsing**: SS has no regex support. Character-level parsing is explicit and maintainable.

## Interfaces

```
import { URL, UrlParts } from "@/lib/url"
```

## Tensions

None. Pure library addition, no compiler changes needed.
