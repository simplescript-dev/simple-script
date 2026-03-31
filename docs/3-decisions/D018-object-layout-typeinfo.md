# D018: Object Layout with RC + TypeInfo

## Status
firm

## Resolves
Object memory layout redesign — RC header moves from hidden prefix to struct offset 0, plus TypeInfo pointer at offset 1 for vtable-based drop dispatch.

## Depends On
- axioms.md → C4 (no GC, deterministic RC)
- axioms.md → C2 (runtime functions generated as LLVM IR)
- D017 (field-level const — mutable fields require proper RC on field reassignment)

## Decision
Every class instance has a fixed two-field header:

```llvm
%Player = type {
    i32,              ; rc (offset 0)
    %TypeInfo*,       ; type_info (offset 1)
    ptr,              ; name: string (offset 2)
    i64,              ; health: int (offset 3)
    i64,              ; x: int (offset 4)
    i64               ; y: int (offset 5)
}
```

RC operations use bitcast to generic header:
```llvm
%RcHeader = type { i32, %TypeInfo* }
%hdr = bitcast %Player* %p to %RcHeader*
call void @ss_retain(%RcHeader* %hdr)
```

TypeInfo is a per-class global constant:
```llvm
%TypeInfo = type {
    void (%RcHeader*)*,         ; drop function pointer
    i8* (%RcHeader*, i64)*,     ; deep_clone function pointer
    i8* (%RcHeader*, i64)*,     ; shallow_clone function pointer
    i64,                         ; object size (bytes)
    ptr                          ; type name string
}

@Player_type_info = constant %TypeInfo {
    void (%RcHeader*)* @ss_drop_Player,
    i8* (%RcHeader*, i64)* @ss_deep_clone_Player,
    i8* (%RcHeader*, i64)* @ss_shallow_clone_Player,
    i64 48,
    ptr @.str.Player
}
```

`ss_release` is fully generic — reads drop function from TypeInfo vtable. No tag-based dispatch.

## Key Reasoning (3 sentences max)
RC and fields in same contiguous memory improves cache locality (rc_inc + field access hit same cache line). TypeInfo pointer enables generic ss_release without tag-based switch — scales cleanly to any number of classes. DWARF debug info can describe rc as a regular struct field, improving debuggability.

## Rejected Alternatives
- Hidden header (current approach): RC at negative offset, tag-based drop dispatch. Requires magic number validation, cache-unfriendly, debugger-hostile.
- Separate RC table (Swift-style side table): Over-engineered for a language without weak references.
- No TypeInfo, keep tag-based dispatch: Doesn't scale. Adding new class-specific behavior requires new tag values and more switch cases.

## Interfaces With Other Decisions
- D017 (field-level const): const fields have no layout difference — enforcement is compile-time only.
- D019 (Perceus IR): ALLOC instruction fills both rc=1 and TypeInfo pointer.
- D020 (runtime functions): ss_release reads TypeInfo to find drop. ss_alloc initializes rc and TypeInfo.
- D022 (clone): TypeInfo contains clone function pointers for vtable dispatch.

## Open Tensions
- Phase 4 (interface): TypeInfo will need extension for method vtable. Current layout has 5 fields. Adding method dispatch may require a variable-length method table appended after the fixed fields.
- 8 bytes overhead per object (TypeInfo pointer). Acceptable for heap objects, but makes small-object allocation less efficient.

## Notes
Replaces current hidden-header layout (16 bytes prefix with rc:i64 + tag:i32 + magic:i32). New layout: rc:i32 + TypeInfo*:ptr as struct fields. All field GEP indices shift by +2 (rc=0, type_info=1, first_field=2). Decision confirmed 2026-03-31.
