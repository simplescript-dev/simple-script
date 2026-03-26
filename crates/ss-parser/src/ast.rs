use ss_lexer::Span;

#[derive(Debug, Clone)]
pub struct Program {
    pub stmts: Vec<Stmt>,
}

#[derive(Debug, Clone)]
pub struct Stmt {
    pub kind: StmtKind,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub enum StmtKind {
    FunctionDecl {
        name: String,
        params: Vec<Param>,
        return_type: Option<TypeAnnotation>,
        body: Block,
    },
    ClassDecl {
        name: String,
        extends: Option<String>,
        fields: Vec<Param>,
        implements: Vec<String>,
        methods: Vec<Stmt>,
    },
    InterfaceDecl {
        name: String,
        methods: Vec<InterfaceMethod>,
    },
    VarDecl {
        kind: VarKind,
        name: String,
        type_ann: Option<TypeAnnotation>,
        init: Expr,
    },
    Assignment {
        target: String,
        op: AssignOp,
        value: Expr,
    },
    IndexAssign {
        object: String,
        index: Expr,
        value: Expr,
    },
    ExprStmt(Expr),
    Return(Option<Expr>),
    If {
        condition: Expr,
        then_block: Block,
        else_block: Option<Block>,
    },
    For {
        init: Box<Stmt>,
        condition: Expr,
        update: Box<Stmt>,
        body: Block,
    },
    ForIn {
        item: String,
        iterable: Expr,
        body: Block,
    },
    While {
        condition: Expr,
        body: Block,
    },
    DoWhile {
        body: Block,
        condition: Expr,
    },
    Break,
    Continue,
    EnumDecl {
        name: String,
        variants: Vec<String>,
    },
    Switch {
        subject: Expr,
        cases: Vec<SwitchCase>,
        default: Option<Block>,
    },
}

#[derive(Debug, Clone)]
pub struct InterfaceMethod {
    pub name: String,
    pub params: Vec<Param>,
    pub return_type: Option<TypeAnnotation>,
}

#[derive(Debug, Clone)]
pub struct SwitchCase {
    pub pattern: SwitchPattern,
    pub body: Block,
}

#[derive(Debug, Clone)]
pub enum SwitchPattern {
    IntLit(i64),
    StringLit(String),
    Ident(String),
}

#[derive(Debug, Clone)]
pub struct Param {
    pub name: String,
    pub type_ann: TypeAnnotation,
    pub default: Option<Expr>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum VarKind {
    Const,
    Let,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AssignOp {
    Assign,        // =
    PlusAssign,    // +=
    MinusAssign,   // -=
    StarAssign,    // *=
    SlashAssign,   // /=
    PercentAssign, // %=
}

#[derive(Debug, Clone, PartialEq)]
pub enum TypeAnnotation {
    Int,
    Double,
    String,
    Bool,
    Void,
    Named(std::string::String),
}

pub type Block = Vec<Stmt>;

#[derive(Debug, Clone)]
pub struct Expr {
    pub kind: ExprKind,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub enum ExprKind {
    IntLit(i64),
    DoubleLit(f64),
    StringLit(String),
    BoolLit(bool),
    TemplateLit(Vec<TemplateExprFragment>),
    Ident(String),
    Binary {
        left: Box<Expr>,
        op: BinOp,
        right: Box<Expr>,
    },
    Unary {
        op: UnaryOp,
        operand: Box<Expr>,
    },
    Call {
        callee: String,
        args: Vec<Expr>,
    },
    // OOP
    NewExpr {
        class_name: String,
        args: Vec<Expr>,
    },
    MemberAccess {
        object: Box<Expr>,
        member: String,
    },
    MethodCall {
        object: Box<Expr>,
        method: String,
        args: Vec<Expr>,
    },
    This,
    Grouping(Box<Expr>),
    PostfixIncrement(String), // i++
    PostfixDecrement(String), // i--
    // Arrays
    ArrayLit(Vec<Expr>),                      // [1, 2, 3]
    IndexAccess { object: Box<Expr>, index: Box<Expr> },  // arr[0]
    Ternary { condition: Box<Expr>, then_expr: Box<Expr>, else_expr: Box<Expr> }, // a ? b : c
}

#[derive(Debug, Clone)]
pub enum TemplateExprFragment {
    Literal(String),
    Expr(Expr),
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    And,
    Or,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum UnaryOp {
    Neg,
    Not,
}
