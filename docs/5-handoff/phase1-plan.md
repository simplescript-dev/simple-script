# Phase 1 Implementation Plan: Perceus RC Foundation

## Overview
Transform SimpleScript from "all fields immutable + hidden RC header + ad-hoc RC" to "field-level const + TypeInfo vtable + Perceus IR". Compiler source uses OLD syntax throughout (Plan A bootstrap strategy).

## Dependencies Graph

```
[1. Parser: field const]  [2. Parser: field assign]  [3. Parser: named params]
         |                         |                          |
         v                         v                          v
   [4. Checker: const field validation] ←──────────────────────
         |
         v
[5. Object layout: RC@0 + TypeInfo@1]
         |
    ┌────┴────┐
    v         v
[6. Runtime] [7. Per-class drop/clone gen]
    |              |
    v              v
[8. Codegen: field assign + new layout]
         |
         v
[9. PIR lowering: AST → Perceus IR]
         |
         v
[10. PIR Pass 1: Liveness + rc_dec insertion]
         |
         v
[11. PIR → LLVM IR codegen]
         |
         v
[12. Collection rename: Array → List]
         |
         v
[13. Set type: Map wrapper]
         |
         v
[14. mimalloc integration]
         |
         v
[15. Test suite + validation]
```

## Sub-Tasks (execution order)

### Step 1: Parser — Field-Level const (D017)
**File:** parser.ss
**What:** Extend `parseClassDecl()` field parsing to recognize `const` modifier before field name.
**AST change:** PARAM node gets S3="const" or S3="" to indicate field constness.
**Current:** `parseParams()` parses `name: Type`. Need to check for `const` keyword before name.
**Size:** ~15 lines parser change.
**Verify:** Parse `class Player { const name: string; health: int }` → AST has const metadata.

### Step 2: Parser — Field Assignment (D017)
**File:** parser.ss
**What:** Extend `parseAssignOrExpr()` to handle `obj.field = value` and `obj.field += value`.
**Current:** Only handles `name = value` where name is a simple identifier. Does NOT handle member access on LHS.
**Approach:** After parsing primary expression, check if it ends with `.field` and next token is `=`/`+=`/etc. Create new AST node `MEMBER_ASSIGN` with:
- I1 = object expression (may be nested MEMBER_ACCESS chain)
- S1 = final field name
- S2 = operator ("ASSIGN", "PLUS_ASSIGN", etc.)
- I2 = value expression
**Nested:** `a.b.c = v` → I1 is MEMBER_ACCESS(MEMBER_ACCESS(a, b), c)... actually I1 should be the full chain and S1 the last field. Or: I1 = object expr for `a.b`, S1 = `c`.
**Size:** ~40-60 lines parser change.
**Verify:** Parse `hero.health -= 25` and `hero.weapon.damage += 10` → correct AST.

### Step 3: Parser — Named Parameter Construction (D017)
**File:** parser.ss
**What:** Extend `new ClassName(...)` parsing to support `new Player(name: "Alice", health: 100)`.
**Approach:** In argument parsing for NEW_EXPR, check if current pattern is `IDENT : expr`. If so, create NAMED_ARG nodes with S1=paramName, I1=valueExpr.
**Size:** ~30 lines parser change.
**Verify:** Parse `new Player(name: "Alice", health: 100)` → AST with named arg nodes.

### Step 4: Checker — const Field Validation (D017)
**File:** checker.ss
**What:** Add a check pass that rejects assignment to `const` fields.
**Approach:**
- Build a Map `constFields`: `"ClassName.fieldName" → 1` during class declaration walk
- When encountering MEMBER_ASSIGN node, check if target field is in constFields
- For nested `a.b.c = v`, walk the chain to find the final field's class and check const status
- Error on const field assignment: use `checkerError()` with source location
**Size:** ~50-80 lines.
**Verify:** `hero.name = "Bob"` produces compile error. `hero.health -= 25` passes.

