pub mod types;
pub mod checker;

pub use types::Type;
pub use checker::{Checker, CheckError, TypedProgram};
