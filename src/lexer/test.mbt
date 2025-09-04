///|
test "lexer" {
  // `inspect` is used to check the output of the function
  // Just write `inspect(value)` and execute `moon test --update`
  // to update the expected output, and verify them afterwards
  let input = "let x : Int = 42;"
  let tokens = tokenize(input)
  inspect(
    tokens,
    content=(
      #|[{token: Let, pos: {line: 1, column: 1}}, {token: Identifier("x"), pos: {line: 1, column: 5}}, {token: Colon, pos: {line: 1, column: 7}}, {token: Int, pos: {line: 1, column: 9}}, {token: Assign, pos: {line: 1, column: 13}}, {token: Number(42), pos: {line: 1, column: 15}}, {token: Semicolon, pos: {line: 1, column: 17}}, {token: EOF, pos: {line: 1, column: 18}}]
    ),
  )
  let complex_input = "fn add(a : Int, b : Int) -> Int { a + b }"
  let complex_tokens = tokenize(complex_input)
  inspect(
    complex_tokens,
    content=(
      #|[{token: Fn, pos: {line: 1, column: 1}}, {token: Identifier("add"), pos: {line: 1, column: 4}}, {token: LParen, pos: {line: 1, column: 7}}, {token: Identifier("a"), pos: {line: 1, column: 8}}, {token: Colon, pos: {line: 1, column: 10}}, {token: Int, pos: {line: 1, column: 12}}, {token: Comma, pos: {line: 1, column: 15}}, {token: Identifier("b"), pos: {line: 1, column: 17}}, {token: Colon, pos: {line: 1, column: 19}}, {token: Int, pos: {line: 1, column: 21}}, {token: RParen, pos: {line: 1, column: 24}}, {token: Arrow, pos: {line: 1, column: 26}}, {token: Int, pos: {line: 1, column: 29}}, {token: LCurlyBracket, pos: {line: 1, column: 33}}, {token: Identifier("a"), pos: {line: 1, column: 35}}, {token: Plus, pos: {line: 1, column: 37}}, {token: Identifier("b"), pos: {line: 1, column: 39}}, {token: RCurlyBracket, pos: {line: 1, column: 41}}, {token: EOF, pos: {line: 1, column: 42}}]
    ),
  )
}
