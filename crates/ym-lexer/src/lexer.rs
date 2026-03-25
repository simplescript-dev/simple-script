use crate::token::{Span, TemplateFragment, Token, TokenKind};

#[derive(Debug, thiserror::Error)]
pub enum LexError {
    #[error("unexpected character '{ch}' at line {line}:{col}")]
    UnexpectedChar { ch: char, line: u32, col: u32 },
    #[error("unterminated string at line {line}:{col}")]
    UnterminatedString { line: u32, col: u32 },
    #[error("unterminated template string at line {line}:{col}")]
    UnterminatedTemplate { line: u32, col: u32 },
    #[error("invalid number at line {line}:{col}")]
    InvalidNumber { line: u32, col: u32 },
}

pub struct Lexer<'a> {
    source: &'a [u8],
    pos: usize,
    line: u32,
    col: u32,
}

impl<'a> Lexer<'a> {
    pub fn new(source: &'a str) -> Self {
        Self {
            source: source.as_bytes(),
            pos: 0,
            line: 1,
            col: 1,
        }
    }

    pub fn tokenize(&mut self) -> Result<Vec<Token>, LexError> {
        let mut tokens = Vec::new();
        loop {
            self.skip_whitespace_and_comments();
            if self.is_eof() {
                tokens.push(self.make_token(TokenKind::Eof));
                break;
            }

            let ch = self.peek();

            // Newline
            if ch == b'\n' {
                tokens.push(self.make_token(TokenKind::Newline));
                self.advance();
                self.line += 1;
                self.col = 1;
                continue;
            }

            let token = match ch {
                // String literal
                b'"' => self.lex_string()?,
                // Single-quoted string (same as double-quoted)
                b'\'' => self.lex_single_quote_string()?,
                // Template literal
                b'`' => self.lex_template()?,
                // Number
                b'0'..=b'9' => self.lex_number()?,
                // Identifier or keyword
                b'a'..=b'z' | b'A'..=b'Z' | b'_' => self.lex_ident_or_keyword(),
                // Operators and delimiters
                b'+' => self.lex_plus(),
                b'-' => self.lex_minus(),
                b'*' => self.lex_star(),
                b'/' => self.lex_two_char(TokenKind::Slash, b'=', TokenKind::SlashAssign),
                b'%' => self.lex_two_char(TokenKind::Percent, b'=', TokenKind::PercentAssign),
                b'=' => self.lex_eq(),
                b'!' => self.lex_bang(),
                b'?' => self.single_token(TokenKind::Question),
                b'<' => self.lex_lt(),
                b'>' => self.lex_gt(),
                b'&' => self.lex_and()?,
                b'|' => self.lex_or()?,
                b'(' => self.single_token(TokenKind::LParen),
                b')' => self.single_token(TokenKind::RParen),
                b'{' => self.single_token(TokenKind::LBrace),
                b'}' => self.single_token(TokenKind::RBrace),
                b'[' => self.single_token(TokenKind::LBracket),
                b']' => self.single_token(TokenKind::RBracket),
                b',' => self.single_token(TokenKind::Comma),
                b':' => self.single_token(TokenKind::Colon),
                b';' => self.single_token(TokenKind::Semicolon),
                b'.' => self.single_token(TokenKind::Dot),
                _ => {
                    return Err(LexError::UnexpectedChar {
                        ch: ch as char,
                        line: self.line,
                        col: self.col,
                    });
                }
            };
            tokens.push(token);
        }
        Ok(tokens)
    }

    fn is_eof(&self) -> bool {
        self.pos >= self.source.len()
    }

    fn peek(&self) -> u8 {
        self.source[self.pos]
    }

    fn peek_next(&self) -> Option<u8> {
        if self.pos + 1 < self.source.len() {
            Some(self.source[self.pos + 1])
        } else {
            None
        }
    }

    fn advance(&mut self) -> u8 {
        let ch = self.source[self.pos];
        self.pos += 1;
        self.col += 1;
        ch
    }

    fn make_token(&self, kind: TokenKind) -> Token {
        Token {
            kind,
            span: Span {
                start: self.pos,
                end: self.pos,
                line: self.line,
                col: self.col,
            },
        }
    }

    fn make_token_at(&self, kind: TokenKind, start: usize, line: u32, col: u32) -> Token {
        Token {
            kind,
            span: Span {
                start,
                end: self.pos,
                line,
                col,
            },
        }
    }

