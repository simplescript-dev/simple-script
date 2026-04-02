---
id: D065
title: INDEX_ACCESS type inference + builtin function return types
status: implemented
depends-on: [D053, D059]
---

## Decision

Extend `checkerInferType()` with INDEX_ACCESS support and register actual return types for built-in functions (replacing the generic "builtin" marker).

## Changes

### 1. INDEX_ACCESS in checkerInferType (checker.ss)

Added `extractElemType(t)` helper that extracts the type parameter from generic types:
- `"Array<string>"` → `"string"`, `"List<int>"` → `"int"`
- Handles nested generics: `"Array<Array<int>>"` → `"Array<int>"`
- Returns `""` for non-generic types

INDEX_ACCESS case:
- Infers the indexed expression's type via recursive `checkerInferType`
- If base type is Array/List/Tuple, extracts and returns element type
- Otherwise returns `""` (skip check)

### 2. INDEX_ASSIGN type checking (check_stmts.ss)

New type check site (8th): verifies assigned value type vs array element type.
- Looks up array variable type via `lookupVar`
- Extracts element type via `extractElemType`
- Checks with `isTypeCompatible`, errors on mismatch

### 3. Built-in function return types (checker.ss)

Changed `initChecker()` from registering all builtins as `"builtin"` to actual return types:
- **String-returning**: readLine, readFile, arg, getenv, listDir, sha256, tcpRead, fromCharCode, base64Encode, base64Decode
- **Int-returning**: parseInt, args, system, tcpListen, tcpAccept, tcpWrite, mkdir, mkdirp, fileExists, removeFile, renameFile, charCodeAt, timeMs, timeUnix, fileSize
- **Void-returning**: println, print, writeFile, appendFile, exit, tcpClose
- **Other**: parseDouble→double, Map→Map, Set→Set

This enables `checkerInferType(CALL)` to resolve return types for all builtins, not just user functions.

## Reasoning

- INDEX_ACCESS was the largest gap in `checkerInferType` — array element operations are common and type errors there produce silent wrong code
- Built-in function return types were low-hanging fruit: the codegen already had this info in `gen_registry.ss`, the checker just wasn't using it
- Both changes are conservative: unknown types still return `""` (check skipped), only verified mismatches produce errors

## Type Check Sites (8 total)

1. VAR_DECL (D053)
2. ASSIGN (D053)
3. MEMBER_ASSIGN (D053)
4. CALL args (D053)
5. METHOD_CALL args (D054)
6. RETURN (D060)
7. NEW_EXPR args (D064)
8. **INDEX_ASSIGN (D065)**

## Rejected Alternatives

- Full inferType migration (I003 Phase 4): Too large for one round. The two implementations serve different purposes (source-level types vs LLVM types) and have ~50 call sites to migrate. Better to enhance incrementally.
