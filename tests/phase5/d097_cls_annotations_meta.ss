// D097: cls.annotations 走 Meta 对象路径,plain comptime 访问。
// Meta 对象在 interp store 由 buildClassAnnotationMetaArray 构造;
// for-in 走 comptimeDepth>0 array 分支,绑 `a` 到 AnnotationMeta TV;
// a.name / a.args 通过 interpGetField 自然解析。

import { assertEqual } from "@/lib/test"

@Deprecated
@Override
class Target {
    x: int
}

@Route("/users", "GET")
@Tag("public")
class Api {
    z: int
}

function main() {
    test("D097 — cls.annotations Meta iteration, a.name", () => {
        const names = comptime {
            let acc = ""
            for (a in Target.annotations) {
                acc = acc + a.name + ";"
            }
            return acc
        }
        assertEqual(names, "Deprecated;Override;")
    })
    test("D097 — cls.annotations Meta iteration, a.args", () => {
        const argStr = comptime {
            let acc = ""
            for (a in Api.annotations) {
                for (v in a.args) {
                    acc = acc + a.name + "(" + v + ");"
                }
            }
            return acc
        }
        assertEqual(argStr, "Route(/users);Route(GET);Tag(public);")
    })
}
