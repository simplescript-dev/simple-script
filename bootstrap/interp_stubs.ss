// interp_stubs.ss — Stub declarations for compiler globals
//
// The interpreter files (interp_calls.ss, interp_reflect.ss) reference codegen
// globals like classFields, funcRetTypes, etc. In the full compiler these are
// provided by codegen.ss, gen_class.ss, gen_registry.ss, gen_annotations.ss.
// For standalone interpreter tests, this file provides empty stubs so the
// tests compile without pulling in the entire compiler.

// gen_registry.ss
let funcRetTypes = ""
let funcParamCount = ""

// gen_class.ss
let classFields = ""
let classFieldTypes = ""
let classMethods = ""
let classParents = ""
let classNodeIds = ""
let ifaceMethodsCG = ""
let ifaceMethodRets = ""
let ifaceMethodPars = ""
let ifaceImplementors = ""

// codegen.ss
let enumDeclNodes = ""
let enumTypes = ""
let enumReady = 0

// gen_annotations.ss
let annClassNodeIds: Array<string> = []
let annClassAnnNames: Array<string> = []

// codegen.ss — addStringConst stub (returns input as-is)
function addStringConst(value: string): string {
    return value
}
