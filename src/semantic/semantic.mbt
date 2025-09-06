///|
/// 语义分析器
pub struct SemanticAnalyzer {
  mut scopes : Array[Scope]
  mut current_function : String?
  mut errors : Array[String]
}

///|
/// 作用域
struct Scope {
  variables : Map[String, Type]
  functions : Map[String, FunctionType]
}

///|
/// 类型定义
pub enum Type {
  Int
  Double
  Bool
  Unit
  Array(Type)
  Function(Array[Type], Type) // 参数类型列表, 返回类型
} derive(Eq, Show)

///|
/// 函数类型
priv struct FunctionType {
  params : Array[Type]
  return_type : Type
}

///|
/// 语义分析结果
pub struct SemanticResult {
  typed_program : @ast.Program
  errors : Array[String]
}

///|
/// 创建新的语义分析器
pub fn SemanticAnalyzer::new() -> SemanticAnalyzer {
  let global_scope = Scope::{ variables: Map::new(), functions: Map::new() }
  SemanticAnalyzer::{
    scopes: [global_scope],
    current_function: None,
    errors: [],
  }
}

///|
/// 分析程序
pub fn analyze(
  self : SemanticAnalyzer,
  program : @ast.Program,
) -> SemanticResult {
  self.analyze_program_internal(program)
  SemanticResult::{ typed_program: program, errors: self.errors }
}

///|
/// 分析程序
fn analyze_program_internal(
  self : SemanticAnalyzer,
  program : @ast.Program,
) -> Unit {
  // 第一遍：收集所有函数声明
  for decl in program.declarations {
    match decl {
      @ast.TopFnDecl(_generic_param, name, params, return_type, _) => {
        let param_types = params.map(fn(p) { self.ast_type_to_type(p.1) })
        let ret_type = self.ast_type_to_type(return_type)
        let func_type = FunctionType::{
          params: param_types,
          return_type: ret_type,
        }
        self.scopes[0].functions.set(name, func_type)
      }
      @ast.MainFnDecl(_) => {
        let func_type = FunctionType::{ params: [], return_type: Unit }
        self.scopes[0].functions.set("main", func_type)
      }
      @ast.StructDecl(_, _, _) =>
        // 结构体声明不需要类型检查
        ()
      @ast.EnumDecl(_, _, _) =>
        // 枚举声明不需要类型检查
        ()
      _ => ()
    }
  }

  // 第二遍：分析函数体和顶层声明
  for decl in program.declarations {
    self.analyze_declaration(decl)
  }
}

///|
/// 分析声明
fn analyze_declaration(self : SemanticAnalyzer, decl : @ast.TopLevel) -> Unit {
  match decl {
    @ast.TopFnDecl(_generic_param, name, params, return_type, body) => {
      self.current_function = Some(name)
      self.push_scope()

      // 添加参数到作用域
      for param in params {
        let param_type = self.ast_type_to_type(param.1)
        self.add_variable(param.0, param_type)
      }
      let expected_return = self.ast_type_to_type(return_type)
      let actual_return = self.analyze_expression(body)
      if not(self.types_compatible(actual_return, expected_return)) {
        self.add_error(
          "函数 '" +
          name +
          "' 返回类型不匹配，期望 " +
          expected_return.to_string() +
          "，实际 " +
          actual_return.to_string(),
        )
      }
      self.pop_scope()
      self.current_function = None
    }
    @ast.StructDecl(_, _, _) =>
      // 结构体声明不需要类型检查
      ()
    @ast.EnumDecl(_, _, _) =>
      // 枚举声明不需要类型检查
      ()
    @ast.MainFnDecl(body) => {
      self.current_function = Some("main")
      self.push_scope()
      let actual_return = self.analyze_expression(body)
      if not(self.types_compatible(actual_return, Unit)) {
        self.add_error("main 函数必须返回 Unit 类型")
      }
      self.pop_scope()
      self.current_function = None
    }
    @ast.TopLetDecl(name, type_annotation, expr) => {
      let expr_type = self.analyze_expression(expr)
      let expected_type = match type_annotation {
        Some(t) => self.ast_type_to_type(t)
        None => expr_type
      }
      if not(self.types_compatible(expr_type, expected_type)) {
        self.add_error("变量 '" + name + "' 类型不匹配")
      }
      self.add_variable(name, expected_type)
    }
    @ast.TopLetWildcardDecl(type_annotation, expr) => {
      let expr_type = self.analyze_expression(expr)
      let expected_type = match type_annotation {
        Some(t) => self.ast_type_to_type(t)
        None => expr_type
      }
      if not(self.types_compatible(expr_type, expected_type)) {
        self.add_error("通配符 let 语句类型不匹配")
      }
      // 通配符不需要添加到符号表中
    }
  }
}

