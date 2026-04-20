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
        system(`rm -f ${runtimeCacheObj} ${runtimeCacheDecls} ${rtLL} ${rtLL}.str`)
        return
    }
    // Generate declarations from runtime IR
    system(`grep '^define ' ${rtLL} | grep -v '^define internal ' | sed 's/define /declare /;s/ {$//' > ${runtimeCacheDecls}`)
    system(`grep '^declare ' ${rtLL} >> ${runtimeCacheDecls}`)
    system(`grep '^@\.rt\.' ${rtLL} | sed 's/ = constant \(\[[^]]*\]\).*/= external constant \1/' >> ${runtimeCacheDecls}`)
    system(`grep '^@stdin\|^@stdout' ${rtLL} >> ${runtimeCacheDecls}`)
    system(`grep '^%TypeInfo\|^%ObjHeader' ${rtLL} >> ${runtimeCacheDecls}`)
    system(`grep '^@ss_' ${rtLL} | sed 's/ = global / = external global /;s/ zeroinitializer.*//;s/ null.*//;s/ 0, align [0-9]*//;s/ 0$//' >> ${runtimeCacheDecls}`)
    system(`rm -f ${rtLL} ${rtLL}.str`)
}
