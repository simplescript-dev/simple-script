# D035: Standard Library — path.ss & fs.ss

**Status:** Accepted
**Depends on:** D021 (Array/List), class static method pattern (JSON.parse)

## Decision

Add two standard library modules following Node.js API conventions:

1. **path.ss** — Pure SS path string manipulation
2. **fs.ss** — High-level file system wrapper over existing runtime functions

## API Design

### path.ss

Static methods on `Path` class (same pattern as `JSON`, `Math`):

| Method | Signature | Description |
|--------|-----------|-------------|
| `Path.join(a, b)` | `(string, string): string` | Join 2 path segments |
| `Path.join(a, b, c)` | `(string, string, string): string` | Join 3 segments |
| `Path.join(a, b, c, d)` | `(string, string, string, string): string` | Join 4 segments |
| `Path.basename(path)` | `(string): string` | Last component of path |
| `Path.dirname(path)` | `(string): string` | Directory portion |
| `Path.extname(path)` | `(string): string` | File extension (with dot) |
| `Path.isAbsolute(path)` | `(string): int` | 1 if starts with `/` |
| `Path.normalize(path)` | `(string): string` | Resolve `.` and `..` |
| `Path.resolve(base, rel)` | `(string, string): string` | Resolve relative to base |

### fs.ss

Static methods on `FS` class wrapping runtime builtins:

| Method | Wraps | Description |
|--------|-------|-------------|
| `FS.readFile(path)` | `readFile` | Read file content |
| `FS.writeFile(path, content)` | `writeFile` | Write file |
| `FS.appendFile(path, content)` | `appendFile` | Append to file |
| `FS.exists(path)` | `fileExists` | Check existence |
| `FS.fileSize(path)` | `fileSize` | Get file size |
| `FS.mkdir(path)` | `mkdir` | Create directory |
| `FS.mkdirp(path)` | `mkdirp` | Create directory recursively |
| `FS.readDir(path)` | `listDir` + split | List directory as `Array<string>` |
| `FS.remove(path)` | `removeFile` | Remove file |
| `FS.rename(old, new)` | `renameFile` | Rename file |

## Reasoning

- **Node.js API alignment** (V1): `Path.join`, `Path.basename` etc. mirror `path.join`, `path.basename` from Node.js. Familiar to TS/JS developers.
- **Pure SS** (V4): path.ss is 100% pure SS string manipulation. fs.ss is thin wrapper over existing C-backed runtime functions.
- **Static method pattern**: Reuses established `class X() + function X_method()` pattern from json.ss (JSON.parse etc.).
- **Overloaded join**: 2/3/4-arg variants use SS function overloading (different param count → different mangled names).

## Rejected Alternatives

- **Global functions** (`joinPath`, `readDir`): Less organized, pollutes global namespace.
- **Rest parameters** (`Path.join(...parts)`): SS doesn't support rest params. Overloaded variants are simpler.
- **Class instances** (`new Path("/usr/local")`): Unnecessary complexity for stateless operations.

## Tensions

- `FS.readDir` returns `Array<string>` parsed from newline-separated `listDir()` output. If `listDir()` runtime format changes, this breaks. Acceptable since we control the runtime.
