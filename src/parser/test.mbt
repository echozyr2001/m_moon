///|
test "parser" {
  // `inspect` is used to check the output of the function
  // Just write `inspect(value)` and execute `moon test --update`
  // to update the expected output, and verify them afterwards

  // Test simple let declaration
  let input1 = "let x : Int = 42 + 1;"
  let tokens1 = @lexer.tokenize(input1)
  let parser1 = Parser::new(tokens1)
  let result1 = parser1.parse_program()
  inspect(
    result1,
    content=(
      #|Some({declarations: [TopLetDecl("x", Some(IntType), BinaryOp(Add, IntLiteral(42), IntLiteral(1)))]})
    ),
  )

  // Test function declaration
  let input2 = "fn add(a : Int, b : Int) -> Int { a + b }"
  let tokens2 = @lexer.tokenize(input2)
  let parser2 = Parser::new(tokens2)
  let result2 = parser2.parse_program()
  inspect(
    result2,
    content=(
      #|Some({declarations: [TopFnDecl(None, "add", [("a", IntType), ("b", IntType)], IntType, BlockExpr([], Some(BinaryOp(Add, Identifier("a"), Identifier("b")))))]})
    ),
  )

  // Test main function
  let input3 = "fn main { 42 }"
  let tokens3 = @lexer.tokenize(input3)
  let parser3 = Parser::new(tokens3)
  let result3 = parser3.parse_program()
  inspect(
    result3,
    content="Some({declarations: [MainFnDecl(BlockExpr([], Some(IntLiteral(42))))]})",
  )
}
