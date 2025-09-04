///|
/// 类型系统
pub(all) enum Type {
  UnitType
  BoolType
  IntType
  DoubleType
  ArrayType(Type)
  TupleType(Array[Type])
  FunctionType(Array[Type], Type) // (参数类型, 返回类型)
} derive(Eq, Show)

///|
/// 表达式AST节点
pub(all) enum Expr {
  // 字面量
  UnitLiteral
  BoolLiteral(Bool)
  IntLiteral(Int)
  DoubleLiteral(Double)
  Identifier(String)

  // 复合表达式
  TupleExpr(Array[Expr])
  ArrayExpr(Array[Expr])
  ArrayMake(Expr, Expr) // Array::make(size, value)

  // 运算
  BinaryOp(BinaryOperator, Expr, Expr)
  UnaryOp(UnaryOperator, Expr)

  // 控制流
  IfExpr(Expr, Expr, Expr?) // if condition then else
  BlockExpr(Array[Stmt], Expr?)

  // 函数调用和数组访问
  FunctionCall(Expr, Array[Expr])
  ArrayAccess(Expr, Expr)

  // 分组
  GroupExpr(Expr)
} derive(Eq, Show)

///|
/// 二元操作符
pub(all) enum BinaryOperator {
  // 算术
  Add
  Sub
  Mul
  Div
  Mod

  // 比较
  Equal
  NotEqual
  Less
  Greater
  LessEqual
  GreaterEqual

  // 逻辑
  And
  Or
} derive(Eq, Show)

///|
/// 一元操作符
pub(all) enum UnaryOperator {
  Negate
  Not
} derive(Eq, Show)

///|
/// 语句AST节点
pub(all) enum Stmt {
  LetStmt(String, Type?, Expr, Bool) // name, type, expr, is_mut
  LetTupleStmt(Array[String], Type?, Expr)
  FnDeclStmt(String, Array[(String, Type?)], Type?, Expr) // name, params, return_type, body
  AssignStmt(LeftValue, Expr)
  WhileStmt(Expr, Array[Stmt])
  ReturnStmt(Expr?)
  ExprStmt(Expr)
} derive(Eq, Show)

///|
/// 左值表达式（可赋值的表达式）
pub(all) enum LeftValue {
  Variable(String)
  ArrayAccess(LeftValue, Expr)
} derive(Eq, Show)

///|
/// 顶层声明AST节点
pub(all) enum TopLevel {
  TopLetDecl(String, Type?, Expr)
  MainFnDecl(Expr) // fn main body
  TopFnDecl(String, Array[(String, Type)], Type, Expr) // name, params, return_type, body
} derive(Eq, Show)

///|
/// 程序根节点
pub(all) struct Program {
  declarations : Array[TopLevel]
} derive(Eq, Show)