///|
/// 分析语句
fn analyze_statement(self : SemanticAnalyzer, stmt : @ast.Stmt) -> Type {
  match stmt {
    @ast.ExprStmt(expr) => self.analyze_expression(expr)
    @ast.LetStmt(binding, type_annotation, expr) => {
      let expr_type = self.analyze_expression(expr)
      let expected_type = match type_annotation {
        Some(t) => self.ast_type_to_type(t)
        None => expr_type
      }
      match binding {
        @ast.Binding::Variable(name) => {
          if not(self.types_compatible(expr_type, expected_type)) {
            self.add_error("变量 '" + name + "' 类型不匹配")
          }
          self.add_variable(name, expected_type)
        }
        @ast.Binding::Wildcard =>
          // 通配符不需要类型检查
          ()
      }
      Unit
    }
    @ast.LetMutStmt(name, type_annotation, expr) => {
      let expr_type = self.analyze_expression(expr)
      let expected_type = match type_annotation {
        Some(t) => self.ast_type_to_type(t)
        None => expr_type
      }
      if not(self.types_compatible(expr_type, expected_type)) {
        self.add_error("可变变量 '" + name + "' 类型不匹配")
      }
      self.add_variable(name, expected_type)
      Unit
    }
    @ast.AssignStmt(target, expr) => {
      let target_type = self.analyze_left_value(target)
      let expr_type = self.analyze_expression(expr)
      if not(self.types_compatible(expr_type, target_type)) {
        self.add_error("赋值类型不匹配")
      }
      Unit
    }
    @ast.ReturnStmt(expr_opt) =>
      match expr_opt {
        Some(expr) => self.analyze_expression(expr)
        None => Unit
      }
    @ast.WhileStmt(condition, body) => {
      let cond_type = self.analyze_expression(condition)
      if not(self.types_compatible(cond_type, Bool)) {
        self.add_error("while 循环条件必须是布尔类型")
      }
      self.push_scope()
      for stmt in body {
        ignore(self.analyze_statement(stmt))
      }
      self.pop_scope()
      Unit
    }
    @ast.FnDeclStmt(name, params, return_type, body) => {
      // 局部函数声明
      let param_types = params.map(fn(p) {
        match p.1 {
          Some(t) => self.ast_type_to_type(t)
          None => {
            self.add_error("函数参数必须有类型注解")
            Unit
          }
        }
      })
      let ret_type = match return_type {
        Some(t) => self.ast_type_to_type(t)
        None => Unit
      }
      let func_type = FunctionType::{
        params: param_types,
        return_type: ret_type,
      }
      self.add_function(name, func_type)

      // 分析函数体
      self.push_scope()
      for param in params {
        match param.1 {
          Some(t) => self.add_variable(param.0, self.ast_type_to_type(t))
          None => ()
        }
      }
      let actual_return = self.analyze_expression(body)
      if not(self.types_compatible(actual_return, ret_type)) {
        self.add_error("局部函数 '" + name + "' 返回类型不匹配")
      }
      self.pop_scope()
      Unit
    }
    @ast.LetTupleStmt(bindings, _type_annotation, expr) => {
      ignore(self.analyze_expression(expr))
      // 简化处理：假设所有变量都是Unit类型
      for binding in bindings {
        match binding {
          @ast.Binding::Variable(name) => self.add_variable(name, Unit)
          @ast.Binding::Wildcard =>
            // 通配符不需要添加到作用域
            ()
        }
      }
      Unit
    }
  }
}

