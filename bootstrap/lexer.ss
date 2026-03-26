// SimpleScript Bootstrap Lexer
// Tokenizes .ss source code. Tokens stored as "KIND\tVALUE" lines in a string.

// ── Lexer state ───────────────────────────────────────────────

let src = ""
let pos = 0
let srcLen = 0
let curLine = 1
let curCol = 1
let tokenBuf = ""
let tokenCount = 0
let tkKinds = ""
let tkValues = ""
let tkMapReady = 0

function initTkMap() {
    if (tkMapReady == 1) { return }
    tkKinds = Map()
    tkValues = Map()
    tkMapReady = 1
}

// ── Public API ────────────────────────────────────────────────

function tokenize(source: string): string {
    initTkMap()
    src = source
    pos = 0
    srcLen = src.length()
    curLine = 1
    curCol = 1
    tokenBuf = ""
    tokenCount = 0

    while (pos < srcLen) {
        skipWS()
        if (pos >= srcLen) { break }
        const ch = src.charAt(pos)
        if (ch == "\n") {
            emit("NEWLINE", "\\n")
            advance()
            curLine = curLine + 1
            curCol = 1
            continue
        }
        if (ch == "\"") { lexString(); continue }
        if (ch == "'") { lexSQString(); continue }
        if (ch == "`") { lexTemplate(); continue }
        if (isDigit(ch)) { lexNumber(); continue }
        if (isAlpha(ch) || ch == "_") { lexIdent(); continue }
        if (ch == "+") { lexPlus(); continue }
        if (ch == "-") { lexMinus(); continue }
        if (ch == "*") { lexStar(); continue }
        if (ch == "/") { lexSlash(); continue }
        if (ch == "%") { lexPercent(); continue }
        if (ch == "=") { lexEq(); continue }
        if (ch == "!") { lexBang(); continue }
        if (ch == "?") { emit("QUESTION", "?"); advance(); continue }
        if (ch == "<") { lexLt(); continue }
        if (ch == ">") { lexGt(); continue }
        if (ch == "&") { lexAnd(); continue }
        if (ch == "|") { lexOr(); continue }
        if (ch == "(") { emit("LPAREN", "("); advance(); continue }
        if (ch == ")") { emit("RPAREN", ")"); advance(); continue }
        if (ch == "{") { emit("LBRACE", "{"); advance(); continue }
        if (ch == "}") { emit("RBRACE", "}"); advance(); continue }
        if (ch == "[") { emit("LBRACKET", "["); advance(); continue }
        if (ch == "]") { emit("RBRACKET", "]"); advance(); continue }
        if (ch == ",") { emit("COMMA", ","); advance(); continue }
        if (ch == ":") { emit("COLON", ":"); advance(); continue }
        if (ch == ";") { emit("SEMICOLON", ";"); advance(); continue }
        if (ch == ".") { emit("DOT", "."); advance(); continue }
        println("lexer error: unexpected '" + ch + "' at line " + curLine)
        exit(1)
    }
    emit("EOF", "")
    return "done"
}

// ── Token access helpers ──────────────────────────────────────

// Token access — O(1) via Map
function tkGet(tokens: string, index: int): string {
    // Legacy compatibility — returns "KIND\tVALUE" but now from Map
    const idx = index + ""
    if (tkKinds.has(idx) == 1) {
        return tkKinds.getString(idx) + "\t" + tkValues.getString(idx)
    }
    return "EOF\t"
}

function tkKind(tokenLine: string): string {
    const tabPos = tokenLine.indexOf("\t")
    if (tabPos < 0) { return tokenLine }
    return tokenLine.substring(0, tabPos)
}

function tkValue(tokenLine: string): string {
    const tabPos = tokenLine.indexOf("\t")
    if (tabPos < 0) { return "" }
    return tokenLine.substring(tabPos + 1, tokenLine.length() - tabPos - 1)
}

function tkCount(): int {
    return tokenCount
}

// ── Internal ──────────────────────────────────────────────────

function emit(kind: string, value: string) {
    const idx = tokenCount + ""
    tkKinds.set(idx, kind)
    tkValues.set(idx, value)
    tokenCount = tokenCount + 1
}

function advance(): string {
    const ch = src.charAt(pos)
    pos = pos + 1
    curCol = curCol + 1
    return ch
}

function peek(): string {
    if (pos >= srcLen) { return "" }
    return src.charAt(pos)
}

function peekNext(): string {
    if (pos + 1 >= srcLen) { return "" }
    return src.charAt(pos + 1)
}

function isDigit(ch: string): bool {
    return "0123456789".contains(ch) && ch != ""
}

function isAlpha(ch: string): bool {
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_".contains(ch) && ch != ""
}

function isAlphaNum(ch: string): bool {
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789".contains(ch) && ch != ""
}

