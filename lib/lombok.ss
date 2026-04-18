// Lombok-style annotation handlers for SimpleScript.
// Import via `import { X } from "@/lib/lombok"` and apply as `@X class Foo`.
// Semantics match Java Lombok.

function ToString(cls: string) {
    @methodOf(cls) function toString(): string {
        let parts = ""
        for (f in cls.fields) {
            if (parts != "") { parts = parts + ", " }
            parts = parts + f.name + "=" + this[f.name]
        }
        return cls.name + "(" + parts + ")"
    }
}

// Per-field accessor methods. Naming: get_<field>.
// Return type inferred from the RETURN expression — works for any field type.
function Getter(cls: string) {
    for (f in cls.fields) {
        @methodOf(cls) function [`get_${f.name}`]() {
            return this[f.name]
        }
    }
}

// Per-field mutators. Naming: set_<field>. Parameter forced to int because
// type-position comptime interpolation (`v: ${f.type}`) is not yet supported —
// @Setter on non-int fields will fail to compile.
function Setter(cls: string) {
    for (f in cls.fields) {
        @methodOf(cls) function [`set_${f.name}`](v: int) {
            this[f.name] = v
        }
    }
}
