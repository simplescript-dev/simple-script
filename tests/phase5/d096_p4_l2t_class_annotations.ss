// D096 Phase 4 L2θ — cls.annotations 反射 (class 级注解)
// handler 内 for (a in cls.annotations) 展开类头部注解名;嵌套 a.args 走
// classAnnotationArgs。覆盖:(a) 多个类级注解 (b) 无额外注解 (c) 带 string
// 参数的类级注解 args 反射。

import { assertEqual } from "@/lib/test"

function Scan(cls: string) {
    @methodOf(cls) function scanTag(): string {
        let acc = ""
        for (a in cls.annotations) {
            acc = acc + a + ";"
        }
        return acc
    }
}

function ScanArgs(cls: string) {
    @methodOf(cls) function argTag(): string {
        let acc = ""
        for (a in cls.annotations) {
            for (v in a.args) {
                acc = acc + a + "(" + v + ");"
            }
        }
        return acc
    }
}

@Scan
@Deprecated
@Override
class Multi {
    x: int
}

@Scan
class Solo {
    y: int
}

@ScanArgs
@Route("/users", "GET")
@Tag("public")
class Api {
    z: int
}

function main() {
    test("L2θ — 多个类级注解", () => {
        const m = new Multi(x: 1)
        // Handler @Scan itself is first, then @Deprecated @Override.
        assertEqual(m.scanTag(), "Scan;Deprecated;Override;")
    })
    test("L2θ — 仅 handler 一个注解", () => {
        const s = new Solo(y: 2)
        assertEqual(s.scanTag(), "Scan;")
    })
    test("L2θ — class 级注解 a.args", () => {
        const a = new Api(z: 3)
        // @ScanArgs 无 args;@Route("/users","GET") 两个 string arg;
        // @Tag("public") 单 string arg。
        assertEqual(a.argTag(), "Route(/users);Route(GET);Tag(public);")
    })
}
