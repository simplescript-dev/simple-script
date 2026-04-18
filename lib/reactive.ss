// reactive — Vue-style 响应式底层原语,基于 D096 class get/set accessors。
// 用户可用 ref(v) 包一个值,effect(fn) 注册副作用;对 .value 的读写会
// 把当前 effect 记到依赖表,写入时重跑订阅的 effects。
// 类名 RxRef 而非 Ref,避开 D082 built-in Ref<T> 的 .value 拦截。

let activeEffectId = 0
let reactiveEffects = []
let reactiveDeps = Map()

function effect(fn: fn) {
    reactiveEffects.push(fn)
    const eid = reactiveEffects.length()
    activeEffectId = eid
    fn()
    activeEffectId = 0
}

function track(depKey: string) {
    if (activeEffectId == 0) { return }
    const cur = reactiveDeps.has(depKey) == 1 ? reactiveDeps.getString(depKey) : ""
    const sid = `${activeEffectId}`
    if (cur != "") {
        const parts = cur.split(",")
        for (p in parts) {
            if (p == sid) { return }
        }
    }
    const next = cur == "" ? sid : `${cur},${sid}`
    reactiveDeps.set(depKey, next)
}

function trigger(depKey: string) {
    if (reactiveDeps.has(depKey) == 0) { return }
    const eids = reactiveDeps.getString(depKey)
    if (eids == "") { return }
    const parts = eids.split(",")
    for (p in parts) {
        const eid = parseInt(p)
        if (eid >= 1 && eid <= reactiveEffects.length()) {
            const f = reactiveEffects[eid - 1]
            f()
        }
    }
}

let nextRefId = 1

class RxRef {
    _v: int = 0
    _depKey: string = ""
    get value(): int {
        track(this._depKey)
        return this._v
    }
    set value(v: int) {
        this._v = v
        trigger(this._depKey)
    }
}

function rxRef(v: int): RxRef {
    const key = `RxRef#${nextRefId}`
    nextRefId = nextRefId + 1
    return new RxRef(_v: v, _depKey: key)
}
