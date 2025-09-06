///|
test "main" {
  let generator = @mbtsmith.RandProgGenerator::new()

  // 生成完整程序
  let program = generator.gen_program()
  println("Generated program:")
  // println(program.to_string())
  println("---")
  let tokens = @lexer.tokenize(program.to_string())
  println("Tokens generated: " + tokens.length().to_string())
  for i = 0; i < tokens.length() && i < 10; i = i + 1 {
    println("Token " + i.to_string() + ": " + tokens[i].token.to_string())
  }
  println("---")
  let parser = @parser.Parser::new(tokens)
  println("Starting parsing...")
  let ast = parser.parse_program()
  match ast {
    Some(ast) => {
      println("Parsing successful!")
      let semantic = @semantic.SemanticAnalyzer::new()
      let _ = semantic.analyze(ast)
      let _ = @codegen.generate_riscv_assembly(ast)
      println("Success!")
    }
    None => {
      println("Parsing failed")
      abort("Parsing failed")
    }
  }
}
