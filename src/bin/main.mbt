///|
/// MiniMoonBit 编译器主程序
fn main {
  let verbose = @ref.new(false)
  let file = @ref.new("")
  let input = @ref.new("")
  let output = @ref.new("")
  let typecheck_only = @ref.new(false)
  let write_debug = @ref.new(false)
  let show_tokens = @ref.new(false)
  let show_ast = @ref.new(false)
  let show_semantic = @ref.new(false)
  let usage = "MiniMoonBit Compiler\nUsage: minimoonbit [options] <input_file>"

  // 获取命令行参数，跳过第一个参数
  let args = @sys.get_cli_args()
  let actual_args = if args.length() > 1 {
    let mut result = []
    for i = 1; i < args.length(); i = i + 1 {
      result = result + [args[i]]
    }
    result
  } else {
    []
  }
  @ArgParser.parse(
    [
      ("--verbose", "-v", Set(verbose), "enable verbose output"),
      ("--input", "-i", Set_string(input), "input file name"),
      ("--output", "-o", Set_string(output), "output file name"),
      ("--typecheck", "", Set(typecheck_only), "only perform type checking"),
      ("--debug", "-d", Set(write_debug), "write debug files"),
      ("--show-tokens", "", Set(show_tokens), "display token list"),
      ("--show-ast", "", Set(show_ast), "display AST structure"),
      (
        "--show-semantic",
        "",
        Set(show_semantic),
        "display semantic analysis results",
      ),
    ],
    res_file => file.val = res_file,
    usage,
    actual_args,
  )
  let (source_code, filename) = match get_input_source(input.val, file.val) {
    Ok((code, name)) => (code, name)
    Err(error) => {
      if error == "未指定输入文件" {
        println("错误: " + error)
        println(
          "MiniMoonBit Compiler\nUsage: minimoonbit [options] <input_file>",
        )
      } else {
        println("编译失败: " + error)
      }
      abort("编译失败")
      ("", "") // This line will never be reached, but satisfies the type checker
    }
  }
  if verbose.val {
    println("=== MiniMoonBit 编译器 ===")
    println("源文件: " + filename)
  }
  match
    compile(
      source_code,
      filename,
      output.val,
      typecheck_only.val,
      verbose.val,
      write_debug.val,
      show_tokens.val,
      show_ast.val,
      show_semantic.val,
    ) {
    Ok(stats) => {
      if typecheck_only.val {
        println("类型检查通过!")
      } else {
        println("编译成功!")
      }
      if verbose.val {
        println(stats.to_string())
      }
    }
    Err(error) => {
      println("编译失败: " + error)
      abort("编译失败")
    }
  }
}

///|
/// 编译源代码
fn compile(
  source : String,
  filename : String,
  output_file : String,
  typecheck_only : Bool,
  verbose : Bool,
  write_debug : Bool,
  show_tokens : Bool,
  show_ast : Bool,
  show_semantic : Bool,
) -> Result[CompileStats, String] {
  // 词法分析
  if verbose {
    println("词法分析...")
  }
  let tokens = @lexer.tokenize(source)
  if show_tokens {
    display_tokens(tokens)
  }
  if write_debug {
    write_debug_file(filename + ".tokens", format_tokens_for_file(tokens))
  }
  if verbose {
    println("生成 " + tokens.length().to_string() + " 个tokens")
  }

  // 语法分析
  if verbose {
    println("语法分析...")
  }
  let parser = @parser.Parser::new(tokens)
  let ast = parser.parse_program()
  match ast {
    Some(program) => {
      if show_ast {
        display_ast(program)
      }
      if write_debug {
        write_debug_file(filename + ".parser", format_ast_for_file(program))
      }
      if verbose {
        println(
          "生成AST，包含 " +
          program.declarations.length().to_string() +
          " 个声明",
        )
      }

      // 语义分析
      if verbose {
        println("语义分析...")
      }
      let semantic_result = @semantic.analyze_program(program)
      if semantic_result.errors.length() > 0 {
        if show_semantic {
          display_semantic_errors(semantic_result.errors)
        }
        if write_debug {
          write_debug_file(
            filename + ".semantic",
            format_semantic_errors(semantic_result.errors),
          )
        }
        return Err(
          "语义分析失败: " +
          semantic_result.errors.length().to_string() +
          " 个错误\n" +
          format_semantic_errors(semantic_result.errors),
        )
      }
      if show_semantic {
        display_semantic_result(semantic_result)
      }
      if write_debug {
        write_debug_file(
          filename + ".semantic",
          "语义分析通过，无错误",
        )
      }
      if verbose {
        println("语义分析通过")
      }

      // 如果只是类型检查，在这里返回
      if typecheck_only {
        let stats = CompileStats::{
          tokens_count: tokens.length(),
          declarations_count: program.declarations.length(),
          semantic_errors: semantic_result.errors.length(),
        }
        return Ok(stats)
      }

      // 代码生成
      if verbose {
        println("代码生成...")
      }
      let assembly_code = @codegen.generate_riscv_assembly(program)

      // 确定输出文件名
      let final_output_file = if output_file != "" {
        output_file
      } else {
        filename + ".s"
      }

      // 写入输出文件
      write_output_file(final_output_file, assembly_code)
      if write_debug {
        write_debug_file(filename + ".s", assembly_code)
      }
      if verbose {
        println("生成RISC-V汇编代码: " + final_output_file)
      }
      let stats = CompileStats::{
        tokens_count: tokens.length(),
        declarations_count: program.declarations.length(),
        semantic_errors: semantic_result.errors.length(),
      }
      Ok(stats)
    }
    None =>
      // 获取详细的解析错误信息
      match parser.get_last_error() {
        Some(error) => {
          let error_msg = format_parse_error(error)
          Err(error_msg)
        }
        None => Err("语法分析失败: 未知错误")
      }
  }
}