///|
/// 分析左值
fn analyze_left_value(self : SemanticAnalyzer, lvalue : @ast.LeftValue) -> Type {
  match lvalue {
    @ast.Variable(name) =>
      match self.lookup_variable(name) {
        Some(t) => t
        None => {
          self.add_error("未定义的变量: " + name)
          Unit
        }
      }
    @ast.ArrayAccess(lvalue, index) => {
      let array_type = self.analyze_left_value(lvalue)
      let index_type = self.analyze_expression(index)
      if not(self.types_compatible(index_type, Int)) {
        self.add_error("数组索引必须是整数类型")
      }
      match array_type {
        Array(element_type) => element_type
        _ => {
          self.add_error("只能对数组类型进行索引访问")
          Unit
        }
      }
    }
    @ast.FieldAccess(target, _field_name) => {
      // 简化处理：假设字段访问返回Int类型
      ignore(self.analyze_left_value(target))
      Int
    }
  }
} ///|

///|
/// 分析表达式
fn analyze_expression(self : SemanticAnalyzer, expr : @ast.Expr) -> Type {
  match expr {
    @ast.IntLiteral(_) => Int
    @ast.DoubleLiteral(_) => Double
    @ast.BoolLiteral(_) => Bool
    @ast.UnitLiteral => Unit
    @ast.Identifier(name) =>
      match self.lookup_variable(name) {
        Some(t) => t
        None => {
          self.add_error("未定义的变量: " + name)
          Unit
        }
      }
    @ast.BinaryOp(op, left, right) => {
      let left_type = self.analyze_expression(left)
      let right_type = self.analyze_expression(right)
      self.analyze_binary_op(left_type, op, right_type)
    }
    @ast.UnaryOp(op, expr) => {
      let expr_type = self.analyze_expression(expr)
      self.analyze_unary_op(op, expr_type)
    }
    @ast.FunctionCall(func_expr, args) =>
      // 简化处理：假设func_expr是Identifier
      match func_expr {
        @ast.Identifier(name) =>
          match self.lookup_function(name) {
            Some(func_type) => {
              if args.length() != func_type.params.length() {
                self.add_error("函数 '" + name + "' 参数数量不匹配")
                return Unit
              }
              for i = 0; i < args.length(); i = i + 1 {
                let arg_type = self.analyze_expression(args[i])
                let expected_type = func_type.params[i]
                if not(self.types_compatible(arg_type, expected_type)) {
                  self.add_error(
                    "函数 '" +
                    name +
                    "' 第 " +
                    (i + 1).to_string() +
                    " 个参数类型不匹配",
                  )
                }
              }
              func_type.return_type
            }
            None => {
              self.add_error("未定义的函数: " + name)
              Unit
            }
          }
        _ => {
          self.add_error("不支持的函数调用形式")
          Unit
        }
      }
    @ast.ArrayAccess(array, index) => {
      let array_type = self.analyze_expression(array)
      let index_type = self.analyze_expression(index)
      if not(self.types_compatible(index_type, Int)) {
        self.add_error("数组索引必须是整数类型")
      }
      match array_type {
        Array(element_type) => element_type
        _ => {
          self.add_error("只能对数组类型进行索引访问")
          Unit
        }
      }
    }
    @ast.ArrayMake(size, init) => {
      let size_type = self.analyze_expression(size)
      let init_type = self.analyze_expression(init)
      if not(self.types_compatible(size_type, Int)) {
        self.add_error("数组大小必须是整数类型")
      }
      Array(init_type)
    }
    @ast.IfExpr(condition, then_branch, else_branch) => {
      let cond_type = self.analyze_expression(condition)
      if not(self.types_compatible(cond_type, Bool)) {
        self.add_error("if 条件必须是布尔类型")
      }
      let then_type = self.analyze_expression(then_branch)
      match else_branch {
        Some(else_expr) => {
          let else_type = self.analyze_expression(else_expr)
          if not(self.types_compatible(then_type, else_type)) {
            self.add_error("if-else 分支类型不匹配")
          }
          then_type
        }
        None => Unit
      }
    }
    @ast.BlockExpr(stmts, final_expr) => {
      self.push_scope()
      for stmt in stmts {
        ignore(self.analyze_statement(stmt))
      }
      let result_type = match final_expr {
        Some(expr) => self.analyze_expression(expr)
        None => Unit
      }
      self.pop_scope()
      result_type
    }
    @ast.GroupExpr(expr) => self.analyze_expression(expr)
    @ast.TupleExpr(exprs) => {
      // 简化处理：返回Unit类型
      for expr in exprs {
        ignore(self.analyze_expression(expr))
      }
      Unit
    }
    @ast.ArrayExpr(exprs) => {
      if exprs.length() == 0 {
        self.add_error("空数组需要类型注解")
        return Unit
      }
      let first_type = self.analyze_expression(exprs[0])
      for i = 1; i < exprs.length(); i = i + 1 {
        let elem_type = self.analyze_expression(exprs[i])
        if not(self.types_compatible(elem_type, first_type)) {
          self.add_error("数组元素类型不一致")
        }
      }
      Array(first_type)
    }
    @ast.StructConstruct(_struct_name, fields) => {
      // 简化处理：假设结构体构造返回Unit类型
      for field in fields {
        ignore(self.analyze_expression(field.1))
      }
      Unit
    }
    @ast.EnumConstruct(_type_name, _variant_name, args) => {
      // 简化处理：假设枚举构造返回Unit类型
      for arg in args {
        ignore(self.analyze_expression(arg))
      }
      Unit
    }
    @ast.MatchExpr(expr, arms) => {
      let _expr_type = self.analyze_expression(expr)
      // 简化处理：假设所有分支返回相同类型
      if arms.length() > 0 {
        self.analyze_expression(arms[0].expr)
      } else {
        Unit
      }
    }
    @ast.FieldAccess(target, _field_name) => {
      // 简化处理：假设字段访问返回Int类型
      ignore(self.analyze_expression(target))
      Int
    }
    @ast.FunctionExpr(params, return_type, body) => {
      // 函数表达式：分析函数体并返回函数类型
      self.push_scope()
      // 添加参数到作用域
      for param in params {
        match param.1 {
          Some(param_type) => {
            let type_val = self.ast_type_to_type(param_type)
            self.add_variable(param.0, type_val)
          }
          None =>
            // 参数没有类型注解，假设为Int类型
            self.add_variable(param.0, Int)
        }
      }
      // 分析函数体
      let _body_type = self.analyze_expression(body)
      self.pop_scope()

      // 返回函数类型
      match return_type {
        Some(rt) => {
          let return_type_val = self.ast_type_to_type(rt)
          let param_types = params.map(fn(p) {
            match p.1 {
              Some(t) => self.ast_type_to_type(t)
              None => Int // 默认参数类型
            }
          })
          Function(param_types, return_type_val)
        }
        None => {
          // 没有返回类型注解，假设返回Unit
          let param_types = params.map(fn(p) {
            match p.1 {
              Some(t) => self.ast_type_to_type(t)
              None => Int // 默认参数类型
            }
          })
          Function(param_types, Unit)
        }
      }
    }
  }
} ///|

