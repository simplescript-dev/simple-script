// Test: D088 — bracket write (obj[name] = value) during for-in unrolling

import { assertEqual } from "@/lib/test"

class Point {
    x: int
    y: int
}

class Config {
    host: string
    port: int
}

// Copy all fields from src to dst using for-in + bracket write
function copyPoint(dst: Point, src: Point) {
    for (name in src.fields()) {
        dst[name] = src[name]
    }
}

function copyConfig(dst: Config, src: Config) {
    for (name in src.fields()) {
        dst[name] = src[name]
    }
}

// String literal bracket write
function setX(p: Point, val: int) {
    p["x"] = val
}

function main() {
    test("bracket write — for-in copy int fields", () => {
        const src = new Point(x: 10, y: 20)
        const dst = new Point(x: 0, y: 0)
        copyPoint(dst, src)
        assertEqual(dst.x, 10)
        assertEqual(dst.y, 20)
    })

    test("bracket write — for-in copy mixed types", () => {
        const src = new Config(host: "localhost", port: 8080)
        const dst = new Config(host: "", port: 0)
        copyConfig(dst, src)
        assertEqual(dst.host, "localhost")
        assertEqual(dst.port, 8080)
    })

    test("bracket write — string literal index", () => {
        const p = new Point(x: 1, y: 2)
        setX(p, 99)
        assertEqual(p.x, 99)
    })

    test("bracket write — independent objects", () => {
        const a = new Point(x: 5, y: 10)
        const b = new Point(x: 0, y: 0)
        copyPoint(b, a)
        a.x = 999
        assertEqual(b.x, 5)
        assertEqual(a.x, 999)
    })
}