///|
/// 获取输入源代码
fn get_input_source(
  input_file : String,
  file : String,
) -> Result[(String, String), String] {
  if input_file != "" {
    match read_file(input_file) {
      Ok(code) => Ok((code, input_file))
      Err(error) => Err("读取文件失败: " + error)
    }
  } else if file != "" {
    match read_file(file) {
      Ok(code) => Ok((code, file))
      Err(error) => Err("读取文件失败: " + error)
    }
  } else {
    Err("未指定输入文件")
  }
}

///|
/// 读取文件内容
fn read_file(filename : String) -> Result[String, String] {
  Ok(@fs.read_file_to_string(filename)) catch {
    error => Err(error.to_string())
  }
}

///|
/// 格式化tokens用于文件输出
fn format_tokens_for_file(tokens : Array[@lexer.TokenWithPos]) -> String {
  let mut content = ""
  for i = 0; i < tokens.length(); i = i + 1 {
    let token = tokens[i]
    content = content +
      "[" +
      i.to_string() +
      "] " +
      token.token.to_string() +
      " at (" +
      token.pos.line.to_string() +
      ":" +
      token.pos.column.to_string() +
      ")\n"
  }
  content
}

///|
/// 格式化AST用于文件输出
fn format_ast_for_file(program : @ast.Program) -> String {
  let mut content = ""
  for i = 0; i < program.declarations.length(); i = i + 1 {
    content = content +
      "[" +
      i.to_string() +
      "] " +
      format_declaration(program.declarations[i], "  ") +
      "\n"
  }
  content
}

///|
/// 写入输出文件
fn write_output_file(filename : String, content : String) -> Unit {
  @fs.write_string_to_file(filename, content) catch {
    error => {
      println("写入输出文件失败: " + error.to_string())
      abort("写入输出文件失败")
    }
  }
}

///|
/// 写入调试文件
fn write_debug_file(filename : String, content : String) -> Unit {
  @fs.write_string_to_file(filename, content) catch {
    _ => () // 忽略写入错误
  }
}

///|
/// 编译统计信息
struct CompileStats {
  tokens_count : Int
  declarations_count : Int
  semantic_errors : Int
} derive(Show)

///|
/// 显示Token列表
fn display_tokens(tokens : Array[@lexer.TokenWithPos]) -> Unit {
  println("=== 词法分析结果 ===")
  println("Token数量: " + tokens.length().to_string())
  println("")
  println("详细Token列表:")
  for i = 0; i < tokens.length(); i = i + 1 {
    let token = tokens[i]
    println(
      "[" +
      i.to_string() +
      "] " +
      token.token.to_string() +
      " at (" +
      token.pos.line.to_string() +
      ":" +
      token.pos.column.to_string() +
      ")",
    )
  }
}

///|
/// 显示AST结构
fn display_ast(program : @ast.Program) -> Unit {
  println("=== 语法分析结果 (AST) ===")
  println(
    "程序包含 " +
    program.declarations.length().to_string() +
    " 个顶层声明",
  )
  println("")
  println("AST结构:")
  for i = 0; i < program.declarations.length(); i = i + 1 {
    println(
      "[" +
      i.to_string() +
      "] " +
      format_declaration(program.declarations[i], "  "),
    )
  }
  println("")
  println("简化表示:")
  println(program.to_string())
}

