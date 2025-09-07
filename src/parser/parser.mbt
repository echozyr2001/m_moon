///|
/// 解析错误信息
pub struct ParseError {
  message : String
  position : Int
  expected : String
  actual : String
  context : String
  source_lines : Array[String]
  error_line : Int
  error_column : Int
} derive(Show, Eq)

///|
/// 语法分析器
pub struct Parser {
  tokens : Array[@lexer.TokenWithPos]
  mut position : Int
  mut last_error : ParseError?
  source_lines : Array[String]
}

///|
pub fn Parser::new(tokens : Array[@lexer.TokenWithPos]) -> Parser {
  // 从tokens中提取源码行信息
  let source_lines = extract_source_lines_simple(tokens)
  { tokens, position: 0, last_error: None, source_lines }
}

///|
/// 从tokens中提取源码行信息（简化版本）
fn extract_source_lines_simple(
  tokens : Array[@lexer.TokenWithPos],
) -> Array[String] {
  if tokens.length() == 0 {
    return []
  }

  // 找到最大行号
  let max_line = tokens[tokens.length() - 1].pos.line
  let lines = @ref.new([])

  // 初始化所有行为空字符串
  for i = 0; i < max_line; i = i + 1 {
    lines.val = lines.val + [""]
  }

  // 填充每一行的内容
  for i = 0; i < tokens.length(); i = i + 1 {
    let token = tokens[i]
    let line_index = token.pos.line - 1
    if line_index < lines.val.length() {
      let current_line = lines.val[line_index]
      let token_str = token.token.to_string()
      // 在tokens之间添加空格，但避免在特殊字符前后添加不必要的空格
      let separator = if should_add_space_before(current_line, token_str) {
        " "
      } else {
        ""
      }
      let new_line = current_line + separator + token_str
      lines.val[line_index] = new_line
    }
  }
  lines.val
}

///|
/// 判断是否应该在token前添加空格
fn should_add_space_before(current_line : String, token_str : String) -> Bool {
  // 如果当前行为空，不需要添加空格
  if current_line == "" {
    return false
  }

  // 获取当前行的最后一个字符
  let last_char = if current_line.length() > 0 {
    current_line[current_line.length() - 1]
  } else {
    ' '
  }

  // 获取token的第一个字符
  let first_char = if token_str.length() > 0 { token_str[0] } else { ' ' }

  // 不需要空格的情况：
  // 1. 括号、大括号等配对符号
  // 2. 某些标点符号组合

  // 检查是否是括号类符号
  if (last_char == '(' || last_char == '[' || last_char == '{') ||
    first_char == ')' ||
    first_char == ']' ||
    first_char == '}' {
    return false
  }

  // 检查是否是某些标点符号组合
  if last_char == ',' || last_char == ';' || last_char == ':' {
    return false
  }

  // 其他情况通常需要空格
  true
}

///|
/// 记录解析错误
fn record_error(
  self : Parser,
  message : String,
  expected : String,
  context : String,
) -> Unit {
  let actual_token = if self.position < self.tokens.length() {
    self.tokens[self.position].token.to_string()
  } else {
    "EOF"
  }

  // 获取错误位置的行列信息
  let (error_line, error_column) = if self.position < self.tokens.length() {
    let token = self.tokens[self.position]
    (token.pos.line, token.pos.column)
    // 如果是EOF，使用最后一个token的位置
  } else if self.tokens.length() > 0 {
    let last_token = self.tokens[self.tokens.length() - 1]
    (last_token.pos.line, last_token.pos.column + 1)
  } else {
    (1, 1)
  }

  // 获取源码上下文（错误行前后各2行）
  let context_lines = get_source_context(self.source_lines, error_line)
  let error = ParseError::{
    message,
    position: self.position,
    expected,
    actual: actual_token,
    context,
    source_lines: context_lines,
    error_line,
    error_column,
  }
  self.last_error = Some(error)
}

///|
/// 获取源码上下文
fn get_source_context(
  source_lines : Array[String],
  error_line : Int,
) -> Array[String] {
  let start_line = if error_line > 2 { error_line - 2 } else { 1 }
  let end_line = if error_line + 2 <= source_lines.length() {
    error_line + 2
  } else {
    source_lines.length()
  }
  let context = @ref.new([])
  for i = start_line - 1; i < end_line; i = i + 1 {
    if i < source_lines.length() {
      context.val = context.val + [source_lines[i]]
    }
  }
  context.val
}

///|
/// 获取最后一个错误
pub fn get_last_error(self : Parser) -> ParseError? {
  self.last_error
}

///|
/// 清除错误
fn clear_error(self : Parser) -> Unit {
  self.last_error = None
}

///|
fn current_token(self : Parser) -> @lexer.Token {
  if self.position >= self.tokens.length() {
    EOF
  } else {
    self.tokens[self.position].token
  }
}

///|
fn advance_parser(self : Parser) -> Unit {
  if self.position < self.tokens.length() {
    self.position = self.position + 1
  }
}

///|
fn expect_token(self : Parser, expected : @lexer.Token) -> Bool {
  if self.current_token() == expected {
    self.advance_parser()
    true
  } else {
    false
  }
}

///|
/// 期望token并记录错误
fn expect_token_with_error(
  self : Parser,
  expected : @lexer.Token,
  context : String,
) -> Bool {
  if self.current_token() == expected {
    self.advance_parser()
    true
  } else {
    self.record_error(
      "期望token: " + expected.to_string(),
      expected.to_string(),
      context,
    )
    false
  }
}

// 解析类型

