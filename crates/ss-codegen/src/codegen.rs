use std::collections::HashMap;
use std::path::Path;

use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::module::Module;
use inkwell::targets::{CodeModel, FileType, InitializationConfig, RelocMode, Target, TargetMachine};
use inkwell::types::{BasicMetadataTypeEnum, BasicType};
use inkwell::values::{BasicValueEnum, FunctionValue, PointerValue};
use inkwell::AddressSpace;
use inkwell::OptimizationLevel;

use ss_parser::*;

#[derive(Debug, thiserror::Error)]
pub enum CodegenError {
    #[error("codegen error: {0}")]
    General(String),
    #[error("undefined variable: {0}")]
    UndefinedVar(String),
    #[error("undefined function: {0}")]
    UndefinedFunc(String),
}

impl From<inkwell::builder::BuilderError> for CodegenError {
    fn from(e: inkwell::builder::BuilderError) -> Self {
        CodegenError::General(e.to_string())
    }
}

impl From<inkwell::support::LLVMString> for CodegenError {
    fn from(e: inkwell::support::LLVMString) -> Self {
        CodegenError::General(e.to_string())
    }
}

pub struct Codegen<'ctx> {
    pub(crate) context: &'ctx Context,
    pub(crate) module: Module<'ctx>,
    pub(crate) builder: Builder<'ctx>,
    pub(crate) variables: Vec<HashMap<String, (PointerValue<'ctx>, VarType)>>,
    pub(crate) var_class: HashMap<String, String>,  // var_name -> class_name
    pub(crate) current_function: Option<FunctionValue<'ctx>>,
    pub(crate) current_this: Option<PointerValue<'ctx>>,
    pub(crate) current_class: Option<String>,
    pub(crate) loop_stack: Vec<LoopContext<'ctx>>,
    pub(crate) classes: HashMap<String, ClassInfo<'ctx>>,
    pub(crate) func_defaults: HashMap<String, Vec<Option<ss_parser::Expr>>>,
    pub(crate) str_counter: usize,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct LoopContext<'ctx> {
    pub(crate) break_bb: inkwell::basic_block::BasicBlock<'ctx>,
    pub(crate) continue_bb: inkwell::basic_block::BasicBlock<'ctx>,
}

#[derive(Debug, Clone)]
pub(crate) struct ClassInfo<'ctx> {
    pub(crate) struct_type: inkwell::types::StructType<'ctx>,
    pub(crate) fields: Vec<(String, VarType)>,
    pub(crate) parent: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub(crate) enum VarType {
    Int,
    Double,
    String,
    Bool,
    Object, // pointer to class struct
}

impl<'ctx> Codegen<'ctx> {
    pub fn new(context: &'ctx Context) -> Self {
        let module = context.create_module("simplescript");
        let builder = context.create_builder();

        Self {
            context,
            module,
            builder,
            variables: vec![HashMap::new()],
            var_class: HashMap::new(),
            current_function: None,
            current_this: None,
            current_class: None,
            loop_stack: vec![],
            classes: HashMap::new(),
            func_defaults: HashMap::new(),
            str_counter: 0,
        }
    }

    pub fn compile(&mut self, program: &Program) -> Result<(), CodegenError> {
        self.declare_runtime_functions();

        // Pass 1: forward-declare functions, compile classes, create globals
        for stmt in &program.stmts {
            self.forward_declare(stmt)?;
        }

        // Pass 2: compile top-level const/let as LLVM globals
        for stmt in &program.stmts {
            if let StmtKind::VarDecl { kind, name, type_ann: _, init } = &stmt.kind {
                self.compile_global_var(name, init, *kind == VarKind::Const)?;
            }
        }

        // Pass 3: compile functions
        for stmt in &program.stmts {
            if !matches!(&stmt.kind, StmtKind::VarDecl { .. }) {
                self.compile_stmt(stmt)?;
            }
        }

        Ok(())
    }

