///|
/// RISC-V 汇编代码生成器
pub struct RiscVCodeGen {
  mut output : String
  mut label_counter : Int
  mut stack_offset : Int
  mut local_vars : Map[String, Int] // 变量名 -> 栈偏移
  function_params : Map[String, Int] // 参数名 -> 寄存器/栈位置
  mut current_return_label : String // 当前函数的返回标签
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
    current_return_label: "",
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
      self.emit_line("  # 设置栈帧")
      self.emit_line("  addi sp, sp, -16")
      self.emit_line("  sd ra, 8(sp)")
      self.emit_line("  sd fp, 0(sp)")
      self.emit_line("  mv fp, sp")
      self.stack_offset = 0
      self.local_vars.clear()
      self.function_params.clear()
      self.current_return_label = self.new_label("function_return")
      self.generate_expression(body)
      // 调用 print_int 输出结果
      self.emit_line("  # 输出结果")
      self.emit_line("  call minimbt_print_int")
      self.emit_line(self.current_return_label + ":")
      self.emit_line("  # 恢复栈帧")
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
      self.emit_line("  # 设置栈帧")
      self.emit_line("  addi sp, sp, -16")
      self.emit_line("  sd ra, 8(sp)")
      self.emit_line("  sd fp, 0(sp)")
      self.emit_line("  mv fp, sp")
      self.stack_offset = 0
      self.local_vars.clear()
      self.function_params.clear()
      self.current_return_label = self.new_label("function_return")

      // 简化参数处理：只处理前8个参数，保存到栈上
      for i = 0; i < params.length() && i < 8; i = i + 1 {
        self.stack_offset = self.stack_offset - 8
        self.emit_line("  addi sp, sp, -8")
        self.emit_line("  sd a" + i.to_string() + ", 0(sp)")
        self.function_params.set(params[i].0, self.stack_offset)
      }
      self.generate_expression(body)
      self.emit_line(self.current_return_label + ":")
      // 恢复栈指针到参数保存前的位置  
      if params.length() > 0 && params.length() <= 8 {
        self.emit_line("  addi sp, sp, " + (params.length() * 8).to_string())
      }
      self.emit_line("  # 恢复栈帧")
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
    @ast.ArrayExpr(elems) => self.generate_array_expr(elems)
    @ast.GroupExpr(inner) => self.generate_expression(inner)
    @ast.TupleExpr(elems) => self.generate_tuple_expr(elems)
    @ast.StructConstruct(name, fields) =>
      self.generate_struct_construct(name, fields)
    @ast.EnumConstruct(name, variant, args) =>
      self.generate_enum_construct(name, variant, args)
    @ast.FieldAccess(target, field_name) =>
      self.generate_field_access(target, field_name)
    @ast.MatchExpr(expr, arms) => self.generate_match_expr(expr, arms)
    @ast.FunctionExpr(params, return_type, body) =>
      self.generate_function_expr(params, return_type, body)
  }
}

