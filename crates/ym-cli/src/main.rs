use clap::{Parser, Subcommand};
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Parser)]
#[command(name = "ss", about = "SimpleScript compiler", version = "2.0.0")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start interactive REPL
    Repl,
    /// Create a new SimpleScript project
    New {
        /// Project name
        name: String,
    },
    /// Run all .ss files in a directory as tests
    Test {
        /// Test directory (default: tests/)
        #[arg(default_value = "tests")]
        dir: PathBuf,
    },
    /// Type-check a .ss file without compiling
    Check {
        /// Source file path
        file: PathBuf,
    },
    /// Format a .ss file
    Fmt {
        /// Source file path
        file: PathBuf,
    },
    /// Clean cached build artifacts
    Clean,
    /// Build a .ss file into a native binary
    Build {
        /// Source file (default: src/main.ss or main.ss)
        file: Option<PathBuf>,
        /// Output binary name
        #[arg(short, long)]
        output: Option<PathBuf>,
        /// Release mode (optimized)
        #[arg(long)]
        release: bool,
        /// Print LLVM IR instead of compiling
        #[arg(long)]
        emit_ir: bool,
    },
    /// Build and run a .ss file
    Run {
        /// Source file (default: src/main.ss or main.ss)
        file: Option<PathBuf>,
        /// Release mode (optimized)
        #[arg(long)]
        release: bool,
        /// Watch mode: recompile on file change
        #[arg(long)]
        watch: bool,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Repl => {
            run_repl();
        }
        Commands::New { name } => {
            create_project(&name);
        }
        Commands::Check { file } => {
            let start = std::time::Instant::now();
            match check_only(&file) {
                Ok(()) => {
                    let ms = start.elapsed().as_millis();
                    println!("\x1b[32mok\x1b[0m: {} ({ms}ms)", file.display());
                }
                Err(e) => {
                    print_error(&file, &e);
                    std::process::exit(1);
                }
            }
        }
        Commands::Fmt { file } => {
            format_file(&file);
        }
        Commands::Clean => {
            let tmp = std::env::temp_dir();
            let mut cleaned = 0;
            for name in ["ss_runtime.o", "simplescript_output", "simplescript_output.o",
                         "simplescript_watch_output", "simplescript_test_output",
                         "ss_repl.ss", "ss_repl_bin"] {
                let path = tmp.join(name);
                if path.exists() {
                    let _ = std::fs::remove_file(&path);
                    cleaned += 1;
                }
            }
            println!("cleaned {cleaned} cached files");
        }
        Commands::Test { dir } => {
            run_tests(&dir);
        }
        Commands::Build { file, output, release, emit_ir } => {
            let file = resolve_entry_file(file);
            let output = output.unwrap_or_else(|| {
                // Try ss.json "name" field, then fall back to file stem
                if let Ok(config) = std::fs::read_to_string("ss.json") {
                    if let Some(name) = extract_json_string(&config, "name") {
                        return PathBuf::from(name);
                    }
                }
                let stem = file.file_stem().unwrap().to_str().unwrap();
                PathBuf::from(stem)
            });
            if emit_ir {
                match emit_llvm_ir(&file) {
                    Ok(ir) => print!("{ir}"),
                    Err(e) => { print_error(&file, &e); std::process::exit(1); }
                }
                return;
            }
            let start = std::time::Instant::now();
            match compile(&file, &output, release) {
                Ok(()) => {
                    let ms = start.elapsed().as_millis();
                    let size = std::fs::metadata(&output).map(|m| m.len()).unwrap_or(0);
                    println!("\x1b[32mcompiled\x1b[0m: {} ({ms}ms, {:.0}KB)", output.display(), size as f64 / 1024.0);
                }
                Err(e) => {
                    print_error(&file, &e);
                    std::process::exit(1);
                }
            }
        }
        Commands::Run { file, release, watch } => {
            let file = resolve_entry_file(file);
            if watch {
                run_watch(&file, release);
            } else {
                let output = std::env::temp_dir().join("simplescript_output");
                match compile(&file, &output, release) {
                    Ok(()) => {
                        let status = Command::new(&output)
                            .status()
                            .expect("failed to run binary");
                        std::process::exit(status.code().unwrap_or(1));
                    }
                    Err(e) => {
                        print_error(&file, &e);
                        std::process::exit(1);
                    }
                }
            }
        }
    }
}

