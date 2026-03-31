# D025: Interface Polymorphism via Switch-based Dispatch

## Status
Accepted

## Resolves
No runtime polymorphism beyond class inheritance — interface-typed variables cannot be declared, interface methods cannot be dispatched dynamically.

## Depends On
- D018 (object layout — TypeInfo at offset 1)
- D019 (Perceus IR — interface-typed vars need RC tracking)
- axioms.md → C5 (no user-facing memory syntax)
- axioms.md → V3 (best practices from mature compilers)

## Decision
Implement interface polymorphism using switch-based dispatch via `class_id` in TypeInfo:

1. **TypeInfo extended**: `%TypeInfo = type { ptr, ptr, ptr, i64, ptr, i32 }` — 6th field `class_id: i32` uniquely identifies each class at compile time.

2. **Interface values are plain `ptr`**: No fat pointers. Interface-typed variables hold a direct pointer to a class instance. The concrete type is recovered at runtime via TypeInfo.class_id.

3. **Switch-based dispatch**: For each (interface, method) pair, the compiler generates a dispatch function `@__iface_InterfaceName_methodName(ptr %self, ...)` that:
   - Loads TypeInfo from the object header (offset 1)
   - Loads class_id from TypeInfo (slot 5)
   - Switches on class_id to the correct concrete class method
   - Default case returns zero/null

4. **RC unchanged**: `ss_retain`/`ss_release` operate on ObjHeader (rc@0, TypeInfo@1), which is type-agnostic. Interface values use the new RC system (same as class instances).

5. **Existing infrastructure reused**: Parser (`parseInterfaceDecl`, class `: IFace` syntax), checker (`checkInterfaceImpl`), and lexer (`interface` keyword) were already implemented. Only codegen layer needed changes.

### Syntax
```
interface Shape {
    function area(): int
    function name(): string
}

class Circle(r: int) : Shape {
    function area(): int { return this.r * this.r * 3 }
    function name(): string { return "circle" }
}

function printShape(s: Shape) {
    println(s.name())
}
```

## Key Reasoning (3 sentences max)
SimpleScript is a whole-program compiler that sees all types at compile time, making switch-based dispatch the simplest correct approach. No fat pointers means zero architectural disruption — interface values flow through the existing type system, RC system, and PIR analysis unchanged. LLVM can optimize the switch to a jump table, matching the performance of vtable/itable approaches for small implementor counts.

## Rejected Alternatives
- **Fat pointer (Go-style itable)**: `{data_ptr, itable_ptr}` per interface value. Would require changing all variable storage from `ptr` to `{ptr, ptr}` for interface types, disrupting RC, PIR, and the entire codegen pipeline.
- **TypeInfo-embedded itable array**: Add per-interface itable pointers to TypeInfo. Requires runtime linear scan to find the correct itable by interface ID. More complex than switch-based dispatch for the same O(n) cost.
- **Global vtable with interface slots**: Assign globally unique vtable slots to interface methods. Conflicts with existing per-hierarchy vtable slot numbering. Would require sparse vtables.

## Interfaces With Other Decisions
- D018 (object layout): ObjHeader unchanged. TypeInfo gains one i32 field.
- D019 (PIR): Interface-typed variables recognized by `isUserClass()` → PIR manages their RC automatically.
- D024 (REUSE): Interface-typed variables are not ALLOC sources, so REUSE is unaffected.

## Open Tensions
- gen_class.ss grew to 648 lines (above 500-line guideline). Interface dispatch generation (~100 lines) is a candidate for extraction to a separate file if more interface features are added.
- Switch-based dispatch is O(n) in the number of implementors. For large n, itable-based dispatch (O(1)) would be better. Current approach is correct and simple; optimize later if profiling shows need.
- No interface inheritance (`interface A extends B`) yet. Can be added by merging method lists during registration.

## Notes
Implementation: ~130 lines across 10 files. 4 new test files in tests/phase5/ (interface_basic, interface_multi, interface_multi_iface, interface_return). Closure TypeInfo constants updated to include class_id=0 (gen_calls.ss). Bootstrap fixed-point verified. Decision confirmed 2026-03-31.