///|
pub fn parse_type(self : Parser) -> @ast.Type? {
  match self.current_token() {
    Unit => {
      self.advance_parser()
      Some(@ast.UnitType)
    }
    Bool => {
      self.advance_parser()
      Some(@ast.BoolType)
    }
    Int => {
      self.advance_parser()
      Some(@ast.IntType)
    }
    Double => {
      self.advance_parser()
      Some(@ast.DoubleType)
    }
    Array => {
      // println("Debug: Parsing Array type")
      self.advance_parser()
      // println("Debug: After advance_parser")
      if !self.expect_token(LBracket) {
        // println("Debug: Failed to find LBracket")
        return None
      }
      // println("Debug: Found LBracket, parsing inner type")
      match self.parse_type() {
        Some(inner_type) =>
          // println("Debug: Parsed inner type successfully")
          if self.expect_token(RBracket) {
            // println("Debug: Array type parsing successful")
            Some(@ast.ArrayType(inner_type))
          } else {
            // println("Debug: Failed to find RBracket")
            None
          }
        None =>
          // println("Debug: Failed to parse inner type")
          None
      }
    }
    LParen => {
      // println("Debug: Parsing tuple type")
      self.advance_parser()
      let types = []

      // 检查是否是空元组类型或单个类型分组
      if self.current_token() == RParen {
        // println("Debug: Empty tuple, returning UnitType")
        self.advance_parser()
        return Some(@ast.UnitType)
      }

      // 解析第一个类型
      // println("Debug: Parsing first type in tuple")
      match self.parse_type() {
        Some(first_type) => {
          // println("Debug: First type parsed successfully")
          types.push(first_type)

          // 检查是否还有更多类型（元组）或者是函数类型
          while self.current_token() == Comma {
            // println("Debug: Found comma, parsing next type")
            self.advance_parser()
            match self.parse_type() {
              Some(t) =>
                // println("Debug: Next type parsed successfully")
                types.push(t)
              None =>
                // println("Debug: Failed to parse next type in tuple")
                return None
            }
          }
          // println("Debug: Expecting closing paren")
          if !self.expect_token(RParen) {
            // println("Debug: Failed to find closing paren")
            return None
          }

          // 检查是否是函数类型
          if self.current_token() == Arrow {
            // println("Debug: Found arrow, parsing function type")
            self.advance_parser()
            match self.parse_type() {
              Some(return_type) =>
                // println("Debug: Function type parsed successfully")
                Some(@ast.FunctionType(types, return_type))
              None =>
                // println("Debug: Failed to parse return type")
                None
            }
          } else if types.length() == 1 {
            // 单个类型的分组
            // println("Debug: Single type grouping")
            Some(types[0])
          } else {
            // 元组类型
            // println("Debug: Tuple type with multiple elements")
            Some(@ast.TupleType(types))
          }
        }
        None =>
          // println("Debug: Failed to parse first type in tuple")
          None
      }
    }
    @lexer.UpperIdentifier(name) => {
      self.advance_parser()
      // 检查是否是泛型类型
      if self.current_token() == LBracket {
        self.advance_parser()
        match self.parse_type() {
          Some(inner_type) =>
            if self.expect_token(RBracket) {
              Some(@ast.GenericType(name, inner_type))
            } else {
              None
            }
          None => None
        }
      } else {
        Some(@ast.UserDefinedType(name))
      }
    }
    _ => None
  }
}

// 解析表达式（递归下降）

///|
pub fn parse_expr(self : Parser) -> @ast.Expr? {
  self.parse_or_expr()
}

///|
fn parse_or_expr(self : Parser) -> @ast.Expr? {
  match self.parse_and_expr() {
    Some(left) => {
      let mut result = left
      while self.current_token() == Or {
        self.advance_parser()
        match self.parse_and_expr() {
          Some(right) =>
            result = @ast.BinaryOp(@ast.BinaryOperator::Or, result, right)
          None => return None
        }
      }
      Some(result)
    }
    None => None
  }
}

///|
fn parse_and_expr(self : Parser) -> @ast.Expr? {
  match self.parse_cmp_expr() {
    Some(left) => {
      let mut result = left
      while self.current_token() == And {
        self.advance_parser()
        match self.parse_cmp_expr() {
          Some(right) =>
            result = @ast.BinaryOp(@ast.BinaryOperator::And, result, right)
          None => return None
        }
      }
      Some(result)
    }
    None => None
  }
}

///|
fn parse_cmp_expr(self : Parser) -> @ast.Expr? {
  match self.parse_add_sub_expr() {
    Some(left) =>
      match self.current_token() {
        Equal => {
          self.advance_parser()
          match self.parse_add_sub_expr() {
            Some(right) =>
              Some(@ast.BinaryOp(@ast.BinaryOperator::Equal, left, right))
            None => None
          }
        }
        NotEqual => {
          self.advance_parser()
          match self.parse_add_sub_expr() {
            Some(right) =>
              Some(@ast.BinaryOp(@ast.BinaryOperator::NotEqual, left, right))
            None => None
          }
        }
        Less => {
          self.advance_parser()
          match self.parse_add_sub_expr() {
            Some(right) =>
              Some(@ast.BinaryOp(@ast.BinaryOperator::Less, left, right))
            None => None
          }
        }
        Greater => {
          self.advance_parser()
          match self.parse_add_sub_expr() {
            Some(right) =>
              Some(@ast.BinaryOp(@ast.BinaryOperator::Greater, left, right))
            None => None
          }
        }
        LessEqual => {
          self.advance_parser()
          match self.parse_add_sub_expr() {
            Some(right) =>
              Some(@ast.BinaryOp(@ast.BinaryOperator::LessEqual, left, right))
            None => None
          }
        }
        GreaterEqual => {
          self.advance_parser()
          match self.parse_add_sub_expr() {
            Some(right) =>
              Some(
                @ast.BinaryOp(@ast.BinaryOperator::GreaterEqual, left, right),
              )
            None => None
          }
        }
        _ => Some(left)
      }
    None => None
  }
}

