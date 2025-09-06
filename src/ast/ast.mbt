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
  UserDefinedType(String) // 用户定义类型
  GenericType(String, Type) // 泛型类型，如 [T]
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
  StructConstruct(String, Array[(String, Expr)]) // Point::{ x: 1, y: 2 }
  EnumConstruct(String, String?, Array[Expr]) // Point(1, 2) 或 Point::Variant(1, 2)

  // 运算
  BinaryOp(BinaryOperator, Expr, Expr)
  UnaryOp(UnaryOperator, Expr)

  // 控制流
  IfExpr(Expr, Expr, Expr?) // if condition then else
  MatchExpr(Expr, Array[MatchArm]) // match expr { arms }
  BlockExpr(Array[Stmt], Expr?)

  // 函数调用和访问
  FunctionCall(Expr, Array[Expr])
  ArrayAccess(Expr, Expr)
  FieldAccess(Expr, String) // expr.field

  // 函数表达式
  FunctionExpr(Array[(String, Type?)], Type?, Expr) // 参数列表, 返回类型, 函数体

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
/// 模式匹配
pub(all) enum Pattern {
  NumberPattern(Int)
  BoolPattern(Bool)
  TuplePattern(Array[Pattern])
  WildcardPattern
  VariablePattern(String)
  EnumVariantPattern(String, String?, Array[Pattern]) // Type::Variant(patterns) 或 Variant(patterns)
} derive(Eq, Show)

///|
/// 匹配分支
pub(all) struct MatchArm {
  pattern : Pattern
  expr : Expr
} derive(Eq, Show)

///|
/// 语句AST节点
pub(all) enum Stmt {
  LetStmt(Binding, Type?, Expr) // binding, type, expr
  LetMutStmt(String, Type?, Expr) // name, type, expr
  LetTupleStmt(Array[Binding], Type?, Expr)
  FnDeclStmt(String, Array[(String, Type?)], Type?, Expr) // name, params, return_type, body
  AssignStmt(LeftValue, Expr)
  WhileStmt(Expr, Array[Stmt])
  ReturnStmt(Expr?)
  ExprStmt(Expr)
} derive(Eq, Show)

///|
/// 绑定（变量名或通配符）
pub(all) enum Binding {
  Variable(String)
  Wildcard
} derive(Eq, Show)

///|
/// 左值表达式（可赋值的表达式）
pub(all) enum LeftValue {
  Variable(String)
  FieldAccess(LeftValue, String) // left.field
  ArrayAccess(LeftValue, Expr)
} derive(Eq, Show)

///|
/// 结构体字段
pub(all) struct StructField {
  name : String
  field_type : Type
} derive(Eq, Show)

///|
/// 枚举变体
pub(all) struct EnumVariant {
  name : String
  field_types : Array[Type]
} derive(Eq, Show)

///|
/// 顶层声明AST节点
pub(all) enum TopLevel {
  TopLetDecl(String, Type?, Expr)
  TopLetWildcardDecl(Type?, Expr) // 新增：支持 let _ = ... 的顶级声明
  MainFnDecl(Expr) // fn main body
  TopFnDecl(String?, String, Array[(String, Type)], Type, Expr) // generic_param?, name, params, return_type, body
  StructDecl(String, String?, Array[StructField]) // name, generic_param?, fields
  EnumDecl(String, String?, Array[EnumVariant]) // name, generic_param?, variants
} derive(Eq, Show)

///|
/// 程序根节点
pub(all) struct Program {
  declarations : Array[TopLevel]
} derive(Eq, Show)
