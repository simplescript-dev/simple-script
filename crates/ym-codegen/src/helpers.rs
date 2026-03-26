use inkwell::values::{BasicValueEnum, PointerValue};
use inkwell::types::BasicMetadataTypeEnum;
use inkwell::AddressSpace;
use ym_parser::*;
use crate::codegen::{Codegen, CodegenError, VarType};

impl<'ctx> Codegen<'ctx> {
    pub(crate) fn compile_print_arg(&mut self, arg: &Expr) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        if let ExprKind::Ident(name) = &arg.kind {
            if let Some(tag) = self.var_class.get(name).cloned() {
                if tag == "__int_array__" || tag == "__str_array__" {
                    let arr = self.compile_expr(arg)?;
                    let func = self.module.get_function("ss_arrayToString").unwrap();
                    return Ok(self.builder.build_call(func, &[arr.into()], "ats")?
                        .try_as_basic_value().left().unwrap());
                }
            }
            if let Some(class_name) = self.var_class.get(name).cloned() {
                if self.classes.contains_key(&class_name) {
                    let ts_fn = format!("{class_name}_toString");
                    if let Some(to_string) = self.module.get_function(&ts_fn) {
                        let obj = self.compile_expr(arg)?;
                        return Ok(self.builder.build_call(to_string, &[obj.into()], "ts")?
                            .try_as_basic_value().left().unwrap());
                    }
                }
            }
        }
        let val = self.compile_expr(arg)?;
        self.value_to_string(val)
    }

    pub(crate) fn value_to_string(&mut self, val: BasicValueEnum<'ctx>) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        if val.is_pointer_value() {
            Ok(val)
        } else if val.is_int_value() {
            let int_val = val.into_int_value();
            if int_val.get_type().get_bit_width() == 64 {
                let i64s = self.module.get_function("ss_i64_to_string").unwrap();
                Ok(self.builder.build_call(i64s, &[val.into()], "i64s")?
                    .try_as_basic_value().left().unwrap())
            } else {
                let i2s = self.module.get_function("ss_int_to_string").unwrap();
                Ok(self.builder.build_call(i2s, &[val.into()], "i2s")?
                    .try_as_basic_value().left().unwrap())
            }
        } else if val.is_float_value() {
            let d2s = self.module.get_function("ss_double_to_string").unwrap();
            Ok(self.builder.build_call(d2s, &[val.into()], "d2s")?
                .try_as_basic_value().left().unwrap())
        } else {
            Ok(self.build_global_string("<unknown>").into())
        }
    }

    pub(crate) fn load_var(&self, name: &str) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        let (ptr, var_type) = self.get_var(name)
            .ok_or(CodegenError::UndefinedVar(name.to_string()))?;
        let llvm_type: inkwell::types::BasicTypeEnum = match var_type {
            VarType::Int | VarType::Bool => self.context.i32_type().into(),
            VarType::Double => self.context.f64_type().into(),
            VarType::String | VarType::Object => self.context.ptr_type(AddressSpace::default()).into(),
        };
        Ok(self.builder.build_load(llvm_type, ptr, name)?)
    }

    pub(crate) fn build_global_string(&mut self, s: &str) -> PointerValue<'ctx> {
        let name = format!(".str.{}", self.str_counter);
        self.str_counter += 1;
        let val = self.context.const_string(s.as_bytes(), true);
        let global = self.module.add_global(val.get_type(), Some(AddressSpace::default()), &name);
        global.set_initializer(&val);
        global.set_constant(true);
        global.as_pointer_value()
    }

    pub(crate) fn to_i64(&self, val: BasicValueEnum<'ctx>) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        let i64_type = self.context.i64_type();
        if val.is_int_value() {
            let int_val = val.into_int_value();
            if int_val.get_type().get_bit_width() == 64 { return Ok(val); }
            Ok(self.builder.build_int_s_extend(int_val, i64_type, "sext")?.into())
        } else if val.is_pointer_value() {
            Ok(self.builder.build_ptr_to_int(val.into_pointer_value(), i64_type, "ptoi")?.into())
        } else {
            Ok(i64_type.const_int(0, false).into())
        }
    }

    pub(crate) fn to_i32(&self, val: BasicValueEnum<'ctx>) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        let i32_type = self.context.i32_type();
        if val.is_int_value() {
            let int_val = val.into_int_value();
            if int_val.get_type().get_bit_width() == 32 { return Ok(val); }
            Ok(self.builder.build_int_truncate(int_val, i32_type, "trunc")?.into())
        } else {
            Ok(val)
        }
    }

    pub(crate) fn to_bool(&self, val: BasicValueEnum<'ctx>) -> Result<inkwell::values::IntValue<'ctx>, CodegenError> {
        if val.is_int_value() {
            let int_val = val.into_int_value();
            if int_val.get_type().get_bit_width() == 1 { return Ok(int_val); }
            let zero = int_val.get_type().const_int(0, false);
            Ok(self.builder.build_int_compare(inkwell::IntPredicate::NE, int_val, zero, "tobool")?)
        } else if val.is_float_value() {
            let zero = self.context.f64_type().const_float(0.0);
            Ok(self.builder.build_float_compare(inkwell::FloatPredicate::ONE, val.into_float_value(), zero, "ftobool")?)
        } else {
            Ok(self.context.bool_type().const_int(1, false))
        }
    }

    pub(crate) fn value_to_var_type(&self, val: &BasicValueEnum) -> VarType {
        if val.is_int_value() { VarType::Int }
        else if val.is_float_value() { VarType::Double }
        else if val.is_pointer_value() { VarType::String }
        else { VarType::Int }
    }

    pub(crate) fn type_ann_to_var_type(&self, ann: &TypeAnnotation) -> VarType {
        match ann {
            TypeAnnotation::Int => VarType::Int,
            TypeAnnotation::Double => VarType::Double,
            TypeAnnotation::String => VarType::String,
            TypeAnnotation::Bool => VarType::Bool,
            _ => VarType::Object,
        }
    }

    pub(crate) fn type_ann_to_llvm_meta(&self, ann: &TypeAnnotation) -> BasicMetadataTypeEnum<'ctx> {
        match ann {
            TypeAnnotation::Int | TypeAnnotation::Bool => self.context.i32_type().into(),
            TypeAnnotation::Double => self.context.f64_type().into(),
            _ => self.context.ptr_type(AddressSpace::default()).into(),
        }
    }

    pub(crate) fn find_return_type(&self, body: &[Stmt]) -> VarType {
        for stmt in body {
            if let StmtKind::Return(Some(expr)) = &stmt.kind {
                return match &expr.kind {
                    ExprKind::IntLit(_) => VarType::Int,
                    ExprKind::DoubleLit(_) => VarType::Double,
                    ExprKind::StringLit(_) | ExprKind::TemplateLit(_) => VarType::String,
                    ExprKind::BoolLit(_) => VarType::Bool,
                    _ => VarType::Int,
                };
            }
            if let StmtKind::If { then_block, else_block, .. } = &stmt.kind {
                let t = self.find_return_type(then_block);
                if !matches!(t, VarType::Int) || else_block.is_some() { return t; }
            }
        }
        VarType::Int
    }
}