fn run_repl() {
    use std::io::{self, Write, BufRead};

    println!("SimpleScript REPL (type 'exit' to quit)");
    println!("");

    let mut history = String::new();
    let stdin = io::stdin();
    let mut buffer = String::new();
    let mut brace_depth = 0i32;

    loop {
        if buffer.is_empty() {
            print!("\x1b[1;36m>\x1b[0m ");
        } else {
            print!("\x1b[1;36m.\x1b[0m ");
        }
        io::stdout().flush().unwrap();

        let mut line = String::new();
        if stdin.lock().read_line(&mut line).unwrap() == 0 {
            break;
        }

        let trimmed = line.trim();
        if buffer.is_empty() {
            if trimmed == "exit" || trimmed == "quit" { break; }
            if trimmed.is_empty() { continue; }
        }

        // Track braces for multi-line input (skip braces inside strings)
        let mut in_string = false;
        let mut escape = false;
        for ch in trimmed.chars() {
            if escape { escape = false; continue; }
            if ch == '\\' && in_string { escape = true; continue; }
            if (ch == '"' || ch == '\'') && !in_string { in_string = true; continue; }
            if (ch == '"' || ch == '\'') && in_string { in_string = false; continue; }
            if ch == '`' { in_string = !in_string; continue; }
            if !in_string {
                if ch == '{' { brace_depth += 1; }
                if ch == '}' { brace_depth -= 1; }
            }
        }

        buffer.push_str(trimmed);
        buffer.push('\n');

        // If braces not balanced, continue reading
        if brace_depth > 0 { continue; }

        let input = buffer.trim().to_string();
        buffer.clear();
        brace_depth = 0;

        // Definitions go to history
        let source = if input.starts_with("function ") || input.starts_with("class ") {
            history.push_str(&input);
            history.push('\n');
            continue;
        } else {
            // Auto-print expressions (not statements)
            let stmt = if is_expression(&input) {
                format!("println({})", input)
            } else {
                input.clone()
            };
            format!("{}\nfunction main() {{\n  {}\n}}", history, stmt)
        };

        // Write temp file and compile+run
        let tmp = std::env::temp_dir().join("ss_repl.ss");
        let output = std::env::temp_dir().join("ss_repl_bin");
        std::fs::write(&tmp, &source).unwrap();

        match compile(&tmp, &output, false) {
            Ok(()) => {
                let _ = Command::new(&output).status();
            }
            Err(e) => {
                eprintln!("\x1b[31merror\x1b[0m: {e}");
            }
        }
    }
}

fn is_expression(input: &str) -> bool {
    let s = input.trim();
    // Not an expression if it's a statement keyword or assignment
    if s.starts_with("println") || s.starts_with("print(") || s.starts_with("const ")
        || s.starts_with("let ") || s.starts_with("if ") || s.starts_with("for ")
        || s.starts_with("while ") || s.starts_with("switch ") || s.starts_with("return")
        || s.starts_with("break") || s.starts_with("continue")
        || s.starts_with("writeFile") || s.starts_with("exit")
        || s.contains("= ") || s.contains("+=") || s.contains("-=")
        || s.contains("*=") || s.contains("/=") || s.contains("++") || s.contains("--")
    {
        return false;
    }
    true
}

fn resolve_entry_file(file: Option<PathBuf>) -> PathBuf {
    if let Some(f) = file { return f; }
    // Read from ss.json if present
    if let Ok(config) = std::fs::read_to_string("ss.json") {
        if let Some(main) = extract_json_string(&config, "main") {
            let p = PathBuf::from(main);
            if p.exists() { return p; }
        }
    }
    for candidate in ["src/main.ss", "main.ss"] {
        let p = PathBuf::from(candidate);
        if p.exists() { return p; }
    }
    eprintln!("error: no .ss file specified and no src/main.ss or main.ss found");
    std::process::exit(1);
}

fn extract_json_string(json: &str, key: &str) -> Option<String> {
    let search = format!("\"{}\"", key);
    let pos = json.find(&search)?;
    let rest = &json[pos + search.len()..];
    let colon = rest.find(':')?;
    let after = rest[colon + 1..].trim();
    if after.starts_with('"') {
        let end = after[1..].find('"')?;
        Some(after[1..1 + end].to_string())
    } else {
        None
    }
}

