///|
/// Token 定义 - 代表源代码中的最小词法单元
pub(all) enum Token {
  // 关键字
  True
  False
  Unit
  Bool
  Int
  Double
  Array
  Not
  If
  Else
  Fn
  Let
  Mut
  While
  Return
  Main
  Struct
  Enum
  Match

  // 字面量
  Number(Int)
  Identifier(String)
  UpperIdentifier(String) // 大写开头的标识符

  // 比较操作符
  Equal // ==
  NotEqual // !=
  GreaterEqual // >=
  LessEqual // <=
  Less // <
  Greater // >

  // 逻辑操作符
  And // &&
  Or // ||

  // 算术操作符
  Plus // +
  Minus // -
  Multiply // *
  Divide // /
  Modulo // %

  // 其他符号
  Dot // .
  Assign // =
  LParen // (
  RParen // )
  LBracket // [
  RBracket // ]
  LCurlyBracket // {
  RCurlyBracket // }
  Arrow // ->
  MatchArrow // =>
  Colon // :
  DoubleColon // ::
  Semicolon // ;
  Comma // ,
  Exclamation // !
  Wildcard // _

  // 特殊
  EOF
  Unknown(Char)
} derive(Eq, Show)

///|
/// 位置信息 - 记录Token在源代码中的位置
pub(all) struct Position {
  line : Int
  column : Int
} derive(Eq, Show)

///|
/// 带位置信息的Token
pub(all) struct TokenWithPos {
  token : Token
  pos : Position
} derive(Eq, Show)
