///|
/// 语法分析器
pub struct Parser {
  tokens : Array[@lexer.TokenWithPos]
  mut position : Int
}

///|
pub fn Parser::new(tokens : Array[@lexer.TokenWithPos]) -> Parser {
  { tokens, position: 0 }
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
      self.advance_parser()
      if !self.expect_token(LBracket) {
        return None
      }
      match self.parse_type() {
        Some(inner_type) =>
          if self.expect_token(RBracket) {
            Some(@ast.ArrayType(inner_type))
          } else {
            None
          }
        None => None
      }
    }
    LParen => {
      self.advance_parser()
      let types = []

      // 检查是否是空元组类型或单个类型分组
      if self.current_token() == RParen {
        self.advance_parser()
        return Some(@ast.UnitType)
      }

      // 解析第一个类型
      match self.parse_type() {
        Some(first_type) => {
          types.push(first_type)

          // 检查是否还有更多类型（元组）或者是函数类型
          while self.current_token() == Comma {
            self.advance_parser()
            match self.parse_type() {
              Some(t) => types.push(t)
              None => return None
            }
          }
          if !self.expect_token(RParen) {
            return None
          }

          // 检查是否是函数类型
          if self.current_token() == Arrow {
            self.advance_parser()
            match self.parse_type() {
              Some(return_type) => Some(@ast.FunctionType(types, return_type))
              None => None
            }
          } else if types.length() == 1 {
            // 单个类型的分组
            Some(types[0])
          } else {
            // 元组类型
            Some(@ast.TupleType(types))
          }
        }
        None => None
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
  } else {
    self.parse_get_or_apply_expr()
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
    _ => None
  }
}

///|
fn parse_block_expr(self : Parser) -> @ast.Expr? {
  if !self.expect_token(LCurlyBracket) {
    return None
  }
  let stmts = []
  let mut final_expr = None
  while self.current_token() != RCurlyBracket && self.current_token() != EOF {
    // 暂时先只支持表达式，语句解析稍后添加
    match self.parse_expr() {
      Some(expr) => {
        final_expr = Some(expr)
        break
      }
      None => return None
    }
  }
  if self.expect_token(RCurlyBracket) {
    Some(BlockExpr(stmts, final_expr))
  } else {
    None
  }
}

///|
pub fn parse_program(self : Parser) -> @ast.Program? {
  let declarations = []
  while self.current_token() != EOF {
    match self.parse_top_level() {
      Some(decl) => declarations.push(decl)
      None => return None
    }
  }
  Some(@ast.Program::{ declarations, })
}

///|
fn parse_top_level(self : Parser) -> @ast.TopLevel? {
  match self.current_token() {
    Let => self.parse_top_let_decl()
    Fn => self.parse_toplevel_fn_decl()
    _ => None
  }
}

///|
fn parse_top_let_decl(self : Parser) -> @ast.TopLevel? {
  if !self.expect_token(Let) {
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
      if self.expect_token(Assign) {
        match self.parse_expr() {
          Some(expr) =>
            if self.expect_token(Semicolon) {
              Some(@ast.TopLetDecl(name, type_annotation, expr))
            } else {
              None
            }
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
fn parse_toplevel_fn_decl(self : Parser) -> @ast.TopLevel? {
  if !self.expect_token(Fn) {
    return None
  }
  match self.current_token() {
    Main => {
      self.advance_parser()
      match self.parse_block_expr() {
        Some(body) => Some(MainFnDecl(body))
        None => None
      }
    }
    @lexer.Identifier(name) => {
      self.advance_parser()
      if self.expect_token(LParen) {
        let params = []

        // 解析参数列表
        if self.current_token() != RParen {
          match self.parse_param() {
            Some(param) => {
              params.push(param)
              while self.current_token() == Comma {
                self.advance_parser()
                match self.parse_param() {
                  Some(param) => params.push(param)
                  None => return None
                }
              }
            }
            None => return None
          }
        }
        if self.expect_token(RParen) && self.expect_token(Arrow) {
          match self.parse_type() {
            Some(return_type) =>
              match self.parse_block_expr() {
                Some(body) => Some(TopFnDecl(name, params, return_type, body))
                None => None
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
    _ => None
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