fn format_file(file: &Path) {
    let source = std::fs::read_to_string(file)
        .unwrap_or_else(|e| { eprintln!("error: {e}"); std::process::exit(1); });

    let mut output = String::new();
    let mut indent = 0u32;

    for line in source.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            output.push('\n');
            continue;
        }

        // Decrease indent for closing braces
        if trimmed.starts_with('}') || trimmed.starts_with(']') {
            indent = indent.saturating_sub(1);
        }

        // Write indented line
        for _ in 0..indent {
            output.push_str("    ");
        }
        output.push_str(trimmed);
        output.push('\n');

        // Increase indent for opening braces
        if trimmed.ends_with('{') || trimmed.ends_with('[') {
            indent += 1;
        }
    }

    // Remove trailing empty lines
    let output = output.trim_end().to_string() + "\n";

    std::fs::write(file, &output)
        .unwrap_or_else(|e| { eprintln!("error: {e}"); std::process::exit(1); });
    println!("formatted: {}", file.display());
}

fn run_watch(file: &Path, release: bool) {
    use std::time::Duration;

    println!("\x1b[1;36m[watch]\x1b[0m watching {} for changes...", file.display());
    let mut last_modified = get_mtime(file);
    let output = std::env::temp_dir().join("simplescript_watch_output");

    // Initial run
    run_once(file, &output, release);

    loop {
        std::thread::sleep(Duration::from_millis(500));

        let current = get_mtime(file);
        if current != last_modified {
            last_modified = current;
            println!("\n\x1b[1;36m[watch]\x1b[0m file changed, recompiling...");
            run_once(file, &output, release);
        }
    }
}

fn get_mtime(file: &Path) -> u64 {
    std::fs::metadata(file)
        .and_then(|m| m.modified())
        .map(|t| t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs())
        .unwrap_or(0)
}

fn run_once(file: &Path, output: &Path, release: bool) {
    let start = std::time::Instant::now();
    match compile(file, output, release) {
        Ok(()) => {
            let elapsed = start.elapsed();
            println!("\x1b[1;32m[ok]\x1b[0m compiled in {:.0}ms", elapsed.as_millis());
            let _ = Command::new(output)
                .status();
        }
        Err(e) => {
            print_error(file, &e);
        }
    }
    println!("\x1b[1;36m[watch]\x1b[0m waiting for changes...");
}

fn run_tests(dir: &Path) {
    let mut files: Vec<PathBuf> = Vec::new();
    collect_ss_files(dir, &mut files);
    files.sort();

    if files.is_empty() {
        eprintln!("no .ss files found in {}", dir.display());
        std::process::exit(1);
    }

    let total = files.len();
    let mut passed = 0;
    let mut failed = Vec::new();
    let start = std::time::Instant::now();

    for file in &files {
        let name = file.strip_prefix(dir).unwrap_or(file).display().to_string();
        let output = std::env::temp_dir().join("simplescript_test_output");

        match compile(file, &output, false) {
            Ok(()) => {
                let result = Command::new(&output)
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .status();

                match result {
                    Ok(status) if status.success() => {
                        println!("  \x1b[32m✓\x1b[0m {name}");
                        passed += 1;
                    }
                    _ => {
                        println!("  \x1b[31m✗\x1b[0m {name} (runtime error)");
                        failed.push(name);
                    }
                }
            }
            Err(e) => {
                println!("  \x1b[31m✗\x1b[0m {name} ({e})");
                failed.push(name);
            }
        }

        let _ = std::fs::remove_file(&output);
    }

    let elapsed = start.elapsed();
    println!("\n{passed}/{total} passed in {:.1}s", elapsed.as_secs_f64());

    if !failed.is_empty() {
        println!("\nfailed:");
        for f in &failed {
            println!("  {f}");
        }
        std::process::exit(1);
    }
}

fn collect_ss_files(dir: &Path, files: &mut Vec<PathBuf>) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_ss_files(&path, files);
            } else if path.extension().is_some_and(|e| e == "ss") {
                // Skip interactive tests
                let name = path.file_name().unwrap().to_str().unwrap();
                if name != "guess_game.ss" && name != "args_basic.ss"
                    && name != "ygrep.ss" && name != "math.ss" && name != "utils.ss" {
                    files.push(path);
                }
            }
        }
    }
}

