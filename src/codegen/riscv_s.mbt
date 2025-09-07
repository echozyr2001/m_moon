///|
/// RISC-V 汇编代码生成器
pub struct RiscVCodeGen {
  mut output : String
  mut label_counter : Int
  mut stack_offset : Int
  mut local_vars : Map[String, Int] // 变量名 -> 栈偏移
  function_params : Map[String, Int] // 参数名 -> 寄存器/栈位置
}

///|
/// 创建新的代码生成器
pub fn RiscVCodeGen::new() -> RiscVCodeGen {
  RiscVCodeGen::{
    output: "",
    label_counter: 0,
    stack_offset: 0,
    local_vars: Map::new(),
    function_params: Map::new(),
  }
}

///|
/// 生成程序的汇编代码
pub fn generate_program(self : RiscVCodeGen, program : @ast.Program) -> String {
  self.emit_header()

  // 生成所有顶层声明
  for decl in program.declarations {
    self.generate_top_level(decl)
  }
  self.output
}

///|
/// 生成汇编文件头部
fn emit_header(self : RiscVCodeGen) -> Unit {
  self.emit_line(".text")
  self.emit_line(".global minimbt_main")
  self.emit_line("")
}

///|
/// 生成顶层声明
fn generate_top_level(self : RiscVCodeGen, decl : @ast.TopLevel) -> Unit {
  match decl {
    @ast.MainFnDecl(body) => {
      self.emit_line("minimbt_main:")
      self.emit_line("  # 保存返回地址和帧指针")
      self.emit_line("  addi sp, sp, -16")
      self.emit_line("  sd ra, 8(sp)")
      self.emit_line("  sd fp, 0(sp)")
      self.emit_line("  addi fp, sp, 16")
      self.stack_offset = 0
      self.local_vars.clear()
      self.function_params.clear()
      self.generate_expression(body)
      self.emit_line("  # 恢复返回地址和帧指针")
      self.emit_line("  ld ra, 8(sp)")
      self.emit_line("  ld fp, 0(sp)")
      self.emit_line("  addi sp, sp, 16")
      self.emit_line("  ret")
      self.emit_line("")
    }
    @ast.StructDecl(_, _, _) =>
      // 结构体声明不需要生成代码
      ()
    @ast.EnumDecl(_, _, _) =>
      // 枚举声明不需要生成代码
      ()
    @ast.TopFnDecl(_generic_param, name, params, _return_type, body) => {
      self.emit_line("minimbt_" + name + ":")
      self.emit_line("  # 保存返回地址和帧指针")
      self.emit_line("  addi sp, sp, -16")
      self.emit_line("  sd ra, 8(sp)")
      self.emit_line("  sd fp, 0(sp)")
      self.emit_line("  addi fp, sp, 16")
      self.stack_offset = 0
      self.local_vars.clear()
      self.function_params.clear()

      // 保存参数到栈上 (前8个参数使用a0-a7寄存器)
      if params.length() > 0 {
        let param_stack_size = params.length() * 8
        self.emit_line("  # 保存参数到栈上")
        self.emit_line("  addi sp, sp, -" + param_stack_size.to_string())
        for i = 0; i < params.length() && i < 8; i = i + 1 {
          self.emit_line(
            "  sd a" + i.to_string() + ", " + (i * 8).to_string() + "(sp)",
          )
          // 保存参数相对于帧指针的偏移：fp - 16 (ra+fp) - 8*i - 8
          let param_offset = -16 - param_stack_size + i * 8
          self.function_params.set(params[i].0, param_offset)
        }
      }
      self.generate_expression(body)
      // 恢复参数栈空间
      if params.length() > 0 {
        let param_stack_size = params.length() * 8
        self.emit_line("  # 恢复参数栈空间")
        self.emit_line("  addi sp, sp, " + param_stack_size.to_string())
      }
      self.emit_line("  # 恢复返回地址和帧指针")
      self.emit_line("  ld ra, 8(sp)")
      self.emit_line("  ld fp, 0(sp)")
      self.emit_line("  addi sp, sp, 16")
      self.emit_line("  ret")
      self.emit_line("")
    }
    @ast.TopLetDecl(name, _type_annotation, _expr) => {
      // 全局变量，简化处理为在.data段
      self.emit_line(".data")
      self.emit_line("minimbt_" + name + ":")
      self.emit_line("  .quad 0  # 全局变量 " + name)
      self.emit_line(".text")
      self.emit_line("")
    }
    @ast.TopLetWildcardDecl(_type_annotation, _expr) =>
      // 通配符全局 let 语句，不需要生成特殊的代码
      // 只需要确保表达式被求值（如果它有副作用的话）
      // 在简化的编译器中，我们可以忽略它
      ()
  }
}

