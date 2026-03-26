#[derive(Debug, Clone, PartialEq)]
pub enum Type {
    Int,
    Double,
    String,
    Bool,
    Void,
    Named(String),
    Unknown,
}

impl std::fmt::Display for Type {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Type::Int => write!(f, "int"),
            Type::Double => write!(f, "double"),
            Type::String => write!(f, "string"),
            Type::Bool => write!(f, "bool"),
            Type::Void => write!(f, "void"),
            Type::Named(n) => write!(f, "{n}"),
            Type::Unknown => write!(f, "unknown"),
        }
    }
}