    fn compile_global_var(&mut self, name: &str, init: &Expr, is_const: bool) -> Result<(), CodegenError> {
        match &init.kind {
            ExprKind::IntLit(n) => {
                let val = self.context.i32_type().const_int(*n as u64, true);
                let global = self.module.add_global(self.context.i32_type(), Some(AddressSpace::default()), name);
                global.set_initializer(&val);
                global.set_constant(is_const);
                self.set_var(name, global.as_pointer_value(), VarType::Int);
            }
            ExprKind::DoubleLit(n) => {
                let val = self.context.f64_type().const_float(*n);
                let global = self.module.add_global(self.context.f64_type(), Some(AddressSpace::default()), name);
                global.set_initializer(&val);
                global.set_constant(is_const);
                self.set_var(name, global.as_pointer_value(), VarType::Double);
            }
            ExprKind::StringLit(s) => {
                let str_ptr = self.build_global_string(s);
                let global = self.module.add_global(self.context.ptr_type(AddressSpace::default()), Some(AddressSpace::default()), name);
                global.set_initializer(&str_ptr);
                global.set_constant(is_const);
                self.set_var(name, global.as_pointer_value(), VarType::String);
            }
            ExprKind::BoolLit(b) => {
                let val = self.context.i32_type().const_int(*b as u64, false);
                let global = self.module.add_global(self.context.i32_type(), Some(AddressSpace::default()), name);
                global.set_initializer(&val);
                global.set_constant(is_const);
                self.set_var(name, global.as_pointer_value(), VarType::Bool);
            }
            _ => {
                let ptr_type = self.context.ptr_type(AddressSpace::default());
                let global = self.module.add_global(ptr_type, Some(AddressSpace::default()), name);
                global.set_initializer(&ptr_type.const_null());
                global.set_constant(is_const);
                self.set_var(name, global.as_pointer_value(), VarType::String);
            }
        }
        Ok(())
    }

    fn forward_declare(&mut self, stmt: &Stmt) -> Result<(), CodegenError> {
        match &stmt.kind {
            StmtKind::FunctionDecl { name, params, return_type, body } => {
                if name == "main" {
                    return Ok(());
                }
                if self.module.get_function(name).is_some() {
                    return Ok(());
                }
                let param_types: Vec<BasicMetadataTypeEnum> = params.iter()
                    .map(|p| self.type_ann_to_llvm_meta(&p.type_ann))
                    .collect();
                let ret_type = if let Some(ann) = return_type {
                    self.type_ann_to_var_type(ann)
                } else {
                    self.find_return_type(body)
                };
                let fn_type = match ret_type {
                    VarType::Int | VarType::Bool => self.context.i32_type().fn_type(&param_types, false),
                    VarType::Double => self.context.f64_type().fn_type(&param_types, false),
                    VarType::String | VarType::Object => self.context.ptr_type(AddressSpace::default()).fn_type(&param_types, false),
                };
                self.module.add_function(name, fn_type, None);
                // Store default param values
                let defaults: Vec<Option<ss_parser::Expr>> = params.iter()
                    .map(|p| p.default.clone())
                    .collect();
                self.func_defaults.insert(name.clone(), defaults);
                Ok(())
            }
            _ => Ok(()),
        }
    }

    pub fn write_object_file(&self, path: &Path) -> Result<(), CodegenError> {
        self.write_object_file_opt(path, false)
    }

    pub fn write_object_file_opt(&self, path: &Path, release: bool) -> Result<(), CodegenError> {
        Target::initialize_x86(&InitializationConfig::default());

        let opt_level = if release { OptimizationLevel::Aggressive } else { OptimizationLevel::Default };

        let triple = TargetMachine::get_default_triple();
        let target = Target::from_triple(&triple)
?;
        let machine = target
            .create_target_machine(
                &triple,
                "x86-64",
                "",
                opt_level,
                RelocMode::Default,
                CodeModel::Default,
            )
            .ok_or(CodegenError::General("failed to create target machine".into()))?;

        machine
            .write_to_file(&self.module, FileType::Object, path)
?;

        Ok(())
    }

    pub fn print_ir(&self) -> String {
        self.module.print_to_string().to_string()
    }

    // --- Runtime function declarations ---

    // declare_runtime_functions moved to runtime_decl.rs
    // --- Scopes ---

    fn push_scope(&mut self) {
        self.variables.push(HashMap::new());
    }

    fn pop_scope(&mut self) {
        self.variables.pop();
    }

    fn set_var(&mut self, name: &str, ptr: PointerValue<'ctx>, ty: VarType) {
        self.variables.last_mut().unwrap().insert(name.to_string(), (ptr, ty));
    }

    pub(crate) fn get_var(&self, name: &str) -> Option<(PointerValue<'ctx>, VarType)> {
        for scope in self.variables.iter().rev() {
            if let Some(v) = scope.get(name) {
                return Some(*v);
            }
        }
        None
    }

