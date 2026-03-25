use std::collections::HashMap;
use ym_parser::*;
use crate::types::Type;

#[derive(Debug, thiserror::Error)]
pub enum CheckError {
    #[error("undefined variable '{name}' at line {line}{}", hint.as_ref().map(|h| format!(". did you mean '{h}'?")).unwrap_or_default())]
    UndefinedVar { name: String, line: u32, hint: Option<String> },
    #[error("undefined function '{name}' at line {line}{}", hint.as_ref().map(|h| format!(". did you mean '{h}'?")).unwrap_or_default())]
    UndefinedFunc { name: String, line: u32, hint: Option<String> },
    #[error("type mismatch: expected {expected}, found {found} at line {line}")]
    TypeMismatch { expected: Type, found: Type, line: u32 },
    #[error("cannot reassign const variable '{name}' at line {line}")]
    ConstReassign { name: String, line: u32 },
    #[error("wrong number of arguments for '{name}': expected {expected}, found {found} at line {line}")]
    ArgCount { name: String, expected: usize, found: usize, line: u32 },
}

#[derive(Debug, Clone)]
struct VarInfo {
    ty: Type,
    is_const: bool,
}

#[derive(Debug, Clone)]
pub struct FuncInfo {
    pub params: Vec<Type>,
    pub return_type: Type,
}

pub struct Checker {
    scopes: Vec<HashMap<String, VarInfo>>,
    functions: HashMap<String, FuncInfo>,
}

/// MVP: TypedProgram is just the AST with type info attached.
/// For now we reuse the AST directly since codegen only needs
/// to know variable types from the checker's symbol table.
pub struct TypedProgram {
    pub program: Program,
    pub global_vars: HashMap<String, Type>,
    pub functions: HashMap<String, FuncInfo>,
}

