// D096 Phase 4 L2α — TypeValue 在 comptime 支持 .name / .fields / .fields()
// 根因修复:
//   - ctMethodCallDispatch 补 objType=="type" 分支(T.fields() / T.name())
//   - MEMBER_ACCESS 的 .fields/.name 支持 interpType=="type"
//   - interpCtFieldsArray 从空壳改为读 classFields
class Counter {
    count: int = 0
    label: string = "x"
}

// D088 Phase 4:class 名在 comptime 当作 TypeValue 传递
const CN_NAME = comptime {
    return Counter.name
}

const CN_FIELD_COUNT = comptime {
    const fs = Counter.fields
    return fs.length()
}

const CN_FIRST_FIELD = comptime {
    const fs = Counter.fields()
    return fs[0]
}

function main() {
    println(`name=${CN_NAME}`)
    println(`count=${CN_FIELD_COUNT}`)
    println(`first=${CN_FIRST_FIELD}`)
}
