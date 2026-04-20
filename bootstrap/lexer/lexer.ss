// SimpleScript Bootstrap Lexer
// Tokenizes .ss source code. Tokens stored as "KIND\tVALUE" lines in a string.

import { lexPlus, lexMinus, lexStar, lexSlash, lexPercent, lexEq, lexBang, lexLt, lexGt, lexAnd, lexOr, lexQuestion, lexAnnotation, lexCaret, lexTilde } from "./lex_ops"

// ── Lexer state ───────────────────────────────────────────────

let src = ""
let pos = 0
let srcLen = 0
let curLine = 1
let curCol = 1
let tokenBuf = ""
let tokenCount = 0
let tkKinds: Array<string> = []
let tkValues: Array<string> = []
let tkLines: Array<int> = []
let tkCols: Array<int> = []
let tokenStartCol = 1

// ── Public API ────────────────────────────────────────────────

function tokenize(source: string): string {
    src = source
    pos = 0
    srcLen = src.length()
    curLine = 1
    curCol = 1
    tokenBuf = ""
    tokenCount = 0
    tkKinds = []
    tkValues = []
    tkLines = []
    tkCols = []

    while (pos < srcLen) {
        skipWS()
        if (pos >= srcLen) { break }
        tokenStartCol = curCol
        const ch = peek()
        if (ch == 10) {
            emit("NEWLINE", "\\n")
            advance()
            curLine = curLine + 1
            curCol = 1
            continue
        }
        if (ch == 34) { lexString(); continue }
        if (ch == 39) { lexSQString(); continue }
        if (ch == 96) { lexTemplate(); continue }
        if (isDigit(ch)) { lexNumber(); continue }
        if (isAlpha(ch)) { lexIdent(); continue }
        if (ch == 43) { lexPlus(); continue }
        if (ch == 45) { lexMinus(); continue }
        if (ch == 42) { lexStar(); continue }
        if (ch == 47) { lexSlash(); continue }
        if (ch == 37) { lexPercent(); continue }
        if (ch == 61) { lexEq(); continue }
        if (ch == 33) { lexBang(); continue }
        if (ch == 63) { lexQuestion(); continue }
        if (ch == 60) { lexLt(); continue }
        if (ch == 62) { lexGt(); continue }
        if (ch == 38) { lexAnd(); continue }
        if (ch == 124) { lexOr(); continue }
        if (ch == 94) { lexCaret(); continue }
        if (ch == 126) { lexTilde(); continue }
        if (ch == 64) { lexAnnotation(); continue }
        if (ch == 40) { emit("LPAREN", "("); advance(); continue }
        if (ch == 41) { emit("RPAREN", ")"); advance(); continue }
        if (ch == 123) { emit("LBRACE", "{"); advance(); continue }
        if (ch == 125) { emit("RBRACE", "}"); advance(); continue }
        if (ch == 91) { emit("LBRACKET", "["); advance(); continue }
        if (ch == 93) { emit("RBRACKET", "]"); advance(); continue }
        if (ch == 44) { emit("COMMA", ","); advance(); continue }
        if (ch == 58) { emit("COLON", ":"); advance(); continue }
        if (ch == 59) { emit("SEMICOLON", ";"); advance(); continue }
        if (ch == 46) {
            advance()
            if (pos + 1 < srcLen && peek() == 46 && peekNext() == 46) { advance(); advance(); emit("SPREAD", "..."); continue }
            emit("DOT", ".")
            continue
        }
        // `${...}` at top level — type-position comptime interpolation
        // (e.g. `v: ${f.type}`). Emits TMPL_EXPR_START + body tokens + TMPL_EXPR_END.
        if (ch == 36 && peekNext() == 123) {
            tokenStartCol = curCol
            advance()
            advance()
            emit("TMPL_EXPR_START", "${")
            lexInterpExprBody()
            continue
        }
        println("lexer error: unexpected '" + fromCharCode(ch) + "' at line " + curLine)
        exit(1)
    }
    emit("EOF", "")
    return "done"
}

// ── Token access helpers ──────────────────────────────────────

function tkCount(): int {
    return tokenCount
}

// ── Internal ──────────────────────────────────────────────────

function emit(kind: string, value: string) {
    tkKinds.push(kind)
    tkValues.push(value)
    tkLines.push(curLine)
    tkCols.push(tokenStartCol)
    tokenCount = tokenCount + 1
}

function tkLine(index: int): int {
    return tkLines[index]
}

function tkCol(index: int): int {
    return tkCols[index]
}