///|
/// 分析二元操作
fn analyze_binary_op(
  self : SemanticAnalyzer,
  left_type : Type,
  op : @ast.BinaryOperator,
  right_type : Type,
) -> Type {
  match op {
    @ast.Add | @ast.Sub | @ast.Mul | @ast.Div | @ast.Mod =>
      if self.types_compatible(left_type, Int) &&
        self.types_compatible(right_type, Int) {
        Int
      } else if self.types_compatible(left_type, Double) &&
        self.types_compatible(right_type, Double) {
        Double
      } else {
        self.add_error(
          "算术运算符要求两侧类型相同且为数值类型",
        )
        Unit
      }
    @ast.Equal | @ast.NotEqual =>
      if self.types_compatible(left_type, right_type) {
        Bool
      } else {
        self.add_error("相等比较要求两侧类型相同")
        Bool
      }
    @ast.Less | @ast.LessEqual | @ast.Greater | @ast.GreaterEqual =>
      if (
          self.types_compatible(left_type, Int) &&
          self.types_compatible(right_type, Int)
        ) ||
        (
          self.types_compatible(left_type, Double) &&
          self.types_compatible(right_type, Double)
        ) {
        Bool
      } else {
        self.add_error(
          "比较运算符要求两侧类型相同且为数值类型",
        )
        Bool
      }
    @ast.And | @ast.Or =>
      if self.types_compatible(left_type, Bool) &&
        self.types_compatible(right_type, Bool) {
        Bool
      } else {
        self.add_error("逻辑运算符要求两侧都是布尔类型")
        Bool
      }
  }
}

