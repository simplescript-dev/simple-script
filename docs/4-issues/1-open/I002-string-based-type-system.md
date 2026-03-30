---
id: I002
title: Type system uses raw string comparison
severity: high
related-decisions: []
related-principles: [P10]
origin: design-improvements.md DI-3
---
## Description
Types represented as bare strings: `"int"`, `"string"`, `"ptr"`, `"Array<int>"`, `"Map<string,int>"`.

Current problems:
- `inferType()` previously defaulted unknown variables to `"int"` (fixed to exit, but shows fragility)
- Generic parsing uses hand-written `indexOf("<")` + `substring()` — nested generics like `Map<string, Array<int>>` parse incorrectly
- No nullable types (`string?` vs `string`)
- No union types
- No type aliases
- Runtime types (`i32`, `ptr`) and semantic types (`int`, `string`) mixed throughout codegen

## Impact
- Adding generic-aware features requires increasingly brittle string manipulation
- Null safety impossible without nullable type distinction
- Runtime/semantic type confusion causes subtle codegen bugs (wrong LLVM type selected)
- Cannot implement proper type checking (I003) without structured type representation

## Best Practices
- **Go compiler**: `types.Type` interface — `*types.Basic`, `*types.Pointer`, `*types.Struct`, etc.
- **Rust compiler**: `ty::TyKind` enum — `Int`, `Str`, `Ref(ty)`, `Adt(def, substs)`, etc.
- **TypeScript compiler**: `Type` object with `flags`, `symbol`, `typeArguments`

## Proposed Solution
> ⚠️ **Blocked**: SS has no enum value types (enum is integer-only constant), cannot implement tagged union.
>
> **Short-term**: Types remain strings, but introduce `TypeInfo` concept — Map storing `kind`/`base`/`params` fields. Unified parsing functions replace ad-hoc indexOf/substring.
>
> **Long-term**: After SS supports enum + struct, migrate to structured type system.

## Context
Files: gen_exprs.ss (`inferType`, `resolveObjClass`), gen_stmts.ss, gen_class.ss, codegen.ss (`ssTypeToLLVM`).