///|
/// 生成表达式代码，结果放在a0寄存器中
fn generate_expression(self : RiscVCodeGen, expr : @ast.Expr) -> Unit {
  match expr {
    @ast.IntLiteral(value) => self.emit_line("  li a0, " + value.to_string())
    @ast.DoubleLiteral(value) => {
      // 浮点数处理，简化为整数
      // 在实际实现中，应该使用浮点寄存器
      let int_val = value.to_int()
      self.emit_line("  li a0, " + int_val.to_string())
    }
    @ast.BoolLiteral(value) => {
      let int_val = if value { 1 } else { 0 }
      self.emit_line("  li a0, " + int_val.to_string())
    }
    @ast.UnitLiteral => self.emit_line("  li a0, 0  # Unit值")
    @ast.Identifier(name) => self.generate_load_variable(name)
    @ast.BinaryOp(op, left, right) => self.generate_binary_op(op, left, right)
    @ast.UnaryOp(op, operand) => self.generate_unary_op(op, operand)
    @ast.FunctionCall(func_expr, args) =>
      self.generate_function_call(func_expr, args)
    @ast.IfExpr(condition, then_branch, else_branch) =>
      self.generate_if_expression(condition, then_branch, else_branch)
    @ast.BlockExpr(stmts, final_expr) =>
      self.generate_block_expression(stmts, final_expr)
    @ast.ArrayMake(size, init_value) =>
      self.generate_array_make(size, init_value)
    @ast.ArrayAccess(array, index) => self.generate_array_access(array, index)
    @ast.GroupExpr(inner) => self.generate_expression(inner)
    _ => {
      self.emit_line("  # 未实现的表达式类型")
      self.emit_line("  li a0, 0")
    }
  }
}

///|
/// 生成二元操作
fn generate_binary_op(
  self : RiscVCodeGen,
  op : @ast.BinaryOperator,
  left : @ast.Expr,
  right : @ast.Expr,
) -> Unit {
  // 计算右操作数，保存到栈上
  self.generate_expression(right)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 计算左操作数
  self.generate_expression(left)

  // 从栈上恢复右操作数到a1
  self.emit_line("  ld a1, 0(sp)")
  self.emit_line("  addi sp, sp, 8")
  match op {
    @ast.Add => self.emit_line("  add a0, a0, a1")
    @ast.Sub => self.emit_line("  sub a0, a0, a1")
    @ast.Mul => self.emit_line("  mul a0, a0, a1")
    @ast.Div => self.emit_line("  div a0, a0, a1")
    @ast.Mod => self.emit_line("  rem a0, a0, a1")
    @ast.Equal => {
      self.emit_line("  sub a0, a0, a1")
      self.emit_line("  seqz a0, a0")
    }
    @ast.NotEqual => {
      self.emit_line("  sub a0, a0, a1")
      self.emit_line("  snez a0, a0")
    }
    @ast.Less => self.emit_line("  slt a0, a0, a1")
    @ast.Greater => self.emit_line("  slt a0, a1, a0")
    @ast.LessEqual => {
      self.emit_line("  slt a0, a1, a0")
      self.emit_line("  xori a0, a0, 1")
    }
    @ast.GreaterEqual => {
      self.emit_line("  slt a0, a0, a1")
      self.emit_line("  xori a0, a0, 1")
    }
    @ast.And => self.emit_line("  and a0, a0, a1")
    @ast.Or => self.emit_line("  or a0, a0, a1")
  }
}

///|
/// 生成一元操作
fn generate_unary_op(
  self : RiscVCodeGen,
  op : @ast.UnaryOperator,
  operand : @ast.Expr,
) -> Unit {
  self.generate_expression(operand)
  match op {
    @ast.Negate => self.emit_line("  neg a0, a0")
    @ast.Not => self.emit_line("  seqz a0, a0")
  }
}