///|
fn parse_add_sub_expr(self : Parser) -> @ast.Expr? {
  match self.parse_mul_div_expr() {
    Some(left) => {
      let mut result = left
      while true {
        match self.current_token() {
          Plus => {
            self.advance_parser()
            match self.parse_mul_div_expr() {
              Some(right) =>
                result = @ast.BinaryOp(@ast.BinaryOperator::Add, result, right)
              None => return None
            }
          }
          Minus => {
            self.advance_parser()
            match self.parse_mul_div_expr() {
              Some(right) =>
                result = @ast.BinaryOp(@ast.BinaryOperator::Sub, result, right)
              None => return None
            }
          }
          _ => break
        }
      }
      Some(result)
    }
    None => None
  }
}

///|
fn parse_mul_div_expr(self : Parser) -> @ast.Expr? {
  match self.parse_if_expr() {
    Some(left) => {
      let mut result = left
      while true {
        match self.current_token() {
          Multiply => {
            self.advance_parser()
            match self.parse_if_expr() {
              Some(right) =>
                result = @ast.BinaryOp(@ast.BinaryOperator::Mul, result, right)
              None => return None
            }
          }
          Divide => {
            self.advance_parser()
            match self.parse_if_expr() {
              Some(right) =>
                result = @ast.BinaryOp(@ast.BinaryOperator::Div, result, right)
              None => return None
            }
          }
          Modulo => {
            self.advance_parser()
            match self.parse_if_expr() {
              Some(right) =>
                result = @ast.BinaryOp(@ast.BinaryOperator::Mod, result, right)
              None => return None
            }
          }
          _ => break
        }
      }
      Some(result)
    }
    None => None
  }
}

///|
fn parse_if_expr(self : Parser) -> @ast.Expr? {
  if self.current_token() == If {
    self.advance_parser()
    match self.parse_expr() {
      Some(condition) =>
        match self.parse_block_expr() {
          Some(then_expr) => {
            let else_expr = if self.current_token() == Else {
              self.advance_parser()
              if self.current_token() == If {
                self.parse_if_expr()
              } else {
                self.parse_block_expr()
              }
            } else {
              None
            }
            Some(IfExpr(condition, then_expr, else_expr))
          }
          None => None
        }
      None => None
    }
  } else if self.current_token() == Match {
    self.parse_match_expr()
  } else {
    self.parse_get_or_apply_expr()
  }
}

///|
fn parse_match_expr(self : Parser) -> @ast.Expr? {
  if !self.expect_token(Match) {
    return None
  }
  match self.parse_expr() {
    Some(expr) =>
      if self.expect_token(LCurlyBracket) {
        let arms = []
        while self.current_token() != RCurlyBracket &&
              self.current_token() != EOF {
          match self.parse_match_arm() {
            Some(arm) => {
              arms.push(arm)
              // 可选的分号
              if self.current_token() == Semicolon {
                self.advance_parser()
              }
            }
            None => return None
          }
        }
        if self.expect_token(RCurlyBracket) {
          Some(@ast.MatchExpr(expr, arms))
        } else {
          None
        }
      } else {
        None
      }
    None => None
  }
}

