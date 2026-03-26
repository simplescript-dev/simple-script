use inkwell::AddressSpace;
use crate::codegen::Codegen;

impl<'ctx> Codegen<'ctx> {
    pub(crate) fn declare_runtime_functions(&self) {
        let i8_ptr = self.context.ptr_type(AddressSpace::default());
        let i32_type = self.context.i32_type();
        let f64_type = self.context.f64_type();
        let i64_type = self.context.i64_type();
        let void_type = self.context.void_type();

        // I/O
        let println_type = void_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_println", println_type, None);
        self.module.add_function("ym_print", println_type, None);
        let readline_type = i8_ptr.fn_type(&[], false);
        self.module.add_function("ym_readLine", readline_type, None);
        let readfile_type = i8_ptr.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_readFile", readfile_type, None);
        let writefile_type = void_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_writeFile", writefile_type, None);
        self.module.add_function("ym_appendFile", writefile_type, None);

        // Type conversion
        let concat_type = i8_ptr.fn_type(&[i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_string_concat", concat_type, None);
        let i2s_type = i8_ptr.fn_type(&[i32_type.into()], false);
        self.module.add_function("ym_int_to_string", i2s_type, None);
        let d2s_type = i8_ptr.fn_type(&[f64_type.into()], false);
        self.module.add_function("ym_double_to_string", d2s_type, None);
        let i64_to_s_type = i8_ptr.fn_type(&[i64_type.into()], false);
        self.module.add_function("ym_i64_to_string", i64_to_s_type, None);

        // String comparison
        let seq_type = i32_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_string_eq", seq_type, None);
        self.module.add_function("ym_string_ne", seq_type, None);

        // String parsing
        let parse_int_type = i32_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_parseInt", parse_int_type, None);
        let parse_double_type = f64_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_parseDouble", parse_double_type, None);
        let strlen_type = i32_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_stringLength", strlen_type, None);

        // String methods
        let str_str = i8_ptr.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_trim", str_str, None);
        self.module.add_function("ym_toUpperCase", str_str, None);
        self.module.add_function("ym_toLowerCase", str_str, None);
        let bool_str_str = i32_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_startsWith", bool_str_str, None);
        self.module.add_function("ym_endsWith", bool_str_str, None);
        self.module.add_function("ym_contains", bool_str_str, None);
        let str3 = i8_ptr.fn_type(&[i8_ptr.into(), i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_replace", str3, None);
        let str_int = i8_ptr.fn_type(&[i8_ptr.into(), i32_type.into()], false);
        self.module.add_function("ym_charAt", str_int, None);
        self.module.add_function("ym_repeat", str_int, None);
        let substr_type = i8_ptr.fn_type(&[i8_ptr.into(), i32_type.into(), i32_type.into()], false);
        self.module.add_function("ym_substring", substr_type, None);
        self.module.add_function("ym_indexOf", seq_type, None);
        let pad_type = i8_ptr.fn_type(&[i8_ptr.into(), i32_type.into(), i8_ptr.into()], false);
        self.module.add_function("ym_padStart", pad_type, None);
        self.module.add_function("ym_padEnd", pad_type, None);
        let split_type = i8_ptr.fn_type(&[i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_split", split_type, None);
        let join_type = i8_ptr.fn_type(&[i8_ptr.into(), i8_ptr.into()], false);
        self.module.add_function("ym_join", join_type, None);

        // Array
        self.module.add_function("ym_newArray", i8_ptr.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_arrayGet", i64_type.fn_type(&[i8_ptr.into(), i32_type.into()], false), None);
        self.module.add_function("ym_arraySet", void_type.fn_type(&[i8_ptr.into(), i32_type.into(), i64_type.into()], false), None);
        self.module.add_function("ym_arrayLen", i32_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_arrayPush", i8_ptr.fn_type(&[i8_ptr.into(), i64_type.into()], false), None);
        let void_ptr = void_type.fn_type(&[i8_ptr.into()], false);
        self.module.add_function("ym_arrayReverse", void_ptr, None);
        self.module.add_function("ym_arraySort", void_ptr, None);
        self.module.add_function("ym_arrayIndexOf", i32_type.fn_type(&[i8_ptr.into(), i64_type.into()], false), None);
        self.module.add_function("ym_arraySlice", i8_ptr.fn_type(&[i8_ptr.into(), i32_type.into(), i32_type.into()], false), None);
        self.module.add_function("ym_arrayConcat", i8_ptr.fn_type(&[i8_ptr.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_arrayToString", i8_ptr.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_arrayFirst", i64_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_arrayLast", i64_type.fn_type(&[i8_ptr.into()], false), None);

        // CLI args
        self.module.add_function("ym_initArgs", void_type.fn_type(&[i32_type.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_argCount", i32_type.fn_type(&[], false), None);
        self.module.add_function("ym_argGet", i8_ptr.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_timeMs", i64_type.fn_type(&[], false), None);
        self.module.add_function("ym_exit", void_type.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_system", i32_type.fn_type(&[i8_ptr.into()], false), None);

        // TCP
        self.module.add_function("ym_tcpListen", i32_type.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_tcpAccept", i32_type.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_tcpRead", i8_ptr.fn_type(&[i32_type.into(), i32_type.into()], false), None);
        self.module.add_function("ym_tcpWrite", i32_type.fn_type(&[i32_type.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_tcpWriteBytes", i32_type.fn_type(&[i32_type.into(), i8_ptr.into(), i32_type.into()], false), None);
        self.module.add_function("ym_tcpClose", void_type.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_strcmp", i32_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_base64Encode", i8_ptr.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_base64Decode", i8_ptr.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_charCodeAt", i32_type.fn_type(&[i8_ptr.into(), i32_type.into()], false), None);
        self.module.add_function("ym_fromCharCode", i8_ptr.fn_type(&[i32_type.into()], false), None);
        self.module.add_function("ym_getenv", i8_ptr.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_timeUnix", i64_type.fn_type(&[], false), None);

        // File system
        self.module.add_function("ym_mkdir", i32_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_mkdirp", i32_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_fileExists", i32_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_fileSize", i64_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_removeFile", i32_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_renameFile", i32_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_listDir", i8_ptr.fn_type(&[i8_ptr.into()], false), None);

        // Crypto
        self.module.add_function("ym_sha256", i8_ptr.fn_type(&[i8_ptr.into()], false), None);

        // Math
        let f1 = f64_type.fn_type(&[f64_type.into()], false);
        for name in ["ym_sqrt", "ym_abs", "ym_floor", "ym_ceil", "ym_round", "ym_log", "ym_sin", "ym_cos"] {
            self.module.add_function(name, f1, None);
        }
        let f2 = f64_type.fn_type(&[f64_type.into(), f64_type.into()], false);
        for name in ["ym_pow", "ym_min", "ym_max"] {
            self.module.add_function(name, f2, None);
        }
        self.module.add_function("ym_random", f64_type.fn_type(&[], false), None);

        // HashMap
        self.module.add_function("ym_mapNew", i8_ptr.fn_type(&[], false), None);
        self.module.add_function("ym_mapSet", void_type.fn_type(&[i8_ptr.into(), i8_ptr.into(), i64_type.into()], false), None);
        self.module.add_function("ym_mapGet", i64_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_mapHas", i32_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false), None);
        self.module.add_function("ym_mapSize", i32_type.fn_type(&[i8_ptr.into()], false), None);
        self.module.add_function("ym_mapKeys", str_str, None);
        self.module.add_function("ym_mapDelete", void_type.fn_type(&[i8_ptr.into(), i8_ptr.into()], false), None);
    }
}
