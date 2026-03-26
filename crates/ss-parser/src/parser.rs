use ss_lexer::{Token, TokenKind};
use crate::ast::*;

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("expected {expected}, found {found} at line {line}:{col}")]
    Expected {
        expected: String,
        found: String,
        line: u32,
        col: u32,
    },
    #[error("unexpected token {found} at line {line}:{col}")]
    Unexpected {
        found: String,
        line: u32,
        col: u32,
    },
    #[error("unexpected end of file")]
    UnexpectedEof,
}

pub struct Parser {
    tokens: Vec<Token>,
    pos: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self { tokens, pos: 0 }
    }

    pub fn parse(&mut self) -> Result<Program, ParseError> {
        let mut stmts = Vec::new();
        self.skip_newlines();
        while !self.is_at_end() {
            stmts.push(self.parse_stmt()?);
            self.skip_newlines();
        }
        Ok(Program { stmts })
    }

    // --- Helpers ---

    pub(crate) fn is_at_end(&self) -> bool {
        matches!(self.peek_kind(), TokenKind::Eof)
    }

    pub(crate) fn peek(&self) -> &Token {
        &self.tokens[self.pos]
    }

    pub(crate) fn peek_kind(&self) -> &TokenKind {
        &self.tokens[self.pos].kind
    }

    pub(crate) fn advance(&mut self) -> &Token {
        let token = &self.tokens[self.pos];
        if !self.is_at_end() {
            self.pos += 1;
        }
        token
    }

    pub(crate) fn expect(&mut self, kind: &TokenKind) -> Result<&Token, ParseError> {
        if self.peek_kind() == kind {
            Ok(self.advance())
        } else {
            Err(ParseError::Expected {
                expected: format!("{:?}", kind),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            })
        }
    }

    pub(crate) fn expect_ident(&mut self) -> Result<String, ParseError> {
        match self.peek_kind().clone() {
            TokenKind::Ident(name) => {
                let name = name.clone();
                self.advance();
                Ok(name)
            }
            _ => Err(ParseError::Expected {
                expected: "identifier".to_string(),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        }
    }

    pub(crate) fn skip_newlines(&mut self) {
        while matches!(self.peek_kind(), TokenKind::Newline) {
            self.advance();
        }
    }

    pub(crate) fn expect_newline_or_rbrace(&mut self) -> Result<(), ParseError> {
        match self.peek_kind() {
            TokenKind::Newline => { self.advance(); Ok(()) }
            TokenKind::RBrace | TokenKind::Eof => Ok(()),
            TokenKind::Semicolon => { self.advance(); Ok(()) }
            _ => Err(ParseError::Expected {
                expected: "newline or '}'".to_string(),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        }
    }

    // --- Statements ---

    fn parse_stmt(&mut self) -> Result<Stmt, ParseError> {
        self.skip_newlines();
        let span = self.peek().span;

        match self.peek_kind() {
            TokenKind::Function => self.parse_function_decl(),
            TokenKind::Class => self.parse_class_decl(),
            TokenKind::Interface => self.parse_interface_decl(),
            TokenKind::Enum => self.parse_enum_decl(),
            TokenKind::Switch => self.parse_switch(),
            TokenKind::Const | TokenKind::Let => self.parse_var_decl(),
            TokenKind::Return => self.parse_return(),
            TokenKind::If => self.parse_if(),
            TokenKind::For => self.parse_for(),
            TokenKind::While => self.parse_while(),
            TokenKind::Do => self.parse_do_while(),
            TokenKind::Break => {
                let span = self.peek().span;
                self.advance();
                self.expect_newline_or_rbrace()?;
                Ok(Stmt { kind: StmtKind::Break, span })
            }
            TokenKind::Continue => {
                let span = self.peek().span;
                self.advance();
                self.expect_newline_or_rbrace()?;
                Ok(Stmt { kind: StmtKind::Continue, span })
            }
            TokenKind::Ident(_) => {
                // Could be assignment (x = ..., x += ...) or expression statement (fn call)
                self.parse_assignment_or_expr_stmt()
            }
            _ => {
                let expr = self.parse_expr()?;
                self.expect_newline_or_rbrace()?;
                Ok(Stmt { kind: StmtKind::ExprStmt(expr), span })
            }
        }
    }

    fn parse_interface_decl(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::Interface)?;
        let name = self.expect_ident()?;

        self.skip_newlines();
        self.expect(&TokenKind::LBrace)?;
        self.skip_newlines();

        let mut methods = Vec::new();
        while !matches!(self.peek_kind(), TokenKind::RBrace | TokenKind::Eof) {
            self.expect(&TokenKind::Function)?;
            let method_name = self.expect_ident()?;
            self.expect(&TokenKind::LParen)?;
            let params = self.parse_params()?;
            self.expect(&TokenKind::RParen)?;
            let return_type = if matches!(self.peek_kind(), TokenKind::Colon) {
                self.advance();
                Some(self.parse_type_annotation()?)
            } else {
                None
            };
            self.expect_newline_or_rbrace()?;
            self.skip_newlines();
            methods.push(InterfaceMethod { name: method_name, params, return_type });
        }
        self.expect(&TokenKind::RBrace)?;

        Ok(Stmt {
            kind: StmtKind::InterfaceDecl { name, methods },
            span,
        })
    }

    fn parse_enum_decl(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::Enum)?;
        let name = self.expect_ident()?;

        self.expect(&TokenKind::LBrace)?;
        self.skip_newlines();
        let mut variants = Vec::new();
        while !matches!(self.peek_kind(), TokenKind::RBrace | TokenKind::Eof) {
            variants.push(self.expect_ident()?);
            if matches!(self.peek_kind(), TokenKind::Comma) {
                self.advance();
            }
            self.skip_newlines();
        }
        self.expect(&TokenKind::RBrace)?;

        Ok(Stmt {
            kind: StmtKind::EnumDecl { name, variants },
            span,
        })
    }

    fn parse_switch(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::Switch)?;
        self.expect(&TokenKind::LParen)?;
        let subject = self.parse_expr()?;
        self.expect(&TokenKind::RParen)?;

        self.skip_newlines();
        self.expect(&TokenKind::LBrace)?;
        self.skip_newlines();

        let mut cases = Vec::new();
        let mut default = None;

        while !matches!(self.peek_kind(), TokenKind::RBrace | TokenKind::Eof) {
            if matches!(self.peek_kind(), TokenKind::Default) {
                self.advance(); // default
                self.expect(&TokenKind::ThinArrow)?;
                let body = self.parse_switch_body()?;
                default = Some(body);
            } else {
                self.expect(&TokenKind::Case)?;
                let pattern = self.parse_switch_pattern()?;
                self.expect(&TokenKind::ThinArrow)?;
                let body = self.parse_switch_body()?;
                cases.push(SwitchCase { pattern, body });
            }
            self.skip_newlines();
        }

        self.expect(&TokenKind::RBrace)?;

        Ok(Stmt {
            kind: StmtKind::Switch { subject, cases, default },
            span,
        })
    }

    fn parse_switch_pattern(&mut self) -> Result<SwitchPattern, ParseError> {
        match self.peek_kind().clone() {
            TokenKind::IntLit(n) => {
                let n = n;
                self.advance();
                Ok(SwitchPattern::IntLit(n))
            }
            TokenKind::StringLit(s) => {
                let s = s.clone();
                self.advance();
                Ok(SwitchPattern::StringLit(s))
            }
            TokenKind::Ident(name) => {
                let name = name.clone();
                self.advance();
                Ok(SwitchPattern::Ident(name))
            }
            _ => Err(ParseError::Expected {
                expected: "pattern".to_string(),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        }
    }

    fn parse_switch_body(&mut self) -> Result<Block, ParseError> {
        if matches!(self.peek_kind(), TokenKind::LBrace) {
            self.parse_block()
        } else {
            // Single statement
            let stmt = self.parse_stmt()?;
            Ok(vec![stmt])
        }
    }

    fn parse_class_decl(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::Class)?;
        let name = self.expect_ident()?;

        // Optional extends
        let extends = if matches!(self.peek_kind(), TokenKind::Extends) {
            self.advance();
            Some(self.expect_ident()?)
        } else {
            None
        };

        // Constructor params
        self.expect(&TokenKind::LParen)?;
        let fields = self.parse_params()?;
        self.expect(&TokenKind::RParen)?;

        // Optional implements: `: InterfaceName`
        let mut implements = Vec::new();
        if matches!(self.peek_kind(), TokenKind::Colon) {
            self.advance();
            loop {
                implements.push(self.expect_ident()?);
                if matches!(self.peek_kind(), TokenKind::Comma) {
                    self.advance();
                } else {
                    break;
                }
            }
        }

        self.skip_newlines();

        // Optional body with methods
        let methods = if matches!(self.peek_kind(), TokenKind::LBrace) {
            self.expect(&TokenKind::LBrace)?;
            self.skip_newlines();
            let mut methods = Vec::new();
            while !matches!(self.peek_kind(), TokenKind::RBrace | TokenKind::Eof) {
                methods.push(self.parse_function_decl()?);
                self.skip_newlines();
            }
            self.expect(&TokenKind::RBrace)?;
            methods
        } else {
            Vec::new()
        };

        Ok(Stmt {
            kind: StmtKind::ClassDecl { name, extends, fields, implements, methods },
            span,
        })
    }

    fn parse_function_decl(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        // Skip optional 'override' keyword
        if matches!(self.peek_kind(), TokenKind::Override) {
            self.advance();
        }
        self.expect(&TokenKind::Function)?;
        let name = self.expect_ident()?;

        self.expect(&TokenKind::LParen)?;
        let params = self.parse_params()?;
        self.expect(&TokenKind::RParen)?;

        let return_type = if matches!(self.peek_kind(), TokenKind::Colon) {
            self.advance();
            Some(self.parse_type_annotation()?)
        } else {
            None
        };

        self.skip_newlines();
        let body = self.parse_block()?;

        Ok(Stmt {
            kind: StmtKind::FunctionDecl { name, params, return_type, body },
            span,
        })
    }

    fn parse_params(&mut self) -> Result<Vec<Param>, ParseError> {
        let mut params = Vec::new();
        self.skip_newlines();
        if matches!(self.peek_kind(), TokenKind::RParen) {
            return Ok(params);
        }

        loop {
            self.skip_newlines();
            let name = self.expect_ident()?;
            self.expect(&TokenKind::Colon)?;
            let type_ann = self.parse_type_annotation()?;
            let default = if matches!(self.peek_kind(), TokenKind::Assign) {
                self.advance();
                Some(self.parse_expr()?)
            } else {
                None
            };
            params.push(Param { name, type_ann, default });

            if matches!(self.peek_kind(), TokenKind::Comma) {
                self.advance();
            } else {
                break;
            }
        }
        Ok(params)
    }

    fn parse_type_annotation(&mut self) -> Result<TypeAnnotation, ParseError> {
        match self.peek_kind() {
            TokenKind::IntType => { self.advance(); Ok(TypeAnnotation::Int) }
            TokenKind::DoubleType => { self.advance(); Ok(TypeAnnotation::Double) }
            TokenKind::StringType => { self.advance(); Ok(TypeAnnotation::String) }
            TokenKind::BoolType => { self.advance(); Ok(TypeAnnotation::Bool) }
            TokenKind::Ident(name) => {
                let name = name.clone();
                self.advance();
                Ok(TypeAnnotation::Named(name))
            }
            _ => Err(ParseError::Expected {
                expected: "type".to_string(),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        }
    }

    fn parse_block(&mut self) -> Result<Block, ParseError> {
        self.expect(&TokenKind::LBrace)?;
        self.skip_newlines();

        let mut stmts = Vec::new();
        while !matches!(self.peek_kind(), TokenKind::RBrace | TokenKind::Eof) {
            stmts.push(self.parse_stmt()?);
            self.skip_newlines();
        }

        self.expect(&TokenKind::RBrace)?;
        Ok(stmts)
    }

    fn parse_var_decl(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        let kind = match self.peek_kind() {
            TokenKind::Const => { self.advance(); VarKind::Const }
            TokenKind::Let => { self.advance(); VarKind::Let }
            _ => unreachable!(),
        };

        let name = self.expect_ident()?;

        let type_ann = if matches!(self.peek_kind(), TokenKind::Colon) {
            self.advance();
            Some(self.parse_type_annotation()?)
        } else {
            None
        };

        self.expect(&TokenKind::Assign)?;
        let init = self.parse_expr()?;
        self.expect_newline_or_rbrace()?;

        Ok(Stmt {
            kind: StmtKind::VarDecl { kind, name, type_ann, init },
            span,
        })
    }

    fn parse_return(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::Return)?;

        let value = if matches!(self.peek_kind(), TokenKind::Newline | TokenKind::RBrace | TokenKind::Eof) {
            None
        } else {
            Some(self.parse_expr()?)
        };
        self.expect_newline_or_rbrace()?;

        Ok(Stmt { kind: StmtKind::Return(value), span })
    }

    fn parse_if(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::If)?;
        self.expect(&TokenKind::LParen)?;
        let condition = self.parse_expr()?;
        self.expect(&TokenKind::RParen)?;

        self.skip_newlines();
        let then_block = self.parse_block()?;

        let else_block = if matches!(self.peek_kind(), TokenKind::Else) {
            self.advance();
            self.skip_newlines();
            if matches!(self.peek_kind(), TokenKind::If) {
                // else if -> wrap in block
                let else_if = self.parse_if()?;
                Some(vec![else_if])
            } else {
                Some(self.parse_block()?)
            }
        } else {
            None
        };

        Ok(Stmt {
            kind: StmtKind::If { condition, then_block, else_block },
            span,
        })
    }

    fn parse_for_in(&mut self, span: ss_lexer::Span) -> Result<Stmt, ParseError> {
        let item = self.expect_ident()?;
        self.advance(); // skip "in"
        let iterable = self.parse_expr()?;
        self.expect(&TokenKind::RParen)?;
        self.skip_newlines();
        let body = self.parse_block()?;

        Ok(Stmt {
            kind: StmtKind::ForIn { item, iterable, body },
            span,
        })
    }

    fn parse_for(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::For)?;
        self.expect(&TokenKind::LParen)?;

        // Check for for-in: for (item in expr)
        if let TokenKind::Ident(_) = self.peek_kind() {
            if self.pos + 1 < self.tokens.len() {
                if let TokenKind::Ident(kw) = &self.tokens[self.pos + 1].kind {
                    if kw == "in" {
                        return self.parse_for_in(span);
                    }
                }
            }
        }

        // C-style for: let i = 0
        let init = self.parse_var_decl_no_newline()?;
        self.expect(&TokenKind::Semicolon)?;

        // Condition: i < 3
        let condition = self.parse_expr()?;
        self.expect(&TokenKind::Semicolon)?;

        // Update: i++
        let update = self.parse_update_stmt()?;
        self.expect(&TokenKind::RParen)?;

        self.skip_newlines();
        let body = self.parse_block()?;

        Ok(Stmt {
            kind: StmtKind::For {
                init: Box::new(init),
                condition,
                update: Box::new(update),
                body,
            },
            span,
        })
    }

    fn parse_var_decl_no_newline(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        let kind = match self.peek_kind() {
            TokenKind::Const => { self.advance(); VarKind::Const }
            TokenKind::Let => { self.advance(); VarKind::Let }
            _ => return Err(ParseError::Expected {
                expected: "const or let".to_string(),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        };

        let name = self.expect_ident()?;

        let type_ann = if matches!(self.peek_kind(), TokenKind::Colon) {
            self.advance();
            Some(self.parse_type_annotation()?)
        } else {
            None
        };

        self.expect(&TokenKind::Assign)?;
        let init = self.parse_expr()?;

        Ok(Stmt {
            kind: StmtKind::VarDecl { kind, name, type_ann, init },
            span,
        })
    }

    fn parse_update_stmt(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        let name = self.expect_ident()?;

        match self.peek_kind() {
            TokenKind::PlusPlus => {
                self.advance();
                Ok(Stmt {
                    kind: StmtKind::ExprStmt(Expr {
                        kind: ExprKind::PostfixIncrement(name),
                        span,
                    }),
                    span,
                })
            }
            TokenKind::MinusMinus => {
                self.advance();
                Ok(Stmt {
                    kind: StmtKind::ExprStmt(Expr {
                        kind: ExprKind::PostfixDecrement(name),
                        span,
                    }),
                    span,
                })
            }
            TokenKind::PlusAssign | TokenKind::MinusAssign | TokenKind::StarAssign
            | TokenKind::SlashAssign | TokenKind::PercentAssign | TokenKind::Assign => {
                let op = match self.peek_kind() {
                    TokenKind::PlusAssign => AssignOp::PlusAssign,
                    TokenKind::MinusAssign => AssignOp::MinusAssign,
                    TokenKind::StarAssign => AssignOp::StarAssign,
                    TokenKind::SlashAssign => AssignOp::SlashAssign,
                    TokenKind::PercentAssign => AssignOp::PercentAssign,
                    _ => AssignOp::Assign,
                };
                self.advance();
                let value = self.parse_expr()?;
                Ok(Stmt {
                    kind: StmtKind::Assignment { target: name, op, value },
                    span,
                })
            }
            _ => Err(ParseError::Expected {
                expected: "++, --, +=, -=, or =".to_string(),
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        }
    }

    fn parse_while(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::While)?;
        self.expect(&TokenKind::LParen)?;
        let condition = self.parse_expr()?;
        self.expect(&TokenKind::RParen)?;

        self.skip_newlines();
        let body = self.parse_block()?;

        Ok(Stmt { kind: StmtKind::While { condition, body }, span })
    }

    fn parse_do_while(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;
        self.expect(&TokenKind::Do)?;
        self.skip_newlines();
        let body = self.parse_block()?;
        self.skip_newlines();
        self.expect(&TokenKind::While)?;
        self.expect(&TokenKind::LParen)?;
        let condition = self.parse_expr()?;
        self.expect(&TokenKind::RParen)?;
        self.expect_newline_or_rbrace()?;
        Ok(Stmt { kind: StmtKind::DoWhile { body, condition }, span })
    }

    fn parse_assignment_or_expr_stmt(&mut self) -> Result<Stmt, ParseError> {
        let span = self.peek().span;

        if let TokenKind::Ident(name) = self.peek_kind().clone() {
            let name = name.clone();

            // Look ahead for index assignment: arr[i] = value
            if self.pos + 1 < self.tokens.len() && matches!(self.tokens[self.pos + 1].kind, TokenKind::LBracket) {
                self.advance(); // ident
                self.advance(); // [
                let index = self.parse_expr()?;
                self.expect(&TokenKind::RBracket)?;
                if matches!(self.peek_kind(), TokenKind::Assign) {
                    self.advance(); // =
                    let value = self.parse_expr()?;
                    self.expect_newline_or_rbrace()?;
                    return Ok(Stmt {
                        kind: StmtKind::IndexAssign { object: name, index, value },
                        span,
                    });
                }
                // Not assignment, was just arr[i] as expression
                // This is tricky — we already consumed tokens. Build an expr stmt.
                let obj_expr = Expr { kind: ExprKind::Ident(name), span };
                let access = Expr {
                    kind: ExprKind::IndexAccess { object: Box::new(obj_expr), index: Box::new(index) },
                    span,
                };
                self.expect_newline_or_rbrace()?;
                return Ok(Stmt { kind: StmtKind::ExprStmt(access), span });
            }

            // Look ahead for assignment operators
            if self.pos + 1 < self.tokens.len() {
                match &self.tokens[self.pos + 1].kind {
                    TokenKind::Assign => {
                        self.advance(); // ident
                        self.advance(); // =
                        let value = self.parse_expr()?;
                        self.expect_newline_or_rbrace()?;
                        return Ok(Stmt {
                            kind: StmtKind::Assignment { target: name, op: AssignOp::Assign, value },
                            span,
                        });
                    }
                    TokenKind::PlusAssign => {
                        self.advance();
                        self.advance();
                        let value = self.parse_expr()?;
                        self.expect_newline_or_rbrace()?;
                        return Ok(Stmt {
                            kind: StmtKind::Assignment { target: name, op: AssignOp::PlusAssign, value },
                            span,
                        });
                    }
                    TokenKind::MinusAssign | TokenKind::StarAssign | TokenKind::SlashAssign | TokenKind::PercentAssign => {
                        let op = match &self.tokens[self.pos + 1].kind {
                            TokenKind::MinusAssign => AssignOp::MinusAssign,
                            TokenKind::StarAssign => AssignOp::StarAssign,
                            TokenKind::SlashAssign => AssignOp::SlashAssign,
                            TokenKind::PercentAssign => AssignOp::PercentAssign,
                            _ => unreachable!(),
                        };
                        self.advance();
                        self.advance();
                        let value = self.parse_expr()?;
                        self.expect_newline_or_rbrace()?;
                        return Ok(Stmt {
                            kind: StmtKind::Assignment { target: name, op, value },
                            span,
                        });
                    }
                    TokenKind::PlusPlus => {
                        self.advance(); self.advance();
                        self.expect_newline_or_rbrace()?;
                        return Ok(Stmt {
                            kind: StmtKind::ExprStmt(Expr { kind: ExprKind::PostfixIncrement(name), span }),
                            span,
                        });
                    }
                    TokenKind::MinusMinus => {
                        self.advance(); self.advance();
                        self.expect_newline_or_rbrace()?;
                        return Ok(Stmt {
                            kind: StmtKind::ExprStmt(Expr { kind: ExprKind::PostfixDecrement(name), span }),
                            span,
                        });
                    }
                    _ => {}
                }
            }
        }

        // Not an assignment, parse as expression statement
        let expr = self.parse_expr()?;
        self.expect_newline_or_rbrace()?;
        Ok(Stmt { kind: StmtKind::ExprStmt(expr), span })
    }

    // --- Expressions (precedence climbing) ---

}