///|
/// 分析一元操作
fn analyze_unary_op(
  self : SemanticAnalyzer,
  op : @ast.UnaryOperator,
  expr_type : Type,
) -> Type {
  match op {
    @ast.Negate =>
      if self.types_compatible(expr_type, Int) ||
        self.types_compatible(expr_type, Double) {
        expr_type
      } else {
        self.add_error("负号运算符要求操作数为数值类型")
        Unit
      }
    @ast.Not =>
      if self.types_compatible(expr_type, Bool) {
        Bool
      } else {
        self.add_error("逻辑非运算符要求操作数为布尔类型")
        Bool
      }
  }
}

///|
/// AST类型转换为语义类型
fn ast_type_to_type(self : SemanticAnalyzer, ast_type : @ast.Type) -> Type {
  match ast_type {
    @ast.IntType => Int
    @ast.DoubleType => Double
    @ast.BoolType => Bool
    @ast.UnitType => Unit
    @ast.ArrayType(element_type) => Array(self.ast_type_to_type(element_type))
    @ast.TupleType(_) => Unit // 简化处理
    @ast.FunctionType(params, return_type) => {
      let param_types = params.map(fn(t) { self.ast_type_to_type(t) })
      let ret_type = self.ast_type_to_type(return_type)
      Function(param_types, ret_type)
    }
    @ast.UserDefinedType(_name) =>
      // 简化处理：假设用户定义类型为Int
      Int
    @ast.GenericType(_name, _inner_type) =>
      // 简化处理：假设泛型类型为Int
      Int
  }
} ///|

///|
/// 作用域管理
fn push_scope(self : SemanticAnalyzer) -> Unit {
  let new_scope = Scope::{ variables: Map::new(), functions: Map::new() }
  self.scopes = self.scopes + [new_scope]
}

///|
fn pop_scope(self : SemanticAnalyzer) -> Unit {
  if self.scopes.length() > 1 {
    let mut new_scopes = []
    for i = 0; i < self.scopes.length() - 1; i = i + 1 {
      new_scopes = new_scopes + [self.scopes[i]]
    }
    self.scopes = new_scopes
  }
}

///|
fn add_variable(self : SemanticAnalyzer, name : String, type_ : Type) -> Unit {
  let current_scope_index = self.scopes.length() - 1
  self.scopes[current_scope_index].variables.set(name, type_)
}

///|
fn add_function(
  self : SemanticAnalyzer,
  name : String,
  func_type : FunctionType,
) -> Unit {
  let current_scope_index = self.scopes.length() - 1
  self.scopes[current_scope_index].functions.set(name, func_type)
}

///|
fn lookup_variable(self : SemanticAnalyzer, name : String) -> Type? {
  for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
    match self.scopes[i].variables.get(name) {
      Some(t) => return Some(t)
      None => continue
    }
  }
  None
}

///|
fn lookup_function(self : SemanticAnalyzer, name : String) -> FunctionType? {
  for i = self.scopes.length() - 1; i >= 0; i = i - 1 {
    match self.scopes[i].functions.get(name) {
      Some(t) => return Some(t)
      None => continue
    }
  }
  None
}

///|
/// 类型兼容性检查
fn types_compatible(
  self : SemanticAnalyzer,
  actual : Type,
  expected : Type,
) -> Bool {
  ignore(self)
  actual == expected
}

///|
/// 添加错误
fn add_error(self : SemanticAnalyzer, message : String) -> Unit {
  self.errors = self.errors + [message]
}

///|
/// 公共接口：分析程序
pub fn analyze_program(program : @ast.Program) -> SemanticResult {
  let analyzer = SemanticAnalyzer::new()
  analyzer.analyze(program)
}
