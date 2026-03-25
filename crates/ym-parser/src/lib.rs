pub mod ast;
pub mod parser;
mod expr_parser;

pub use ast::*;
pub use parser::{Parser, ParseError};

pub fn parse(tokens: Vec<ym_lexer::Token>) -> Result<Program, ParseError> {
    let mut parser = Parser::new(tokens);
    parser.parse()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_mvp() {
        let source = r#"function main() {
    const name = "SimpleScript"
    let count = 0
    for (let i = 0; i < 3; i++) {
        count = count + 1
        println(`hello, ${name}! count=${count}`)
    }
}"#;
        let tokens = ym_lexer::tokenize(source).unwrap();
        let program = parse(tokens).unwrap();

        assert_eq!(program.stmts.len(), 1);
        match &program.stmts[0].kind {
            StmtKind::FunctionDecl { name, params, body, .. } => {
                assert_eq!(name, "main");
                assert_eq!(params.len(), 0);
                // const name, let count, for loop = 3 stmts
                assert_eq!(body.len(), 3);
            }
            _ => panic!("expected FunctionDecl"),
        }
    }

    #[test]
    fn test_parse_if_else() {
        let source = r#"function test() {
    if (x > 0) {
        println("positive")
    } else {
        println("non-positive")
    }
}"#;
        let tokens = ym_lexer::tokenize(source).unwrap();
        let program = parse(tokens).unwrap();
        assert_eq!(program.stmts.len(), 1);
    }

    #[test]
    fn test_parse_expressions() {
        let source = r#"function calc() {
    const x = 1 + 2 * 3
    const y = (1 + 2) * 3
    const z = a && b || c
}"#;
        let tokens = ym_lexer::tokenize(source).unwrap();
        let program = parse(tokens).unwrap();
        assert_eq!(program.stmts.len(), 1);
        match &program.stmts[0].kind {
            StmtKind::FunctionDecl { body, .. } => {
                assert_eq!(body.len(), 3);
            }
            _ => panic!("expected FunctionDecl"),
        }
    }
}
