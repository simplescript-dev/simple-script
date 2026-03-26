use ss_lexer::{Token, TokenKind, TemplateFragment};
use crate::ast::*;
use crate::parser::{Parser, ParseError};

impl Parser {
    pub(crate) fn parse_expr(&mut self) -> Result<Expr, ParseError> {
        let expr = self.parse_or()?;
        // Ternary: expr ? then : else
        if matches!(self.peek_kind(), TokenKind::Question) {
            self.advance(); // ?
            let then_expr = self.parse_expr()?;
            self.expect(&TokenKind::Colon)?;
            let else_expr = self.parse_expr()?;
            let span = expr.span;
            return Ok(Expr {
                kind: ExprKind::Ternary {
                    condition: Box::new(expr),
                    then_expr: Box::new(then_expr),
                    else_expr: Box::new(else_expr),
                },
                span,
            });
        }
        Ok(expr)
    }

    fn parse_or(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_and_expr()?;
        while matches!(self.peek_kind(), TokenKind::Or) {
            self.advance();
            let right = self.parse_and_expr()?;
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op: BinOp::Or, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_and_expr(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_equality()?;
        while matches!(self.peek_kind(), TokenKind::And) {
            self.advance();
            let right = self.parse_equality()?;
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op: BinOp::And, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_equality(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_comparison()?;
        loop {
            let op = match self.peek_kind() {
                TokenKind::Eq => BinOp::Eq,
                TokenKind::Ne => BinOp::Ne,
                _ => break,
            };
            self.advance();
            let right = self.parse_comparison()?;
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_comparison(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_additive()?;
        loop {
            let op = match self.peek_kind() {
                TokenKind::Lt => BinOp::Lt,
                TokenKind::Gt => BinOp::Gt,
                TokenKind::Le => BinOp::Le,
                TokenKind::Ge => BinOp::Ge,
                _ => break,
            };
            self.advance();
            let right = self.parse_additive()?;
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_additive(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_multiplicative()?;
        loop {
            let op = match self.peek_kind() {
                TokenKind::Plus => BinOp::Add,
                TokenKind::Minus => BinOp::Sub,
                _ => break,
            };
            self.advance();
            let right = self.parse_multiplicative()?;
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_multiplicative(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_power()?;
        loop {
            let op = match self.peek_kind() {
                TokenKind::Star => BinOp::Mul,
                TokenKind::Slash => BinOp::Div,
                TokenKind::Percent => BinOp::Mod,
                _ => break,
            };
            self.advance();
            let right = self.parse_power()?;
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_power(&mut self) -> Result<Expr, ParseError> {
        let mut left = self.parse_unary()?;
        if matches!(self.peek_kind(), TokenKind::Power) {
            self.advance();
            let right = self.parse_power()?; // right-associative
            let span = left.span;
            left = Expr {
                kind: ExprKind::Binary { left: Box::new(left), op: BinOp::Pow, right: Box::new(right) },
                span,
            };
        }
        Ok(left)
    }

    fn parse_unary(&mut self) -> Result<Expr, ParseError> {
        let span = self.peek().span;
        match self.peek_kind() {
            TokenKind::Minus => {
                self.advance();
                let operand = self.parse_unary()?;
                Ok(Expr {
                    kind: ExprKind::Unary { op: UnaryOp::Neg, operand: Box::new(operand) },
                    span,
                })
            }
            TokenKind::Not => {
                self.advance();
                let operand = self.parse_unary()?;
                Ok(Expr {
                    kind: ExprKind::Unary { op: UnaryOp::Not, operand: Box::new(operand) },
                    span,
                })
            }
            _ => self.parse_primary(),
        }
    }

    fn parse_primary(&mut self) -> Result<Expr, ParseError> {
        let mut expr = self.parse_atom()?;

        // Postfix: .member, .method(), [index], keep chaining
        while matches!(self.peek_kind(), TokenKind::Dot | TokenKind::LBracket) {
            // Index access: arr[i]
            if matches!(self.peek_kind(), TokenKind::LBracket) {
                self.advance(); // [
                let index = self.parse_expr()?;
                self.expect(&TokenKind::RBracket)?;
                let span = expr.span;
                expr = Expr {
                    kind: ExprKind::IndexAccess { object: Box::new(expr), index: Box::new(index) },
                    span,
                };
                continue;
            }

            // Member access below
            self.advance(); // .
            let member = self.expect_ident()?;
            let span = expr.span;

            if matches!(self.peek_kind(), TokenKind::LParen) {
                // method call: obj.method(args)
                self.advance(); // (
                let args = self.parse_args()?;
                self.expect(&TokenKind::RParen)?;
                expr = Expr {
                    kind: ExprKind::MethodCall {
                        object: Box::new(expr),
                        method: member,
                        args,
                    },
                    span,
                };
            } else {
                // member access: obj.field
                expr = Expr {
                    kind: ExprKind::MemberAccess {
                        object: Box::new(expr),
                        member,
                    },
                    span,
                };
            }
        }

        Ok(expr)
    }

    fn parse_atom(&mut self) -> Result<Expr, ParseError> {
        let span = self.peek().span;

        match self.peek_kind().clone() {
            TokenKind::IntLit(n) => {
                let n = n;
                self.advance();
                Ok(Expr { kind: ExprKind::IntLit(n), span })
            }
            TokenKind::DoubleLit(n) => {
                let n = n;
                self.advance();
                Ok(Expr { kind: ExprKind::DoubleLit(n), span })
            }
            TokenKind::StringLit(s) => {
                let s = s.clone();
                self.advance();
                Ok(Expr { kind: ExprKind::StringLit(s), span })
            }
            TokenKind::True => {
                self.advance();
                Ok(Expr { kind: ExprKind::BoolLit(true), span })
            }
            TokenKind::False => {
                self.advance();
                Ok(Expr { kind: ExprKind::BoolLit(false), span })
            }
            TokenKind::TemplateLit(fragments) => {
                let fragments = fragments.clone();
                self.advance();
                let parsed = self.parse_template_fragments(fragments)?;
                Ok(Expr { kind: ExprKind::TemplateLit(parsed), span })
            }
            TokenKind::New => {
                self.advance();
                let class_name = self.expect_ident()?;
                self.expect(&TokenKind::LParen)?;
                let args = self.parse_args()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr { kind: ExprKind::NewExpr { class_name, args }, span })
            }
            TokenKind::This => {
                self.advance();
                Ok(Expr { kind: ExprKind::This, span })
            }
            TokenKind::Ident(name) => {
                let name = name.clone();
                self.advance();

                // Check for function call
                if matches!(self.peek_kind(), TokenKind::LParen) {
                    self.advance(); // (
                    let args = self.parse_args()?;
                    self.expect(&TokenKind::RParen)?;
                    Ok(Expr { kind: ExprKind::Call { callee: name, args }, span })
                } else {
                    Ok(Expr { kind: ExprKind::Ident(name), span })
                }
            }
            TokenKind::LParen => {
                self.advance();
                let expr = self.parse_expr()?;
                self.expect(&TokenKind::RParen)?;
                Ok(Expr { kind: ExprKind::Grouping(Box::new(expr)), span })
            }
            TokenKind::LBracket => {
                self.advance(); // [
                self.skip_newlines();
                let mut elements = Vec::new();
                if !matches!(self.peek_kind(), TokenKind::RBracket) {
                    loop {
                        self.skip_newlines();
                        elements.push(self.parse_expr()?);
                        self.skip_newlines();
                        if matches!(self.peek_kind(), TokenKind::Comma) {
                            self.advance();
                        } else {
                            break;
                        }
                    }
                }
                self.skip_newlines();
                self.expect(&TokenKind::RBracket)?;
                Ok(Expr { kind: ExprKind::ArrayLit(elements), span })
            }
            _ => Err(ParseError::Unexpected {
                found: format!("{:?}", self.peek_kind()),
                line: self.peek().span.line,
                col: self.peek().span.col,
            }),
        }
    }

    pub(crate) fn parse_args(&mut self) -> Result<Vec<Expr>, ParseError> {
        let mut args = Vec::new();
        self.skip_newlines();
        if matches!(self.peek_kind(), TokenKind::RParen) {
            return Ok(args);
        }

        loop {
            self.skip_newlines();
            args.push(self.parse_expr()?);
            self.skip_newlines();
            if matches!(self.peek_kind(), TokenKind::Comma) {
                self.advance();
            } else {
                break;
            }
        }
        Ok(args)
    }

    pub(crate) fn parse_template_fragments(&mut self, fragments: Vec<TemplateFragment>) -> Result<Vec<TemplateExprFragment>, ParseError> {
        let mut result = Vec::new();
        for frag in fragments {
            match frag {
                TemplateFragment::Literal(s) => {
                    result.push(TemplateExprFragment::Literal(s));
                }
                TemplateFragment::Expr(tokens) => {
                    let mut sub_parser = Parser::new(
                        tokens.into_iter()
                            .chain(std::iter::once(Token {
                                kind: TokenKind::Eof,
                                span: ss_lexer::Span { start: 0, end: 0, line: 0, col: 0 },
                            }))
                            .collect()
                    );
                    let expr = sub_parser.parse_expr()?;
                    result.push(TemplateExprFragment::Expr(expr));
                }
            }
        }
        Ok(result)
    }
}
