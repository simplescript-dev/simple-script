// tools/spring_boot_annotation_linter.ss
//
// D123 Spring Boot 复刻 —— 静态 annotation 白名单守护。
// 扫描目标目录(默认 examples/spring-parity)下所有 .ss 文件,提取 ANNOTATION
// 节点,annotation 名必须在 Spring Boot 官方白名单或 SS 内建 annotation 白名单;
// 违反 → exit 1。
//
// 动机: 防玩具注解(@Field/@Alias/@PositionalOnly 等)污染 Spring Boot 复刻
// 范围。机械 gate 不靠自觉反思。与 reflection_health_linter/dual_track_linter/
// bugfix_linter 同风格。
//
// 用法:
//   bin/ss run tools/spring_boot_annotation_linter.ss
//   bin/ss run tools/spring_boot_annotation_linter.ss --dir tests/spring_parity

import { tokenize } from "@/bootstrap/lexer/lexer"
import { parse, nGetKind, nGetS1, nGetI1, nGetI2, nGetI4, nGetList, nGetLine } from "@/bootstrap/parse/parser"

// ── 白名单 ────────────────────────────────────────────────────
// Spring Boot 3.x 核心注解 (stereotype + web + DI + config + conditional)
const SPRING_BOOT_ANNOTATIONS = ",SpringBootApplication,RestController,Controller,Service,Component,Repository,Configuration,Bean,Autowired,Qualifier,Value,GetMapping,PostMapping,PutMapping,DeleteMapping,PatchMapping,RequestMapping,PathVariable,RequestParam,RequestBody,RequestHeader,ResponseBody,ResponseStatus,ExceptionHandler,ControllerAdvice,RestControllerAdvice,CrossOrigin,Scope,Lazy,Primary,Profile,EnableAutoConfiguration,ComponentScan,Conditional,ConditionalOnProperty,ConditionalOnMissingBean,ConditionalOnClass,Import,ConfigurationProperties,"

// SS / Java 标准 annotation (Spring Boot app 中允许出现)
const SS_BUILTIN_ANNOTATIONS = ",methodOf,derive,Override,Deprecated,SuppressWarnings,"

// ── state ────────────────────────────────────────────────────
let files: Array<string> = []
let violations = 0
let seenAnnotations: Map<string, string> = new Map()

function isAllowed(name: string): int {
    if (SPRING_BOOT_ANNOTATIONS.indexOf(`,${name},`) >= 0) { return 1 }
    if (SS_BUILTIN_ANNOTATIONS.indexOf(`,${name},`) >= 0) { return 1 }
    return 0
}

function visit(nodeId: int, path: string) {
    if (nodeId <= 0) { return }
    const kind = nGetKind(nodeId)
    if (kind == "ANNOTATION") {
        const name = nGetS1(nodeId)
        seenAnnotations.set(name, "1")
        if (isAllowed(name) == 0) {
            println(`${path}:${nGetLine(nodeId)}: FAKE annotation @${name} (not in Spring Boot or SS builtin whitelist)`)
            violations = violations + 1
        }
    }
    const list = nGetList(nodeId)
    if (list != "") {
        for (p in list.split(",")) {
            if (p == "") { continue }
            const cid = parseInt(p)
            if (cid > 0) { visit(cid, path) }
        }
    }
    // I4 挂载点 (attachAnnotations: FUNC_DECL / CLASS_DECL / class-method 的
    // ANNOTATION_LIST 挂在 I4;field PARAM 走 list slot 本函数上一段已覆盖)
    const i4 = nGetI4(nodeId)
    if (i4 > 0 && nGetKind(i4) == "ANNOTATION_LIST") { visit(i4, path) }
    // CLASS_DECL.I2 = methodsBlock (包裹 class body 的 FUNC_DECL 方法)
    if (kind == "CLASS_DECL") {
        const mb = nGetI2(nodeId)
        if (mb > 0) { visit(mb, path) }
    }
    // FUNC_DECL.I1 = body (block) — 防 top-level function 内嵌 annotation
    if (kind == "FUNC_DECL") {
        const body = nGetI1(nodeId)
        if (body > 0) { visit(body, path) }
    }
}

function processFile(path: string) {
    const source = readFile(path)
    tokenize(source)
    const rootId = parse("done")
    visit(rootId, path)
}

function collectSSFiles(dir: string) {
    if (fileExists(dir) == 0) { return }
    const entries = listDir(dir)
    if (entries == "") { return }
    for (entry in entries.split("\n")) {
        if (entry == "") { continue }
        if (entry.endsWith(".ss") == 1) { files.push(`${dir}/${entry}`) }
        else { collectSSFiles(`${dir}/${entry}`) }
    }
}

function main() {
    let scanDir = "examples/spring-parity"
    let i = 1
    while (i < args()) {
        const a = arg(i)
        if (a == "--dir" && i + 1 < args()) { scanDir = arg(i + 1); i = i + 1 }
        i = i + 1
    }
    collectSSFiles(scanDir)
    let fi = 0
    while (fi < files.length()) { processFile(files[fi]); fi = fi + 1 }
    println("=== Spring Boot annotation whitelist linter ===")
    println(`扫 ${files.length()} 个 .ss 文件 (dir=${scanDir})`)
    println(`不同 annotation: ${seenAnnotations.size()}`)
    if (violations > 0) {
        println("")
        println(`GATE BLOCKED — ${violations} fake annotation(s)`)
        println("  Spring Boot 复刻范围只许真 Spring Boot / SS 内建注解,别编造。")
        println("  若是新增 Spring Boot 注解未收录,在 SPRING_BOOT_ANNOTATIONS 补上并注明 Spring Boot 版本。")
        exit(1)
    }
    println("GATE PASS — 0 fake annotations")
}
