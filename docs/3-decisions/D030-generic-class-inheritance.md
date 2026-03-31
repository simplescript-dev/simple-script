# D030: Generic Class Inheritance

## Status: Accepted

## Context

D027 implemented generic classes via monomorphization, D025 implemented class inheritance with vtable dispatch. These two features were independent — combining them enables TypeScript-equivalent generic inheritance patterns essential for real-world data modeling.

Three forms needed:
- **Case A**: Generic extends non-generic — `class Box<T> extends Container(value: T)`
- **Case B**: Non-generic extends specialized generic — `class IntBox extends Box<int>(extra: int)`
- **Case C**: Generic extends generic (type param forwarding) — `class LabeledBox<T> extends Box<T>(label: string)`

## Decision

Extend the existing monomorphization + inheritance infrastructure with:

1. **Parser**: `extends` clause accepts full type annotations (`parseTypeAnn()` instead of `pExpectIdent()`), storing `"Box<int>"` in CLASS_DECL S2.

2. **splitParentType helper**: Depth-counting parser to extract base name and type args from `"Box<int>"`, handling nested generics like `"Box<Array<int>>"`.

3. **registerClass** (Case B): When extends clause contains generic type args, builds substitution Map, computes mangled parent name, calls `preRegisterSpecializedClass` for the parent.

4. **preRegisterSpecializedClass** (Cases A & C): After own field/method registration, reads `rawParent` from AST. If parent is generic, resolves type args through current subs, recursively registers mangled parent, then does inline inheritance resolution (field prepending + type copying + vtable building).

5. **Deferred struct emission**: `registrationPhase` flag set to 1 during `registerAllDecls`. Specialized class structs are deferred until after `buildClassVtables()` provides vtable info. File-mode output writes to `${outFile}.str`.

6. **Deferred codegen**: Generic parents from `extends` may have no `new` expression. `generateDeferredSpecializations()` iterates `specClassNodeId`, rebuilds subs, and generates IR using state-save/buffer/flush pattern.

## Pre-existing Bug Fix

`resolveInheritance` had a 3+ level inheritance field duplication bug: flat Map iteration could process parent before child, causing grandparent fields to be prepended twice. Fixed by switching to recursive resolve-parent-first pattern (same as `buildVtableForClass`).

## Key Timing Constraints

- `registrationPhase = 1` must be set **before** the registration loop (not after), because `registerClass` → `preRegisterSpecializedClass` is called inside the loop
- `classNeedsVtable` on a parent must be set **before** recursive `preRegisterSpecializedClass` call (Case C), otherwise parent struct emits without vtable slot
- Deferred struct emission must use `strOutFile ?? irOutFile` for file-mode output, not just `strConsts`

## Files Changed

| File | Changes |
|------|---------|
| `bootstrap/parser.ss` | 1 line: `pExpectIdent()` → `parseTypeAnn()` |
| `bootstrap/checker.ss` | ~5 lines: strip generic args from parent name |
| `bootstrap/gen_class.ss` | ~130 lines: splitParentType + registerClass Case B + preRegisterSpecializedClass inheritance + deferred struct/codegen |
| `bootstrap/codegen.ss` | ~15 lines: registrationPhase timing + emitDeferredStructDefs call + generateDeferredSpecializations call + reset |
| `tests/phase5/` | 3 test files (Cases A, B, C) |