### Step 5: Object Layout Redesign (D018)
**File:** gen_class.ss
**What:** Change class struct layout:
- Old: `[vtable_ptr?][field1][field2]...` with hidden RC header at -16 bytes
- New: `[rc:i32][type_info:ptr][field1][field2]...`
**Changes:**
- `emitClassStruct()`: Prepend `i32, ptr` to all class struct types
- `getFieldIndex()`: Add +2 offset for rc and type_info fields
- `emitClassConstructor()`: Initialize rc=1 and type_info pointer instead of calling ss_rc_alloc
- All GEP indices shift by +2
**Size:** ~60-80 lines changed in gen_class.ss.
**Verify:** LLVM IR shows `%Player = type { i32, ptr, ptr, i64, i64, i64 }`.

### Step 6: Runtime Function Redesign (D020)
**File:** gen_runtime.ss
**What:** Replace current RC runtime functions with new ones:
- `ss_retain`: increment rc at offset 0 (no magic check, no null check needed internally)
- `ss_release`: decrement rc, if 0 read TypeInfo.drop and call it
- `ss_is_unique`: return rc == 1
- `ss_alloc`: allocate via mimalloc (or calloc initially), return raw pointer
- `ss_dealloc`: free via mimalloc (or free)
- `ss_shallow_copy`: memcpy + reset rc = 1
**Remove:** ss_rc_alloc, ss_rc_retain, ss_rc_release, ss_rc_release_no_children, ss_rc_realloc, ss_rc_strdup, ss_rc_calloc and their tag-based dispatch logic.
**Add:** `%RcHeader` and `%TypeInfo` type definitions.
**Size:** Major rewrite of emitRuntimeRC section (~200 lines replaced).
**Verify:** IR output contains new function definitions with correct signatures.

### Step 7: Per-Class Drop/Clone Generation (D018, D022)
**File:** gen_class.ss (new section)
**What:** For each class, compiler generates:
- `ss_drop_ClassName`: rc_dec all ref-type fields, call ss_dealloc
- `ss_deep_clone_ClassName`: allocate new object, copy fields (const/string → rc_inc, mutable ref → recursive deepClone)
- `ss_shallow_clone_ClassName`: ss_shallow_copy + rc_inc all ref-type fields
- `@ClassName_type_info`: global constant with function pointers + size + name
**Size:** ~100-150 lines new code.
**Verify:** TypeInfo constants appear in IR. Drop functions correctly release ref fields.

### Step 8: Codegen — Field Assignment + New Layout (D017, D018)
**Files:** gen_stmts.ss, gen_class.ss
**What:**
- Add `genMemberAssign()` in gen_stmts.ss: handle MEMBER_ASSIGN AST node
  - Walk member access chain → emit GEP sequence
  - For ref-type fields: rc_dec old value, rc_inc new value
  - For simple assign: store new value
  - For compound assign (+=/-=): load, compute, store
- Update `emitClassConstructor()` for new layout (rc at 0, TypeInfo at 1)
- Update `genNewExpr()` for named parameter support
**Size:** ~80-120 lines new/changed.
**Verify:** `hero.health -= 25` compiles to correct GEP+load+sub+store. `hero.name = "Bob"` rejected by checker.

### Step 9: PIR Lowering — AST → Perceus IR (D019)
**File:** new `gen_pir.ss`
**What:** Translate AST into PIR instruction sequence.
- VAR_DECL with class type → ALLOC + (if init from existing var) RC_INC
- MEMBER_ASSIGN → FIELD_SET
- MEMBER_ACCESS → FIELD_GET
- CALL with class params → CALL with param mode tags
- NEW_EXPR → ALLOC
- Method call .deepClone() → DEEP_CLONE
- Method call .shallowClone() → SHALLOW_CLONE
**Global state:** New Map-based node system for PIR (pirKind, pirStr1, etc.)
**Size:** ~200-300 lines.
**Verify:** Simple function lowers to correct PIR instruction sequence.

