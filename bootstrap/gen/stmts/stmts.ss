// gen/stmts.ss — Statement codegen dispatcher + barrel。

import { genFuncDeclStmt, genVarDecl, genDestructureArray, genAssign, genMemberAssign, isOwnedExpr, genReturn } from "../gen_decls"
import { interpShouldStop, interpCheckLoopExit, interpEnumValues, interpEnumTypes, interpEnumNodes, interpAsInt, interpAsStr, interpType, interpNewInt, interpTruthy, interpToStr, interpSetField, interpArraySet } from "../../eval/interp_core"
import { emitCondToI1, genBlock, genNestedBlock, runComptimeBlockBody, genBreak, genContinueStmt } from "./stmts_core"
import { genPostfixStmt, genIndexAssign } from "./stmts_simple"
import { registerEnum } from "./stmts_enum"
import { genTryCatch, genThrow } from "./stmts_exc"
import { genIf, genSwitch } from "./stmts_branch"
import { genFor, genWhile, genDoWhile } from "./stmts_loop_classic"
import { genForIn } from "./stmts_loop_forin"

function genStmt(id: int) {
    const kind = nGetKind(id)
    if (kind == "FUNC_DECL") { genFuncDeclStmt(id); return }
    if (kind == "VAR_DECL") { genVarDecl(id); return }
    if (kind == "DESTRUCTURE_ARRAY") { genDestructureArray(id); return }
    if (kind == "DESTRUCTURE_OBJECT") { genDestructureObject(id); return }
    if (kind == "ASSIGN") { genAssign(id); return }
    if (kind == "EXPR_STMT") {
        const esExpr = nGetI1(id)
        if (esExpr > 0 && nGetKind(esExpr) == "CALL" && nGetS1(esExpr) == "annotationMapping") { return }
        if (comptimeMustBeKnown == 1) {
            genVal(esExpr)
            return
        }
        genExpr(esExpr)
        return
    }
    if (kind == "RETURN") { genReturn(id); return }
    if (kind == "IF") { genIf(id); return }
    if (kind == "FOR") { genFor(id); return }
    if (kind == "FOR_IN" || kind == "FOR_OF") { genForIn(id); return }
    if (kind == "WHILE") { genWhile(id); return }
    if (kind == "BREAK") { genBreak(); return }
    if (kind == "CONTINUE") { genContinueStmt(); return }
    if (kind == "POSTFIX_INC" || kind == "POSTFIX_DEC") { genPostfixStmt(id); return }
    if (kind == "DO_WHILE") { genDoWhile(id); return }
    if (kind == "SWITCH") { genSwitch(id); return }
    if (kind == "INDEX_ASSIGN") { genIndexAssign(id); return }
    if (kind == "MEMBER_ASSIGN") { genMemberAssign(id); return }
    if (kind == "CLASS_DECL") { genClassDecl(id); return }
    if (kind == "ENUM_DECL") { registerEnum(id); return }
    if (kind == "INTERFACE_DECL") { return }
    if (kind == "TRY") { genTryCatch(id); return }
    if (kind == "THROW") { genThrow(id); return }
    if (kind == "COMPTIME_BLOCK") {
        runComptimeBlockBody(nGetI1(id))
        flushComptimeIR()
        flushComptimeSS()
        return
    }
}
