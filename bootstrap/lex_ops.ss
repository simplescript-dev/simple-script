// lex_ops.ss — Multi-char operator lexers
// Used by lexer.ss via textual import. No own imports needed.

// ── Multi-char operators ──────────────────────────────────────

function lexPlus() {
    advance()
    if (pos < srcLen && peek() == 43) { advance(); emit("PLUS_PLUS", "++"); return }
    if (pos < srcLen && peek() == 61) { advance(); emit("PLUS_ASSIGN", "+="); return }
    emit("PLUS", "+")
}

function lexMinus() {
    advance()
    if (pos < srcLen && peek() == 45) { advance(); emit("MINUS_MINUS", "--"); return }
    if (pos < srcLen && peek() == 61) { advance(); emit("MINUS_ASSIGN", "-="); return }
    if (pos < srcLen && peek() == 62) { advance(); emit("THIN_ARROW", "->"); return }
    emit("MINUS", "-")
}

function lexStar() {
    advance()
    if (pos < srcLen && peek() == 42) {
        advance()
        if (pos < srcLen && peek() == 61) { advance(); emit("POWER_ASSIGN", "**="); return }
        emit("POWER", "**")
        return
    }
    if (pos < srcLen && peek() == 61) { advance(); emit("STAR_ASSIGN", "*="); return }
    emit("STAR", "*")
}

function lexSlash() {
    advance()
    if (pos < srcLen && peek() == 61) { advance(); emit("SLASH_ASSIGN", "/="); return }
    emit("SLASH", "/")
}

function lexPercent() {
    advance()
    if (pos < srcLen && peek() == 61) { advance(); emit("PERCENT_ASSIGN", "%="); return }
    emit("PERCENT", "%")
}

function lexEq() {
    advance()
    if (pos < srcLen && peek() == 61) { advance(); emit("EQ", "=="); return }
    if (pos < srcLen && peek() == 62) { advance(); emit("ARROW", "=>"); return }
    emit("ASSIGN", "=")
}

function lexBang() {
    advance()
    if (pos < srcLen && peek() == 61) { advance(); emit("NE", "!="); return }
    emit("NOT", "!")
}

function lexLt() {
    advance()
    if (pos < srcLen && peek() == 61) { advance(); emit("LE", "<="); return }
    if (pos < srcLen && peek() == 60) { advance(); emit("SHL", "<<"); return }
    emit("LT", "<")
}

function lexGt() {
    advance()
    if (pos < srcLen && peek() == 61) { advance(); emit("GE", ">="); return }
    if (pos < srcLen && peek() == 62) {
        advance()
        if (pos < srcLen && peek() == 62) { advance(); emit("USHR", ">>>"); return }
        emit("SHR", ">>")
        return
    }
    emit("GT", ">")
}

function lexAnd() {
    advance()
    if (pos < srcLen && peek() == 38) { advance(); emit("AND", "&&"); return }
    emit("BIT_AND", "&")
}

function lexOr() {
    advance()
    if (pos < srcLen && peek() == 124) { advance(); emit("OR", "||"); return }
    emit("BIT_OR", "|")
}

function lexQuestion() {
    advance()
    if (pos < srcLen && peek() == 63) { advance(); emit("NULLISH", "??"); return }
    if (pos < srcLen && peek() == 46) { advance(); emit("OPT_CHAIN", "?."); return }
    emit("QUESTION", "?")
}

function lexAnnotation() {
    advance()
    let name = ""
    while (pos < srcLen && isAlphaNum(peek())) {
        name = name + fromCharCode(peek())
        advance()
    }
    emit("ANNOTATION", name)
}

function lexCaret() {
    advance()
    emit("BIT_XOR", "^")
}

function lexTilde() {
    advance()
    emit("BIT_NOT", "~")
}
