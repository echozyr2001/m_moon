///|
/// 词法分析器
pub struct Lexer {
  input : String
  mut position : Int
  mut line : Int
  mut column : Int
}

///|
pub fn Lexer::new(input : String) -> Lexer {
  { input, position: 0, line: 1, column: 1 }
}

///|
fn current_char(self : Lexer) -> Char? {
  if self.position >= self.input.length() {
    None
  } else {
    match self.input.get(self.position) {
      Some(code) => Some(code.unsafe_to_char())
      None => None
    }
  }
}

///|
fn peek_char(self : Lexer, offset : Int) -> Char? {
  let pos = self.position + offset
  if pos >= self.input.length() {
    None
  } else {
    match self.input.get(pos) {
      Some(code) => Some(code.unsafe_to_char())
      None => None
    }
  }
}

///|
fn advance(self : Lexer) -> Unit {
  if self.position < self.input.length() {
    if self.input[self.position] == '\n' {
      self.line = self.line + 1
      self.column = 1
    } else {
      self.column = self.column + 1
    }
    self.position = self.position + 1
  }
}

///|
fn skip_whitespace(self : Lexer) -> Unit {
  while true {
    match self.current_char() {
      Some(' ') | Some('\t') | Some('\r') | Some('\n') => self.advance()
      _ => break
    }
  }
}

///|
fn skip_comment(self : Lexer) -> Unit {
  // 跳过 // 注释
  if self.current_char() == Some('/') && self.peek_char(1) == Some('/') {
    while true {
      match self.current_char() {
        Some('\n') | None => break
        _ => self.advance()
      }
    }
  }
}

///|
fn read_number(self : Lexer) -> Int {
  let mut num = 0
  while true {
    match self.current_char() {
      Some(c) if c >= '0' && c <= '9' => {
        num = num * 10 + (c.to_int() - '0'.to_int())
        self.advance()
      }
      _ => break
    }
  }
  num
}