impl Checker {
    pub fn new() -> Self {
        let mut functions = HashMap::new();
        // Built-in: println(s: string) -> void
        functions.insert("println".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::Void,
        });
        functions.insert("print".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::Void,
        });
        functions.insert("readLine".to_string(), FuncInfo {
            params: vec![],
            return_type: Type::String,
        });
        functions.insert("readFile".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::String,
        });
        functions.insert("writeFile".to_string(), FuncInfo {
            params: vec![Type::String, Type::String],
            return_type: Type::Void,
        });
        functions.insert("appendFile".to_string(), FuncInfo {
            params: vec![Type::String, Type::String],
            return_type: Type::Void,
        });
        functions.insert("args".to_string(), FuncInfo {
            params: vec![],
            return_type: Type::Int,
        });
        functions.insert("arg".to_string(), FuncInfo {
            params: vec![Type::Int],
            return_type: Type::String,
        });
        functions.insert("exit".to_string(), FuncInfo {
            params: vec![Type::Int],
            return_type: Type::Void,
        });
        functions.insert("system".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::Int,
        });
        functions.insert("tcpListen".to_string(), FuncInfo {
            params: vec![Type::Int],
            return_type: Type::Int,
        });
        functions.insert("tcpAccept".to_string(), FuncInfo {
            params: vec![Type::Int],
            return_type: Type::Int,
        });
        functions.insert("tcpRead".to_string(), FuncInfo {
            params: vec![Type::Int, Type::Int],
            return_type: Type::String,
        });
        functions.insert("tcpWrite".to_string(), FuncInfo {
            params: vec![Type::Int, Type::String],
            return_type: Type::Int,
        });
        functions.insert("tcpWriteBytes".to_string(), FuncInfo {
            params: vec![Type::Int, Type::String, Type::Int],
            return_type: Type::Int,
        });
        functions.insert("tcpClose".to_string(), FuncInfo {
            params: vec![Type::Int],
            return_type: Type::Void,
        });
        functions.insert("getenv".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::String,
        });
        functions.insert("timeUnix".to_string(), FuncInfo {
            params: vec![],
            return_type: Type::Unknown,
        });
        functions.insert("parseInt".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::Int,
        });
        functions.insert("parseDouble".to_string(), FuncInfo {
            params: vec![Type::String],
            return_type: Type::Double,
        });
        functions.insert("Map".to_string(), FuncInfo {
            params: vec![],
            return_type: Type::Unknown,
        });
        for name in ["sqrt", "abs", "floor", "ceil", "round", "log", "sin", "cos"] {
            functions.insert(name.to_string(), FuncInfo {
                params: vec![Type::Double],
                return_type: Type::Double,
            });
        }
        for name in ["pow", "min", "max"] {
            functions.insert(name.to_string(), FuncInfo {
                params: vec![Type::Double, Type::Double],
                return_type: Type::Double,
            });
        }
        functions.insert("random".to_string(), FuncInfo {
            params: vec![],
            return_type: Type::Double,
        });

        Self {
            scopes: vec![HashMap::new()],
            functions,
        }
    }

    pub fn check(&mut self, program: &Program) -> Result<TypedProgram, CheckError> {
        // First pass: register all functions
        for stmt in &program.stmts {
            if let StmtKind::FunctionDecl { name, params, return_type, .. } = &stmt.kind {
                let param_types: Vec<Type> = params.iter()
                    .map(|p| self.resolve_type_annotation(&p.type_ann))
                    .collect();
                let ret_type = return_type.as_ref()
                    .map(|t| self.resolve_type_annotation(t))
                    .unwrap_or(Type::Void);
                self.functions.insert(name.clone(), FuncInfo {
                    params: param_types,
                    return_type: ret_type,
                });
            }
        }

        // Second pass: check function bodies
        for stmt in &program.stmts {
            self.check_stmt(stmt)?;
        }

        Ok(TypedProgram {
            program: program.clone(),
            global_vars: self.scopes[0].iter()
                .map(|(k, v)| (k.clone(), v.ty.clone()))
                .collect(),
            functions: self.functions.clone(),
        })
    }

    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    fn define_var(&mut self, name: &str, ty: Type, is_const: bool) {
        let scope = self.scopes.last_mut().unwrap();
        scope.insert(name.to_string(), VarInfo { ty, is_const });
    }

    fn lookup_var(&self, name: &str) -> Option<&VarInfo> {
        for scope in self.scopes.iter().rev() {
            if let Some(info) = scope.get(name) {
                return Some(info);
            }
        }
        None
    }

    fn resolve_type_annotation(&self, ann: &TypeAnnotation) -> Type {
        match ann {
            TypeAnnotation::Int => Type::Int,
            TypeAnnotation::Double => Type::Double,
            TypeAnnotation::String => Type::String,
            TypeAnnotation::Bool => Type::Bool,
            TypeAnnotation::Void => Type::Void,
            TypeAnnotation::Named(_) => Type::Unknown,
        }
    }

    fn find_similar_var(&self, name: &str) -> Option<String> {
        for scope in self.scopes.iter().rev() {
            for key in scope.keys() {
                if levenshtein(name, key) <= 2 && name != key { return Some(key.clone()); }
            }
        }
        None
    }

    fn find_similar_func(&self, name: &str) -> Option<String> {
        for key in self.functions.keys() {
            if levenshtein(name, key) <= 2 && name != key { return Some(key.clone()); }
        }
        None
    }

    fn check_stmt(&mut self, stmt: &Stmt) -> Result<(), CheckError> {
        match &stmt.kind {
            StmtKind::InterfaceDecl { .. } => Ok(()),
            StmtKind::Break | StmtKind::Continue => Ok(()),
            StmtKind::EnumDecl { name: _, variants: _ } => Ok(()),
            StmtKind::Switch { subject, cases, default } => {
                self.infer_expr(subject)?;
                for case in cases {
                    for s in &case.body { self.check_stmt(s)?; }
                }
                if let Some(d) = default {
                    for s in d { self.check_stmt(s)?; }
                }
                Ok(())
            }
            StmtKind::ClassDecl { name: _, extends: _, fields: _, implements: _, methods } => {
                // MVP: just check method bodies
                for method in methods {
                    self.check_stmt(method)?;
                }
                Ok(())
            }
            StmtKind::FunctionDecl { name: _, params, return_type: _, body } => {
                self.push_scope();
                for param in params {
                    let ty = self.resolve_type_annotation(&param.type_ann);
                    self.define_var(&param.name, ty, false);
                }
                for s in body {
                    self.check_stmt(s)?;
                }
                self.pop_scope();
                Ok(())
            }
            StmtKind::VarDecl { kind, name, type_ann, init } => {
                let init_type = self.infer_expr(init)?;
                let declared_type = type_ann.as_ref()
                    .map(|t| self.resolve_type_annotation(t))
                    .unwrap_or(init_type.clone());

                if type_ann.is_some() && declared_type != init_type && init_type != Type::Unknown {
                    return Err(CheckError::TypeMismatch {
                        expected: declared_type,
                        found: init_type,
                        line: stmt.span.line,
                    });
                }

                self.define_var(name, declared_type, *kind == VarKind::Const);
                Ok(())
            }
            StmtKind::IndexAssign { object: _, index, value } => {
                self.infer_expr(index)?;
                self.infer_expr(value)?;
                Ok(())
            }
            StmtKind::Assignment { target, op: _, value } => {
                if let Some(info) = self.lookup_var(target) {
                    if info.is_const {
                        return Err(CheckError::ConstReassign {
                            name: target.clone(),
                            line: stmt.span.line,
                        });
                    }
                } else {
                    let hint = self.find_similar_var(target);
                    return Err(CheckError::UndefinedVar {
                        name: target.clone(),
                        line: stmt.span.line,
                        hint,
                    });
                }
                self.infer_expr(value)?;
                Ok(())
            }
            StmtKind::ExprStmt(expr) => {
                self.infer_expr(expr)?;
                Ok(())
            }
            StmtKind::Return(value) => {
                if let Some(expr) = value {
                    self.infer_expr(expr)?;
                }
                Ok(())
            }
            StmtKind::If { condition, then_block, else_block } => {
                self.infer_expr(condition)?;
                self.push_scope();
                for s in then_block { self.check_stmt(s)?; }
                self.pop_scope();
                if let Some(else_b) = else_block {
                    self.push_scope();
                    for s in else_b { self.check_stmt(s)?; }
                    self.pop_scope();
                }
                Ok(())
            }
            StmtKind::For { init, condition, update, body } => {
                self.push_scope();
                self.check_stmt(init)?;
                self.infer_expr(condition)?;
                self.check_stmt(update)?;
                for s in body { self.check_stmt(s)?; }
                self.pop_scope();
                Ok(())
            }
            StmtKind::ForIn { item, iterable, body } => {
                self.push_scope();
                self.infer_expr(iterable)?;
                self.define_var(item, Type::Unknown, false);
                for s in body { self.check_stmt(s)?; }
                self.pop_scope();
                Ok(())
            }
            StmtKind::While { condition, body } | StmtKind::DoWhile { body, condition } => {
                self.infer_expr(condition)?;
                self.push_scope();
                for s in body { self.check_stmt(s)?; }
                self.pop_scope();
                Ok(())
            }
        }
    }

    fn infer_expr(&self, expr: &Expr) -> Result<Type, CheckError> {
        match &expr.kind {
            ExprKind::IntLit(_) => Ok(Type::Int),
            ExprKind::DoubleLit(_) => Ok(Type::Double),
            ExprKind::StringLit(_) => Ok(Type::String),
            ExprKind::BoolLit(_) => Ok(Type::Bool),
            ExprKind::TemplateLit(_) => Ok(Type::String),
            ExprKind::Ident(name) => {
                match self.lookup_var(name) {
                    Some(info) => Ok(info.ty.clone()),
                    None => Err(CheckError::UndefinedVar {
                        hint: self.find_similar_var(name),
                        name: name.clone(),
                        line: expr.span.line,
                    }),
                }
            }
            ExprKind::Binary { left, op, right } => {
                let lt = self.infer_expr(left)?;
                let rt = self.infer_expr(right)?;
                match op {
                    BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::Div | BinOp::Mod | BinOp::Pow => {
                        // String + String = String (concatenation)
                        if *op == BinOp::Add && lt == Type::String && rt == Type::String {
                            return Ok(Type::String);
                        }
                        Ok(lt) // MVP: assume same type
                    }
                    BinOp::Eq | BinOp::Ne | BinOp::Lt | BinOp::Gt | BinOp::Le | BinOp::Ge => {
                        Ok(Type::Bool)
                    }
                    BinOp::And | BinOp::Or => Ok(Type::Bool),
                }
            }
            ExprKind::Unary { op, operand } => {
                let t = self.infer_expr(operand)?;
                match op {
                    UnaryOp::Neg => Ok(t),
                    UnaryOp::Not => Ok(Type::Bool),
                }
            }
            ExprKind::Call { callee, args } => {
                if let Some(func) = self.functions.get(callee) {
                    // MVP: relaxed arg count check for println (variadic-ish)
                    if callee != "println" && args.len() > func.params.len() {
                        return Err(CheckError::ArgCount {
                            name: callee.clone(),
                            expected: func.params.len(),
                            found: args.len(),
                            line: expr.span.line,
                        });
                    }
                    for arg in args {
                        self.infer_expr(arg)?;
                    }
                    Ok(func.return_type.clone())
                } else {
                    Err(CheckError::UndefinedFunc {
                        hint: self.find_similar_func(callee),
                        name: callee.clone(),
                        line: expr.span.line,
                    })
                }
            }
            ExprKind::Grouping(inner) => self.infer_expr(inner),
            ExprKind::ArrayLit(elements) => {
                for e in elements { self.infer_expr(e)?; }
                Ok(Type::Unknown) // array type
            }
            ExprKind::IndexAccess { object, index } => {
                self.infer_expr(object)?;
                self.infer_expr(index)?;
                Ok(Type::Unknown) // element type
            }
            ExprKind::NewExpr { class_name, args } => {
                for arg in args { self.infer_expr(arg)?; }
                Ok(Type::Named(class_name.clone()))
            }
            ExprKind::MemberAccess { object, member: _ } => {
                self.infer_expr(object)?;
                Ok(Type::Unknown) // MVP: don't track field types
            }
            ExprKind::MethodCall { object, method: _, args } => {
                self.infer_expr(object)?;
                for arg in args { self.infer_expr(arg)?; }
                Ok(Type::Unknown) // MVP: don't track method return types
            }
            ExprKind::This => Ok(Type::Unknown),
            ExprKind::Ternary { condition, then_expr, else_expr } => {
                self.infer_expr(condition)?;
                let t = self.infer_expr(then_expr)?;
                self.infer_expr(else_expr)?;
                Ok(t)
            }
            ExprKind::PostfixIncrement(name) | ExprKind::PostfixDecrement(name) => {
                match self.lookup_var(name) {
                    Some(info) => Ok(info.ty.clone()),
                    None => Err(CheckError::UndefinedVar {
                        hint: self.find_similar_var(name),
                        name: name.clone(),
                        line: expr.span.line,
                    }),
                }
            }
        }
    }
}

fn levenshtein(a: &str, b: &str) -> usize {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    let mut curr = vec![0; b.len() + 1];
    for i in 1..=a.len() {
        curr[0] = i;
        for j in 1..=b.len() {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            curr[j] = (prev[j] + 1).min(curr[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    prev[b.len()]
}