fn create_project(name: &str) {
    let dir = Path::new(name);
    if dir.exists() {
        eprintln!("error: directory '{}' already exists", name);
        std::process::exit(1);
    }

    std::fs::create_dir_all(dir.join("src")).expect("failed to create directory");

    // ss.json
    let config = format!(r#"{{
  "name": "{}",
  "version": "0.1.0",
  "target": "bin",
  "main": "src/main.ss"
}}"#, name);
    std::fs::write(dir.join("ss.json"), config).expect("failed to write ss.json");

    // src/main.ss
    let main = format!(r#"function main() {{
    println("Hello from {}!")
}}"#, name);
    std::fs::write(dir.join("src/main.ss"), main).expect("failed to write main.ss");

    println!("created project: {}", name);
    println!("  {}/ss.json", name);
    println!("  {}/src/main.ss", name);
    println!("");
    println!("  cd {} && ss run src/main.ss", name);
}

fn print_error(file: &Path, err: &str) {
    // Try to extract line number from error message
    let line_num = extract_line_number(err);
    eprintln!("\x1b[1;31merror\x1b[0m: {err}");
    if let Some(line) = line_num {
        eprintln!("  \x1b[1;34m-->\x1b[0m {}:{}", file.display(), line);
        // Show the source line
        if let Ok(source) = std::fs::read_to_string(file) {
            let lines: Vec<&str> = source.lines().collect();
            if line > 0 && (line as usize) <= lines.len() {
                let src_line = lines[line as usize - 1];
                eprintln!("   \x1b[1;34m|\x1b[0m");
                eprintln!(" \x1b[1;34m{line}\x1b[0m \x1b[1;34m|\x1b[0m {src_line}");
                eprintln!("   \x1b[1;34m|\x1b[0m");
            }
        }
    }
}

fn extract_line_number(err: &str) -> Option<u32> {
    // Match patterns like "at line 5" or "line 5:3"
    if let Some(pos) = err.find("line ") {
        let after = &err[pos + 5..];
        let num_str: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
        num_str.parse().ok()
    } else {
        None
    }
}

fn emit_llvm_ir(source_path: &Path) -> Result<String, String> {
    let source = resolve_imports(source_path)?;
    let tokens = ym_lexer::tokenize(&source).map_err(|e| format!("{e}"))?;
    let program = ym_parser::parse(tokens).map_err(|e| format!("{e}"))?;
    let mut checker = ym_checker::Checker::new();
    checker.check(&program).map_err(|e| format!("{e}"))?;
    let context = inkwell::context::Context::create();
    let mut codegen = ym_codegen::Codegen::new(&context);
    codegen.compile(&program).map_err(|e| format!("{e}"))?;
    Ok(codegen.print_ir())
}

fn check_only(source_path: &Path) -> Result<(), String> {
    let source = resolve_imports(source_path)?;
    let tokens = ym_lexer::tokenize(&source).map_err(|e| format!("{e}"))?;
    let program = ym_parser::parse(tokens).map_err(|e| format!("{e}"))?;
    let mut checker = ym_checker::Checker::new();
    checker.check(&program).map_err(|e| format!("{e}"))?;
    Ok(())
}

fn resolve_imports(source_path: &Path) -> Result<String, String> {
    let mut visited = std::collections::HashSet::new();
    resolve_imports_inner(source_path, &mut visited)
}

fn resolve_imports_inner(source_path: &Path, visited: &mut std::collections::HashSet<PathBuf>) -> Result<String, String> {
    let canonical = source_path.canonicalize()
        .unwrap_or_else(|_| source_path.to_path_buf());

    if !visited.insert(canonical) {
        return Ok(String::new()); // already imported, skip (prevents cycles)
    }

    let source = std::fs::read_to_string(source_path)
        .map_err(|e| format!("cannot read {}: {e}", source_path.display()))?;

    let base_dir = source_path.parent().unwrap_or(Path::new("."));
    let mut imported_code = String::new();
    let mut main_code = String::new();

    for line in source.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("import ") {
            if let Some(path) = extract_import_path(trimmed) {
                let mut import_path = base_dir.join(&path);
                if import_path.extension().is_none() {
                    import_path.set_extension("ss");
                }
                let imported = resolve_imports_inner(&import_path, visited)?;
                imported_code.push_str(&imported);
                imported_code.push('\n');
            }
        } else {
            main_code.push_str(line);
            main_code.push('\n');
        }
    }

    Ok(format!("{imported_code}{main_code}"))
}