function getSourceLine(lineNum: int): string {
    let current = 1
    let start = 0
    let i = 0
    while (i < srcLen) {
        if (charCodeAt(src, i) == 10) {
            if (current == lineNum) {
                return src.substring(start, i - start)
            }
            current = current + 1
            start = i + 1
        }
        i = i + 1
    }
    if (current == lineNum) {
        return src.substring(start, srcLen - start)
    }
    return ""
}

function advance() {
    pos = pos + 1
    curCol = curCol + 1
}

function peek(): int {
    if (pos >= srcLen) { return 0 }
    return charCodeAt(src, pos)
}

function peekNext(): int {
    if (pos + 1 >= srcLen) { return 0 }
    return charCodeAt(src, pos + 1)
}

function isDigit(ch: int): bool {
    return ch >= 48 && ch <= 57
}

function isAlpha(ch: int): bool {
    return (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95
}

function isAlphaNum(ch: int): bool {
    return isDigit(ch) || isAlpha(ch)
}

function hexVal(ch: int): int {
    if (ch >= 48 && ch <= 57) { return ch - 48 }
    if (ch >= 97 && ch <= 102) { return ch - 87 }
    if (ch >= 65 && ch <= 70) { return ch - 55 }
    return -1
}

function escapeChar(ch: int): string {
    if (ch == 110) { return "\n" }
    if (ch == 116) { return "\t" }
    if (ch == 114) { return "\r" }
    if (ch == 92) { return "\\" }
    if (ch == 34) { return "\"" }
    if (ch == 39) { return "'" }
    if (ch == 96) { return "`" }
    if (ch == 36) { return "$" }
    if (ch == 48) { return "" }
    return "\\" + fromCharCode(ch)
}

// ── Skip whitespace + comments ────────────────────────────────

function skipWS() {
    while (pos < srcLen) {
        const ch = peek()
        if (ch == 32 || ch == 9 || ch == 13) {
            advance()
            continue
        }
        if (ch == 47 && peekNext() == 47) {
            while (pos < srcLen && peek() != 10) {
                advance()
            }
            continue
        }
        if (ch == 47 && peekNext() == 42) {
            advance()
            advance()
            while (pos < srcLen) {
                if (peek() == 42 && peekNext() == 47) {
                    advance()
                    advance()
                    break
                }
                if (peek() == 10) {
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

function lexStringWith(quote: int) {
    advance()
    let value = ""
    while (pos < srcLen) {
        if (peek() == quote) { break }
        if (peek() == 92) {
            advance()
            if (pos >= srcLen) { println("lexer error: unterminated string"); exit(1) }
            value = value + escapeChar(peek())
            advance()
        } else if (peek() == 10) {
            println("lexer error: unterminated string at line " + curLine)
            exit(1)
        } else {
            value = value + fromCharCode(peek())
            advance()
        }
    }
    if (pos >= srcLen) { println("lexer error: unterminated string"); exit(1) }
    advance()
    emit("STRING", value)
}

function lexString() { lexStringWith(34) }
function lexSQString() { lexStringWith(39) }

// ── Template literal ──────────────────────────────────────────

// Tokenize `${...}` body up to matching `}`. Caller has already advanced past
// `${` and emitted TMPL_EXPR_START. Shared by template literals and the
// top-level type-position branch — keeps the two sites from drifting (the
// inlined copy in lexTemplate was 47 lines).
function lexInterpExprBody() {
    let depth = 1
    while (pos < srcLen) {
        if (depth <= 0) { break }
        skipWS()
        if (pos >= srcLen) { break }
        tokenStartCol = curCol
        const ch = peek()
        if (ch == 123) { depth = depth + 1; emit("LBRACE", "{"); advance() } else if (ch == 125) {
            depth = depth - 1
            if (depth > 0) { emit("RBRACE", "}"); advance() } else { advance() }
        } else if (ch == 96) {
            lexTemplate()
        } else if (ch == 34) {
            lexString()
        } else if (isDigit(ch)) {
            lexNumber()
        } else if (isAlpha(ch)) {
            lexIdent()
        } else if (ch == 43) { lexPlus()
        } else if (ch == 45) { lexMinus()
        } else if (ch == 42) { lexStar()
        } else if (ch == 47) { emit("SLASH", "/"); advance()
        } else if (ch == 40) { emit("LPAREN", "("); advance()
        } else if (ch == 41) { emit("RPAREN", ")"); advance()
        } else if (ch == 91) { emit("LBRACKET", "["); advance()
        } else if (ch == 93) { emit("RBRACKET", "]"); advance()
        } else if (ch == 44) { emit("COMMA", ","); advance()
        } else if (ch == 46) { emit("DOT", "."); advance()
        } else if (ch == 58) { emit("COLON", ":"); advance()
        } else if (ch == 63) { lexQuestion()
        } else if (ch == 61) { lexEq()
        } else if (ch == 33) { lexBang()
        } else if (ch == 60) { lexLt()
        } else if (ch == 62) { lexGt()
        } else if (ch == 38) { lexAnd()
        } else if (ch == 124) { lexOr()
        } else if (ch == 94) { lexCaret()
        } else if (ch == 126) { lexTilde()
        } else if (ch == 37) { emit("PERCENT", "%"); advance()
        } else {
            println(`lexer error: unexpected '${fromCharCode(ch)}' in template`)
            exit(1)
        }
    }
    tokenStartCol = curCol
    emit("TMPL_EXPR_END", "}")
}

function lexTemplate() {
    advance()
    let literal = ""
    while (pos < srcLen) {
        if (peek() == 96) { break }
        // template char processing
        if (peek() == 36 && peekNext() == 123) {
            if (literal.length() > 0) {
                tokenStartCol = curCol
                emit("TMPL_LIT", literal)
                literal = ""
            }
            tokenStartCol = curCol
            advance()
            advance()
            emit("TMPL_EXPR_START", "${")
            lexInterpExprBody()
            continue
        }
        if (peek() == 92) {
            advance()
            if (pos < srcLen) {
                literal = literal + escapeChar(peek())
                advance()
            }
            continue
        }
        if (peek() == 10) {
            curLine = curLine + 1
            curCol = 0
        }
        literal = literal + fromCharCode(peek())
        advance()
    }
    if (pos >= srcLen) { println("lexer error: unterminated template"); exit(1) }
    advance()
    if (literal.length() > 0) {
        tokenStartCol = curCol
        emit("TMPL_LIT", literal)
    }
    tokenStartCol = curCol
    emit("TMPL_END", "`")
}

// ── Numbers ───────────────────────────────────────────────────

function lexNumber() {
    let start = pos
    // Check for 0x, 0b, 0o prefix
    if (peek() == 48 && pos + 1 < srcLen) {
        const next = peekNext()
        if (next == 120 || next == 88) {
            advance(); advance()
            let val = 0
            while (pos < srcLen) {
                const dv = hexVal(peek())
                if (dv < 0) { break }
                val = val * 16 + dv
                advance()
            }
            emit("INT", `${val}`)
            return
        }
        if (next == 98 || next == 66) {
            advance(); advance()
            let val = 0
            while (pos < srcLen && (peek() == 48 || peek() == 49)) {
                val = val * 2 + (peek() - 48)
                advance()
            }
            emit("INT", `${val}`)
            return
        }
        if (next == 111 || next == 79) {
            advance(); advance()
            let val = 0
            while (pos < srcLen && peek() >= 48 && peek() <= 55) {
                val = val * 8 + (peek() - 48)
                advance()
            }
            emit("INT", `${val}`)
            return
        }
    }
    // Regular decimal number
    let isDouble = 0
    while (pos < srcLen && (isDigit(peek()) || peek() == 95)) {
        advance()
    }
    if (pos < srcLen && peek() == 46) {
        if (pos + 1 < srcLen && isDigit(peekNext())) {
            isDouble = 1
            advance()
            while (pos < srcLen && (isDigit(peek()) || peek() == 95)) {
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
    if (text == "try") { return "TRY" }
    if (text == "catch") { return "CATCH" }
    if (text == "throw") { return "THROW" }
    if (text == "import") { return "IMPORT" }
    if (text == "from") { return "FROM" }
    if (text == "in") { return "IN" }
    if (text == "int") { return "INT_TYPE" }
    if (text == "double") { return "DOUBLE_TYPE" }
    if (text == "string") { return "STRING_TYPE" }
    if (text == "bool") { return "BOOL_TYPE" }
    if (text == "void") { return "VOID_TYPE" }
    if (text == "private") { return "PRIVATE" }
    if (text == "protected") { return "PROTECTED" }
    if (text == "super") { return "SUPER" }
    if (text == "static") { return "STATIC" }
    if (text == "abstract") { return "ABSTRACT" }
    if (text == "finally") { return "FINALLY" }
    if (text == "instanceof") { return "INSTANCEOF" }
    if (text == "as") { return "AS" }
    if (text == "comptime") { return "COMPTIME" }
    return "IDENT"
}

// ── Multi-char operators ── (see lex_ops.ss)