    fn skip_whitespace_and_comments(&mut self) {
        while !self.is_eof() {
            let ch = self.peek();
            match ch {
                b' ' | b'\t' | b'\r' => {
                    self.advance();
                }
                b'/' if self.peek_next() == Some(b'/') => {
                    // Line comment
                    while !self.is_eof() && self.peek() != b'\n' {
                        self.advance();
                    }
                }
                b'/' if self.peek_next() == Some(b'*') => {
                    // Block comment
                    self.advance(); // /
                    self.advance(); // *
                    while !self.is_eof() {
                        if self.peek() == b'*' && self.peek_next() == Some(b'/') {
                            self.advance(); // *
                            self.advance(); // /
                            break;
                        }
                        if self.peek() == b'\n' {
                            self.line += 1;
                            self.col = 0; // will be incremented by advance
                        }
                        self.advance();
                    }
                }
                _ => break,
            }
        }
    }

    fn single_token(&mut self, kind: TokenKind) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        self.make_token_at(kind, start, line, col)
    }

    fn lex_two_char(&mut self, single: TokenKind, next: u8, double: TokenKind) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() && self.peek() == next {
            self.advance();
            self.make_token_at(double, start, line, col)
        } else {
            self.make_token_at(single, start, line, col)
        }
    }

    fn lex_string(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance(); // skip opening "

        let mut value = String::new();
        while !self.is_eof() && self.peek() != b'"' {
            if self.peek() == b'\\' {
                self.advance();
                if self.is_eof() {
                    return Err(LexError::UnterminatedString { line, col });
                }
                match self.peek() {
                    b'n' => value.push('\n'),
                    b't' => value.push('\t'),
                    b'r' => value.push('\r'),
                    b'0' => value.push('\0'),
                    b'\\' => value.push('\\'),
                    b'"' => value.push('"'),
                    _ => {
                        value.push('\\');
                        value.push(self.peek() as char);
                    }
                }
                self.advance();
            } else if self.peek() == b'\n' {
                return Err(LexError::UnterminatedString { line, col });
            } else {
                value.push(self.peek() as char);
                self.advance();
            }
        }

        if self.is_eof() {
            return Err(LexError::UnterminatedString { line, col });
        }
        self.advance(); // skip closing "

        Ok(self.make_token_at(TokenKind::StringLit(value), start, line, col))
    }

    fn lex_single_quote_string(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance(); // skip opening '

        let mut value = String::new();
        while !self.is_eof() && self.peek() != b'\'' {
            if self.peek() == b'\\' {
                self.advance();
                if self.is_eof() {
                    return Err(LexError::UnterminatedString { line, col });
                }
                match self.peek() {
                    b'n' => value.push('\n'),
                    b't' => value.push('\t'),
                    b'r' => value.push('\r'),
                    b'0' => value.push('\0'),
                    b'\\' => value.push('\\'),
                    b'\'' => value.push('\''),
                    _ => {
                        value.push('\\');
                        value.push(self.peek() as char);
                    }
                }
                self.advance();
            } else if self.peek() == b'\n' {
                return Err(LexError::UnterminatedString { line, col });
            } else {
                value.push(self.peek() as char);
                self.advance();
            }
        }

        if self.is_eof() {
            return Err(LexError::UnterminatedString { line, col });
        }
        self.advance(); // skip closing '

        Ok(self.make_token_at(TokenKind::StringLit(value), start, line, col))
    }

    fn lex_template(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance(); // skip opening `

        let mut fragments = Vec::new();
        let mut current_lit = String::new();

        while !self.is_eof() && self.peek() != b'`' {
            if self.peek() == b'$' && self.peek_next() == Some(b'{') {
                // Save current literal if non-empty
                if !current_lit.is_empty() {
                    fragments.push(TemplateFragment::Literal(current_lit.clone()));
                    current_lit.clear();
                }

                self.advance(); // $
                self.advance(); // {

                // Collect tokens until matching }
                let mut expr_tokens = Vec::new();
                let mut brace_depth = 1;
                while !self.is_eof() && brace_depth > 0 {
                    self.skip_whitespace_and_comments();
                    if self.is_eof() {
                        return Err(LexError::UnterminatedTemplate { line, col });
                    }

                    if self.peek() == b'{' {
                        brace_depth += 1;
                        expr_tokens.push(self.single_token(TokenKind::LBrace));
                    } else if self.peek() == b'}' {
                        brace_depth -= 1;
                        if brace_depth > 0 {
                            expr_tokens.push(self.single_token(TokenKind::RBrace));
                        } else {
                            self.advance(); // skip closing }
                        }
                    } else {
                        // Lex one token inside the template expression
                        let ch = self.peek();
                        let token = match ch {
                            b'"' => self.lex_string()?,
                            b'0'..=b'9' => self.lex_number()?,
                            b'a'..=b'z' | b'A'..=b'Z' | b'_' => self.lex_ident_or_keyword(),
                            b'+' => self.lex_plus(),
                            b'-' => self.lex_minus(),
                            b'*' => self.single_token(TokenKind::Star),
                            b'/' => self.single_token(TokenKind::Slash),
                            b'%' => self.lex_two_char(TokenKind::Percent, b'=', TokenKind::PercentAssign),
                            b'=' => self.lex_eq(),
                            b'!' => self.lex_bang(),
                            b'<' => self.lex_lt(),
                            b'>' => self.lex_gt(),
                            b'(' => self.single_token(TokenKind::LParen),
                            b')' => self.single_token(TokenKind::RParen),
                            b'[' => self.single_token(TokenKind::LBracket),
                            b']' => self.single_token(TokenKind::RBracket),
                            b',' => self.single_token(TokenKind::Comma),
                            b':' => self.single_token(TokenKind::Colon),
                            b'.' => self.single_token(TokenKind::Dot),
                            _ => {
                                return Err(LexError::UnexpectedChar {
                                    ch: ch as char,
                                    line: self.line,
                                    col: self.col,
                                });
                            }
                        };
                        expr_tokens.push(token);
                    }
                }

                fragments.push(TemplateFragment::Expr(expr_tokens));
            } else if self.peek() == b'\\' {
                self.advance();
                if !self.is_eof() {
                    match self.peek() {
                        b'n' => current_lit.push('\n'),
                        b't' => current_lit.push('\t'),
                        b'\\' => current_lit.push('\\'),
                        b'`' => current_lit.push('`'),
                        b'$' => current_lit.push('$'),
                        _ => {
                            current_lit.push('\\');
                            current_lit.push(self.peek() as char);
                        }
                    }
                    self.advance();
                }
            } else {
                if self.peek() == b'\n' {
                    self.line += 1;
                    self.col = 0;
                }
                current_lit.push(self.peek() as char);
                self.advance();
            }
        }

        if self.is_eof() {
            return Err(LexError::UnterminatedTemplate { line, col });
        }
        self.advance(); // skip closing `

        // Push remaining literal
        if !current_lit.is_empty() {
            fragments.push(TemplateFragment::Literal(current_lit));
        }

        Ok(self.make_token_at(TokenKind::TemplateLit(fragments), start, line, col))
    }

    fn lex_number(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        let mut is_double = false;

        while !self.is_eof() && (self.peek().is_ascii_digit() || self.peek() == b'_') {
            self.advance();
        }

        if !self.is_eof() && self.peek() == b'.' && self.peek_next().is_some_and(|c| c.is_ascii_digit()) {
            is_double = true;
            self.advance(); // .
            while !self.is_eof() && (self.peek().is_ascii_digit() || self.peek() == b'_') {
                self.advance();
            }
        }

        let text: String = self.source[start..self.pos]
            .iter()
            .filter(|&&b| b != b'_')
            .map(|&b| b as char)
            .collect();

        if is_double {
            let value: f64 = text.parse().map_err(|_| LexError::InvalidNumber { line, col })?;
            Ok(self.make_token_at(TokenKind::DoubleLit(value), start, line, col))
        } else {
            let value: i64 = text.parse().map_err(|_| LexError::InvalidNumber { line, col })?;
            Ok(self.make_token_at(TokenKind::IntLit(value), start, line, col))
        }
    }

    fn lex_ident_or_keyword(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;

        while !self.is_eof() && (self.peek().is_ascii_alphanumeric() || self.peek() == b'_') {
            self.advance();
        }

        let text = std::str::from_utf8(&self.source[start..self.pos]).unwrap();
        let kind = match text {
            "function" => TokenKind::Function,
            "const" => TokenKind::Const,
            "let" => TokenKind::Let,
            "return" => TokenKind::Return,
            "if" => TokenKind::If,
            "else" => TokenKind::Else,
            "for" => TokenKind::For,
            "while" => TokenKind::While,
            "do" => TokenKind::Do,
            "break" => TokenKind::Break,
            "continue" => TokenKind::Continue,
            "true" => TokenKind::True,
            "false" => TokenKind::False,
            "class" => TokenKind::Class,
            "new" => TokenKind::New,
            "this" => TokenKind::This,
            "interface" => TokenKind::Interface,
            "override" => TokenKind::Override,
            "extends" => TokenKind::Extends,
            "sealed" => TokenKind::Sealed,
            "enum" => TokenKind::Enum,
            "switch" => TokenKind::Switch,
            "case" => TokenKind::Case,
            "default" => TokenKind::Default,
            "null" => TokenKind::Null,
            "int" => TokenKind::IntType,
            "double" => TokenKind::DoubleType,
            "string" => TokenKind::StringType,
            "bool" => TokenKind::BoolType,
            _ => TokenKind::Ident(text.to_string()),
        };

        self.make_token_at(kind, start, line, col)
    }

    fn lex_star(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() {
            match self.peek() {
                b'*' => { self.advance(); return self.make_token_at(TokenKind::Power, start, line, col); }
                b'=' => { self.advance(); return self.make_token_at(TokenKind::StarAssign, start, line, col); }
                _ => {}
            }
        }
        self.make_token_at(TokenKind::Star, start, line, col)
    }

    fn lex_plus(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() {
            match self.peek() {
                b'+' => {
                    self.advance();
                    return self.make_token_at(TokenKind::PlusPlus, start, line, col);
                }
                b'=' => {
                    self.advance();
                    return self.make_token_at(TokenKind::PlusAssign, start, line, col);
                }
                _ => {}
            }
        }
        self.make_token_at(TokenKind::Plus, start, line, col)
    }

    fn lex_minus(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() {
            match self.peek() {
                b'-' => {
                    self.advance();
                    return self.make_token_at(TokenKind::MinusMinus, start, line, col);
                }
                b'=' => {
                    self.advance();
                    return self.make_token_at(TokenKind::MinusAssign, start, line, col);
                }
                b'>' => {
                    self.advance();
                    return self.make_token_at(TokenKind::ThinArrow, start, line, col);
                }
                _ => {}
            }
        }
        self.make_token_at(TokenKind::Minus, start, line, col)
    }

    fn lex_eq(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() {
            match self.peek() {
                b'=' => {
                    self.advance();
                    return self.make_token_at(TokenKind::Eq, start, line, col);
                }
                b'>' => {
                    self.advance();
                    return self.make_token_at(TokenKind::Arrow, start, line, col);
                }
                _ => {}
            }
        }
        self.make_token_at(TokenKind::Assign, start, line, col)
    }

    fn lex_bang(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() && self.peek() == b'=' {
            self.advance();
            return self.make_token_at(TokenKind::Ne, start, line, col);
        }
        self.make_token_at(TokenKind::Not, start, line, col)
    }

    fn lex_lt(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() && self.peek() == b'=' {
            self.advance();
            return self.make_token_at(TokenKind::Le, start, line, col);
        }
        self.make_token_at(TokenKind::Lt, start, line, col)
    }

    fn lex_gt(&mut self) -> Token {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() && self.peek() == b'=' {
            self.advance();
            return self.make_token_at(TokenKind::Ge, start, line, col);
        }
        self.make_token_at(TokenKind::Gt, start, line, col)
    }

    fn lex_and(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() && self.peek() == b'&' {
            self.advance();
            Ok(self.make_token_at(TokenKind::And, start, line, col))
        } else {
            Err(LexError::UnexpectedChar {
                ch: '&',
                line,
                col,
            })
        }
    }

    fn lex_or(&mut self) -> Result<Token, LexError> {
        let start = self.pos;
        let line = self.line;
        let col = self.col;
        self.advance();
        if !self.is_eof() && self.peek() == b'|' {
            self.advance();
            Ok(self.make_token_at(TokenKind::Or, start, line, col))
        } else {
            Err(LexError::UnexpectedChar {
                ch: '|',
                line,
                col,
            })
        }
    }
}