///|
/// 生成函数调用
fn generate_function_call(
  self : RiscVCodeGen,
  func_expr : @ast.Expr,
  args : Array[@ast.Expr],
) -> Unit {
  match func_expr {
    @ast.Identifier(func_name) =>
      // 检查是否是预定义函数
      if is_predefined_function(self, func_name) {
        self.generate_predefined_function_call(func_name, args)
      } else {
        // 保存调用者保存的寄存器
        self.emit_line("  # 保存调用者保存的寄存器")
        self.emit_line("  addi sp, sp, -64")
        for i = 0; i < 8; i = i + 1 {
          self.emit_line(
            "  sd a" + i.to_string() + ", " + (i * 8).to_string() + "(sp)",
          )
        }

        // 计算参数并放入寄存器 (修复多参数问题)
        if args.length() > 1 {
          // 先将所有参数计算结果保存到栈上
          let param_stack_size = args.length() * 8
          self.emit_line("  addi sp, sp, -" + param_stack_size.to_string())
          for i = 0; i < args.length() && i < 8; i = i + 1 {
            self.generate_expression(args[i])
            self.emit_line("  sd a0, " + (i * 8).to_string() + "(sp)")
          }

          // 从栈上加载到正确的寄存器
          for i = 0; i < args.length() && i < 8; i = i + 1 {
            self.emit_line(
              "  ld a" + i.to_string() + ", " + (i * 8).to_string() + "(sp)",
            )
          }
          self.emit_line("  addi sp, sp, " + param_stack_size.to_string())
        } else if args.length() == 1 {
          self.generate_expression(args[0])
        }

        // 调用函数
        self.emit_line("  call minimbt_" + func_name)

        // 恢复调用者保存的寄存器
        self.emit_line("  # 恢复调用者保存的寄存器")
        for i = 1; i < 8; i = i + 1 {
          self.emit_line(
            "  ld a" + i.to_string() + ", " + (i * 8).to_string() + "(sp)",
          )
        }
        self.emit_line("  addi sp, sp, 64")
      }
    _ => {
      self.emit_line("  # 不支持的函数调用形式")
      self.emit_line("  li a0, 0")
    }
  }
}

///|
/// 生成if表达式
fn generate_if_expression(
  self : RiscVCodeGen,
  condition : @ast.Expr,
  then_branch : @ast.Expr,
  else_branch : @ast.Expr?,
) -> Unit {
  let else_label = self.new_label("else")
  let end_label = self.new_label("end_if")

  // 计算条件
  self.generate_expression(condition)
  self.emit_line("  beqz a0, " + else_label)

  // then分支
  self.generate_expression(then_branch)
  self.emit_line("  j " + end_label)

  // else分支
  self.emit_line(else_label + ":")
  match else_branch {
    Some(else_expr) => self.generate_expression(else_expr)
    None => self.emit_line("  li a0, 0  # Unit值")
  }
  self.emit_line(end_label + ":")
}

///|
/// 生成块表达式
fn generate_block_expression(
  self : RiscVCodeGen,
  stmts : Array[@ast.Stmt],
  final_expr : @ast.Expr?,
) -> Unit {
  // 保存当前作用域状态
  let saved_vars = self.local_vars.copy()
  let saved_offset = self.stack_offset

  // 执行所有语句
  for stmt in stmts {
    self.generate_statement(stmt)
  }

  // 计算最终表达式
  match final_expr {
    Some(expr) => self.generate_expression(expr)
    None => self.emit_line("  li a0, 0  # Unit值")
  }

  // 恢复栈状态
  if self.stack_offset > saved_offset {
    let diff = self.stack_offset - saved_offset
    self.emit_line("  addi sp, sp, " + diff.to_string())
  }

  // 恢复作用域
  self.local_vars = saved_vars
  self.stack_offset = saved_offset
}

///|
/// 生成数组创建
fn generate_array_make(
  self : RiscVCodeGen,
  size : @ast.Expr,
  init_value : @ast.Expr,
) -> Unit {
  // 计算初始值
  self.generate_expression(init_value)
  self.emit_line("  mv a1, a0")

  // 计算大小
  self.generate_expression(size)

  // 根据初始值类型调用相应的数组创建函数
  // 这里简化处理，假设都是整数数组
  // 在实际实现中，应该根据类型系统选择正确的函数
  self.emit_line("  call minimbt_create_array")
}

///|
/// 生成数组访问
fn generate_array_access(
  self : RiscVCodeGen,
  array : @ast.Expr,
  index : @ast.Expr,
) -> Unit {
  // 计算索引
  self.generate_expression(index)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 计算数组地址
  self.generate_expression(array)

  // 恢复索引
  self.emit_line("  ld a1, 0(sp)")
  self.emit_line("  addi sp, sp, 8")

  // 计算偏移并加载值
  self.emit_line("  slli a1, a1, 3  # 索引 * 8")
  self.emit_line("  add a0, a0, a1")
  self.emit_line("  ld a0, 0(a0)")
}

