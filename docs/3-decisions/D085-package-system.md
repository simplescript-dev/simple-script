# D085: Package System — Local Path + Global Cache

**Status:** Done
**Depends on:** import system (existing)

## Background

Need `import { x } from "@van/tailwindcss"` to work. No remote registry — all packages are local (developed by the same author). Previous system used `ss_modules/` with git clone, which required copying packages per project.

## Decision

Two resolution strategies, both using `ss.json` dependencies:

### Strategy C: Local Path Reference (development)

```json
{
    "dependencies": {
        "@van/tailwindcss": "../van-ss/tailwindcss"
    }
}
```

Path is relative to project root. Source changes take effect immediately — no install step.

### Strategy B: Global Package Cache (published)

```json
{
    "dependencies": {
        "@van/tailwindcss": "0.1.0"
    }
}
```

Resolves to `~/.ss/packages/@van/tailwindcss/0.1.0/`. Installed via `ss publish` from the package directory.

### Package Entry Point

When a dependency resolves to a directory:
1. Read `ss.json` → `main` field (e.g., `"main": "src/index.ss"`)
2. Convention fallback: `src/index.ss` → `index.ss`

### Resolution Order

```
import { x } from "@/lib/test"          → projectRoot/lib/test.ss (existing)
import { x } from "./module"             → relative path (existing)
import { x } from "@van/tailwindcss"     → ss.json deps → path or ~/.ss/packages/
```

### CLI Commands

| Command | Action |
|---------|--------|
| `ss add @scope/name path` | Add dependency to ss.json |
| `ss publish` | Copy current package to `~/.ss/packages/{name}/{version}/` |
| `ss init` | Create ss.json with empty dependencies |

### Directory Layout

```
~/.ss/packages/
└── @van/
    └── tailwindcss/
        └── 0.1.0/
            ├── ss.json
            └── src/index.ss
```

## Implementation

All changes in `bootstrap/main.ss`:

- **`loadDeps()`**: Parses ss.json via `JSON.parse()` (lib/json.ss), extracts dependencies into depCache Map
- **`resolvePackage(importPath)`**: Check deps → local path or `~/.ss/packages/` → find entry point
- **`resolvePackageEntry(pkgDir)`**: Read ss.json main field via `JSON.parse()` or convention fallback
- **`resolveInner()`**: Bare import path → `resolvePackage()` (replaces `ss_modules/`)
- **`resolveImports()`**: Ensures projectRoot is absolute (for correct `../` resolution)
- **`cmdAdd()`**: Adds dependency entry to ss.json (string manipulation — no pretty-print stringify yet)
- **`cmdPublish()`**: Copies package to `~/.ss/packages/`

## Rejected Alternatives

### ss_modules/ (node_modules style)
Removed. Requires copying packages per project. Local path references are more efficient for single-author development.

### `ss install` command
Not needed. Path references resolve directly; version references read from `~/.ss/packages/` directly.

### `export` keyword for module visibility
Deferred. Current import system is full-file inlining — export has no effect without symbol-level module resolution (D084).