///|
/// 生成数组字面量
fn generate_array_expr(self : RiscVCodeGen, elems : Array[@ast.Expr]) -> Unit {
  // 分配数组：大小在a0，初始值在a1（此处传0），返回数组指针在a0
  self.emit_line("  # 数组字面量分配与初始化")
  self.emit_line("  li a0, " + elems.length().to_string())
  self.emit_line("  li a1, 0")
  self.emit_line("  call minimbt_create_array")
  // a0 = 数组指针，保存到栈上临时位置
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 逐个初始化元素：计算值放a2，加载数组指针到a0，索引到a1，存储到 a0 + 4 + a1*4
  for i = 0; i < elems.length(); i = i + 1 {
    self.generate_expression(elems[i])
    self.emit_line("  mv a2, a0")
    self.emit_line("  ld a0, 0(sp)")
    self.emit_line("  li a1, " + i.to_string())
    self.emit_line("  addi a0, a0, 4  # 跳过长度字段")
    self.emit_line("  slli a1, a1, 2  # 索引 * 4")
    self.emit_line("  add a0, a0, a1")
    self.emit_line("  sw a2, 0(a0)") // 使用sw存储32位整数
  }

  // 恢复数组指针到a0作为结果
  self.emit_line("  ld a0, 0(sp)")
  self.emit_line("  addi sp, sp, 8")
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
    @ast.Div => {
      // 处理除零情况
      let div_zero_label = self.new_label("div_zero")
      let div_done_label = self.new_label("div_done")
      self.emit_line("  beqz a1, " + div_zero_label)
      self.emit_line("  div a0, a0, a1")
      self.emit_line("  j " + div_done_label)
      self.emit_line(div_zero_label + ":")
      self.emit_line("  li a0, 0  # 除零返回0")
      self.emit_line(div_done_label + ":")
    }
    @ast.Mod => {
      // 处理除零情况
      let mod_zero_label = self.new_label("mod_zero")
      let mod_done_label = self.new_label("mod_done")
      self.emit_line("  beqz a1, " + mod_zero_label)
      self.emit_line("  rem a0, a0, a1")
      self.emit_line("  j " + mod_done_label)
      self.emit_line(mod_zero_label + ":")
      self.emit_line("  li a0, 0  # 模零返回0")
      self.emit_line(mod_done_label + ":")
    }
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
    @ast.And => {
      // 短路求值：如果左操作数为假，直接返回假
      let and_end = self.new_label("and_end")
      self.emit_line("  beqz a0, " + and_end)
      self.emit_line("  and a0, a0, a1")
      self.emit_line(and_end + ":")
    }
    @ast.Or => {
      // 短路求值：如果左操作数为真，直接返回真
      let or_end = self.new_label("or_end")
      self.emit_line("  bnez a0, " + or_end)
      self.emit_line("  or a0, a0, a1")
      self.emit_line(or_end + ":")
    }
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
        // 简化的函数调用：只处理前8个参数
        if args.length() > 8 {
          self.emit_line("  # 超过8个参数，简化处理")
          self.emit_line("  li a0, 0")
          return
        }

        // 保存调用者使用的寄存器 (只保存可能被破坏的寄存器)
        if args.length() > 0 {
          self.emit_line("  # 保存寄存器并计算参数")
          // 先计算所有参数并临时保存
          for i = 0; i < args.length(); i = i + 1 {
            self.generate_expression(args[i])
            self.emit_line("  addi sp, sp, -8")
            self.emit_line("  sd a0, 0(sp)")
          }

          // 从栈上加载参数到寄存器
          for i = 0; i < args.length(); i = i + 1 {
            let stack_pos = (args.length() - 1 - i) * 8
            self.emit_line(
              "  ld a" + i.to_string() + ", " + stack_pos.to_string() + "(sp)",
            )
          }

          // 清理参数栈空间
          self.emit_line("  addi sp, sp, " + (args.length() * 8).to_string())
        }

        // 调用函数
        self.emit_line("  call minimbt_" + func_name)
      }
    _ => {
      // 处理函数表达式调用
      // 先保存函数地址
      self.generate_expression(func_expr)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 计算参数并放入寄存器
      if args.length() > 0 {
        // 先计算所有参数并临时保存
        for i = 0; i < args.length(); i = i + 1 {
          self.generate_expression(args[i])
          self.emit_line("  addi sp, sp, -8")
          self.emit_line("  sd a0, 0(sp)")
        }

        // 从栈上加载参数到寄存器
        for i = 0; i < args.length() && i < 8; i = i + 1 {
          let stack_pos = (args.length() - 1 - i) * 8
          self.emit_line(
            "  ld a" + i.to_string() + ", " + stack_pos.to_string() + "(sp)",
          )
        }

        // 清理参数栈空间
        self.emit_line("  addi sp, sp, " + (args.length() * 8).to_string())
      }

      // 恢复函数地址并调用
      self.emit_line("  ld t0, 0(sp)")
      self.emit_line("  addi sp, sp, 8")
      self.emit_line("  jalr ra, t0, 0")
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
  // 计算初始值并保存
  self.generate_expression(init_value)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 计算大小
  self.generate_expression(size)

  // 恢复初始值到a1
  self.emit_line("  ld a1, 0(sp)")
  self.emit_line("  addi sp, sp, 8")

  // 调用数组创建函数：minimbt_create_array(size, init_value)
  self.emit_line("  call minimbt_create_array")

  // 数组创建后，a0包含数组指针，数组布局为：[长度][元素0][元素1]...
  // 不需要额外处理，因为minimbt_create_array已经正确初始化了数组
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

  // 边界检查
  let bounds_error_label = self.new_label("array_bounds_error")
  let access_done_label = self.new_label("array_access_done")
  self.emit_line("  bltz a1, " + bounds_error_label)
  self.emit_line("  # 假设数组长度在数组的第一个元素")
  self.emit_line("  lw t0, 0(a0)  # 加载数组长度")
  self.emit_line("  bge a1, t0, " + bounds_error_label)

  // 计算偏移并加载值：array[index] = *(array + 4 + index * 4)
  // 数组布局：[长度][元素0][元素1]...
  self.emit_line("  addi a0, a0, 4  # 跳过长度字段")
  self.emit_line("  slli a1, a1, 2  # 索引 * 4")
  self.emit_line("  add a0, a0, a1")
  self.emit_line("  lw a0, 0(a0)") // 使用lw加载32位整数
  self.emit_line("  j " + access_done_label)
  self.emit_line(bounds_error_label + ":")
  self.emit_line("  li a0, 0  # 越界返回0")
  self.emit_line(access_done_label + ":")
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
      if self.current_return_label != "" {
        self.emit_line("  j " + self.current_return_label)
      } else {
        self.emit_line("  ret")
      }
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

      // 检查是否是函数参数
      match self.function_params.get(name) {
        Some(offset) => {
          // 参数在当前函数栈上
          let stack_pos = offset - self.stack_offset
          self.emit_line("  sd a0, " + stack_pos.to_string() + "(sp)")
          return
        }
        None => ()
      }

      // 检查是否是局部变量
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

      // 边界检查
      let assign_bounds_error_label = self.new_label(
        "array_assign_bounds_error",
      )
      let assign_done_label = self.new_label("array_assign_done")
      self.emit_line("  bltz a1, " + assign_bounds_error_label)
      self.emit_line("  lw t0, 0(a0)  # 加载数组长度")
      self.emit_line("  bge a1, t0, " + assign_bounds_error_label)

      // 存储值：array[index] = *(array + 4 + index * 4)
      self.emit_line("  addi a0, a0, 4  # 跳过长度字段")
      self.emit_line("  slli a1, a1, 2  # 索引 * 4")
      self.emit_line("  add a0, a0, a1")
      self.emit_line("  sw a2, 0(a0)") // 使用sw存储32位整数
      self.emit_line("  j " + assign_done_label)
      self.emit_line(assign_bounds_error_label + ":")
      self.emit_line("  # 越界赋值，忽略")
      self.emit_line(assign_done_label + ":")
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
    @ast.Variable(name) => {
      // 检查是否是函数参数
      match self.function_params.get(name) {
        Some(offset) => {
          // 参数在当前函数栈上
          let stack_pos = offset - self.stack_offset
          self.emit_line("  addi a0, sp, " + stack_pos.to_string())
          return
        }
        None => ()
      }

      // 检查是否是局部变量
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
    }
    @ast.ArrayAccess(array_lval, index) => {
      // 递归处理数组访问
      self.generate_expression(index)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")
      self.generate_left_value_address(array_lval)
      self.emit_line("  ld a1, 0(sp)")
      self.emit_line("  addi sp, sp, 8")
      self.emit_line("  addi a0, a0, 4  # 跳过长度字段")
      self.emit_line("  slli a1, a1, 2  # 索引 * 4")
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
    Some(offset) => {
      // 参数保存在当前函数栈上，使用相对于sp的偏移
      let stack_pos = offset - self.stack_offset
      self.emit_line("  ld a0, " + stack_pos.to_string() + "(sp)")
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
  // 计算参数并放入正确的寄存器
  if args.length() > 0 {
    // 临时保存参数
    self.emit_line("  addi sp, sp, -" + (args.length() * 8).to_string())
    for i = 0; i < args.length(); i = i + 1 {
      self.generate_expression(args[i])
      self.emit_line("  sd a0, " + (i * 8).to_string() + "(sp)")
    }

    // 加载参数到寄存器
    for i = 0; i < args.length() && i < 8; i = i + 1 {
      self.emit_line(
        "  ld a" + i.to_string() + ", " + (i * 8).to_string() + "(sp)",
      )
    }
    self.emit_line("  addi sp, sp, " + (args.length() * 8).to_string())
  }

  // 调用预定义函数
  self.emit_line("  call minimbt_" + func_name)
}

///|
/// 生成元组表达式
fn generate_tuple_expr(self : RiscVCodeGen, elems : Array[@ast.Expr]) -> Unit {
  // 分配元组内存：大小 + 元素
  let tuple_size = (elems.length() + 1) * 8 // 8字节对齐
  self.emit_line("  li a0, " + tuple_size.to_string())
  self.emit_line("  call minimbt_malloc")

  // 保存元组指针
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 存储元素数量
  self.emit_line("  li t0, " + elems.length().to_string())
  self.emit_line("  sd t0, 0(a0)")

  // 存储每个元素
  for i = 0; i < elems.length(); i = i + 1 {
    self.generate_expression(elems[i])
    self.emit_line("  ld t0, 0(sp)  # 元组指针")
    self.emit_line("  sd a0, " + ((i + 1) * 8).to_string() + "(t0)")
  }

  // 恢复元组指针
  self.emit_line("  ld a0, 0(sp)")
  self.emit_line("  addi sp, sp, 8")
}

///|
/// 生成结构体构造
fn generate_struct_construct(
  self : RiscVCodeGen,
  _name : String,
  fields : Array[(String, @ast.Expr)],
) -> Unit {
  // 简化处理：分配内存并存储字段
  let struct_size = fields.length() * 8
  self.emit_line("  li a0, " + struct_size.to_string())
  self.emit_line("  call minimbt_malloc")

  // 保存结构体指针
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 存储每个字段
  for i = 0; i < fields.length(); i = i + 1 {
    self.generate_expression(fields[i].1)
    self.emit_line("  ld t0, 0(sp)  # 结构体指针")
    self.emit_line("  sd a0, " + (i * 8).to_string() + "(t0)")
  }

  // 恢复结构体指针
  self.emit_line("  ld a0, 0(sp)")
  self.emit_line("  addi sp, sp, 8")
}

///|
/// 生成枚举构造
fn generate_enum_construct(
  self : RiscVCodeGen,
  _name : String,
  _variant : String?,
  args : Array[@ast.Expr],
) -> Unit {
  // 简化处理：分配内存并存储变体信息
  let enum_size = (args.length() + 2) * 8 // 变体索引 + 参数
  self.emit_line("  li a0, " + enum_size.to_string())
  self.emit_line("  call minimbt_malloc")

  // 保存枚举指针
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 存储变体索引（简化处理）
  self.emit_line("  li t0, 0  # 变体索引")
  self.emit_line("  sd t0, 0(a0)")

  // 存储参数数量
  self.emit_line("  li t0, " + args.length().to_string())
  self.emit_line("  sd t0, 8(a0)")

  // 存储每个参数
  for i = 0; i < args.length(); i = i + 1 {
    self.generate_expression(args[i])
    self.emit_line("  ld t0, 0(sp)  # 枚举指针")
    self.emit_line("  sd a0, " + ((i + 2) * 8).to_string() + "(t0)")
  }

  // 恢复枚举指针
  self.emit_line("  ld a0, 0(sp)")
  self.emit_line("  addi sp, sp, 8")
}

///|
/// 生成字段访问
fn generate_field_access(
  self : RiscVCodeGen,
  target : @ast.Expr,
  field_name : String,
) -> Unit {
  // 计算目标对象地址
  self.generate_expression(target)

  // 简化处理：假设字段按顺序存储
  // 在实际实现中，需要根据字段名查找偏移
  self.emit_line("  # 字段访问: " + field_name)
  self.emit_line("  lw a0, 0(a0)  # 加载第一个字段")
}

///|
/// 生成模式匹配表达式
fn generate_match_expr(
  self : RiscVCodeGen,
  expr : @ast.Expr,
  arms : Array[@ast.MatchArm],
) -> Unit {
  // 计算匹配表达式
  self.generate_expression(expr)

  // 简化处理：只处理第一个分支
  if arms.length() > 0 {
    self.generate_expression(arms[0].expr)
  } else {
    self.emit_line("  li a0, 0")
  }
}

///|
/// 生成函数表达式（闭包）
fn generate_function_expr(
  self : RiscVCodeGen,
  params : Array[(String, @ast.Type?)],
  _return_type : @ast.Type?,
  body : @ast.Expr,
) -> Unit {
  // 为闭包生成一个唯一的函数名
  let closure_name = "closure_" + self.label_counter.to_string()
  self.label_counter = self.label_counter + 1

  // 生成闭包函数
  self.emit_line("")
  self.emit_line("minimbt_" + closure_name + ":")
  self.emit_line("  # 闭包函数")
  self.emit_line("  addi sp, sp, -16")
  self.emit_line("  sd ra, 8(sp)")
  self.emit_line("  sd fp, 0(sp)")
  self.emit_line("  mv fp, sp")

  // 处理参数
  for i = 0; i < params.length() && i < 8; i = i + 1 {
    self.stack_offset = self.stack_offset - 8
    self.emit_line("  addi sp, sp, -8")
    self.emit_line("  sd a" + i.to_string() + ", 0(sp)")
    self.function_params.set(params[i].0, self.stack_offset)
  }

  // 生成函数体
  self.current_return_label = self.new_label("closure_return")
  self.generate_expression(body)
  self.emit_line(self.current_return_label + ":")

  // 恢复栈帧
  if params.length() > 0 && params.length() <= 8 {
    self.emit_line("  addi sp, sp, " + (params.length() * 8).to_string())
  }
  self.emit_line("  ld ra, 8(sp)")
  self.emit_line("  ld fp, 0(sp)")
  self.emit_line("  addi sp, sp, 16")
  self.emit_line("  ret")
  self.emit_line("")

  // 返回闭包函数的地址
  self.emit_line("  la a0, minimbt_" + closure_name)
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
