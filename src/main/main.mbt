///|
/// MiniMoonBit 编译器主程序
fn main {
  let verbose = @ref.new(false)
  let files = []
  let input = @ref.new("")
  let write_debug = @ref.new(false)
  let show_tokens = @ref.new(false)
  let show_ast = @ref.new(false)
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
      ("--debug", "-d", Set(write_debug), "write debug files"),
      ("--show-tokens", "", Set(show_tokens), "display token list"),
      ("--show-ast", "", Set(show_ast), "display AST structure"),
    ],
    file => files.push(file),
    usage,
    actual_args,
  )
  let (source_code, filename) = get_input_source(input.val, files)
  if verbose.val {
    println("=== MiniMoonBit 编译器 ===")
    println("源文件: " + filename)
  }
  match
    compile(
      source_code,
      filename,
      verbose.val,
      write_debug.val,
      show_tokens.val,
      show_ast.val,
    ) {
    Ok(stats) => {
      println("编译成功!")
      if verbose.val {
        println(stats.to_string())
      }
    }
    Err(error) => println("编译失败: " + error)
  }
}

///|
/// 编译源代码
fn compile(
  source : String,
  filename : String,
  verbose : Bool,
  write_debug : Bool,
  show_tokens : Bool,
  show_ast : Bool,
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
      let stats = CompileStats::{
        tokens_count: tokens.length(),
        declarations_count: program.declarations.length(),
      }
      Ok(stats)
    }
    None => Err("语法分析失败")
  }
}

///|
/// 获取输入源代码
fn get_input_source(
  input_file : String,
  files : Array[String],
) -> (String, String) {
  if input_file != "" {
    match read_file(input_file) {
      Ok(code) => (code, input_file)
      Err(error) => {
        println("读取文件失败: " + error)
        abort("文件读取错误")
      }
    }
  } else if files.length() > 0 {
    match read_file(files[0]) {
      Ok(code) => (code, files[0])
      Err(error) => {
        println("读取文件失败: " + error)
        abort("文件读取错误")
      }
    }
  } else {
    abort("没有指定输入文件")
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
    @ast.TopFnDecl(name, params, return_type, body) =>
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
  }
}