///|
/// 生成语句
fn generate_statement(self : RiscVCodeGen, stmt : @ast.Stmt) -> Unit {
  match stmt {
    @ast.LetStmt(binding, _type_annotation, expr) => {
      // 计算表达式值
      self.generate_expression(expr)
      match binding {
        @ast.Binding::Variable(name) => {
          // 分配栈空间并保存值
          self.stack_offset = self.stack_offset - 8
          self.emit_line("  addi sp, sp, -8")
          self.emit_line("  sd a0, 0(sp)")

          // 记录变量位置
          self.local_vars.set(name, self.stack_offset)
        }
        @ast.Binding::Wildcard =>
          // 通配符不需要存储
          ()
      }
    }
    @ast.AssignStmt(target, expr) => self.generate_assignment(target, expr)
    @ast.ExprStmt(expr) => self.generate_expression(expr)
    @ast.ReturnStmt(expr_opt) => {
      match expr_opt {
        Some(expr) => self.generate_expression(expr)
        None => self.emit_line("  li a0, 0")
      }
      self.emit_line("  j function_return")
    }
    @ast.WhileStmt(condition, body) => self.generate_while_loop(condition, body)
    @ast.LetTupleStmt(bindings, _type_annotation, expr) => {
      self.generate_expression(expr)
      // 简化处理：为每个变量分配栈空间
      for binding in bindings {
        match binding {
          @ast.Binding::Variable(name) => {
            self.stack_offset = self.stack_offset - 8
            self.emit_line("  addi sp, sp, -8")
            self.emit_line("  sd a0, 0(sp)")
            self.local_vars.set(name, self.stack_offset)
          }
          @ast.Binding::Wildcard =>
            // 通配符不需要分配空间
            ()
        }
      }
    }
    @ast.LetMutStmt(name, _type_annotation, expr) => {
      // 计算表达式值
      self.generate_expression(expr)

      // 分配栈空间并保存值
      self.stack_offset = self.stack_offset - 8
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 记录变量位置
      self.local_vars.set(name, self.stack_offset)
    }
    _ => self.emit_line("  # 未实现的语句类型")
  }
}

///|
/// 生成赋值语句
fn generate_assignment(
  self : RiscVCodeGen,
  target : @ast.LeftValue,
  expr : @ast.Expr,
) -> Unit {
  match target {
    @ast.Variable(name) => {
      self.generate_expression(expr)
      match self.local_vars.get(name) {
        Some(offset) => {
          let stack_pos = offset - self.stack_offset
          self.emit_line("  sd a0, " + stack_pos.to_string() + "(sp)")
        }
        None => self.emit_line("  # 变量 " + name + " 未找到")
      }
    }
    @ast.ArrayAccess(array_lval, index) => {
      // 计算新值
      self.generate_expression(expr)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 计算索引
      self.generate_expression(index)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 计算数组地址
      self.generate_left_value_address(array_lval)

      // 恢复索引和值
      self.emit_line("  ld a1, 0(sp)") // 索引
      self.emit_line("  ld a2, 8(sp)") // 新值
      self.emit_line("  addi sp, sp, 16")

      // 存储值
      self.emit_line("  slli a1, a1, 3")
      self.emit_line("  add a0, a0, a1")
      self.emit_line("  sd a2, 0(a0)")
    }
    @ast.FieldAccess(target, _field_name) => {
      // 简化处理：假设字段赋值
      self.generate_expression(expr)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")
      self.generate_left_value_address(target)
      self.emit_line("  ld a1, 0(sp)")
      self.emit_line("  addi sp, sp, 8")
      self.emit_line("  sd a1, 0(a0)")
    }
  }
}

///|
/// 生成while循环
fn generate_while_loop(
  self : RiscVCodeGen,
  condition : @ast.Expr,
  body : Array[@ast.Stmt],
) -> Unit {
  let loop_start = self.new_label("while_start")
  let loop_end = self.new_label("while_end")
  self.emit_line(loop_start + ":")

  // 检查条件
  self.generate_expression(condition)
  self.emit_line("  beqz a0, " + loop_end)

  // 执行循环体
  for stmt in body {
    self.generate_statement(stmt)
  }
  self.emit_line("  j " + loop_start)
  self.emit_line(loop_end + ":")
}