### Step 10: PIR Pass 1 — Liveness Analysis (D019)
**File:** new `pir_opt.ss`
**What:** Scan PIR instruction list, mark last-use point for each variable, insert RC_DEC after last use.
**Approach:** Reverse scan → first occurrence of variable (in reverse) is its last use → insert RC_DEC after that instruction.
**Size:** ~80-120 lines.
**Verify:** Variables get exactly one RC_DEC. No leaks, no double-frees.

### Step 11: PIR → LLVM IR Codegen (D019)
**File:** modified codegen pipeline
**What:** Traverse PIR instruction list, emit LLVM IR for each instruction:
- RC_INC → `call void @ss_retain(%RcHeader* %hdr)`
- RC_DEC → `call void @ss_release(%RcHeader* %hdr)`
- ALLOC → `call i8* @ss_alloc(i64 size)` + bitcast + init fields
- FIELD_SET → GEP + store (+ RC ops for ref fields)
- FIELD_GET → GEP + load
- etc.
**Size:** ~150-200 lines.
**Verify:** End-to-end: source → AST → PIR → LLVM IR → binary → correct output.

### Step 12: Collection Rename — Array → List (D021)
**Files:** gen_runtime.ss, gen_exprs.ss, gen_stmts.ss, gen_registry.ss, checker.ss, parser.ss
**What:** Rename all `Array` references to `List` in type annotations, runtime function names (or add aliases), and type inference.
**Approach:** Can be done as simple string replacement in type matching logic. Runtime functions can keep internal `ss_array*` names but user-facing type changes to `List<T>`.
**Size:** ~30-50 lines changed across files.
**Verify:** `let items: List<string> = []` compiles. Old `Array<string>` still works (or produces helpful error).

### Step 13: Set Type (D021)
**File:** gen_runtime.ss (or prelude.ss)
**What:** Implement Set<T> as Map<T, bool> wrapper.
**Approach:** Can be a prelude-level implementation (pure SS) or runtime functions.
Methods: add, has, remove, size, values.
**Size:** ~30-50 lines.
**Verify:** `let s = new Set<string>(); s.add("x"); s.has("x") == true`.

### Step 14: mimalloc Integration (D020)
**File:** build.sh, gen_runtime.ss
**What:** Download and compile mimalloc/src/static.c. Link with musl-gcc. Update ss_alloc/ss_dealloc to use mi_calloc/mi_free.
**Approach:** Add mimalloc as git submodule or vendored source. Compile static.c with musl-gcc. Link into final binary.
**Size:** Build system change + ~10 lines runtime change.
**Verify:** Binary links successfully. Allocation/deallocation works.

### Step 15: Test Suite + Validation
**What:** Write comprehensive tests for all new features:
- Field-level const (compile error tests)
- Field assignment (single, nested, compound)
- Named parameter construction
- deepClone / shallowClone behavior
- Reference semantics (let b = a shares object)
- Function parameter mutation visibility
- Collection operations (List, Set)
- RC correctness (no leaks, no double-frees via valgrind)
**Verify:** All examples from spec/71-perceus-rc.md produce correct output.

## Execution Strategy

**Recommended order:** Steps 1-4 (parser + checker) can be done first with existing codegen (just parse and check, don't generate new code yet). Steps 5-8 (layout + runtime + codegen) form the core implementation. Steps 9-11 (PIR) can be deferred to a sub-phase if needed. Steps 12-14 are independent.

**Minimum viable slice:** Steps 1, 2, 4, 5, 6, 7, 8 give a working compiler with field-level const + field assignment + new object layout. PIR (steps 9-11) can follow as Phase 1b.

## Risk Assessment

- **Highest risk:** Step 5+6 (layout + runtime redesign) — breaks all existing class compilation. Must be done atomically.
- **Bootstrap break:** Step 5 changes object layout → seed compiler's runtime is incompatible → cannot self-bootstrap until Step 15 validates everything.
- **Mitigation:** Keep seed compiler (bin/ss) frozen. Test with seed-compiled new compiler only.