    // --- Statement compilation ---

    fn compile_stmt(&mut self, stmt: &Stmt) -> Result<(), CodegenError> {
        match &stmt.kind {
            StmtKind::InterfaceDecl { .. } => Ok(()),
            StmtKind::Break => {
                if let Some(lc) = self.loop_stack.last() {
                    self.builder.build_unconditional_branch(lc.break_bb)
            ?;
                }
                Ok(())
            }
            StmtKind::Continue => {
                if let Some(lc) = self.loop_stack.last() {
                    self.builder.build_unconditional_branch(lc.continue_bb)
            ?;
                }
                Ok(())
            }
            StmtKind::EnumDecl { .. } => Ok(()), // enums are compile-time only
            StmtKind::Switch { subject, cases, default } => {
                self.compile_switch(subject, cases, default)
            }
            StmtKind::ClassDecl { name, extends, fields, implements: _, methods } => {
                let extends = extends.clone();
                self.compile_class(name, extends.as_deref(), fields, methods)
            }
            StmtKind::FunctionDecl { name, params, return_type, body } => {
                self.compile_function(name, params, return_type.as_ref(), body)
            }
            StmtKind::VarDecl { kind: _, name, type_ann: _, init } => {
                self.compile_var_decl(name, init)
            }
            StmtKind::IndexAssign { object, index, value } => {
                let arr_ptr = self.load_var(object)?.into_pointer_value();
                let idx = self.compile_expr(index)?;
                let idx32 = self.to_i32(idx)?;
                let val = self.compile_expr(value)?;
                let val64 = self.to_i64(val)?;
                let array_set_fn = self.module.get_function("ss_arraySet").unwrap();
                self.builder.build_call(array_set_fn, &[arr_ptr.into(), idx32.into(), val64.into()], "")?;
                Ok(())
            }
            StmtKind::Assignment { target, op, value } => {
                self.compile_assignment(target, op, value)
            }
            StmtKind::ExprStmt(expr) => {
                self.compile_expr(expr)?;
                Ok(())
            }
            StmtKind::Return(value) => {
                if let Some(expr) = value {
                    let val = self.compile_expr(expr)?;
                    self.builder.build_return(Some(&val))
            ?;
                } else {
                    self.builder.build_return(None)
            ?;
                }
                Ok(())
            }
            StmtKind::If { condition, then_block, else_block } => {
                self.compile_if(condition, then_block, else_block)
            }
            StmtKind::For { init, condition, update, body } => {
                self.compile_for(init, condition, update, body)
            }
            StmtKind::ForIn { item, iterable, body } => {
                self.compile_for_in(item, iterable, body)
            }
            StmtKind::DoWhile { body, condition } => {
                self.compile_do_while(condition, body)
            }
            StmtKind::While { condition, body } => {
                self.compile_while(condition, body)
            }
        }
    }

    fn compile_switch(&mut self, subject: &Expr, cases: &[SwitchCase], default: &Option<Vec<Stmt>>) -> Result<(), CodegenError> {
        let subject_val = self.compile_expr(subject)?;
        let function = self.current_function.unwrap();
        let merge_bb = self.context.append_basic_block(function, "switch.merge");

        let mut remaining_cases = cases.iter().peekable();

        while let Some(case) = remaining_cases.next() {
            let case_val: BasicValueEnum = match &case.pattern {
                SwitchPattern::IntLit(n) => self.context.i32_type().const_int(*n as u64, true).into(),
                SwitchPattern::StringLit(_) => {
                    // MVP: string comparison not yet supported in switch
                    return Err(CodegenError::General("string switch not yet supported".into()));
                }
                SwitchPattern::Ident(_) => {
                    return Err(CodegenError::General("pattern match not yet supported".into()));
                }
            };

            let cmp = self.builder.build_int_compare(
                inkwell::IntPredicate::EQ,
                subject_val.into_int_value(),
                case_val.into_int_value(),
                "case_cmp",
            )?;

            let then_bb = self.context.append_basic_block(function, "case.then");
            let next_bb = self.context.append_basic_block(function, "case.next");

            self.builder.build_conditional_branch(cmp, then_bb, next_bb)
    ?;

            // Case body
            self.builder.position_at_end(then_bb);
            for stmt in &case.body {
                self.compile_stmt(stmt)?;
            }
            // If body didn't terminate (return), jump to merge
            if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
                self.builder.build_unconditional_branch(merge_bb)?;
            }

            self.builder.position_at_end(next_bb);
        }