///|
fn read_identifier(self : Lexer) -> String {
  let start = self.position
  while true {
    match self.current_char() {
      Some(c) if (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' => self.advance()
      _ => break
    }
  }
  if start == self.position {
    ""
  } else if start >= 0 &&
    start <= self.position &&
    self.position <= self.input.length() {
    self.input[start:self.position].to_string() catch {
      InvalidIndex =>
        abort("Lexer error: Invalid index when extracting identifier")
      IndexOutOfBounds =>
        abort("Lexer error: Index out of bounds when extracting identifier")
    }
  } else {
    abort("Lexer error: Invalid position state in read_identifier")
  }
}

///|
fn keyword_or_identifier(word : String) -> Token {
  match word {
    "true" => True
    "false" => False
    "Unit" => Unit
    "Bool" => Bool
    "Int" => Int
    "Double" => Double
    "Array" => Array
    "Function" => Function
    "not" => Not
    "if" => If
    "else" => Else
    "fn" => Fn
    "let" => Let
    "mut" => Mut
    "while" => While
    "return" => Return
    "main" => Main
    "struct" => Struct
    "enum" => Enum
    "match" => Match
    _ =>
      // 检查是否是大写开头的标识符
      if word.length() > 0 && word[0] >= 'A' && word[0] <= 'Z' {
        UpperIdentifier(word)
      } else {
        Identifier(word)
      }
  }
}

///|
pub fn next_token(self : Lexer) -> TokenWithPos {
  self.skip_whitespace()
  self.skip_comment()
  self.skip_whitespace()
  let pos = Position::{ line: self.line, column: self.column }
  match self.current_char() {
    None => TokenWithPos::{ token: EOF, pos }
    Some('(') => {
      self.advance()
      TokenWithPos::{ token: LParen, pos }
    }
    Some(')') => {
      self.advance()
      TokenWithPos::{ token: RParen, pos }
    }
    Some('[') => {
      self.advance()
      TokenWithPos::{ token: LBracket, pos }
    }
    Some(']') => {
      self.advance()
      TokenWithPos::{ token: RBracket, pos }
    }
    Some('{') => {
      self.advance()
      TokenWithPos::{ token: LCurlyBracket, pos }
    }
    Some('}') => {
      self.advance()
      TokenWithPos::{ token: RCurlyBracket, pos }
    }
    Some('+') => {
      self.advance()
      TokenWithPos::{ token: Plus, pos }
    }
    Some('*') => {
      self.advance()
      TokenWithPos::{ token: Multiply, pos }
    }
    Some('/') => {
      self.advance()
      TokenWithPos::{ token: Divide, pos }
    }
    Some('%') => {
      self.advance()
      TokenWithPos::{ token: Modulo, pos }
    }
    Some('.') => {
      self.advance()
      TokenWithPos::{ token: Dot, pos }
    }
    Some(';') => {
      self.advance()
      TokenWithPos::{ token: Semicolon, pos }
    }
    Some(',') => {
      self.advance()
      TokenWithPos::{ token: Comma, pos }
    }
    Some('-') =>
      if self.peek_char(1) == Some('>') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: Arrow, pos }
      } else {
        self.advance()
        TokenWithPos::{ token: Minus, pos }
      }
    Some('=') =>
      if self.peek_char(1) == Some('>') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: MatchArrow, pos }
      } else if self.peek_char(1) == Some('=') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: Equal, pos }
      } else {
        self.advance()
        TokenWithPos::{ token: Assign, pos }
      }
    Some('!') =>
      if self.peek_char(1) == Some('=') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: NotEqual, pos }
      } else {
        self.advance()
        TokenWithPos::{ token: Exclamation, pos }
      }
    Some('<') =>
      if self.peek_char(1) == Some('=') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: LessEqual, pos }
      } else {
        self.advance()
        TokenWithPos::{ token: Less, pos }
      }
    Some('>') =>
      if self.peek_char(1) == Some('=') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: GreaterEqual, pos }
      } else {
        self.advance()
        TokenWithPos::{ token: Greater, pos }
      }
    Some('&') =>
      if self.peek_char(1) == Some('&') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: And, pos }
      } else {
        let c = self.current_char().unwrap()
        self.advance()
        TokenWithPos::{ token: Unknown(c), pos }
      }
    Some('|') =>
      if self.peek_char(1) == Some('|') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: Or, pos }
      } else {
        let c = self.current_char().unwrap()
        self.advance()
        TokenWithPos::{ token: Unknown(c), pos }
      }
    Some(':') =>
      if self.peek_char(1) == Some(':') {
        self.advance()
        self.advance()
        TokenWithPos::{ token: DoubleColon, pos }
      } else {
        self.advance()
        TokenWithPos::{ token: Colon, pos }
      }
    Some(c) if c >= '0' && c <= '9' => {
      let num = self.read_number()
      // 检查是否是浮点数
      if self.current_char() == Some('.') {
        self.advance() // 跳过 '.'
        let frac = self.read_number() // 小数部分
        // 手动计算浮点数值：整数部分 + 小数部分 / 10^(小数位数)
        let frac_val = frac.to_double()
        let mut divisor = 10.0
        while frac_val >= divisor {
          divisor = divisor * 10.0
        }
        let double_val = num.to_double() + frac_val / divisor
        TokenWithPos::{ token: DoubleLiteral(double_val), pos }
      } else {
        TokenWithPos::{ token: Number(num), pos }
      }
    }
    Some('_') => {
      self.advance()
      TokenWithPos::{ token: Wildcard, pos }
    }
    Some(c) if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' => {
      let word = self.read_identifier()
      let token = keyword_or_identifier(word)
      TokenWithPos::{ token, pos }
    }
    Some(c) => {
      self.advance()
      TokenWithPos::{ token: Unknown(c), pos }
    }
  }
}

///|
pub fn tokenize(input : String) -> Array[TokenWithPos] {
  let lexer = Lexer::new(input)
  let tokens = []
  while true {
    let token_with_pos = lexer.next_token()
    if token_with_pos.token == EOF {
      tokens.push(token_with_pos)
      break
    }
    tokens.push(token_with_pos)
  }
  tokens
}
