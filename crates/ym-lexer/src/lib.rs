pub mod token;
pub mod lexer;

pub use token::{Token, TokenKind, Span, TemplateFragment};
pub use lexer::{Lexer, LexError};

pub fn tokenize(source: &str) -> Result<Vec<Token>, LexError> {
    let mut lexer = Lexer::new(source);
    lexer.tokenize()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mvp_hello() {
        let source = r#"function main() {
    const name = "SimpleScript"
    let count = 0
    for (let i = 0; i < 3; i++) {
        count = count + 1
        println(`hello, ${name}! count=${count}`)
    }
}"#;
        let tokens = tokenize(source).expect("should tokenize");
        let kinds: Vec<_> = tokens.iter()
            .map(|t| &t.kind)
            .filter(|k| !matches!(k, TokenKind::Newline))
            .collect();

        // function main() {
        assert_eq!(kinds[0], &TokenKind::Function);
        assert_eq!(kinds[1], &TokenKind::Ident("main".to_string()));
        assert_eq!(kinds[2], &TokenKind::LParen);
        assert_eq!(kinds[3], &TokenKind::RParen);
        assert_eq!(kinds[4], &TokenKind::LBrace);

        // const name = "SimpleScript"
        assert_eq!(kinds[5], &TokenKind::Const);
        assert_eq!(kinds[6], &TokenKind::Ident("name".to_string()));
        assert_eq!(kinds[7], &TokenKind::Assign);
        assert_eq!(kinds[8], &TokenKind::StringLit("SimpleScript".to_string()));

        // let count = 0
        assert_eq!(kinds[9], &TokenKind::Let);
        assert_eq!(kinds[10], &TokenKind::Ident("count".to_string()));
        assert_eq!(kinds[11], &TokenKind::Assign);
        assert_eq!(kinds[12], &TokenKind::IntLit(0));
    }

    #[test]
    fn test_template_string() {
        let source = r#"`hello, ${name}!`"#;
        let tokens = tokenize(source).expect("should tokenize");
        match &tokens[0].kind {
            TokenKind::TemplateLit(fragments) => {
                assert_eq!(fragments.len(), 3);
                assert_eq!(fragments[0], TemplateFragment::Literal("hello, ".to_string()));
                match &fragments[1] {
                    TemplateFragment::Expr(expr_tokens) => {
                        assert_eq!(expr_tokens[0].kind, TokenKind::Ident("name".to_string()));
                    }
                    _ => panic!("expected Expr fragment"),
                }
                assert_eq!(fragments[2], TemplateFragment::Literal("!".to_string()));
            }
            _ => panic!("expected TemplateLit"),
        }
    }

    #[test]
    fn test_operators() {
        let tokens = tokenize("a++ b-- c += d -= e == f != g <= h >= i && j || k").unwrap();
        let kinds: Vec<_> = tokens.iter()
            .map(|t| &t.kind)
            .filter(|k| !matches!(k, TokenKind::Newline | TokenKind::Eof))
            .collect();
        assert_eq!(kinds[1], &TokenKind::PlusPlus);
        assert_eq!(kinds[3], &TokenKind::MinusMinus);
        assert_eq!(kinds[5], &TokenKind::PlusAssign);
        assert_eq!(kinds[7], &TokenKind::MinusAssign);
        assert_eq!(kinds[9], &TokenKind::Eq);
        assert_eq!(kinds[11], &TokenKind::Ne);
        assert_eq!(kinds[13], &TokenKind::Le);
        assert_eq!(kinds[15], &TokenKind::Ge);
        assert_eq!(kinds[17], &TokenKind::And);
        assert_eq!(kinds[19], &TokenKind::Or);
    }

    #[test]
    fn test_arrow() {
        let tokens = tokenize("(x: int) => x + 1").unwrap();
        let kinds: Vec<_> = tokens.iter()
            .map(|t| &t.kind)
            .filter(|k| !matches!(k, TokenKind::Newline | TokenKind::Eof))
            .collect();
        // (x : int) => x + 1
        // 0 1 2  3  4  5 6 7
        assert!(kinds.contains(&&TokenKind::Arrow)); // =>
    }
}