        // Default
        if let Some(default_body) = default {
            for stmt in default_body {
                self.compile_stmt(stmt)?;
            }
        }
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(merge_bb)
    ?;
        }

        self.builder.position_at_end(merge_bb);
        Ok(())
    }

    fn compile_class(&mut self, class_name: &str, extends: Option<&str>, fields: &[Param], methods: &[Stmt]) -> Result<(), CodegenError> {
        let i32_type = self.context.i32_type();
        let f64_type = self.context.f64_type();
        let ptr_type = self.context.ptr_type(AddressSpace::default());

        // Build struct type: parent fields first, then own fields
        let mut field_types: Vec<inkwell::types::BasicTypeEnum> = Vec::new();
        let mut field_info: Vec<(String, VarType)> = Vec::new();

        // Inherit parent fields
        if let Some(parent) = extends {
            if let Some(parent_info) = self.classes.get(parent).cloned() {
                for (name, vt) in &parent_info.fields {
                    let ty: inkwell::types::BasicTypeEnum = match vt {
                        VarType::Int | VarType::Bool => i32_type.into(),
                        VarType::Double => f64_type.into(),
                        _ => ptr_type.into(),
                    };
                    field_types.push(ty);
                    field_info.push((name.clone(), vt.clone()));
                }
            }
        }

        for field in fields {
            let (llvm_ty, var_ty) = match &field.type_ann {
                TypeAnnotation::Int => (i32_type.into(), VarType::Int),
                TypeAnnotation::Double => (self.context.f64_type().into(), VarType::Double),
                TypeAnnotation::String => (ptr_type.into(), VarType::String),
                TypeAnnotation::Bool => (i32_type.into(), VarType::Bool),
                _ => (i32_type.into(), VarType::Int),
            };
            field_types.push(llvm_ty);
            field_info.push((field.name.clone(), var_ty));
        }

        let struct_type = self.context.opaque_struct_type(class_name);
        struct_type.set_body(&field_types, false);

        self.classes.insert(class_name.to_string(), ClassInfo {
            struct_type,
            fields: field_info.clone(),
            parent: extends.map(|s| s.to_string()),
        });

        // Generate constructor: ClassName_new(all_fields...) -> ptr
        {
            let mut param_types: Vec<BasicMetadataTypeEnum> = Vec::new();
            for ft in &field_types {
                param_types.push((*ft).into());
            }
            let ctor_type = ptr_type.fn_type(&param_types, false);
            let ctor_name = format!("{class_name}_new");
            let ctor_fn = self.module.add_function(&ctor_name, ctor_type, None);
            let entry = self.context.append_basic_block(ctor_fn, "entry");
            self.builder.position_at_end(entry);

            // malloc struct
            let size = struct_type.size_of().unwrap();
            let malloc_fn = self.get_or_declare_malloc();
            let raw_ptr = self.builder.build_call(malloc_fn, &[size.into()], "raw")
                ?
                .try_as_basic_value().left().unwrap();

            // Store all fields (parent + own)
            for (i, _) in field_info.iter().enumerate() {
                let field_ptr = self.builder.build_struct_gep(struct_type, raw_ptr.into_pointer_value(), i as u32, "field_ptr")?;
                self.builder.build_store(field_ptr, ctor_fn.get_nth_param(i as u32).unwrap())?;
            }

            self.builder.build_return(Some(&raw_ptr))
    ?;
        }

        // Generate methods: ClassName_methodName(this_ptr, params...) -> ret
        for method in methods {
            if let StmtKind::FunctionDecl { name: method_name, params, return_type, body } = &method.kind {
                let ret_type = match return_type {
                    Some(TypeAnnotation::Int) | Some(TypeAnnotation::Bool) => Some(i32_type.as_basic_type_enum()),
                    Some(TypeAnnotation::Double) => Some(f64_type.as_basic_type_enum()),
                    Some(TypeAnnotation::String) | Some(TypeAnnotation::Named(_)) => Some(ptr_type.as_basic_type_enum()),
                    _ => None,
                };

                let mut param_types: Vec<BasicMetadataTypeEnum> = vec![ptr_type.into()]; // this
                for param in params {
                    let ty: BasicMetadataTypeEnum = match &param.type_ann {
                        TypeAnnotation::Int => i32_type.into(),
                        TypeAnnotation::String => ptr_type.into(),
                        TypeAnnotation::Double => self.context.f64_type().into(),
                        _ => ptr_type.into(), // class type = pointer
                    };
                    param_types.push(ty);
                }

                let fn_type: inkwell::types::FunctionType = if let Some(ret) = ret_type {
                    ret.fn_type(&param_types, false)
                } else {
                    self.context.void_type().fn_type(&param_types, false)
                };

                let full_name = format!("{class_name}_{method_name}");
                let function = self.module.add_function(&full_name, fn_type, None);
                let entry_bb = self.context.append_basic_block(function, "entry");
                self.builder.position_at_end(entry_bb);

                let prev_fn = self.current_function;
                let prev_this = self.current_this;
                let prev_class = self.current_class.clone();
                self.current_function = Some(function);
                self.current_this = Some(function.get_nth_param(0).unwrap().into_pointer_value());
                self.current_class = Some(class_name.to_string());

                self.push_scope();

                // Bind params (skip this at index 0)
                for (i, param) in params.iter().enumerate() {
                    let var_ty = match &param.type_ann {
                        TypeAnnotation::Int => VarType::Int,
                        TypeAnnotation::Double => VarType::Double,
                        TypeAnnotation::String => VarType::String,
                        _ => VarType::Object,
                    };
                    // Track class name for Named type params
                    if let TypeAnnotation::Named(type_name) = &param.type_ann {
                        self.var_class.insert(param.name.clone(), type_name.clone());
                    }
                    let llvm_ty: inkwell::types::BasicTypeEnum = match var_ty {
                        VarType::Int | VarType::Bool => i32_type.into(),
                        VarType::Double => self.context.f64_type().into(),
                        _ => ptr_type.into(),
                    };
                    let ptr = self.builder.build_alloca(llvm_ty, &param.name)
            ?;
                    self.builder.build_store(ptr, function.get_nth_param((i + 1) as u32).unwrap())
            ?;
                    self.set_var(&param.name, ptr, var_ty);
                }

                for stmt in body {
                    self.compile_stmt(stmt)?;
                }

                // If no explicit return, add void return
                if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
                    if ret_type.is_some() {
                        let zero = i32_type.const_int(0, false);
                        self.builder.build_return(Some(&zero))
                ?;
                    } else {
                        self.builder.build_return(None)
                ?;
                    }
                }

                self.pop_scope();
                self.current_function = prev_fn;
                self.current_this = prev_this;
                self.current_class = prev_class;
            }
        }

        Ok(())
    }

    fn get_or_declare_malloc(&self) -> FunctionValue<'ctx> {
        if let Some(f) = self.module.get_function("malloc") {
            return f;
        }
        let ptr_type = self.context.ptr_type(AddressSpace::default());
        let i64_type = self.context.i64_type();
        let malloc_type = ptr_type.fn_type(&[i64_type.into()], false);
        self.module.add_function("malloc", malloc_type, None)
    }

    fn compile_function(&mut self, name: &str, params: &[Param], return_type: Option<&TypeAnnotation>, body: &[Stmt]) -> Result<(), CodegenError> {
        let i32_type = self.context.i32_type();
        let f64_type = self.context.f64_type();
        let ptr_type = self.context.ptr_type(AddressSpace::default());

        let function = if let Some(existing) = self.module.get_function(name) {
            existing
        } else {
            let fn_type = if name == "main" {
                i32_type.fn_type(&[i32_type.into(), ptr_type.into()], false)
            } else {
                let param_types: Vec<BasicMetadataTypeEnum> = params.iter()
                    .map(|p| self.type_ann_to_llvm_meta(&p.type_ann))
                    .collect();
                let ret_type = if let Some(ann) = return_type {
                    self.type_ann_to_var_type(ann)
                } else {
                    self.find_return_type(body)
                };
                match ret_type {
                    VarType::Int | VarType::Bool => i32_type.fn_type(&param_types, false),
                    VarType::Double => f64_type.fn_type(&param_types, false),
                    VarType::String | VarType::Object => ptr_type.fn_type(&param_types, false),
                }
            };
            self.module.add_function(name, fn_type, None)
        };
        let entry = self.context.append_basic_block(function, "entry");
        self.builder.position_at_end(entry);
        self.current_function = Some(function);

        self.push_scope();

        // For main: call ss_initArgs(argc, argv)
        if name == "main" {
            let init_args_fn = self.module.get_function("ss_initArgs").unwrap();
            let argc = function.get_nth_param(0).unwrap();
            let argv = function.get_nth_param(1).unwrap();
            self.builder.build_call(init_args_fn, &[argc.into(), argv.into()], "")
    ?;
        }

        for (i, param) in params.iter().enumerate() {
            let var_ty = self.type_ann_to_var_type(&param.type_ann);
            let llvm_ty: inkwell::types::BasicTypeEnum = match var_ty {
                VarType::Int | VarType::Bool => i32_type.into(),
                VarType::Double => f64_type.into(),
                VarType::String | VarType::Object => ptr_type.into(),
            };
            let ptr = self.builder.build_alloca(llvm_ty, &param.name)
    ?;
            self.builder.build_store(ptr, function.get_nth_param(i as u32).unwrap())
    ?;
            self.set_var(&param.name, ptr, var_ty);
        }

        for stmt in body {
            self.compile_stmt(stmt)?;
        }

        // Add default return if block is not terminated
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            if name == "main" {
                let zero = i32_type.const_int(0, false);
                self.builder.build_return(Some(&zero))?;
            } else {
                // Determine default return value from function type
                let fn_ret = function.get_type().get_return_type();
                if let Some(ret_type) = fn_ret {
                    if ret_type.is_int_type() {
                        self.builder.build_return(Some(&i32_type.const_int(0, false)))
                ?;
                    } else if ret_type.is_float_type() {
                        self.builder.build_return(Some(&f64_type.const_float(0.0)))
                ?;
                    } else {
                        // pointer type — return null
                        let null_ptr = ptr_type.const_null();
                        self.builder.build_return(Some(&null_ptr))
                ?;
                    }
                } else {
                    self.builder.build_return(None)
            ?;
                }
            }
        }

        self.pop_scope();
        self.current_function = None;
        Ok(())
    }

    fn compile_var_decl(&mut self, name: &str, init: &Expr) -> Result<(), CodegenError> {
        // Track class/array for NewExpr/ArrayLit
        if let ExprKind::NewExpr { class_name, .. } = &init.kind {
            self.var_class.insert(name.to_string(), class_name.clone());
        }
        if matches!(&init.kind, ExprKind::ArrayLit(_)) {
            self.var_class.insert(name.to_string(), "__int_array__".to_string());
        }
        if let ExprKind::MethodCall { method, .. } = &init.kind {
            if method == "split" {
                self.var_class.insert(name.to_string(), "__str_array__".to_string());
            }
            if method == "concat" || method == "slice" || method == "reverse" {
                self.var_class.insert(name.to_string(), "__int_array__".to_string());
            }
        }
        let value = self.compile_expr(init)?;
        let var_type = self.value_to_var_type(&value);

        let ptr = match var_type {
            VarType::Int => {
                let ptr = self.builder.build_alloca(self.context.i32_type(), name)?;
                self.builder.build_store(ptr, value)?;
                ptr
            }
            VarType::Double => {
                let ptr = self.builder.build_alloca(self.context.f64_type(), name)?;
                self.builder.build_store(ptr, value)?;
                ptr
            }
            VarType::String | VarType::Bool | VarType::Object => {
                let ptr = self.builder.build_alloca(self.context.ptr_type(AddressSpace::default()), name)?;
                self.builder.build_store(ptr, value)?;
                ptr
            }
        };

        self.set_var(name, ptr, var_type);
        Ok(())
    }

    fn compile_assignment(&mut self, target: &str, op: &AssignOp, value: &Expr) -> Result<(), CodegenError> {
        let (ptr, _var_type) = self.get_var(target)
            .ok_or(CodegenError::UndefinedVar(target.to_string()))?;

        let new_val = match op {
            AssignOp::Assign => self.compile_expr(value)?,
            AssignOp::PlusAssign | AssignOp::MinusAssign | AssignOp::StarAssign
            | AssignOp::SlashAssign | AssignOp::PercentAssign => {
                let current = self.load_var(target)?;
                let rhs = self.compile_expr(value)?;

                // String += uses concat
                if matches!(op, AssignOp::PlusAssign) && current.is_pointer_value() {
                    let rhs_str = self.value_to_string(rhs)?;
                    let concat = self.module.get_function("ss_string_concat").unwrap();
                    self.builder.build_call(concat, &[current.into(), rhs_str.into()], "concat")?
                        .try_as_basic_value().left().unwrap()
                } else {
                    let (l, r) = (current.into_int_value(), rhs.into_int_value());
                    match op {
                        AssignOp::PlusAssign => self.builder.build_int_add(l, r, "add")?.into(),
                        AssignOp::MinusAssign => self.builder.build_int_sub(l, r, "sub")?.into(),
                        AssignOp::StarAssign => self.builder.build_int_mul(l, r, "mul")?.into(),
                        AssignOp::SlashAssign => self.builder.build_int_signed_div(l, r, "div")?.into(),
                        AssignOp::PercentAssign => self.builder.build_int_signed_rem(l, r, "rem")?.into(),
                        _ => unreachable!(),
                    }
                }
            }
        };

        // Truncate if needed (e.g., i64 from array into i32 variable)
        let store_val = match _var_type {
            VarType::Int | VarType::Bool => {
                if new_val.is_int_value() && new_val.into_int_value().get_type().get_bit_width() > 32 {
                    self.builder.build_int_truncate(new_val.into_int_value(), self.context.i32_type(), "trunc")
                        ?.into()
                } else {
                    new_val
                }
            }
            _ => new_val,
        };

        self.builder.build_store(ptr, store_val)
?;
        Ok(())
    }

    fn compile_if(&mut self, condition: &Expr, then_block: &[Stmt], else_block: &Option<Vec<Stmt>>) -> Result<(), CodegenError> {
        let cond_val = self.compile_expr(condition)?;
        let function = self.current_function.unwrap();

        let then_bb = self.context.append_basic_block(function, "then");
        let else_bb = self.context.append_basic_block(function, "else");
        let merge_bb = self.context.append_basic_block(function, "merge");

        self.builder.build_conditional_branch(cond_val.into_int_value(), then_bb, else_bb)
?;

        // Then
        self.builder.position_at_end(then_bb);
        self.push_scope();
        for s in then_block { self.compile_stmt(s)?; }
        self.pop_scope();
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(merge_bb)
    ?;
        }

        // Else
        self.builder.position_at_end(else_bb);
        if let Some(else_stmts) = else_block {
            self.push_scope();
            for s in else_stmts { self.compile_stmt(s)?; }
            self.pop_scope();
        }
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(merge_bb)
    ?;
        }

        self.builder.position_at_end(merge_bb);
        Ok(())
    }

    fn compile_for(&mut self, init: &Stmt, condition: &Expr, update: &Stmt, body: &[Stmt]) -> Result<(), CodegenError> {
        let function = self.current_function.unwrap();

        self.push_scope();
        self.compile_stmt(init)?;

        let cond_bb = self.context.append_basic_block(function, "for.cond");
        let body_bb = self.context.append_basic_block(function, "for.body");
        let update_bb = self.context.append_basic_block(function, "for.update");
        let after_bb = self.context.append_basic_block(function, "for.after");

        self.builder.build_unconditional_branch(cond_bb)
?;

        // Condition
        self.builder.position_at_end(cond_bb);
        let cond_val = self.compile_expr(condition)?;
        self.builder.build_conditional_branch(cond_val.into_int_value(), body_bb, after_bb)
?;

        // Body
        self.builder.position_at_end(body_bb);
        self.loop_stack.push(LoopContext { break_bb: after_bb, continue_bb: update_bb });
        for s in body { self.compile_stmt(s)?; }
        self.loop_stack.pop();
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(update_bb)
    ?;
        }

        // Update
        self.builder.position_at_end(update_bb);
        self.compile_stmt(update)?;
        self.builder.build_unconditional_branch(cond_bb)
