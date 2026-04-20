// gen_rt_cache.ss — Runtime LLVM IR cache build (CLI --rt-cache driver)

// ── State ─────────────────────────────────────────────────────

let runtimeCacheObj = "/tmp/ss_rt_cache.o"
let runtimeCacheDecls = "/tmp/ss_rt_cache.decls"
let useRuntimeCache = 0

// ── Build ─────────────────────────────────────────────────────

function buildRuntimeCache() {
    const rtLL = "/tmp/ss_rt_cache.ll"
    resetCodegen()
    irOutFile = rtLL
    writeFile(rtLL, "")
    writeFile(`${rtLL}.str`, "")
    emitRuntimeDefs()
    irOutFile = ""
    const rtBody = readFile(rtLL)
    writeFile(rtLL, `; ModuleID = 'ss_runtime'\nsource_filename = "ss_runtime"\n\n${rtBody}`)
    if (system(`llc-18 -filetype=obj ${rtLL} -o ${runtimeCacheObj}`) != 0) {
        system(`rm -f ${runtimeCacheObj} ${runtimeCacheDecls} ${rtLL}`)
        return
    }
    // Generate declarations from runtime IR
    // 1. Function declares
    system(`grep '^define ' ${rtLL} | grep -v '^define internal ' | sed 's/define /declare /;s/ {$//' > ${runtimeCacheDecls}`)
    // 2. Libc declares
    system(`grep '^declare ' ${rtLL} >> ${runtimeCacheDecls}`)
    // 3. Runtime string constants as external
    system(`grep '^@\.rt\.' ${rtLL} | sed 's/ = constant \(\[[^]]*\]\).*/= external constant \1/' >> ${runtimeCacheDecls}`)
    // 4. @stdin/@stdout and type definitions
    system(`grep '^@stdin\|^@stdout' ${rtLL} >> ${runtimeCacheDecls}`)
    system(`grep '^%TypeInfo\|^%ObjHeader' ${rtLL} >> ${runtimeCacheDecls}`)
    // 5. Runtime globals as external (auto-extracted from .ll)
    system(`grep '^@ss_' ${rtLL} | sed 's/ = global / = external global /;s/ zeroinitializer.*//;s/ null.*//;s/ 0, align [0-9]*//;s/ 0$//' >> ${runtimeCacheDecls}`)
    system(`rm -f ${rtLL} ${rtLL}.str`)
}