///|
/// 生成左值地址
fn generate_left_value_address(
  self : RiscVCodeGen,
  lval : @ast.LeftValue,
) -> Unit {
  match lval {
    @ast.Variable(name) =>
      match self.local_vars.get(name) {
        Some(offset) => {
          let stack_pos = offset - self.stack_offset
          self.emit_line("  addi a0, sp, " + stack_pos.to_string())
        }
        None => {
          self.emit_line("  # 变量 " + name + " 未找到")
          self.emit_line("  li a0, 0")
        }
      }
    @ast.ArrayAccess(array_lval, index) => {
      // 递归处理数组访问
      self.generate_expression(index)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")
      self.generate_left_value_address(array_lval)
      self.emit_line("  ld a1, 0(sp)")
      self.emit_line("  addi sp, sp, 8")
      self.emit_line("  slli a1, a1, 3")
      self.emit_line("  add a0, a0, a1")
    }
    @ast.FieldAccess(target, field_name) => {
      // 简化处理：假设字段访问
      self.generate_left_value_address(target)
      self.emit_line("  # 字段访问: " + field_name)
    }
  }
}

///|
/// 加载变量值
fn generate_load_variable(self : RiscVCodeGen, name : String) -> Unit {
  // 检查是否是函数参数
  match self.function_params.get(name) {
    Some(fp_offset) => {
      // 使用帧指针访问参数
      self.emit_line("  ld a0, " + fp_offset.to_string() + "(fp)")
      return
    }
    None => ()
  }

  // 检查是否是局部变量
  match self.local_vars.get(name) {
    Some(offset) => {
      let stack_pos = offset - self.stack_offset
      self.emit_line("  ld a0, " + stack_pos.to_string() + "(sp)")
    }
    None => {
      // 可能是全局变量或外部函数
      self.emit_line("  # 加载全局变量或调用外部函数: " + name)
      self.emit_line("  call minimbt_" + name)
    }
  }
}

///|
/// 生成新标签
fn new_label(self : RiscVCodeGen, prefix : String) -> String {
  let label = prefix + "_" + self.label_counter.to_string()
  self.label_counter = self.label_counter + 1
  label
}

///|
/// 检查是否是预定义函数
fn is_predefined_function(_self : RiscVCodeGen, func_name : String) -> Bool {
  match func_name {
    "read_int"
    | "print_int"
    | "read_char"
    | "print_char"
    | "print_endline"
    | "int_of_float"
    | "float_of_int"
    | "truncate"
    | "floor"
    | "abs_float"
    | "sqrt"
    | "sin"
    | "cos"
    | "atan"
    | "malloc"
    | "create_array"
    | "create_float_array"
    | "create_ptr_array" => true
    _ => false
  }
}

///|
/// 生成预定义函数调用
fn generate_predefined_function_call(
  self : RiscVCodeGen,
  func_name : String,
  args : Array[@ast.Expr],
) -> Unit {
  // 如果有多个参数，需要保存之前计算的结果
  if args.length() > 1 {
    // 为参数预分配栈空间
    let param_stack_size = args.length() * 8
    self.emit_line("  addi sp, sp, -" + param_stack_size.to_string())

    // 计算所有参数并保存到栈上
    for i = 0; i < args.length() && i < 8; i = i + 1 {
      self.generate_expression(args[i])
      self.emit_line("  sd a0, " + (i * 8).to_string() + "(sp)")
    }

    // 从栈上加载到寄存器
    for i = 0; i < args.length() && i < 8; i = i + 1 {
      self.emit_line(
        "  ld a" + i.to_string() + ", " + (i * 8).to_string() + "(sp)",
      )
    }

    // 恢复栈空间
    self.emit_line("  addi sp, sp, " + param_stack_size.to_string())
  } else if args.length() == 1 {
    // 单参数情况
    self.generate_expression(args[0])
  }

  // 调用预定义函数
  self.emit_line("  call minimbt_" + func_name)
}

///|
/// 输出一行汇编代码
fn emit_line(self : RiscVCodeGen, line : String) -> Unit {
  self.output = self.output + line + "\n"
}

///|
/// 公共接口：生成程序汇编代码
pub fn generate_riscv_assembly(program : @ast.Program) -> String {
  let codegen = RiscVCodeGen::new()
  codegen.generate_program(program)
}