?;

        self.builder.position_at_end(after_bb);
        self.pop_scope();
        Ok(())
    }

    fn compile_for_in(&mut self, item_name: &str, iterable: &Expr, body: &[Stmt]) -> Result<(), CodegenError> {
        let function = self.current_function.unwrap();
        let i32_type = self.context.i32_type();

        self.push_scope();

        // Compile iterable (array)
        let arr_val = self.compile_expr(iterable)?;

        // Get length
        let len_fn = self.module.get_function("ss_arrayLen").unwrap();
        let len = self.builder.build_call(len_fn, &[arr_val.into()], "len")
            ?
            .try_as_basic_value().left().unwrap().into_int_value();

        // Index variable
        let idx_ptr = self.builder.build_alloca(i32_type, "__idx")
?;
        self.builder.build_store(idx_ptr, i32_type.const_int(0, false))
?;

        // Item variable: always i64 (array elements are i64 — may be int or string pointer)
        let i64_type = self.context.i64_type();
        let item_ptr = self.builder.build_alloca(i64_type, item_name)?;
        self.set_var(item_name, item_ptr, VarType::Object);

        let cond_bb = self.context.append_basic_block(function, "forin.cond");
        let body_bb = self.context.append_basic_block(function, "forin.body");
        let update_bb = self.context.append_basic_block(function, "forin.update");
        let after_bb = self.context.append_basic_block(function, "forin.after");

        self.builder.build_unconditional_branch(cond_bb)
?;

        // Condition: idx < len
        self.builder.position_at_end(cond_bb);
        let idx = self.builder.build_load(i32_type, idx_ptr, "idx")
            ?.into_int_value();
        let cmp = self.builder.build_int_compare(inkwell::IntPredicate::SLT, idx, len, "cmp")
?;
        self.builder.build_conditional_branch(cmp, body_bb, after_bb)
?;

        // Body: item = arr[idx]
        self.builder.position_at_end(body_bb);
        let get_fn = self.module.get_function("ss_arrayGet").unwrap();
        let elem = self.builder.build_call(get_fn, &[arr_val.into(), idx.into()], "elem")?
            .try_as_basic_value().left().unwrap();
        // Store i64 element directly (no truncation — preserves string pointers)
        self.builder.build_store(item_ptr, elem)?;

        self.loop_stack.push(LoopContext { break_bb: after_bb, continue_bb: update_bb });
        for s in body { self.compile_stmt(s)?; }
        self.loop_stack.pop();

        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(update_bb)
    ?;
        }

        // Update: idx++
        self.builder.position_at_end(update_bb);
        let idx2 = self.builder.build_load(i32_type, idx_ptr, "idx")
            ?.into_int_value();
        let next = self.builder.build_int_add(idx2, i32_type.const_int(1, false), "next")