function escapeChar(ch: string): string {
    if (ch == "n") { return "\n" }
    if (ch == "t") { return "\t" }
    if (ch == "r") { return "\r" }
    if (ch == "\\") { return "\\" }
    if (ch == "\"") { return "\"" }
    if (ch == "'") { return "'" }
    if (ch == "`") { return "`" }
    if (ch == "$") { return "$" }
    if (ch == "0") { return "" }
    return "\\" + ch
}

// ── Skip whitespace + comments ────────────────────────────────

function skipWS() {
    while (pos < srcLen) {
        const ch = src.charAt(pos)
        if (ch == " " || ch == "\t" || ch == "\r") {
            advance()
            continue
        }
        if (ch == "/" && peekNext() == "/") {
            while (pos < srcLen && src.charAt(pos) != "\n") {
                advance()
            }
            continue
        }
        if (ch == "/" && peekNext() == "*") {
            advance()
            advance()
            while (pos < srcLen) {
                if (src.charAt(pos) == "*" && peekNext() == "/") {
                    advance()
                    advance()
                    break
                }
                if (src.charAt(pos) == "\n") {
                    curLine = curLine + 1
                    curCol = 0
                }
                advance()
            }
            continue
        }
        break
    }
}

// ── String literals ───────────────────────────────────────────

function lexStringWith(quote: string) {
    advance()
    let value = ""
    while (pos < srcLen) {
        if (peek() == quote) { break }
        if (peek() == "\\") {
            advance()
            if (pos >= srcLen) { println("lexer error: unterminated string"); exit(1) }
            value = value + escapeChar(peek())
            advance()
        } else if (peek() == "\n") {
            println("lexer error: unterminated string at line " + curLine)
            exit(1)
        } else {
            value = value + peek()
            advance()
        }
    }
    if (pos >= srcLen) { println("lexer error: unterminated string"); exit(1) }
    advance()
    emit("STRING", value)
}

function lexString() { lexStringWith("\"") }
function lexSQString() { lexStringWith("'") }

// ── Template literal ──────────────────────────────────────────

function lexTemplate() {
    advance()
    let literal = ""
    while (pos < srcLen) {
        if (peek() == "`") { break }
        // template char processing
        if (peek() == "$" && peekNext() == "{") {
            if (literal.length() > 0) {
                emit("TMPL_LIT", literal)
                literal = ""
            }
            advance()
            advance()
            emit("TMPL_EXPR_START", "${")
            let depth = 1
            while (pos < srcLen) {
                if (depth <= 0) { break }
                skipWS()
                if (pos >= srcLen) { break }
                const ch = peek()
                if (ch == "{") { depth = depth + 1; emit("LBRACE", "{"); advance() } else if (ch == "}") {
                    depth = depth - 1
                    if (depth > 0) { emit("RBRACE", "}"); advance() } else { advance() }
                } else if (ch == "`") {
                    lexTemplate()
                } else if (ch == "\"") {
                    lexString()
                } else if (isDigit(ch)) {
                    lexNumber()
                } else if (isAlpha(ch) || ch == "_") {
                    lexIdent()
                } else if (ch == "+") { lexPlus()
                } else if (ch == "-") { lexMinus()
                } else if (ch == "*") { emit("STAR", "*"); advance()
                } else if (ch == "/") { emit("SLASH", "/"); advance()
                } else if (ch == "(") { emit("LPAREN", "("); advance()
                } else if (ch == ")") { emit("RPAREN", ")"); advance()
                } else if (ch == "[") { emit("LBRACKET", "["); advance()
                } else if (ch == "]") { emit("RBRACKET", "]"); advance()
                } else if (ch == ",") { emit("COMMA", ","); advance()
                } else if (ch == ".") { emit("DOT", "."); advance()
                } else if (ch == ":") { emit("COLON", ":"); advance()
                } else if (ch == "?") { emit("QUESTION", "?"); advance()
                } else if (ch == "=") { lexEq()
                } else if (ch == "!") { lexBang()
                } else if (ch == "<") { lexLt()
                } else if (ch == ">") { lexGt()
                } else if (ch == "&") { lexAnd()
                } else if (ch == "|") { lexOr()
                } else {
                    println(`lexer error: unexpected '${ch}' in template`)
                    exit(1)
                }
            }
            emit("TMPL_EXPR_END", "}")
            continue
        }
        if (peek() == "\\") {
            advance()
            if (pos < srcLen) {
                literal = literal + escapeChar(peek())
                advance()
            }
            continue
        }
        if (peek() == "\n") {
            curLine = curLine + 1
            curCol = 0
        }
        literal = literal + peek()
        advance()
    }
    if (pos >= srcLen) { println("lexer error: unterminated template"); exit(1) }
    advance()
    if (literal.length() > 0) {
        emit("TMPL_LIT", literal)
    }
    emit("TMPL_END", "`")
}

// ── Numbers ───────────────────────────────────────────────────

