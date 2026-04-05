# D068 — Access Modifiers: `private` and `protected` Keywords

**Status:** Active
**Depends-on:** D061 (class body fields)

## Decision

Implement `private` and `protected` keywords for class fields and methods, following TypeScript conventions:
- **Default = public** (backward compatible)
- `private` = accessible only within the defining class
- `protected` = accessible within the defining class and its subclasses

## Reasoning

### Spec vs TS conventions

Spec 42 proposes "默认私有" (default private) with 4 levels: default/protected/internal/export. This contradicts TypeScript conventions where class members are **public by default**. Per CLAUDE.md design principles ("Java/TS 优先"), we follow TS:

| Modifier | TS | SS (this decision) |
|----------|-----|---------------------|
| (default) | public | public |
| `private` | class-only | class-only |
| `protected` | class + subclass | class + subclass |

### Why not default-private

1. **Breaking change**: 14230 LOC compiler source + all existing user code would need `export` on every public member
2. **No module system**: SS has no `export` keyword yet — adding default-private without `export` would make cross-file access impossible
3. **TS alignment**: TypeScript uses public-by-default, `private` is opt-in

### Phased approach

- **Phase 1 (complete)**: `private` keyword for class fields and methods
- **Phase 2 (complete)**: `protected` for inheritance visibility
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

### `protected` keyword (Phase 2)

```simplescript
class Entity {
    protected health: int       // accessible in Entity and subclasses
    name: string

    protected function damage(amount: int) {
        this.health = this.health - amount
    }
}

class Player extends Entity {
    function takeDamage(amount: int) {
        this.damage(amount)     // OK — subclass access
        this.health += 5        // OK — subclass access
    }
}

function main() {
    let p = new Player(100, "Alice")
    p.takeDamage(20)            // OK — public method
    p.health                    // ERROR — protected field
    p.damage(10)                // ERROR — protected method
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

Both PARAM (field) and FUNC_DECL (method) nodes use **I3 slot** for access level:
- `nGetI3(id) == 0` → public (default)
- `nGetI3(id) == 1` → private
- `nGetI3(id) == 2` → protected

### Changes by file

1. **lexer.ss**: Add `private` to `keywordKind()` → `"PRIVATE"`
2. **parser.ss**:
   - `isBodyFieldStart()`: handle `private` prefix
   - `parseBodyField()`: consume `private`, set `nSetI3(pId, 1)`
   - `parseClassDecl()`: consume `private` before methods, set `nSetI3(mId, 1)`
3. **checker.ss**:
   - Maps: `privateFields`/`privateMethods`, `protectedFields`/`protectedMethods` (key: `"ClassName.memberName"` → `"1"`)
   - Registration: populate during CLASS_DECL scan (I3==1 → private, I3==2 → protected)
   - `lookupPrivateOwner()`: walks parent chain, finds private member owner
   - `lookupProtectedOwner()`: walks parent chain, finds protected member owner
   - `isSubclassOf(child, ancestor)`: walks parent chain to check inheritance
   - Enforcement at 4 sites: MEMBER_ACCESS, MEMBER_ASSIGN, METHOD_CALL, DESTRUCTURE_OBJECT
   - Private rule: `currentCheckerClass != owningClass` → error
   - Protected rule: `currentCheckerClass != owningClass AND !isSubclassOf(currentCheckerClass, owningClass)` → error

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