///|
/// 格式化声明
fn format_declaration(decl : @ast.TopLevel, indent : String) -> String {
  match decl {
    @ast.MainFnDecl(body) =>
      "MainFunction:\n" + indent + "  body: " + body.to_string()
    @ast.TopFnDecl(_generic_param, name, params, return_type, body) =>
      "Function '" +
      name +
      "':\n" +
      indent +
      "  params: " +
      params.to_string() +
      "\n" +
      indent +
      "  return_type: " +
      return_type.to_string() +
      "\n" +
      indent +
      "  body: " +
      body.to_string()
    @ast.TopLetDecl(name, type_annotation, expr) =>
      "LetDeclaration '" +
      name +
      "':\n" +
      indent +
      "  type: " +
      (match type_annotation {
        Some(t) => t.to_string()
        None => "inferred"
      }) +
      "\n" +
      indent +
      "  value: " +
      expr.to_string()
    @ast.TopLetWildcardDecl(type_annotation, expr) =>
      "LetWildcardDeclaration:\n" +
      indent +
      "  type: " +
      (match type_annotation {
        Some(t) => t.to_string()
        None => "inferred"
      }) +
      "\n" +
      indent +
      "  value: " +
      expr.to_string()
    @ast.StructDecl(name, _generic_param, fields) =>
      "StructDeclaration '" +
      name +
      "':\n" +
      indent +
      "  fields: " +
      fields.to_string()
    @ast.EnumDecl(name, _generic_param, variants) =>
      "EnumDeclaration '" +
      name +
      "':\n" +
      indent +
      "  variants: " +
      variants.to_string()
  }
}

///|
/// 显示语义分析错误
fn display_semantic_errors(errors : Array[String]) -> Unit {
  println("=== 语义分析错误 ===")
  println("错误数量: " + errors.length().to_string())
  println("")
  for i = 0; i < errors.length(); i = i + 1 {
    println("[" + (i + 1).to_string() + "] " + errors[i])
  }
}

///|
/// 显示语义分析结果
fn display_semantic_result(result : @semantic.SemanticResult) -> Unit {
  if result.errors.length() == 0 {
    println("=== 语义分析结果 ===")
    println("语义分析通过，无错误")
  } else {
    display_semantic_errors(result.errors)
  }
}

///|
/// 格式化语义错误用于文件输出
fn format_semantic_errors(errors : Array[String]) -> String {
  let mut content = "语义分析错误报告\n"
  content = content + "错误数量: " + errors.length().to_string() + "\n\n"
  for i = 0; i < errors.length(); i = i + 1 {
    content = content + "[" + (i + 1).to_string() + "] " + errors[i] + "\n"
  }
  content
}

///|
/// 格式化解析错误信息
fn format_parse_error(error : @parser.ParseError) -> String {
  let mut error_msg = "语法分析失败:\n"
  error_msg = error_msg + "  错误: " + error.message + "\n"
  error_msg = error_msg + "  期望: " + error.expected + "\n"
  error_msg = error_msg + "  实际: " + error.actual + "\n"
  error_msg = error_msg + "  上下文: " + error.context + "\n"
  error_msg = error_msg +
    "  位置: 第" +
    error.error_line.to_string() +
    "行，第" +
    error.error_column.to_string() +
    "列\n\n"

  // 添加源码上下文
  error_msg = error_msg + "源码上下文:\n"
  let start_line = if error.error_line > 2 { error.error_line - 2 } else { 1 }
  for i = 0; i < error.source_lines.length(); i = i + 1 {
    let line_num = start_line + i
    let line_content = error.source_lines[i]
    if line_num == error.error_line {
      // 错误行，添加箭头指示
      error_msg = error_msg +
        "  " +
        line_num.to_string() +
        " | " +
        line_content +
        "\n"
      error_msg = error_msg +
        "     | " +
        generate_error_pointer(error.error_column) +
        "\n"
    } else {
      // 普通行
      error_msg = error_msg +
        "  " +
        line_num.to_string() +
        " | " +
        line_content +
        "\n"
    }
  }
  error_msg
}

///|
/// 生成错误指针
fn generate_error_pointer(column : Int) -> String {
  let mut pointer = ""
  for i = 1; i < column; i = i + 1 {
    pointer = pointer + " "
  }
  pointer = pointer + "^"
  pointer
}
