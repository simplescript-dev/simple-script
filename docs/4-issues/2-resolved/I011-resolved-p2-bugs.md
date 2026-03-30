---
id: I011
title: "Resolved P2 bugs — architecture/maintainability"
severity: medium
resolved-by: direct fixes + D001, D002
origin: design-issues.md #13-20
---

### #13: `resetCodegen` missed variable resets ✅
- 20+ variables not reset. Guard flags prevented re-initialization.
- Fixed: reset guard flags, then call init functions, then reset all remaining vars.

### #14: `genMethodCall` 305-line if/else chain ✅
- 25+ built-in methods in serial `if (method == "xxx")` checks.
- Fixed (D001): split into genStringMethod, genHigherOrderMethod, genArrayMethod, genMapMethod. classHasMethod() for parent chain lookup.

### #15: AST nodes use positional slots, not named properties ✅
- `nInt4` means annotation on FUNC_DECL but body on FOR.
- Fixed: 16 semantic accessors (funcName, funcRetType, classNodeName, varName, etc.). Partial migration.

### #16: `inferType` silent fallback to "int" ✅
- Unknown variables/methods/null nodes all returned `"int"`.
- Fixed: NULL_LIT→"ptr", THIS→currentClassName, SPREAD_ELEM→recursive. Removed dead NEW_EXPR duplicate.

### #17: Severe code duplication ✅
- Three identical param alloca/store blocks, two identical annotation parse blocks.
- Fixed: `emitParamAllocas()` (~45→3 lines), `parseAnnotationList()` + `attachAnnotations()`.

### #18: Import path no normalization ✅
- `./foo/../bar` and `./bar` treated as different files.
- Fixed: `normalizePath()` resolves `.`/`..` path components.

### #19: Lexer template string missing `%` operator ✅
- `${x % 3}` triggered lexer error.
- Fixed: added `%` token dispatch in template expression mode.

### #20: Lexer no hex/binary literals ✅
- `0xFF` parsed as `INT 0` + `IDENT xFF`.
- Fixed: `lexNumber` detects `0x`/`0b`/`0o` prefixes.
