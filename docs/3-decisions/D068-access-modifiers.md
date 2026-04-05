# D068 — Access Modifiers: `private` Keyword

**Status:** Active
**Depends-on:** D061 (class body fields)

## Decision

Implement `private` keyword for class fields and methods, following TypeScript conventions:
- **Default = public** (backward compatible)
- `private` = accessible only within the defining class

## Reasoning

### Spec vs TS conventions

Spec 42 proposes "默认私有" (default private) with 4 levels: default/protected/internal/export. This contradicts TypeScript conventions where class members are **public by default**. Per CLAUDE.md design principles ("Java/TS 优先"), we follow TS:

| Modifier | TS | SS (this decision) |
|----------|-----|---------------------|
| (default) | public | public |
| `private` | class-only | class-only |
| `protected` | class + subclass | future phase |

### Why not default-private

1. **Breaking change**: 14230 LOC compiler source + all existing user code would need `export` on every public member
2. **No module system**: SS has no `export` keyword yet — adding default-private without `export` would make cross-file access impossible
3. **TS alignment**: TypeScript uses public-by-default, `private` is opt-in

### Phased approach

- **Phase 1 (this round)**: `private` keyword for class fields and methods
- **Phase 2 (future)**: `protected` for inheritance visibility
- **Phase 3 (future)**: Module-level `export` when module system matures

## Syntax

```simplescript
class Player {
    const name: string           // public (default)
    private health: int          // private — only within Player
    x: int

    function move(dx: int) {     // public method
        this.health -= 1         // OK — same class
        this.x = this.x + dx
    }

    private function heal() {    // private method
        this.health += 10        // OK — same class
    }
}

function main() {
    let p = new Player("Alice", 100, 0)
    p.x = 5                     // OK — public field
    p.move(3)                   // OK — public method
    p.health = 50               // ERROR — private field
    p.heal()                    // ERROR — private method
}
```

### `private` + `const` combination

```simplescript
class Config {
    private const secret: string   // private AND immutable
    name: string
}
```

### Same-class instance access (TS behavior)

```simplescript
class Vec {
    private x: int
    private y: int

    function add(other: Vec): Vec {
        return new Vec(this.x + other.x, this.y + other.y)
        // OK — other.x is private but accessed within Vec class
    }
}
```

## Implementation

### AST storage

Both PARAM (field) and FUNC_DECL (method) nodes use **I3 slot** for private flag:
- `nGetI3(id) == 1` → private
- `nGetI3(id) == 0` → public (default)

### Changes by file

1. **lexer.ss**: Add `private` to `keywordKind()` → `"PRIVATE"`
2. **parser.ss**:
   - `isBodyFieldStart()`: handle `private` prefix
   - `parseBodyField()`: consume `private`, set `nSetI3(pId, 1)`
   - `parseClassDecl()`: consume `private` before methods, set `nSetI3(mId, 1)`
3. **checker.ss**:
   - New Maps: `privateFields`, `privateMethods` (key: `"ClassName.memberName"` → `"1"`)
   - Registration: populate during CLASS_DECL scan
   - Enforcement: check in MEMBER_ACCESS, MEMBER_ASSIGN, METHOD_CALL
   - Rule: if member is private AND `currentCheckerClass != owningClass` → error

### No codegen changes

Access control is purely compile-time. No LLVM IR changes needed.

## Rejected Alternatives

1. **Default-private (spec 42)**: Breaking change, no export keyword yet
2. **`internal` keyword**: Needs package system (doesn't exist)
3. **Annotation-based (`@private`)**: Non-standard, TS uses keyword
4. **String-based S3 slot**: S3 already used for "const" on PARAM nodes; I3 is cleaner

## Tensions

- **Spec 42 deviation**: We use public-by-default instead of spec's private-by-default. Justified by TS alignment principle and backward compatibility.
- **P9 (complexity in compiler)**: Access control adds checker complexity but gives users encapsulation — net positive.
