#[derive(Debug, Clone, PartialEq)]
pub struct Token {
    pub kind: TokenKind,
    pub span: Span,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
    pub line: u32,
    pub col: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum TokenKind {
    // Keywords
    Function,
    Const,
    Let,
    Return,
    If,
    Else,
    For,
    While,
    Do,
    Break,
    Continue,
    True,
    False,
    Class,
    New,
    This,
    Interface,
    Override,
    Extends,
    Sealed,
    Enum,
    Switch,
    Case,
    Default,
    Null,

    // Type keywords (MVP)
    IntType,
    DoubleType,
    StringType,
    BoolType,

    // Literals
    IntLit(i64),
    DoubleLit(f64),
    StringLit(String),
    TemplateLit(Vec<TemplateFragment>),

    // Identifier
    Ident(String),

    // Operators
    Plus,       // +
    Minus,      // -
    Star,       // *
    Power,      // **
    Slash,      // /
    Percent,    // %
    Assign,     // =
    Eq,         // ==
    Ne,         // !=
    Lt,         // <
    Gt,         // >
    Le,         // <=
    Ge,         // >=
    And,        // &&
    Or,         // ||
    Not,        // !
    Question,   // ?
    PlusPlus,   // ++
    MinusMinus, // --
    PlusAssign,  // +=
    MinusAssign, // -=
    StarAssign,  // *=
    SlashAssign, // /=
    PercentAssign, // %=

    // Special
    Arrow,      // =>
    ThinArrow,  // ->

    // Delimiters
    LParen,     // (
    RParen,     // )
    LBrace,     // {
    RBrace,     // }
    LBracket,   // [
    RBracket,   // ]
    Comma,      // ,
    Colon,      // :
    Semicolon,  // ;
    Dot,        // .

    Newline,
    Eof,
}

#[derive(Debug, Clone, PartialEq)]
pub enum TemplateFragment {
    Literal(String),
    Expr(Vec<Token>),
}