function lexNumber() {
    let start = pos
    let isDouble = 0
    while (pos < srcLen && (isDigit(peek()) || peek() == "_")) {
        advance()
    }
    if (pos < srcLen && peek() == ".") {
        if (pos + 1 < srcLen && isDigit(src.charAt(pos + 1))) {
            isDouble = 1
            advance()
            while (pos < srcLen && (isDigit(peek()) || peek() == "_")) {
                advance()
            }
        }
    }
    const text = src.substring(start, pos - start).replace("_", "")
    if (isDouble == 1) {
        emit("DOUBLE", text)
    } else {
        emit("INT", text)
    }
}

// ── Identifiers / keywords ────────────────────────────────────

function lexIdent() {
    let start = pos
    while (pos < srcLen && isAlphaNum(peek())) {
        advance()
    }
    const text = src.substring(start, pos - start)
    const kind = keywordKind(text)
    emit(kind, text)
}

function keywordKind(text: string): string {
    if (text == "function") { return "FUNCTION" }
    if (text == "const") { return "CONST" }
    if (text == "let") { return "LET" }
    if (text == "return") { return "RETURN" }
    if (text == "if") { return "IF" }
    if (text == "else") { return "ELSE" }
    if (text == "for") { return "FOR" }
    if (text == "while") { return "WHILE" }
    if (text == "do") { return "DO" }
    if (text == "break") { return "BREAK" }
    if (text == "continue") { return "CONTINUE" }
    if (text == "true") { return "TRUE" }
    if (text == "false") { return "FALSE" }
    if (text == "class") { return "CLASS" }
    if (text == "new") { return "NEW" }
    if (text == "this") { return "THIS" }
    if (text == "interface") { return "INTERFACE" }
    if (text == "override") { return "OVERRIDE" }
    if (text == "extends") { return "EXTENDS" }
    if (text == "sealed") { return "SEALED" }
    if (text == "enum") { return "ENUM" }
    if (text == "switch") { return "SWITCH" }
    if (text == "case") { return "CASE" }
    if (text == "default") { return "DEFAULT" }
    if (text == "null") { return "NULL" }
    if (text == "import") { return "IMPORT" }
    if (text == "from") { return "FROM" }
    if (text == "in") { return "IN" }
    if (text == "int") { return "INT_TYPE" }
    if (text == "double") { return "DOUBLE_TYPE" }
    if (text == "string") { return "STRING_TYPE" }
    if (text == "bool") { return "BOOL_TYPE" }
    if (text == "void") { return "VOID_TYPE" }
    return "IDENT"
}

// ── Multi-char operators ──────────────────────────────────────

function lexPlus() {
    advance()
    if (pos < srcLen && peek() == "+") { advance(); emit("PLUS_PLUS", "++"); return }
    if (pos < srcLen && peek() == "=") { advance(); emit("PLUS_ASSIGN", "+="); return }
    emit("PLUS", "+")
}

function lexMinus() {
    advance()
    if (pos < srcLen && peek() == "-") { advance(); emit("MINUS_MINUS", "--"); return }
    if (pos < srcLen && peek() == "=") { advance(); emit("MINUS_ASSIGN", "-="); return }
    if (pos < srcLen && peek() == ">") { advance(); emit("THIN_ARROW", "->"); return }
    emit("MINUS", "-")
}

function lexStar() {
    advance()
    if (pos < srcLen && peek() == "*") { advance(); emit("POWER", "**"); return }
    if (pos < srcLen && peek() == "=") { advance(); emit("STAR_ASSIGN", "*="); return }
    emit("STAR", "*")
}

function lexSlash() {
    advance()
    if (pos < srcLen && peek() == "=") { advance(); emit("SLASH_ASSIGN", "/="); return }
    emit("SLASH", "/")
}

function lexPercent() {
    advance()
    if (pos < srcLen && peek() == "=") { advance(); emit("PERCENT_ASSIGN", "%="); return }
    emit("PERCENT", "%")
}

function lexEq() {
    advance()
    if (pos < srcLen && peek() == "=") { advance(); emit("EQ", "=="); return }
    if (pos < srcLen && peek() == ">") { advance(); emit("ARROW", "=>"); return }
    emit("ASSIGN", "=")
}

function lexBang() {
    advance()
    if (pos < srcLen && peek() == "=") { advance(); emit("NE", "!="); return }
    emit("NOT", "!")
}

function lexLt() {
    advance()
    if (pos < srcLen && peek() == "=") { advance(); emit("LE", "<="); return }
    emit("LT", "<")
}

function lexGt() {
    advance()
    if (pos < srcLen && peek() == "=") { advance(); emit("GE", ">="); return }
    emit("GT", ">")
}

function lexAnd() {
    advance()
    if (pos < srcLen && peek() == "&") { advance(); emit("AND", "&&"); return }
    println("lexer error: expected '&&' at line " + curLine)
    exit(1)
}

function lexOr() {
    advance()
    if (pos < srcLen && peek() == "|") { advance(); emit("OR", "||"); return }
    println("lexer error: expected '||' at line " + curLine)
    exit(1)
}
