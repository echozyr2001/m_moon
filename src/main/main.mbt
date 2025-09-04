///|
/// MiniMoonBit 编译器主程序
fn main {

}

///|
/// 入口函数
pub fn compile(source : String) -> Result[String, String] {
  // 1. 词法分析
  let tokens = @lexer.tokenize(source)

  // 2. 语法分析
  let parser = @parser.Parser::new(tokens)
  let ast = parser.parse_program()

  // 3. 语义分析 (TODO)
  // 4. 代码生成 (TODO)

  match ast {
    Some(_) => Ok("Compilation successful")
    None => Err("Parse error")
  }
}
