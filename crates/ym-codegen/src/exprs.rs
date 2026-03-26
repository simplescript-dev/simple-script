use inkwell::values::{BasicValueEnum, BasicMetadataValueEnum, PointerValue};
use inkwell::AddressSpace;
use ym_parser::*;
use crate::codegen::{Codegen, CodegenError, VarType};

impl<'ctx> Codegen<'ctx> {
    pub(crate) fn compile_expr(&mut self, expr: &Expr) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        match &expr.kind {
            ExprKind::IntLit(n) => {
                Ok(self.context.i32_type().const_int(*n as u64, true).into())
            }
            ExprKind::DoubleLit(n) => {
                Ok(self.context.f64_type().const_float(*n).into())
            }
            ExprKind::StringLit(s) => {
                Ok(self.build_global_string(s).into())
            }
            ExprKind::BoolLit(b) => {
                Ok(self.context.i32_type().const_int(*b as u64, false).into())
            }
            ExprKind::TemplateLit(fragments) => {
                self.compile_template(fragments)
            }
            ExprKind::Ident(name) => {
                self.load_var(name)
            }
            ExprKind::Binary { left, op, right } => {
                self.compile_binary(left, op, right)
            }
            ExprKind::Unary { op, operand } => {
                let val = self.compile_expr(operand)?;
                match op {
                    UnaryOp::Neg => {
                        if val.is_float_value() {
                            Ok(self.builder.build_float_neg(val.into_float_value(), "fneg")
                                ?
                                .into())
                        } else {
                            Ok(self.builder.build_int_neg(val.into_int_value(), "neg")
                                ?
                                .into())
                        }
                    }
                    UnaryOp::Not => {
                        let zero = self.context.i32_type().const_int(0, false);
                        Ok(self.builder.build_int_compare(
                            inkwell::IntPredicate::EQ, val.into_int_value(), zero, "not"
                        )?.into())
                    }
                }
            }
            ExprKind::Call { callee, args } => {
                self.compile_call(callee, args)
            }
            ExprKind::Ternary { condition, then_expr, else_expr } => {
                let function = self.current_function.unwrap();
                let cond = self.compile_expr(condition)?;
                let cond_bool = self.to_bool(cond)?;

                let then_bb = self.context.append_basic_block(function, "tern.then");
                let else_bb = self.context.append_basic_block(function, "tern.else");
                let merge_bb = self.context.append_basic_block(function, "tern.merge");

                self.builder.build_conditional_branch(cond_bool, then_bb, else_bb)?;

                self.builder.position_at_end(then_bb);
                let then_val = self.compile_expr(then_expr)?;
                let then_end = self.builder.get_insert_block().unwrap();
                self.builder.build_unconditional_branch(merge_bb)?;

                self.builder.position_at_end(else_bb);
                let else_val = self.compile_expr(else_expr)?;
                let else_end = self.builder.get_insert_block().unwrap();
                self.builder.build_unconditional_branch(merge_bb)?;

                self.builder.position_at_end(merge_bb);

                // Both branches must return same LLVM type
                if then_val.get_type() == else_val.get_type() {
                    let phi = self.builder.build_phi(then_val.get_type(), "tern")?;
                    phi.add_incoming(&[(&then_val, then_end), (&else_val, else_end)]);
                    Ok(phi.as_basic_value())
                } else {
                    Ok(then_val) // fallback
                }
            }
            ExprKind::Grouping(inner) => {
                self.compile_expr(inner)
            }
            ExprKind::NewExpr { class_name, args } => {
                let ctor_name = format!("{class_name}_new");
                let ctor_fn = self.module.get_function(&ctor_name)
                    .ok_or(CodegenError::UndefinedFunc(class_name.clone()))?;
                let compiled_args: Vec<BasicMetadataValueEnum> = args.iter()
                    .map(|a| self.compile_expr(a).map(|v| v.into()))
                    .collect::<Result<_, _>>()?;
                let result = self.builder.build_call(ctor_fn, &compiled_args, "new")?
                    .try_as_basic_value().left().unwrap();
                Ok(result)
            }
            ExprKind::MemberAccess { object, member } => {
                let class_name = self.resolve_class_name(object);
                let obj_ptr = self.compile_expr(object)?;
                self.compile_member_access(obj_ptr.into_pointer_value(), member, &class_name)
            }
            ExprKind::MethodCall { object, method, args } => {
                let class_name = self.resolve_class_name(object);
                let obj_val = self.compile_expr(object)?;

                // Try array methods
                // Array methods
                if class_name == "__int_array__" || class_name == "__str_array__" {
                    if method == "length" {
                        let func = self.module.get_function("ym_arrayLen").unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into()], "len")
                            ?
                            .try_as_basic_value().left().unwrap();
                        return Ok(result);
                    }
                    if method == "push" {
                        let arg_val = self.compile_expr(&args[0])?;
                        let arg64 = self.to_i64(arg_val)?;
                        let func = self.module.get_function("ym_arrayPush").unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into(), arg64.into()], "push")?
                            .try_as_basic_value().left().unwrap();
                        return Ok(result);
                    }
                    if method == "join" {
                        let delim = self.compile_expr(&args[0])?;
                        let func = self.module.get_function("ym_join").unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into(), delim.into()], "join")?
                            .try_as_basic_value().left().unwrap();
                        return Ok(result);
                    }
                    if method == "reverse" {
                        let func = self.module.get_function("ym_arrayReverse").unwrap();
                        self.builder.build_call(func, &[obj_val.into()], "")?;
                        return Ok(obj_val);
                    }
                    if method == "sort" {
                        let func = self.module.get_function("ym_arraySort").unwrap();
                        self.builder.build_call(func, &[obj_val.into()], "")?;
                        return Ok(obj_val);
                    }
                    if method == "concat" {
                        let other = self.compile_expr(&args[0])?;
                        let func = self.module.get_function("ym_arrayConcat").unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into(), other.into()], "cat")?
                            .try_as_basic_value().left().unwrap();
                        return Ok(result);
                    }
                    if method == "indexOf" {
                        let search_val = self.compile_expr(&args[0])?;
                        let search64 = self.to_i64(search_val)?;
                        let func = self.module.get_function("ym_arrayIndexOf").unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into(), search64.into()], "idx")?
                            .try_as_basic_value().left().unwrap();
                        return Ok(result);
                    }
                    if method == "includes" {
                        let search_val = self.compile_expr(&args[0])?;
                        let search64 = self.to_i64(search_val)?;
                        let func = self.module.get_function("ym_arrayIndexOf").unwrap();
                        let idx = self.builder.build_call(func, &[obj_val.into(), search64.into()], "idx")?
                            .try_as_basic_value().left().unwrap();
                        let zero = self.context.i32_type().const_int(0, false);
                        let cmp = self.builder.build_int_compare(inkwell::IntPredicate::SGE, idx.into_int_value(), zero, "inc")?;
                        let result = self.builder.build_int_z_extend(cmp, self.context.i32_type(), "zext")?;
                        return Ok(result.into());
                    }
                    if method == "first" || method == "last" {
                        let fn_name = if method == "first" { "ym_arrayFirst" } else { "ym_arrayLast" };
                        let func = self.module.get_function(fn_name).unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into()], method)?
                            .try_as_basic_value().left().unwrap();
                        // Truncate i64 to i32 for int arrays
                        let is_str = if let ExprKind::Ident(n) = &object.kind {
                            self.var_class.get(n).map(|c| c == "__str_array__").unwrap_or(false)
                        } else { false };
                        if is_str {
                            return Ok(self.builder.build_int_to_ptr(result.into_int_value(), self.context.ptr_type(inkwell::AddressSpace::default()), "itop")?.into());
                        } else {
                            return Ok(self.builder.build_int_truncate(result.into_int_value(), self.context.i32_type(), "trunc")?.into());
                        }
                    }
                    if method == "slice" {
                        let start = self.compile_expr(&args[0])?;
                        let end = self.compile_expr(&args[1])?;
                        let s32 = self.to_i32(start)?;
                        let e32 = self.to_i32(end)?;
                        let func = self.module.get_function("ym_arraySlice").unwrap();
                        let result = self.builder.build_call(func, &[obj_val.into(), s32.into(), e32.into()], "slice")?
                            .try_as_basic_value().left().unwrap();
                        return Ok(result);
                    }
                }

                // map.getString(key) — returns string from map
                if method == "getString" {
                    let key_val = self.compile_expr(&args[0])?;
                    let func = self.module.get_function("ym_mapGet").unwrap();
                    let i64_val = self.builder.build_call(func, &[obj_val.into(), key_val.into()], "get")
                        ?
                        .try_as_basic_value().left().unwrap();
                    let ptr = self.builder.build_int_to_ptr(
                        i64_val.into_int_value(),
                        self.context.ptr_type(AddressSpace::default()),
                        "itop"
                    )?;
                    return Ok(ptr.into());
                }

                // Try string/map builtin methods
                if class_name.is_empty() || !self.classes.contains_key(&class_name) {
                    if let Some(result) = self.try_string_method(obj_val, method, args)? {
                        return Ok(result);
                    }
                }

                self.compile_method_call(obj_val.into_pointer_value(), method, args, &class_name)
            }
            ExprKind::This => {
                Ok(self.current_this.unwrap().into())
            }
            ExprKind::PostfixIncrement(name) => {
                let (ptr, _) = self.get_var(name)
                    .ok_or(CodegenError::UndefinedVar(name.clone()))?;
                let val = self.builder.build_load(self.context.i32_type(), ptr, name)?;
                let one = self.context.i32_type().const_int(1, false);
                let new_val = self.builder.build_int_add(val.into_int_value(), one, "inc")?;
                self.builder.build_store(ptr, new_val)?;
                Ok(val) // return old value (postfix)
            }
            ExprKind::PostfixDecrement(name) => {
                let (ptr, _) = self.get_var(name)
                    .ok_or(CodegenError::UndefinedVar(name.clone()))?;
                let val = self.builder.build_load(self.context.i32_type(), ptr, name)?;
                let one = self.context.i32_type().const_int(1, false);
                let new_val = self.builder.build_int_sub(val.into_int_value(), one, "dec")?;
                self.builder.build_store(ptr, new_val)?;
                Ok(val)
            }
            ExprKind::ArrayLit(elements) => {
                let i32_type = self.context.i32_type();
                let size = i32_type.const_int(elements.len() as u64, false);
                let new_array_fn = self.module.get_function("ym_newArray").unwrap();
                let arr_ptr = self.builder.build_call(new_array_fn, &[size.into()], "arr")?
                    .try_as_basic_value().left().unwrap();

                let array_set_fn = self.module.get_function("ym_arraySet").unwrap();
                for (i, elem) in elements.iter().enumerate() {
                    let val = self.compile_expr(elem)?;
                    let idx = i32_type.const_int(i as u64, false);
                    let val64 = self.to_i64(val)?;
                    self.builder.build_call(array_set_fn, &[arr_ptr.into(), idx.into(), val64.into()], "")
            ?;
                }
                Ok(arr_ptr)
            }
            ExprKind::IndexAccess { object, index } => {
                // Determine if string array or int array
                let is_str = if let ExprKind::Ident(name) = &object.kind {
                    self.var_class.get(name).map(|c| c == "__str_array__").unwrap_or(false)
                } else { false };

                let arr_ptr = self.compile_expr(object)?;
                let idx = self.compile_expr(index)?;
                let idx32 = self.to_i32(idx)?;
                let array_get_fn = self.module.get_function("ym_arrayGet").unwrap();
                let val64 = self.builder.build_call(array_get_fn, &[arr_ptr.into(), idx32.into()], "elem")?
                    .try_as_basic_value().left().unwrap();

                if is_str {
                    // String array: convert i64 to ptr
                    Ok(self.builder.build_int_to_ptr(
                        val64.into_int_value(),
                        self.context.ptr_type(AddressSpace::default()),
                        "itop"
                    )?.into())
                } else {
                    // Int array: truncate i64 to i32
                    Ok(self.builder.build_int_truncate(
                        val64.into_int_value(),
                        self.context.i32_type(),
                        "trunc"
                    )?.into())
                }
            }
        }
    }

    fn resolve_class_name(&self, expr: &Expr) -> String {
        match &expr.kind {
            ExprKind::This => self.current_class.clone().unwrap_or_default(),
            ExprKind::Ident(name) => self.var_class.get(name).cloned().unwrap_or_default(),
            _ => String::new(), // unknown — will try builtin methods first
        }
    }

    fn try_string_method(&mut self, obj_val: BasicValueEnum<'ctx>, method: &str, args: &[Expr]) -> Result<Option<BasicValueEnum<'ctx>>, CodegenError> {
        // toString() on int/double values
        if method == "toString" && obj_val.is_int_value() {
            let func = self.module.get_function("ym_int_to_string").unwrap();
            let result = self.builder.build_call(func, &[obj_val.into()], "itos")
                ?
                .try_as_basic_value().left().unwrap();
            return Ok(Some(result));
        }
        if method == "toString" && obj_val.is_float_value() {
            let func = self.module.get_function("ym_double_to_string").unwrap();
            let result = self.builder.build_call(func, &[obj_val.into()], "dtos")
                ?
                .try_as_basic_value().left().unwrap();
            return Ok(Some(result));
        }

        let runtime_fn = match method {
            "length" => "ym_stringLength",
            "indexOf" => "ym_indexOf",
            "substring" => "ym_substring",
            "toInt" => "ym_parseInt",
            "toDouble" => "ym_parseDouble",
            "toString" => "ym_int_to_string",
            "startsWith" => "ym_startsWith",
            "endsWith" => "ym_endsWith",
            "contains" => "ym_contains",
            "trim" => "ym_trim",
            "replace" => "ym_replace",
            "toUpperCase" => "ym_toUpperCase",
            "toLowerCase" => "ym_toLowerCase",
            "charAt" => "ym_charAt",
            "repeat" => "ym_repeat",
            "padStart" => "ym_padStart",
            "padEnd" => "ym_padEnd",
            "split" => "ym_split",
            // Map methods
            "set" => "ym_mapSet",
            "get" => "ym_mapGet",
            "has" => "ym_mapHas",
            "size" => "ym_mapSize",
            "keys" => "ym_mapKeys",
            "delete" => "ym_mapDelete",
            // Array methods
            "push" => "ym_arrayPush",
            _ => return Ok(None),
        };

        let func = self.module.get_function(runtime_fn)
            .ok_or(CodegenError::General(format!("missing runtime function: {runtime_fn}")))?;

        let mut call_args: Vec<BasicMetadataValueEnum> = vec![obj_val.into()];
        for (i, arg) in args.iter().enumerate() {
            let v = self.compile_expr(arg)?;
            // mapSet/arrayPush: value arg needs i64 conversion
            if (runtime_fn == "ym_mapSet" && i == 1) || (runtime_fn == "ym_arrayPush" && i == 0) {
                call_args.push(self.to_i64(v)?.into());
            } else {
                call_args.push(v.into());
            }
        }

        let result = self.builder.build_call(func, &call_args, "method")
?;

        let val = result.try_as_basic_value()
            .left()
            .unwrap_or(self.context.i32_type().const_int(0, false).into());

        Ok(Some(val))
    }

    fn compile_member_access(&mut self, obj_ptr: PointerValue<'ctx>, member: &str, class_name: &str) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        let class_info = self.classes.get(class_name)
            .ok_or(CodegenError::General(format!("unknown class for member access .{member}")))?
            .clone();

        let field_index = class_info.fields.iter()
            .position(|(name, _)| name == member)
            .ok_or(CodegenError::General(format!("unknown field .{member} on {class_name}")))?;

        let field_ptr = self.builder.build_struct_gep(
            class_info.struct_type, obj_ptr, field_index as u32, "field_ptr"
        )?;

        let field_type: inkwell::types::BasicTypeEnum = match class_info.fields[field_index].1 {
            VarType::Int | VarType::Bool => self.context.i32_type().into(),
            VarType::Double => self.context.f64_type().into(),
            VarType::String | VarType::Object => self.context.ptr_type(AddressSpace::default()).into(),
        };

        Ok(self.builder.build_load(field_type, field_ptr, member)?)
    }

    fn compile_method_call(&mut self, obj_ptr: PointerValue<'ctx>, method: &str, args: &[Expr], class_name: &str) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        // Try class method, then parent method
        let fn_name = format!("{class_name}_{method}");
        let function = if let Some(f) = self.module.get_function(&fn_name) {
            f
        } else if let Some(parent) = self.classes.get(class_name).and_then(|c| c.parent.clone()) {
            let parent_fn = format!("{parent}_{method}");
            self.module.get_function(&parent_fn)
                .ok_or(CodegenError::UndefinedFunc(fn_name))?
        } else {
            return Err(CodegenError::UndefinedFunc(fn_name));
        };

        let mut compiled_args: Vec<BasicMetadataValueEnum> = vec![obj_ptr.into()]; // this
        for arg in args {
            compiled_args.push(self.compile_expr(arg)?.into());
        }

        let result = self.builder.build_call(function, &compiled_args, "mcall")
?;

        result.try_as_basic_value()
            .left()
            .ok_or(())
            .or_else(|_| Ok(self.context.i32_type().const_int(0, false).into()))
    }

    fn compile_short_circuit(&mut self, left: &Expr, op: &BinOp, right: &Expr) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        let function = self.current_function.unwrap();
        let i32_type = self.context.i32_type();

        let lhs = self.compile_expr(left)?;
        let lhs_bool = self.to_bool(lhs)?;

        let rhs_bb = self.context.append_basic_block(function, "sc.rhs");
        let merge_bb = self.context.append_basic_block(function, "sc.merge");

        let entry_bb = self.builder.get_insert_block().unwrap();

        if matches!(op, BinOp::And) {
            // &&: if left is false, skip right (result = 0)
            self.builder.build_conditional_branch(lhs_bool, rhs_bb, merge_bb)?;
        } else {
            // ||: if left is true, skip right (result = 1)
            self.builder.build_conditional_branch(lhs_bool, merge_bb, rhs_bb)?;
        }

        // Evaluate right side
        self.builder.position_at_end(rhs_bb);
        let rhs = self.compile_expr(right)?;
        let rhs_bool = self.to_bool(rhs)?;
        let rhs_as_i32 = self.builder.build_int_z_extend(rhs_bool, i32_type, "zext")?;
        let rhs_end_bb = self.builder.get_insert_block().unwrap();
        self.builder.build_unconditional_branch(merge_bb)?;

        // Merge
        self.builder.position_at_end(merge_bb);
        let phi = self.builder.build_phi(i32_type, "sc.result")?;

        let short_val = if matches!(op, BinOp::And) {
            i32_type.const_int(0, false) // && short-circuits to false
        } else {
            i32_type.const_int(1, false) // || short-circuits to true
        };

        phi.add_incoming(&[(&short_val, entry_bb), (&rhs_as_i32, rhs_end_bb)]);
        Ok(phi.as_basic_value())
    }

    fn compile_binary(&mut self, left: &Expr, op: &BinOp, right: &Expr) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        // Short-circuit evaluation for && and ||
        if matches!(op, BinOp::And | BinOp::Or) {
            return self.compile_short_circuit(left, op, right);
        }

        let lhs = self.compile_expr(left)?;
        let rhs = self.compile_expr(right)?;

        // String operations
        if lhs.is_pointer_value() && rhs.is_pointer_value() {
            let fn_name = match op {
                BinOp::Add => "ym_string_concat",
                BinOp::Eq => "ym_string_eq",
                BinOp::Ne => "ym_string_ne",
                _ => return Err(CodegenError::General(format!("unsupported string op: {:?}", op))),
            };
            let func = self.module.get_function(fn_name).unwrap();
            let result = self.builder.build_call(
                func,
                &[lhs.into(), rhs.into()],
                "str_op",
            )?
                .try_as_basic_value()
                .left()
                .unwrap();
            return Ok(result);
        }

        // Auto-convert: string + int/double → string concat
        if matches!(op, BinOp::Add) && (lhs.is_pointer_value() || rhs.is_pointer_value()) {
            let l_str = self.value_to_string(lhs)?;
            let r_str = self.value_to_string(rhs)?;
            let concat_fn = self.module.get_function("ym_string_concat").unwrap();
            let result = self.builder.build_call(concat_fn, &[l_str.into(), r_str.into()], "concat")
                ?
                .try_as_basic_value().left().unwrap();
            return Ok(result);
        }

        // Mixed int/double — promote int to double
        let (lhs, rhs) = if lhs.is_float_value() && rhs.is_int_value() {
            let promoted = self.builder.build_signed_int_to_float(rhs.into_int_value(), self.context.f64_type(), "itof")?;
            (lhs, promoted.into())
        } else if lhs.is_int_value() && rhs.is_float_value() {
            let promoted = self.builder.build_signed_int_to_float(lhs.into_int_value(), self.context.f64_type(), "itof")?;
            (promoted.into(), rhs)
        } else {
            (lhs, rhs)
        };

        // Double operations
        if lhs.is_float_value() && rhs.is_float_value() {
            let l = lhs.into_float_value();
            let r = rhs.into_float_value();
            let result = match op {
                BinOp::Add => self.builder.build_float_add(l, r, "fadd")?.into(),
                BinOp::Sub => self.builder.build_float_sub(l, r, "fsub")?.into(),
                BinOp::Mul => self.builder.build_float_mul(l, r, "fmul")?.into(),
                BinOp::Div => self.builder.build_float_div(l, r, "fdiv")?.into(),
                BinOp::Mod => self.builder.build_float_rem(l, r, "frem")?.into(),
                BinOp::Pow => {
                    let pow_fn = self.module.get_function("ym_pow").unwrap();
                    self.builder.build_call(pow_fn, &[l.into(), r.into()], "pow")?
                        .try_as_basic_value().left().unwrap()
                }
                BinOp::Eq => self.builder.build_float_compare(inkwell::FloatPredicate::OEQ, l, r, "feq")?.into(),
                BinOp::Ne => self.builder.build_float_compare(inkwell::FloatPredicate::ONE, l, r, "fne")?.into(),
                BinOp::Lt => self.builder.build_float_compare(inkwell::FloatPredicate::OLT, l, r, "flt")?.into(),
                BinOp::Gt => self.builder.build_float_compare(inkwell::FloatPredicate::OGT, l, r, "fgt")?.into(),
                BinOp::Le => self.builder.build_float_compare(inkwell::FloatPredicate::OLE, l, r, "fle")?.into(),
                BinOp::Ge => self.builder.build_float_compare(inkwell::FloatPredicate::OGE, l, r, "fge")?.into(),
                BinOp::And | BinOp::Or => {
                    return Err(CodegenError::General("logical ops not supported on double".into()));
                }
            };
            return Ok(result);
        }

        // Int operations — normalize to same bit width
        let mut l = lhs.into_int_value();
        let mut r = rhs.into_int_value();
        let lw = l.get_type().get_bit_width();
        let rw = r.get_type().get_bit_width();
        if lw > rw {
            r = self.builder.build_int_s_extend(r, l.get_type(), "sext")
    ?;
        } else if rw > lw {
            l = self.builder.build_int_s_extend(l, r.get_type(), "sext")
    ?;
        }

        let result = match op {
            BinOp::Add => self.builder.build_int_add(l, r, "add")
                ?.into(),
            BinOp::Sub => self.builder.build_int_sub(l, r, "sub")
                ?.into(),
            BinOp::Mul => self.builder.build_int_mul(l, r, "mul")
                ?.into(),
            BinOp::Div => self.builder.build_int_signed_div(l, r, "div")
                ?.into(),
            BinOp::Mod => self.builder.build_int_signed_rem(l, r, "rem")
                ?.into(),
            BinOp::Pow => {
                let f64_type = self.context.f64_type();
                let lf = self.builder.build_signed_int_to_float(l, f64_type, "itof")?;
                let rf = self.builder.build_signed_int_to_float(r, f64_type, "itof")?;
                let pow_fn = self.module.get_function("ym_pow").unwrap();
                let result = self.builder.build_call(pow_fn, &[lf.into(), rf.into()], "pow")?
                    .try_as_basic_value().left().unwrap();
                self.builder.build_float_to_signed_int(result.into_float_value(), l.get_type(), "ftoi")?.into()
            }
            BinOp::Eq => self.builder.build_int_compare(inkwell::IntPredicate::EQ, l, r, "eq")
                ?.into(),
            BinOp::Ne => self.builder.build_int_compare(inkwell::IntPredicate::NE, l, r, "ne")
                ?.into(),
            BinOp::Lt => self.builder.build_int_compare(inkwell::IntPredicate::SLT, l, r, "lt")
                ?.into(),
            BinOp::Gt => self.builder.build_int_compare(inkwell::IntPredicate::SGT, l, r, "gt")
                ?.into(),
            BinOp::Le => self.builder.build_int_compare(inkwell::IntPredicate::SLE, l, r, "le")
                ?.into(),
            BinOp::Ge => self.builder.build_int_compare(inkwell::IntPredicate::SGE, l, r, "ge")
                ?.into(),
            BinOp::And | BinOp::Or => self.context.i32_type().const_int(0, false).into(), // unreachable
        };

        Ok(result)
    }

    fn compile_call(&mut self, callee: &str, args: &[Expr]) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        // Map builtin names to runtime function names
        let runtime_name = match callee {
            "println" => "ym_println",
            "print" => "ym_print",
            "readLine" => "ym_readLine",
            "readFile" => "ym_readFile",
            "writeFile" => "ym_writeFile",
            "appendFile" => "ym_appendFile",
            "args" => "ym_argCount",
            "arg" => "ym_argGet",
            "exit" => "ym_exit",
            "parseInt" => "ym_parseInt",
            "parseDouble" => "ym_parseDouble",
            "system" => "ym_system",
            "tcpListen" => "ym_tcpListen",
            "tcpAccept" => "ym_tcpAccept",
            "tcpRead" => "ym_tcpRead",
            "tcpWrite" => "ym_tcpWrite",
            "tcpWriteBytes" => "ym_tcpWriteBytes",
            "tcpClose" => "ym_tcpClose",
            "charCodeAt" => "ym_charCodeAt",
            "base64Encode" => "ym_base64Encode",
            "base64Decode" => "ym_base64Decode",
            "fromCharCode" => "ym_fromCharCode",
            "getenv" => "ym_getenv",
            "timeUnix" => "ym_timeUnix",
            "mkdir" => "ym_mkdir",
            "mkdirp" => "ym_mkdirp",
            "fileExists" => "ym_fileExists",
            "fileSize" => "ym_fileSize",
            "removeFile" => "ym_removeFile",
            "renameFile" => "ym_renameFile",
            "listDir" => "ym_listDir",
            "sha256" => "ym_sha256",
            "sqrt" => "ym_sqrt",
            "abs" => "ym_abs",
            "floor" => "ym_floor",
            "ceil" => "ym_ceil",
            "round" => "ym_round",
            "pow" => "ym_pow",
            "log" => "ym_log",
            "sin" => "ym_sin",
            "cos" => "ym_cos",
            "random" => "ym_random",
            "min" => "ym_min",
            "max" => "ym_max",
            "Map" => "ym_mapNew",
            other => other,
        };

        let function = self.module.get_function(runtime_name)
            .ok_or(CodegenError::UndefinedFunc(callee.to_string()))?;

        let is_print = runtime_name == "ym_println" || runtime_name == "ym_print";
        if is_print && args.len() >= 1 {
            let space = self.build_global_string(" ");
            let first_str = self.compile_print_arg(&args[0])?;
            let mut result = first_str;
            for arg in &args[1..] {
                let arg_str = self.compile_print_arg(arg)?;
                let concat_fn = self.module.get_function("ym_string_concat").unwrap();
                result = self.builder.build_call(concat_fn, &[result.into(), space.into()], "sp")?
                    .try_as_basic_value().left().unwrap();
                result = self.builder.build_call(concat_fn, &[result.into(), arg_str.into()], "cat")?
                    .try_as_basic_value().left().unwrap();
            }
            let print_fn = self.module.get_function(runtime_name).unwrap();
            self.builder.build_call(print_fn, &[result.into()], "call")?;
            return Ok(self.context.i32_type().const_int(0, false).into());
        }

        // Auto-convert args
        let is_math = runtime_name.starts_with("ym_sqrt") || runtime_name.starts_with("ym_abs")
            || runtime_name.starts_with("ym_floor") || runtime_name.starts_with("ym_ceil")
            || runtime_name.starts_with("ym_round") || runtime_name.starts_with("ym_pow")
            || runtime_name.starts_with("ym_log") || runtime_name.starts_with("ym_sin")
            || runtime_name.starts_with("ym_cos") || runtime_name.starts_with("ym_min")
            || runtime_name.starts_with("ym_max");
        let compiled_args: Vec<BasicMetadataValueEnum> = args.iter()
            .map(|a| {
                let v = self.compile_expr(a)?;
                if is_print && !v.is_pointer_value() {
                    Ok(self.value_to_string(v)?.into())
                } else if is_math && v.is_int_value() {
                    Ok(self.builder.build_signed_int_to_float(v.into_int_value(), self.context.f64_type(), "itof")?.into())
                } else {
                    Ok(v.into())
                }
            })
            .collect::<Result<_, CodegenError>>()?;

        // Fill in default arguments if fewer args than params
        let mut compiled_args = compiled_args;
        if let Some(defaults) = self.func_defaults.get(callee).cloned() {
            let provided = compiled_args.len();
            for i in provided..defaults.len() {
                if let Some(default_expr) = &defaults[i] {
                    let v = self.compile_expr(default_expr)?;
                    if is_math && v.is_int_value() {
                        compiled_args.push(self.builder.build_signed_int_to_float(v.into_int_value(), self.context.f64_type(), "itof")?.into());
                    } else {
                        compiled_args.push(v.into());
                    }
                }
            }
        }

        let result = self.builder.build_call(function, &compiled_args, "call")
?;

        // If function returns void, return a dummy 0
        result.try_as_basic_value()
            .left()
            .ok_or(())
            .or_else(|_| Ok(self.context.i32_type().const_int(0, false).into()))
    }

    fn compile_template(&mut self, fragments: &[TemplateExprFragment]) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        if fragments.is_empty() {
            return Ok(self.build_global_string("").into());
        }

        let mut result = self.compile_template_fragment(&fragments[0])?;

        for frag in &fragments[1..] {
            let next = self.compile_template_fragment(frag)?;
            let concat_fn = self.module.get_function("ym_string_concat").unwrap();
            result = self.builder.build_call(
                concat_fn,
                &[result.into(), next.into()],
                "concat",
            )?
                .try_as_basic_value()
                .left()
                .unwrap();
        }

        Ok(result)
    }

    fn compile_template_fragment(&mut self, frag: &TemplateExprFragment) -> Result<BasicValueEnum<'ctx>, CodegenError> {
        match frag {
            TemplateExprFragment::Literal(s) => {
                Ok(self.build_global_string(s).into())
            }
            TemplateExprFragment::Expr(expr) => {
                let val = self.compile_expr(expr)?;
                // Convert to string if needed
                self.value_to_string(val)
            }
        }
    }
}
