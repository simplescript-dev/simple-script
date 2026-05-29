// Runtime prelude — pure SS implementations of string/array methods
// _ss_ prefix avoids conflict with C runtime declarations

// ── Built-in classes ─────────────────────────────────────────

class Error {
    message: string
}

// D080: exec() process output capture
class ExecResult {
    stdout: string
    exitCode: int
}

// D097 Meta objects — comptime reflection carrier classes.
// Constructed by compiler during cls.fields/cls.annotations evaluation;
// user code reads `.name`/`.type`/`.args` via MEMBER_ACCESS on iteration binding.
class FieldMeta {
    name: string
    type: string
    annotations: Array<AnnotationMeta>
}

// D127 §A.1 I003 — args value 形态:AstNodeId(raw int),
// 通过 evalAnnotationArg(nodeId) 按 nKind 分派 eval 得 typed tv;
// 消费走 args.getString/getInt/getBool/getDouble typed accessor
// (I004 接 getEnum / I005 接 getArray / I006 接 getClass)。
class AnnotationMeta {
    name: string
    args: Map<string, int>
}

// D120 §Phase 1 — 补齐 5 类 Meta。
// I021 — annotations 对称 FieldMeta/MethodMeta/ClassMeta,承载 param-level annotation
// (@RequestParam/@PathVariable/…);AST 存于 PARAM.I4 单节点,由
// interp_obj.ss:buildAnnotationMetaArrayFromSingle 包单元素数组交付。
class ParamMeta {
    name: string
    type: string
    annotations: Array<AnnotationMeta>
}

class MethodMeta {
    name: string
    params: Array<ParamMeta>
    returnType: string
    annotations: Array<AnnotationMeta>
}

class ClassMeta {
    name: string
    fields: Array<FieldMeta>
    methods: Array<MethodMeta>
    annotations: Array<AnnotationMeta>
}

// D120 Execute 1 Phase 1 — reflect namespace:checker 接受 `reflect.classes()` 语法,
// comptime 在 method_call.ss 分派到 ctReflectMethodDispatch;runtime 入口不可达
// (所有调用点需在 comptime block 内)。空实例仅为 checker IDENT resolve。
class Reflect {}
const reflect = new Reflect()

// ── Higher-order array methods ────────────────────────────────

function _ss_map(arr: List<int>, callback: fn): List<int> {
    const len = arr.length()
    let result = []
    for (let i = 0; i < len; i++) {
        result = result.push(callback(arr[i]))
    }
    return result
}

function _ss_filter(arr: List<int>, predicate: fn): List<int> {
    const len = arr.length()
    let result = []
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            result = result.push(arr[i])
        }
    }
    return result
}

function _ss_reduce(arr: List<int>, callback: fn, initial: int): int {
    let acc = initial
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        acc = callback(acc, arr[i])
    }
    return acc
}

function _ss_forEach(arr: List<int>, callback: fn) {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        callback(arr[i])
    }
}

function _ss_find(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            return arr[i]
        }
    }
    return 0
}

function _ss_findIndex(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            return i
        }
    }
    return -1
}

function _ss_some(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 1) {
            return 1
        }
    }
    return 0
}

function _ss_every(arr: List<int>, predicate: fn): int {
    const len = arr.length()
    for (let i = 0; i < len; i++) {
        if (predicate(arr[i]) == 0) {
            return 0
        }
    }
    return 1
}

// ── String methods ────────────────────────────────────────────

function _ss_trim(s: string): string {
    let start = 0
    while (start < s.length()) {
        const ch = s.charAt(start)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        start = start + 1
    }
    let end = s.length()
    while (end > start) {
        const ch = s.charAt(end - 1)
        if (ch != " " && ch != "\t" && ch != "\n" && ch != "\r") { break }
        end = end - 1
    }
    return s.substring(start, end - start)
}

function _ss_replace(s: string, old: string, newStr: string): string {
    let result = ""
    let pos = 0
    const oldLen = old.length()
    const sLen = s.length()
    if (oldLen == 0) { return s }
    while (pos <= sLen - oldLen) {
        const remaining = s.substring(pos, sLen - pos)
        const idx = remaining.indexOf(old)
        if (idx < 0) { break }
        result = result + s.substring(pos, idx) + newStr
        pos = pos + idx + oldLen
    }
    result = result + s.substring(pos, sLen - pos)
    return result
}

function _ss_toUpperCase(s: string): string {
    let result = ""
    let i = 0
    while (i < s.length()) {
        const code = charCodeAt(s, i)
        if (code >= 97 && code <= 122) {
            result = result + fromCharCode(code - 32)
        } else {
            result = result + s.charAt(i)
        }
        i = i + 1
    }
    return result
}

function _ss_toLowerCase(s: string): string {
    let result = ""
    let i = 0
    while (i < s.length()) {
        const code = charCodeAt(s, i)
        if (code >= 65 && code <= 90) {
            result = result + fromCharCode(code + 32)
        } else {
            result = result + s.charAt(i)
        }
        i = i + 1
    }
    return result
}

function _ss_repeat(s: string, n: int): string {
    let result = ""
    for (let i = 0; i < n; i++) {
        result = result + s
    }
    return result
}

function _ss_padStart(s: string, width: int, pad: string): string {
    if (s.length() >= width) { return s }
    let result = s
    while (result.length() < width) {
        result = pad + result
    }
    if (result.length() > width) {
        result = result.substring(result.length() - width, width)
    }
    return result
}

function _ss_padEnd(s: string, width: int, pad: string): string {
    if (s.length() >= width) { return s }
    let result = s
    while (result.length() < width) {
        result = result + pad
    }
    if (result.length() > width) {
        result = result.substring(0, width)
    }
    return result
}

// Compile-time directive: maps annotation name → handler function.
// No runtime behavior — processed during compilation.
function annotationMapping(name: string, handler: fn) {}

function _ss_join(arr: List<string>, delim: string): string {
    const len = arr.length()
    if (len == 0) { return "" }
    let result = ""
    let first = 1
    for (let i = 0; i < len; i++) {
        if (first == 1) {
            first = 0
        } else {
            result = result + delim
        }
        result = result + arr[i]
    }
    return result
}

// finding A(D171 收口验收): scalar 数组 join 的 typed 变体。签名 List<int>/<double>/<bool>
// 让 `result + arr[i]` 的 genExprAsString 按真实元素类型转换(int→ss_int_to_string /
// double→ss_double_to_string),而非把位值当 string ptr 解引用(段错根因)。body 与
// _ss_join 同构,仅元素类型差。array.join codegen 按 inferArrayElemType 分派(gen_methods.ss)。
function _ss_joinInt(arr: List<int>, delim: string): string {
    const len = arr.length()
    if (len == 0) { return "" }
    let result = ""
    let first = 1
    for (let i = 0; i < len; i++) {
        if (first == 1) {
            first = 0
        } else {
            result = result + delim
        }
        result = result + arr[i]
    }
    return result
}

function _ss_joinDouble(arr: List<double>, delim: string): string {
    const len = arr.length()
    if (len == 0) { return "" }
    let result = ""
    let first = 1
    for (let i = 0; i < len; i++) {
        if (first == 1) {
            first = 0
        } else {
            result = result + delim
        }
        result = result + arr[i]
    }
    return result
}

function _ss_joinBool(arr: List<bool>, delim: string): string {
    const len = arr.length()
    if (len == 0) { return "" }
    let result = ""
    let first = 1
    for (let i = 0; i < len; i++) {
        if (first == 1) {
            first = 0
        } else {
            result = result + delim
        }
        result = result + arr[i]
    }
    return result
}