///|
fn parse_match_arm(self : Parser) -> @ast.MatchArm? {
  match self.parse_pattern() {
    Some(pattern) =>
      if self.expect_token(MatchArrow) {
        match self.parse_expr() {
          Some(expr) => Some(@ast.MatchArm::{ pattern, expr })
          None => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
fn parse_pattern(self : Parser) -> @ast.Pattern? {
  match self.current_token() {
    Number(n) => {
      self.advance_parser()
      Some(@ast.NumberPattern(n))
    }
    True => {
      self.advance_parser()
      Some(@ast.BoolPattern(true))
    }
    False => {
      self.advance_parser()
      Some(@ast.BoolPattern(false))
    }
    Wildcard => {
      self.advance_parser()
      Some(@ast.WildcardPattern)
    }
    @lexer.Identifier(name) => {
      self.advance_parser()
      Some(@ast.VariablePattern(name))
    }
    LParen => {
      self.advance_parser()
      if self.current_token() == RParen {
        self.advance_parser()
        Some(@ast.TuplePattern([]))
      } else {
        let patterns = []
        match self.parse_pattern() {
          Some(pattern) => {
            patterns.push(pattern)
            while self.current_token() == Comma {
              self.advance_parser()
              match self.parse_pattern() {
                Some(p) => patterns.push(p)
                None => return None
              }
            }
            if self.expect_token(RParen) {
              Some(@ast.TuplePattern(patterns))
            } else {
              None
            }
          }
          None => None
        }
      }
    }
    @lexer.UpperIdentifier(type_name) => {
      self.advance_parser()
      let variant_name = if self.current_token() == DoubleColon {
        self.advance_parser()
        match self.current_token() {
          @lexer.UpperIdentifier(name) => {
            self.advance_parser()
            Some(name)
          }
          _ => return None
        }
      } else {
        None
      }
      let patterns = if self.current_token() == LParen {
        self.advance_parser()
        let pats = []
        if self.current_token() != RParen {
          match self.parse_pattern() {
            Some(pattern) => {
              pats.push(pattern)
              while self.current_token() == Comma {
                self.advance_parser()
                match self.parse_pattern() {
                  Some(p) => pats.push(p)
                  None => return None
                }
              }
            }
            None => return None
          }
        }
        if self.expect_token(RParen) {
          pats
        } else {
          return None
        }
      } else {
        []
      }
      Some(@ast.EnumVariantPattern(type_name, variant_name, patterns))
    }
    _ => None
  }
}

///|
fn parse_get_or_apply_expr(self : Parser) -> @ast.Expr? {
  match self.parse_value_expr() {
    Some(expr) => {
      let mut result = expr
      while true {
        match self.current_token() {
          LBracket => {
            self.advance_parser()
            match self.parse_expr() {
              Some(index) =>
                if self.expect_token(RBracket) {
                  result = ArrayAccess(result, index)
                } else {
                  return None
                }
              None => return None
            }
          }
          LParen => {
            self.advance_parser()
            let args = []
            if self.current_token() != RParen {
              match self.parse_expr() {
                Some(arg) => {
                  args.push(arg)
                  while self.current_token() == Comma {
                    self.advance_parser()
                    match self.parse_expr() {
                      Some(arg) => args.push(arg)
                      None => return None
                    }
                  }
                }
                None => return None
              }
            }
            if self.expect_token(RParen) {
              result = FunctionCall(result, args)
            } else {
              return None
            }
          }
          Dot => {
            self.advance_parser()
            match self.current_token() {
              @lexer.Identifier(field_name) => {
                self.advance_parser()
                result = FieldAccess(result, field_name)
              }
              _ => return None
            }
          }
          _ => break
        }
      }
      Some(result)
    }
    None => None
  }
}

///|
fn parse_value_expr(self : Parser) -> @ast.Expr? {
  // println(
  //   "DEBUG: parse_value_expr called with token: " +
  //   self.current_token().to_string(),
  // )
  match self.current_token() {
    LParen => {
      self.advance_parser()

      // 检查单元类型 ()
      if self.current_token() == RParen {
        self.advance_parser()
        return Some(@ast.UnitLiteral)
      }

      // 解析第一个表达式
      match self.parse_expr() {
        Some(first_expr) =>
          // 检查是否是元组
          if self.current_token() == Comma {
            let exprs = [first_expr]
            while self.current_token() == Comma {
              self.advance_parser()
              match self.parse_expr() {
                Some(expr) => exprs.push(expr)
                None => return None
              }
            }
            if self.expect_token(RParen) {
              Some(TupleExpr(exprs))
            } else {
              None
            }
            // 分组表达式
          } else if self.expect_token(RParen) {
            Some(GroupExpr(first_expr))
          } else {
            None
          }
        None => None
      }
    }
    LBracket => {
      self.advance_parser()
      let exprs = []
      if self.current_token() != RBracket {
        match self.parse_expr() {
          Some(expr) => {
            exprs.push(expr)
            while self.current_token() == Comma {
              self.advance_parser()
              match self.parse_expr() {
                Some(expr) => exprs.push(expr)
                None => return None
              }
            }
          }
          None => return None
        }
      }
      if self.expect_token(RBracket) {
        Some(ArrayExpr(exprs))
      } else {
        None
      }
    }
    LCurlyBracket => self.parse_block_expr()
    True => {
      self.advance_parser()
      Some(@ast.BoolLiteral(true))
    }
    False => {
      self.advance_parser()
      Some(@ast.BoolLiteral(false))
    }
    Number(n) => {
      self.advance_parser()
      Some(@ast.IntLiteral(n))
    }
    DoubleLiteral(d) => {
      self.advance_parser()
      Some(@ast.DoubleLiteral(d))
    }
    @lexer.Identifier(name) => {
      self.advance_parser()
      Some(@ast.Identifier(name))
    }
    Minus => {
      self.advance_parser()
      match self.parse_value_expr() {
        Some(expr) => Some(@ast.UnaryOp(Negate, expr))
        None => None
      }
    }
    Exclamation => {
      self.advance_parser()
      match self.parse_expr() {
        Some(expr) => Some(@ast.UnaryOp(Not, expr))
        None => None
      }
    }
    Array => {
      self.advance_parser()
      if self.expect_token(DoubleColon) &&
        self.expect_token(@lexer.Identifier("make")) {
        if self.expect_token(LParen) {
          match self.parse_expr() {
            Some(size) =>
              if self.expect_token(Comma) {
                match self.parse_expr() {
                  Some(value) =>
                    if self.expect_token(RParen) {
                      Some(ArrayMake(size, value))
                    } else {
                      None
                    }
                  None => None
                }
              } else {
                None
              }
            None => None
          }
        } else {
          None
        }
      } else {
        None
      }
    }
    @lexer.UpperIdentifier(name) => {
      // println("DEBUG: Processing UpperIdentifier(" + name + ")")
      self.advance_parser()
      // println(
      //   "DEBUG: After advance, current token: " +
      //   self.current_token().to_string(),
      // )
      // 检查是否是结构体构造或枚举构造
      if self.current_token() == DoubleColon {
        // println("DEBUG: Found DoubleColon")
        self.advance_parser()
        // println(
        //   "DEBUG: After DoubleColon, current token: " +
        //   self.current_token().to_string(),
        // )
        // 检查是结构体构造还是枚举构造
        match self.current_token() {
          LCurlyBracket => {
            // 结构体构造 StructName::{field: value, ...}
            // println("DEBUG: Parsing struct construction")
            self.advance_parser()
            let fields = []
            if self.current_token() != RCurlyBracket {
              match self.parse_struct_field_expr() {
                Some(field) => {
                  fields.push(field)
                  while self.current_token() == Comma {
                    self.advance_parser()
                    match self.parse_struct_field_expr() {
                      Some(f) => fields.push(f)
                      None => return None
                    }
                  }
                }
                None => return None
              }
            }
            if self.expect_token(RCurlyBracket) {
              Some(@ast.StructConstruct(name, fields))
            } else {
              None
            }
          }
          @lexer.UpperIdentifier(variant_name) => {
            // 枚举构造 EnumName::VariantName 或 EnumName::VariantName(args)
            // println(
            //   "DEBUG: Parsing enum construction with variant: " + variant_name,
            // )
            self.advance_parser()
            // 检查是否有参数
            if self.current_token() == LParen {
              self.advance_parser()
              let args = []
              if self.current_token() != RParen {
                match self.parse_expr() {
                  Some(arg) => {
                    args.push(arg)
                    while self.current_token() == Comma {
                      self.advance_parser()
                      match self.parse_expr() {
                        Some(arg) => args.push(arg)
                        None => return None
                      }
                    }
                  }
                  None => return None
                }
              }
              if self.expect_token(RParen) {
                Some(@ast.EnumConstruct(name, Some(variant_name), args))
              } else {
                None
              }
            } else {
              Some(@ast.EnumConstruct(name, Some(variant_name), []))
            }
          }
          _ =>
            // println(
            //   "DEBUG: Unexpected token after DoubleColon: " +
            //   self.current_token().to_string(),
            // )
            None
        }
        // 直接枚举构造（旧式语法，可能用于兼容）
      } else if self.current_token() == LParen {
        self.advance_parser()
        let args = []
        if self.current_token() != RParen {
          match self.parse_expr() {
            Some(arg) => {
              args.push(arg)
              while self.current_token() == Comma {
                self.advance_parser()
                match self.parse_expr() {
                  Some(arg) => args.push(arg)
                  None => return None
                }
              }
            }
            None => return None
          }
        }
        if self.expect_token(RParen) {
          Some(@ast.EnumConstruct(name, None, args))
        } else {
          None
        }
      } else {
        Some(@ast.EnumConstruct(name, None, []))
      }
    }
    Fn => self.parse_function_expr()
    _ =>
      // println(
      //   "DEBUG: parse_value_expr failed - unhandled token: " +
      //   self.current_token().to_string(),
      // )
      None
  }
}

///|
fn parse_struct_field_expr(self : Parser) -> (String, @ast.Expr)? {
  match self.current_token() {
    @lexer.Identifier(field_name) => {
      self.advance_parser()
      if self.expect_token(Colon) {
        match self.parse_expr() {
          Some(expr) => Some((field_name, expr))
          None => None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn parse_block_expr(self : Parser) -> @ast.Expr? {
  // println(
  //   "Debug: parse_block_expr - starting at position " +
  //   self.position.to_string(),
  // )
  if !self.expect_token(LCurlyBracket) {
    // println("Debug: Failed to find opening curly bracket")
    return None
  }
  // println("Debug: Found opening curly bracket")
  let stmts = []
  let mut final_expr = None
  while self.current_token() != RCurlyBracket && self.current_token() != EOF {
    // println("Debug: Parsing statement or expression in block")
    // 保存当前位置，用于回溯
    let saved_pos = self.position

    // 先尝试解析语句
    match self.parse_stmt() {
      Some(stmt) => {
        // println("Debug: Successfully parsed statement")
        stmts.push(stmt)
        continue
      }
      None => {
        // 保存当前的错误信息
        let saved_error = self.last_error
        // 回溯到保存的位置
        self.position = saved_pos

        // 尝试解析表达式作为最终表达式
        match self.parse_expr() {
          Some(expr) => {
            // 表达式解析成功，清除错误信息
            self.last_error = None
            final_expr = Some(expr)
            break
          }
          None => {
            // 表达式解析也失败，恢复原来的错误信息
            self.last_error = saved_error
            // 如果没有错误信息，记录一个通用错误
            if self.last_error == None {
              self.record_error(
                "无法解析块表达式中的语句或表达式", "语句或表达式",
                "块表达式内部",
              )
            }
            return None
          }
        }
      }
    }
  }
  // println("Debug: Expecting closing curly bracket")
  if self.expect_token(RCurlyBracket) {
    // println("Debug: Block expression parsed successfully")
    Some(BlockExpr(stmts, final_expr))
  } else {
    // println("Debug: Failed to find closing curly bracket")
    None
  }
}

///|
pub fn parse_program(self : Parser) -> @ast.Program? {
  self.clear_error()
  let declarations = []
  while self.current_token() != EOF {
    match self.parse_top_level() {
      Some(decl) => declarations.push(decl)
      None => {
        // 如果没有记录错误，记录一个通用错误
        if self.last_error == None {
          self.record_error(
            "无法解析顶层声明", "函数声明、let声明、结构体声明或枚举声明",
            "程序顶层",
          )
        }
        return None
      }
    }
  }
  Some(@ast.Program::{ declarations, })
}

///|
fn parse_top_level(self : Parser) -> @ast.TopLevel? {
  match self.current_token() {
    Let => self.parse_top_let_decl()
    Fn => self.parse_toplevel_fn_decl()
    Struct => self.parse_struct_decl()
    Enum => self.parse_enum_decl()
    _ => {
      self.record_error(
        "意外的token在程序顶层", "fn、let、struct或enum", "程序顶层声明",
      )
      None
    }
  }
}

///|
fn parse_top_let_decl(self : Parser) -> @ast.TopLevel? {
  if !self.expect_token_with_error(Let, "let声明") {
    return None
  }
  match self.current_token() {
    @lexer.Identifier(name) => {
      self.advance_parser()
      let type_annotation = if self.current_token() == Colon {
        self.advance_parser()
        self.parse_type()
      } else {
        None
      }
      if !self.expect_token_with_error(Assign, "let声明中的赋值") {
        return None
      }
      match self.parse_expr() {
        Some(expr) => {
          // 在文件末尾时，分号是可选的
          if self.current_token() == Semicolon {
            self.advance_parser()
          }
          Some(@ast.TopLetDecl(name, type_annotation, expr))
        }
        None => {
          self.record_error(
            "无法解析let声明的表达式",
            "表达式",
            "let " + name + " = ...",
          )
          None
        }
      }
    }
    Wildcard => {
      self.advance_parser()
      let type_annotation = if self.current_token() == Colon {
        self.advance_parser()
        self.parse_type()
      } else {
        None
      }
      if !self.expect_token_with_error(Assign, "let声明中的赋值") {
        return None
      }
      match self.parse_expr() {
        Some(expr) => {
          // 在文件末尾时，分号是可选的
          if self.current_token() == Semicolon {
            self.advance_parser()
          }
          Some(@ast.TopLetWildcardDecl(type_annotation, expr))
        }
        None => {
          self.record_error(
            "无法解析let声明的表达式", "表达式", "let _ = ...",
          )
          None
        }
      }
    }
    _ => {
      self.record_error(
        "let声明后需要变量名或通配符", "标识符或_", "let声明",
      )
      None
    }
  }
}

///|
fn parse_struct_decl(self : Parser) -> @ast.TopLevel? {
  if !self.expect_token(Struct) {
    return None
  }
  match self.current_token() {
    @lexer.UpperIdentifier(name) => {
      self.advance_parser()
      let generic_param = if self.current_token() == LBracket {
        self.advance_parser()
        match self.current_token() {
          @lexer.UpperIdentifier(param) => {
            self.advance_parser()
            if self.expect_token(RBracket) {
              Some(param)
            } else {
              return None
            }
          }
          _ => return None
        }
      } else {
        None
      }
      if self.expect_token(LCurlyBracket) {
        let fields = []
        while self.current_token() != RCurlyBracket &&
              self.current_token() != EOF {
          match self.parse_struct_field_decl() {
            Some(field) => {
              fields.push(field)
              // 期望分号（除了最后一个字段可选）
              if self.current_token() == Semicolon {
                self.advance_parser()
              } else if self.current_token() != RCurlyBracket {
                // 如果不是分号且不是结束大括号，则错误
                return None
              }
            }
            None =>
              // 字段解析失败
              return None
          }
        }
        if self.expect_token(RCurlyBracket) {
          Some(@ast.StructDecl(name, generic_param, fields))
        } else {
          None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn parse_struct_field_decl(self : Parser) -> @ast.StructField? {
  match self.current_token() {
    @lexer.Identifier(field_name) => {
      self.advance_parser()
      if self.expect_token(Colon) {
        match self.parse_type() {
          Some(field_type) =>
            Some(@ast.StructField::{ name: field_name, field_type })
          None => None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn parse_enum_decl(self : Parser) -> @ast.TopLevel? {
  if !self.expect_token(Enum) {
    return None
  }
  match self.current_token() {
    @lexer.UpperIdentifier(name) => {
      self.advance_parser()
      let generic_param = if self.current_token() == LBracket {
        self.advance_parser()
        match self.current_token() {
          @lexer.UpperIdentifier(param) => {
            self.advance_parser()
            if self.expect_token(RBracket) {
              Some(param)
            } else {
              return None
            }
          }
          _ => return None
        }
      } else {
        None
      }
      if self.expect_token(LCurlyBracket) {
        let variants = []
        while self.current_token() != RCurlyBracket &&
              self.current_token() != EOF {
          match self.parse_enum_variant_decl() {
            Some(variant) => {
              variants.push(variant)
              // 期望分号（除了最后一个变体可选）
              if self.current_token() == Semicolon {
                self.advance_parser()
              } else if self.current_token() != RCurlyBracket {
                // 如果不是分号且不是结束大括号，则错误
                return None
              }
            }
            None => return None
          }
        }
        if self.expect_token(RCurlyBracket) {
          Some(@ast.EnumDecl(name, generic_param, variants))
        } else {
          None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn parse_enum_variant_decl(self : Parser) -> @ast.EnumVariant? {
  match self.current_token() {
    @lexer.UpperIdentifier(variant_name) => {
      self.advance_parser()
      let field_types = if self.current_token() == LParen {
        self.advance_parser()
        let types = []
        if self.current_token() != RParen {
          match self.parse_type() {
            Some(t) => {
              types.push(t)
              while self.current_token() == Comma {
                self.advance_parser()
                match self.parse_type() {
                  Some(t) => types.push(t)
                  None => return None
                }
              }
            }
            None => return None
          }
        }
        if self.expect_token(RParen) {
          types
        } else {
          return None
        }
      } else {
        []
      }
      Some(@ast.EnumVariant::{ name: variant_name, field_types })
    }
    _ => None
  }
}

///|
fn parse_toplevel_fn_decl(self : Parser) -> @ast.TopLevel? {
  // println(
  //   "Debug: parse_toplevel_fn_decl - starting at position " +
  //   self.position.to_string(),
  // )
  if !self.expect_token(Fn) {
    // println("Debug: Failed to expect Fn token")
    return None
  }
  // println("Debug: Successfully parsed Fn token")
  match self.current_token() {
    Main => {
      // println("Debug: Parsing main function")
      self.advance_parser()
      // 检查是否有空参数列表 ()
      if self.current_token() == LParen {
        self.advance_parser()
        if !self.expect_token(RParen) {
          self.record_error(
            "main函数参数列表应为空", ")", "main函数声明",
          )
          return None
        }
      }
      match self.parse_block_expr() {
        Some(body) =>
          // println("Debug: Main function parsed successfully")
          Some(MainFnDecl(body))
        None =>
          // println("Debug: Failed to parse main function body")
          None
      }
    }
    @lexer.Identifier(name) => {
      // println("Debug: Parsing regular function: " + name)
      self.advance_parser()
      if self.expect_token(LParen) {
        // println("Debug: Found opening paren for parameters")
        let params = []

        // 解析参数列表
        if self.current_token() != RParen {
          // println("Debug: Parsing parameters")
          match self.parse_param() {
            Some(param) => {
              // println("Debug: Parsed first parameter")
              params.push(param)
              while self.current_token() == Comma {
                // println("Debug: Found comma, parsing next parameter")
                self.advance_parser()
                match self.parse_param() {
                  Some(param) =>
                    // println("Debug: Parsed additional parameter")
                    params.push(param)
                  None =>
                    // println("Debug: Failed to parse additional parameter")
                    return None
                }
              }
            }
            None =>
              // println("Debug: Failed to parse first parameter")
              return None
          }
        }
        // println("Debug: Expecting closing paren and arrow")
        if self.expect_token(RParen) && self.expect_token(Arrow) {
          // println("Debug: Found RParen and Arrow, parsing return type")
          match self.parse_type() {
            Some(return_type) =>
              // println("Debug: Parsed return type, now parsing function body")
              match self.parse_block_expr() {
                Some(body) =>
                  // println("Debug: Function parsed successfully")
                  Some(TopFnDecl(None, name, params, return_type, body))
                None =>
                  // println("Debug: Failed to parse function body")
                  None
              }
            None =>
              // println("Debug: Failed to parse return type")
              None
          }
        } else {
          // println("Debug: Failed to find RParen or Arrow")
          None
        }
      } else {
        // println("Debug: Failed to expect opening paren")
        None
      }
    }
    _ =>
      // println("Debug: Unexpected token in function declaration")
      None
  }
}

///|
fn parse_param(self : Parser) -> (String, @ast.Type)? {
  match self.current_token() {
    @lexer.Identifier(name) => {
      self.advance_parser()
      if self.expect_token(Colon) {
        match self.parse_type() {
          Some(param_type) => Some((name, param_type))
          None => None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn parse_stmt(self : Parser) -> @ast.Stmt? {
  // println(
  //   "Debug: parse_stmt - current token: " + self.current_token().to_string(),
  // )
  match self.current_token() {
    Let =>
      match self.parse_let_stmt() {
        Some(stmt) => Some(stmt)
        None =>
          // parse_let_stmt已经记录了错误，直接返回None
          None
      }
    While =>
      match self.parse_while_stmt() {
        Some(stmt) => Some(stmt)
        None => {
          self.record_error("无法解析while语句", "while语句", "语句")
          None
        }
      }
    Return =>
      match self.parse_return_stmt() {
        Some(stmt) => Some(stmt)
        None => {
          self.record_error(
            "无法解析return语句", "return语句", "语句",
          )
          None
        }
      }
    Fn =>
      match self.parse_fn_decl_stmt() {
        Some(stmt) => Some(stmt)
        None => {
          self.record_error(
            "无法解析函数声明语句", "函数声明语句", "语句",
          )
          None
        }
      }
    @lexer.Identifier(_) => {
      // 可能是赋值语句或表达式语句
      // 先尝试解析为赋值语句，如果失败则作为表达式语句
      let saved_pos = self.position
      match self.parse_assign_stmt() {
        Some(stmt) => Some(stmt)
        None => {
          self.position = saved_pos
          match self.parse_expr() {
            Some(expr) =>
              if self.expect_token(Semicolon) {
                Some(@ast.ExprStmt(expr))
              } else {
                None
              }
            None => None
          }
        }
      }
    }
    _ =>
      // 尝试解析表达式语句
      match self.parse_expr() {
        Some(expr) =>
          if self.expect_token(Semicolon) {
            Some(@ast.ExprStmt(expr))
          } else {
            None
          }
        None => None
      }
  }
}

///|
fn parse_binding(self : Parser) -> @ast.Binding? {
  match self.current_token() {
    @lexer.Identifier(name) => {
      self.advance_parser()
      Some(@ast.Variable(name))
    }
    Wildcard => {
      self.advance_parser()
      Some(@ast.Wildcard)
    }
    _ => None
  }
}

///|
fn parse_let_stmt(self : Parser) -> @ast.Stmt? {
  if !self.expect_token_with_error(Let, "let语句") {
    return None
  }

  // 检查是否是 mut 语句
  if self.current_token() == Mut {
    // println("Debug: Parsing mut let statement")
    self.advance_parser()
    match self.current_token() {
      @lexer.Identifier(name) => {
        self.advance_parser()
        let type_annotation = if self.current_token() == Colon {
          self.advance_parser()
          self.parse_type()
        } else {
          None
        }
        if !self.expect_token_with_error(Assign, "mut let语句中的赋值") {
          return None
        }
        match self.parse_expr() {
          Some(expr) =>
            if self.expect_token_with_error(Semicolon, "mut let语句结尾") {
              Some(@ast.LetMutStmt(name, type_annotation, expr))
            } else {
              None
            }
          None => {
            self.record_error(
              "无法解析mut let语句的表达式",
              "表达式",
              "let mut " + name + " = ...",
            )
            None
          }
        }
      }
      _ =>
        // println("Debug: Expected identifier after mut")
        None
    }
  } else if self.current_token() == LParen {
    // println("Debug: Parsing tuple destructuring let")
    // 元组解构
    self.advance_parser()
    let bindings = []
    match self.parse_binding() {
      Some(binding) => {
        bindings.push(binding)
        while self.current_token() == Comma {
          self.advance_parser()
          match self.parse_binding() {
            Some(b) => bindings.push(b)
            None => return None
          }
        }
        if !self.expect_token(RParen) {
          return None
        }
        let type_annotation = if self.current_token() == Colon {
          self.advance_parser()
          self.parse_type()
        } else {
          None
        }
        if self.expect_token(Assign) {
          match self.parse_expr() {
            Some(expr) =>
              if self.expect_token(Semicolon) {
                Some(@ast.LetTupleStmt(bindings, type_annotation, expr))
              } else {
                None
              }
            None => None
          }
        } else {
          None
        }
      }
      None => None
    }
  } else {
    // println("Debug: Parsing regular let statement")
    // 普通let语句
    match self.parse_binding() {
      Some(binding) => {
        // println("Debug: Parsed binding successfully")
        let type_annotation = if self.current_token() == Colon {
          self.advance_parser()
          self.parse_type()
        } else {
          None
        }
        if !self.expect_token_with_error(Assign, "let语句中的赋值") {
          return None
        }
        match self.parse_expr() {
          Some(expr) =>
            if self.expect_token_with_error(Semicolon, "let语句结尾") {
              Some(@ast.LetStmt(binding, type_annotation, expr))
            } else {
              None
            }
          None => {
            self.record_error(
              "无法解析let语句的表达式", "表达式", "let语句",
            )
            None
          }
        }
      }
      None => {
        self.record_error(
          "let语句后需要变量名或通配符", "标识符或_", "let语句",
        )
        None
      }
    }
  }
}

///|
fn parse_while_stmt(self : Parser) -> @ast.Stmt? {
  // println("Debug: parse_while_stmt starting")
  if !self.expect_token(While) {
    // println("Debug: Failed to expect While token")
    return None
  }
  match self.parse_expr() {
    Some(condition) =>
      // println("Debug: Parsed while condition successfully")
      if self.expect_token(LCurlyBracket) {
        // println("Debug: Found opening brace for while body")
        let stmts = []
        while self.current_token() != RCurlyBracket &&
              self.current_token() != EOF {
          match self.parse_stmt() {
            Some(stmt) =>
              // println("Debug: Parsed statement in while body")
              stmts.push(stmt)
            None =>
              // println("Debug: Failed to parse statement in while body")
              return None
          }
        }
        if self.expect_token(RCurlyBracket) {
          // println("Debug: While statement parsed successfully")
          Some(@ast.WhileStmt(condition, stmts))
        } else {
          // println("Debug: Failed to find closing brace for while")
          None
        }
      } else {
        // println("Debug: Failed to find opening brace for while")
        None
      }
    None =>
      // println("Debug: Failed to parse while condition")
      None
  }
}

///|
fn parse_return_stmt(self : Parser) -> @ast.Stmt? {
  if !self.expect_token(Return) {
    return None
  }
  let expr = if self.current_token() == Semicolon {
    None
  } else {
    self.parse_expr()
  }
  if self.expect_token(Semicolon) {
    Some(@ast.ReturnStmt(expr))
  } else {
    None
  }
}

///|
fn parse_fn_decl_stmt(self : Parser) -> @ast.Stmt? {
  if !self.expect_token(Fn) {
    return None
  }
  match self.current_token() {
    @lexer.Identifier(name) => {
      self.advance_parser()
      if self.expect_token(LParen) {
        let params = []
        if self.current_token() != RParen {
          match self.parse_nontop_param() {
            Some(param) => {
              params.push(param)
              while self.current_token() == Comma {
                self.advance_parser()
                match self.parse_nontop_param() {
                  Some(param) => params.push(param)
                  None => return None
                }
              }
            }
            None => return None
          }
        }
        if self.expect_token(RParen) {
          let return_type = if self.current_token() == Arrow {
            self.advance_parser()
            self.parse_type()
          } else {
            None
          }
          match self.parse_block_expr() {
            Some(body) => Some(@ast.FnDeclStmt(name, params, return_type, body))
            None => None
          }
        } else {
          None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn parse_nontop_param(self : Parser) -> (String, @ast.Type?)? {
  match self.current_token() {
    @lexer.Identifier(name) => {
      self.advance_parser()
      let type_annotation = if self.current_token() == Colon {
        self.advance_parser()
        self.parse_type()
      } else {
        None
      }
      Some((name, type_annotation))
    }
    _ => None
  }
}

///|
fn parse_assign_stmt(self : Parser) -> @ast.Stmt? {
  match self.parse_left_value() {
    Some(left_value) =>
      if self.expect_token(Assign) {
        match self.parse_expr() {
          Some(expr) =>
            if self.expect_token(Semicolon) {
              Some(@ast.AssignStmt(left_value, expr))
            } else {
              None
            }
          None => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
fn parse_left_value(self : Parser) -> @ast.LeftValue? {
  match self.current_token() {
    @lexer.Identifier(name) => {
      self.advance_parser()
      let mut result = @ast.LeftValue::Variable(name)
      while true {
        match self.current_token() {
          LBracket => {
            self.advance_parser()
            match self.parse_expr() {
              Some(index) =>
                if self.expect_token(RBracket) {
                  result = @ast.ArrayAccess(result, index)
                } else {
                  return None
                }
              None => return None
            }
          }
          Dot => {
            self.advance_parser()
            match self.current_token() {
              @lexer.Identifier(field_name) => {
                self.advance_parser()
                result = @ast.FieldAccess(result, field_name)
              }
              _ => return None
            }
          }
          _ => break
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn parse_function_expr(self : Parser) -> @ast.Expr? {
  if !self.expect_token(Fn) {
    return None
  }
  // 函数表达式直接以 ( 开始，没有函数名
  if self.expect_token(LParen) {
    let params = []
    if self.current_token() != RParen {
      match self.parse_nontop_param() {
        Some(param) => {
          params.push(param)
          while self.current_token() == Comma {
            self.advance_parser()
            match self.parse_nontop_param() {
              Some(param) => params.push(param)
              None => return None
            }
          }
        }
        None => return None
      }
    }
    if self.expect_token(RParen) {
      let return_type = if self.current_token() == Arrow {
        self.advance_parser()
        self.parse_type()
      } else {
        None
      }
      match self.parse_block_expr() {
        Some(body) => Some(@ast.FunctionExpr(params, return_type, body))
        None => None
      }
    } else {
      None
    }
  } else {
    None
  }
}