?;
        self.builder.build_store(idx_ptr, next)
?;
        self.builder.build_unconditional_branch(cond_bb)
?;

        self.builder.position_at_end(after_bb);
        self.pop_scope();
        Ok(())
    }

    fn compile_do_while(&mut self, condition: &Expr, body: &[Stmt]) -> Result<(), CodegenError> {
        let function = self.current_function.unwrap();
        let body_bb = self.context.append_basic_block(function, "do.body");
        let cond_bb = self.context.append_basic_block(function, "do.cond");
        let after_bb = self.context.append_basic_block(function, "do.after");

        self.builder.build_unconditional_branch(body_bb)?;

        self.builder.position_at_end(body_bb);
        self.push_scope();
        self.loop_stack.push(LoopContext { break_bb: after_bb, continue_bb: cond_bb });
        for s in body { self.compile_stmt(s)?; }
        self.loop_stack.pop();
        self.pop_scope();
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(cond_bb)?;
        }

        self.builder.position_at_end(cond_bb);
        let cond_val = self.compile_expr(condition)?;
        let cond_bool = self.to_bool(cond_val)?;
        self.builder.build_conditional_branch(cond_bool, body_bb, after_bb)?;

        self.builder.position_at_end(after_bb);
        Ok(())
    }

    fn compile_while(&mut self, condition: &Expr, body: &[Stmt]) -> Result<(), CodegenError> {
        let function = self.current_function.unwrap();

        let cond_bb = self.context.append_basic_block(function, "while.cond");
        let body_bb = self.context.append_basic_block(function, "while.body");
        let after_bb = self.context.append_basic_block(function, "while.after");

        self.builder.build_unconditional_branch(cond_bb)
?;

        self.builder.position_at_end(cond_bb);
        let cond_val = self.compile_expr(condition)?;
        self.builder.build_conditional_branch(cond_val.into_int_value(), body_bb, after_bb)
?;

        self.builder.position_at_end(body_bb);
        self.push_scope();
        self.loop_stack.push(LoopContext { break_bb: after_bb, continue_bb: cond_bb });
        for s in body { self.compile_stmt(s)?; }
        self.loop_stack.pop();
        self.pop_scope();
        if self.builder.get_insert_block().unwrap().get_terminator().is_none() {
            self.builder.build_unconditional_branch(cond_bb)
    ?;
        }

        self.builder.position_at_end(after_bb);
        Ok(())
    }

    // --- Expression compilation ---


}