fn extract_import_path(line: &str) -> Option<String> {
    // Parse: import { ... } from "path"  or  import { ... } from "./path"
    let from_idx = line.find("from ")?;
    let rest = &line[from_idx + 5..];
    let rest = rest.trim();

    // Extract quoted path
    if rest.starts_with('"') {
        let end = rest[1..].find('"')?;
        Some(rest[1..1 + end].to_string())
    } else {
        None
    }
}

fn compile(source_path: &Path, output_path: &Path, release: bool) -> Result<(), String> {
    // 1. Read source + resolve imports
    let source = resolve_imports(source_path)?;

    // 2. Lex
    let tokens = ym_lexer::tokenize(&source)
        .map_err(|e| format!("{e}"))?;

    // 3. Parse
    let program = ym_parser::parse(tokens)
        .map_err(|e| format!("{e}"))?;

    // 4. Type check
    let mut checker = ym_checker::Checker::new();
    let _typed = checker.check(&program)
        .map_err(|e| format!("{e}"))?;

    // 5. Codegen
    let context = inkwell::context::Context::create();
    let mut codegen = ym_codegen::Codegen::new(&context);
    codegen.compile(&program)
        .map_err(|e| format!("{e}"))?;

    // Debug: print IR
    if std::env::var("SS_DEBUG_IR").is_ok() {
        eprintln!("{}", codegen.print_ir());
    }

    // 6. Write object file
    let obj_path = std::env::temp_dir().join("simplescript_output.o");
    codegen.write_object_file_opt(&obj_path, release)
        .map_err(|e| format!("{e}"))?;

    // 7. Compile runtime.c (cached — only recompile if runtime.c is newer)
    let runtime_c = find_runtime_c()
        .ok_or("cannot find runtime/runtime.c")?;
    let runtime_o = std::env::temp_dir().join("ss_runtime.o");

    let need_recompile = !runtime_o.exists() || {
        let c_mtime = std::fs::metadata(&runtime_c).and_then(|m| m.modified()).ok();
        let o_mtime = std::fs::metadata(&runtime_o).and_then(|m| m.modified()).ok();
        match (c_mtime, o_mtime) {
            (Some(c), Some(o)) => c > o,
            _ => true,
        }
    };

    if need_recompile {
        let cc_status = Command::new("musl-gcc")
            .args(["-c", "-O2"])
            .arg(&runtime_c)
            .arg("-o")
            .arg(&runtime_o)
            .status()
            .map_err(|e| format!("failed to run musl-gcc: {e}"))?;

        if !cc_status.success() {
            return Err("failed to compile runtime.c".into());
        }
    }

    // 8. Link
    let mut link_cmd = Command::new("musl-gcc");
    link_cmd.arg("-static");
    if release {
        link_cmd.args(["-O2", "-s"]); // optimize + strip symbols
    }
    let link_status = link_cmd
        .arg(&obj_path)
        .arg(&runtime_o)
        .arg("-o")
        .arg(output_path)
        .status()
        .map_err(|e| format!("failed to link: {e}"))?;

    if !link_status.success() {
        return Err("linking failed".into());
    }

    // Cleanup
    let _ = std::fs::remove_file(&obj_path);
    let _ = std::fs::remove_file(&runtime_o);

    Ok(())
}

fn find_runtime_c() -> Option<PathBuf> {
    // Try relative to current exe
    let exe = std::env::current_exe().ok()?;
    let exe_dir = exe.parent()?;

    // Try: exe_dir/../../runtime/runtime.c (from target/debug/)
    let path = exe_dir.join("../../runtime/runtime.c");
    if path.exists() { return Some(path); }

    // Try: ./runtime/runtime.c
    let path = PathBuf::from("runtime/runtime.c");
    if path.exists() { return Some(path); }

    // Try: cwd-based search
    let cwd = std::env::current_dir().ok()?;
    let path = cwd.join("runtime/runtime.c");
    if path.exists() { return Some(path); }

    None
}
