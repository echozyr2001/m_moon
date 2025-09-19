///|
/// RISC-V 汇编代码生成器
pub struct RiscVCodeGen {
  mut output : String
  mut label_counter : Int
  mut stack_offset : Int
  mut local_vars : Map[String, Int] // 变量名 -> 栈偏移
  function_params : Map[String, Int] // 参数名 -> 寄存器/栈位置
  mut current_return_label : String // 当前函数的返回标签
  mut current_function_name : String // 当前正在生成的函数名（用于闭包捕获）
  // 预留字段（当前未使用）
  current_inner_function_name : String // 当前正在生成的局部函数名
  declared_capture_globals : Map[String, Bool] // 已声明的捕获全局符号
  mut closure_functions : String // 存储所有的闭包函数定义
  closure_vars : Map[String, Bool] // 变量名 -> 是否为闭包对象
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
    current_function_name: "",
    current_inner_function_name: "",
    declared_capture_globals: Map::new(),
    closure_functions: "",
    closure_vars: Map::new(),
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

  // 在程序末尾添加所有闭包函数
  self.output + self.closure_functions
}

///|
/// 生成汇编文件头部
fn emit_header(self : RiscVCodeGen) -> Unit {
  self.emit_line(".text")
  self.emit_line(".global minimbt_main")
  self.emit_line("")

  // 添加运行时函数
  self.emit_runtime_functions()
}

///|
/// 生成顶层声明
fn generate_top_level(self : RiscVCodeGen, decl : @ast.TopLevel) -> Unit {
  match decl {
    @ast.MainFnDecl(body) => {
      self.current_function_name = "main"
      self.emit_line("minimbt_main:")
      self.emit_line("  # 设置栈帧")
      self.emit_line("  addi sp, sp, -16")
      self.emit_line("  sd ra, 8(sp)")
      self.emit_line("  sd fp, 0(sp)")
      self.emit_line("  mv fp, sp")

      // 重置状态
      self.stack_offset = 0 // 相对于当前fp的偏移
      self.local_vars.clear()
      self.function_params.clear()
      self.current_return_label = self.new_label("function_return")
      self.generate_expression(body)
      // 主函数执行完毕后返回0表示成功
      self.emit_line("  li a0, 0  # 主函数返回0")
      self.emit_line(self.current_return_label + ":")
      self.emit_line("  # 恢复栈帧")
      self.emit_line("  mv sp, fp")
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
      self.current_function_name = name
      self.emit_line("minimbt_" + name + ":")
      self.emit_line("  # 设置栈帧")
      self.emit_line("  addi sp, sp, -16")
      self.emit_line("  sd ra, 8(sp)")
      self.emit_line("  sd fp, 0(sp)")
      self.emit_line("  mv fp, sp")

      // 重置状态
      self.stack_offset = 0 // 相对于当前fp的偏移
      self.local_vars.clear()
      self.function_params.clear()
      self.current_return_label = self.new_label("function_return")

      // 处理函数参数：参数在寄存器a0-a7中，需要保存到栈上
      for i = 0; i < params.length() && i < 8; i = i + 1 {
        self.emit_line("  addi sp, sp, -8")
        self.emit_line("  sd a" + i.to_string() + ", 0(sp)")
        self.stack_offset = self.stack_offset - 8
        self.function_params.set(params[i].0, self.stack_offset)
      }
      self.generate_expression(body)
      self.emit_line(self.current_return_label + ":")

      // 恢复栈帧
      self.emit_line("  # 恢复栈帧")
      self.emit_line("  mv sp, fp") // 恢复到函数开始时的栈指针
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
      // 浮点数处理：创建数据段中的常量并加载其地址
      let float_label = self.new_label("float_const")
      self.emit_line("  la a0, " + float_label)
      self.emit_line("  ld a0, 0(a0)  # 加载64位浮点数作为整数")

      // 在程序末尾添加浮点常量定义
      self.closure_functions = self.closure_functions +
        ".data\n" +
        ".align 8\n" +
        float_label +
        ":\n" +
        "  .double " +
        value.to_string() +
        "\n" +
        ".text\n"
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
      self.generate_function_expr_as_closure(params, return_type, body)
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

  // 逐个初始化元素：计算值放a2，加载数组指针到a0，索引到a1，存储到 a0 + a1*4
  for i = 0; i < elems.length(); i = i + 1 {
    self.generate_expression(elems[i])
    self.emit_line("  mv a2, a0")
    self.emit_line("  ld a0, 0(sp)")
    self.emit_line("  li a1, " + i.to_string())
    self.emit_line("  slli a1, a1, 2   # 索引 * 4")
    self.emit_line("  add a0, a0, a1")
    self.emit_line("  sw a2, 0(a0)     # 存储32位元素")
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
  // 短路求值需要特殊处理
  match op {
    @ast.And => {
      self.generate_expression(left)
      let and_false = self.new_label("and_false")
      let and_end = self.new_label("and_end")
      self.emit_line("  beqz a0, " + and_false)
      // 左操作数为真，计算右操作数
      self.generate_expression(right)
      self.emit_line("  snez a0, a0    # 将右操作数转换为0或1")
      self.emit_line("  j " + and_end)
      self.emit_line(and_false + ":")
      self.emit_line("  li a0, 0       # 左操作数为假，结果为假")
      self.emit_line(and_end + ":")
      return
    }
    @ast.Or => {
      self.generate_expression(left)
      let or_true = self.new_label("or_true")
      let or_end = self.new_label("or_end")
      self.emit_line("  bnez a0, " + or_true)
      // 左操作数为假，计算右操作数
      self.generate_expression(right)
      self.emit_line("  snez a0, a0    # 将右操作数转换为0或1")
      self.emit_line("  j " + or_end)
      self.emit_line(or_true + ":")
      self.emit_line("  li a0, 1       # 左操作数为真，结果为真")
      self.emit_line(or_end + ":")
      return
    }
    _ => ()
  }

  // 保存当前栈偏移
  let saved_offset = self.stack_offset

  // 计算右操作数，保存到栈上
  self.generate_expression(right)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")
  self.stack_offset = self.stack_offset - 8

  // 计算左操作数
  self.generate_expression(left)

  // 从栈上恢复右操作数到a1
  self.emit_line("  ld a1, 0(sp)")
  self.emit_line("  addi sp, sp, 8")
  self.stack_offset = saved_offset
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
    @ast.And | @ast.Or => () // 已在上面处理
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
      // 如果标识符在本地变量/参数中，视作函数指针变量，走间接调用
      if self.function_params.get(func_name) != None ||
        self.local_vars.get(func_name) != None {
        // 先将函数地址加载到寄存器
        self.generate_expression(func_expr)
        // 保存函数地址
        self.emit_line("  addi sp, sp, -8")
        self.emit_line("  sd a0, 0(sp)")

        // 计算实参
        if args.length() > 0 {
          for i = 0; i < args.length(); i = i + 1 {
            self.generate_expression(args[i])
            self.emit_line("  addi sp, sp, -8")
            self.emit_line("  sd a0, 0(sp)")
          }
          // 从栈上加载到a寄存器
          for i = 0; i < args.length() && i < 8; i = i + 1 {
            let stack_pos = (args.length() - 1 - i) * 8
            self.emit_line(
              "  ld a" + i.to_string() + ", " + stack_pos.to_string() + "(sp)",
            )
          }
          // 清理参数栈
          self.emit_line("  addi sp, sp, " + (args.length() * 8).to_string())
        }
        // 间接调用：检查是否是闭包对象
        self.emit_line("  ld t0, 0(sp)    # t0 = 闭包对象或函数指针")
        self.emit_line("  addi sp, sp, 8")

        // 检查是否是闭包对象
        if self.closure_vars.get(func_name) == Some(true) {
          // 闭包对象: [函数指针, 环境指针]
          // 需要将环境指针作为a0传递，其他参数右移
          if args.length() > 0 {
            // 为闭包调用腾出a0位置：将参数右移一位（a0->a1, a1->a2, ...）
            // 从最高寄存器开始，避免覆盖
            for i = args.length() - 1; i >= 0; i = i - 1 {
              if i < 7 { // 确保目标寄存器在有效范围内
                self.emit_line(
                  "  mv a" + (i + 1).to_string() + ", a" + i.to_string(),
                )
              }
            }
          }
          // 加载环境指针和函数指针
          self.emit_line("  ld a0, 8(t0)    # 加载环境指针到a0")
          self.emit_line("  ld t1, 0(t0)    # 加载函数指针到t1")
          self.emit_line("  jalr ra, t1, 0  # 调用闭包函数")
        } else {
          // 常规函数指针，直接调用
          self.emit_line("  jalr ra, t0, 0  # 直接调用函数指针")
        }
      } else if is_predefined_function(self, func_name) {
        // 预定义外部函数，直接调用带前缀的符号
        self.generate_predefined_function_call(func_name, args)
      } else {
        // 简化的函数调用：只处理前8个参数
        if args.length() > 8 {
          self.emit_line("  # 超过8个参数，简化处理")
          self.emit_line("  li a0, 0")
          return
        }

        // 计算所有参数并保存到栈上
        for i = 0; i < args.length(); i = i + 1 {
          self.generate_expression(args[i])
          self.emit_line("  addi sp, sp, -8")
          self.emit_line("  sd a0, 0(sp)")
        }

        // 从栈恢复到寄存器（按顺序）
        for i = 0; i < args.length() && i < 8; i = i + 1 {
          let stack_pos = (args.length() - 1 - i) * 8
          self.emit_line(
            "  ld a" + i.to_string() + ", " + stack_pos.to_string() + "(sp)",
          )
        }

        // 清理栈空间
        self.emit_line("  addi sp, sp, " + (args.length() * 8).to_string())

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

      // 恢复函数地址并调用（支持闭包）
      self.emit_line("  ld t0, 0(sp)    # t0 = 闭包对象或函数指针")
      self.emit_line("  addi sp, sp, 8")

      // 对于函数表达式，我们总是假设它是闭包对象
      // 因为函数表达式总是创建闭包对象
      if args.length() > 0 {
        // 为闭包调用腾出a0位置：将参数右移一位（a0->a1, a1->a2, ...）
        // 从最高寄存器开始，避免覆盖
        for i = args.length() - 1; i >= 0; i = i - 1 {
          if i < 7 { // 确保目标寄存器在有效范围内
            self.emit_line(
              "  mv a" + (i + 1).to_string() + ", a" + i.to_string(),
            )
          }
        }
      }

      // 闭包调用协议：加载环境指针和函数指针
      self.emit_line("  ld a0, 8(t0)    # 加载环境指针到a0")
      self.emit_line("  ld t1, 0(t0)    # 加载函数指针到t1")
      self.emit_line("  jalr ra, t1, 0  # 调用闭包函数")
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
  // 计算大小并保存
  self.generate_expression(size)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 计算初始值
  self.generate_expression(init_value)
  self.emit_line("  mv a1, a0")

  // 恢复大小到a0
  self.emit_line("  ld a0, 0(sp)")
  self.emit_line("  addi sp, sp, 8")

  // 调用数组创建函数：minimbt_create_array(size, init_value)
  // 返回 int32_t* 指针，指向数组元素（没有单独的长度字段）
  self.emit_line("  call minimbt_create_array")
}

///|
/// 生成数组访问
fn generate_array_access(
  self : RiscVCodeGen,
  array : @ast.Expr,
  index : @ast.Expr,
) -> Unit {
  // 计算数组地址并保存
  self.generate_expression(array)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")

  // 计算索引
  self.generate_expression(index)
  self.emit_line("  mv a1, a0")

  // 恢复数组地址
  self.emit_line("  ld a0, 0(sp)")
  self.emit_line("  addi sp, sp, 8")

  // 根据C文档，minimbt_create_array返回int32_t*指针
  // 数组布局：[元素0][元素1][元素2]... (每个元素4字节)
  // 不进行边界检查（在生产环境中应该检查）
  self.emit_line("  slli a1, a1, 2   # 索引 * 4 (int32_t大小)")
  self.emit_line("  add a0, a0, a1")
  self.emit_line("  lw a0, 0(a0)     # 加载32位元素")
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

          // 记录变量位置（相对于fp）
          // 变量存储在当前sp位置，即fp + stack_offset
          self.local_vars.set(name, self.stack_offset)

          // 检查是否是闭包对象
          if self.is_closure_expression(expr) {
            self.closure_vars.set(name, true)
          }
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
    @ast.FnDeclStmt(name, params, _ret_type, body) => {
      // 使用基于环境的闭包处理方式：
      // 1. 创建闭包环境对象，存储捕获的变量
      // 2. 生成闭包对象（包含函数指针和环境指针）
      // 3. 将闭包对象存储为局部变量

      // 分析需要捕获的变量 - 简化实现：检查所有当前作用域中的变量
      let captured_vars = Array::new()

      // 检查所有局部变量
      self.local_vars.each(fn(var_name, offset) {
        // 检查是否不是闭包函数的参数（避免参数名冲突）
        let mut is_param = false
        for j = 0; j < params.length(); j = j + 1 {
          if params[j].0 == var_name {
            is_param = true
            break
          }
        }
        if !is_param {
          captured_vars.push((var_name, offset))
        }
      })

      // 检查所有函数参数
      self.function_params.each(fn(var_name, offset) {
        // 检查是否不是闭包函数的参数（避免参数名冲突）
        let mut is_param = false
        for j = 0; j < params.length(); j = j + 1 {
          if params[j].0 == var_name {
            is_param = true
            break
          }
        }
        if !is_param {
          captured_vars.push((var_name, offset))
        }
      })
      if captured_vars.length() > 0 {
        // 创建环境对象：分配内存存储捕获的变量
        let env_size = captured_vars.length() * 8
        self.emit_line("  li a0, " + env_size.to_string())
        self.emit_line("  call minimbt_malloc")
        self.emit_line("  mv t1, a0  # 保存环境指针")

        // 将捕获的变量存储到环境中
        for i = 0; i < captured_vars.length(); i = i + 1 {
          let (_var_name, offset) = captured_vars[i]
          self.emit_line("  ld a0, " + offset.to_string() + "(fp)")
          self.emit_line("  sd a0, " + (i * 8).to_string() + "(t1)")
        }

        // 创建闭包对象：分配16字节（函数指针 + 环境指针）
        self.emit_line("  li a0, 16")
        self.emit_line("  call minimbt_malloc")
        self.emit_line("  mv t2, a0  # 保存闭包对象指针")

        // 转换为函数表达式形式处理，传入捕获的变量信息
        let param_pairs = Array::new()
        for i = 0; i < params.length(); i = i + 1 {
          param_pairs.push((params[i].0, None))
        }

        // 生成闭包函数（会使用captured_vars信息）  
        self.generate_function_expr_with_env(
          param_pairs,
          None,
          body,
          captured_vars,
        )

        // 将函数地址和环境指针存储到闭包对象中
        self.emit_line("  sd a0, 0(t2)   # 存储函数指针")
        self.emit_line("  sd t1, 8(t2)   # 存储环境指针")
        self.emit_line("  mv a0, t2      # 返回闭包对象")
      } else {
        // 没有捕获变量：仍然创建闭包对象（函数指针 + NULL环境）
        let param_pairs = Array::new()
        for i = 0; i < params.length(); i = i + 1 {
          param_pairs.push((params[i].0, None))
        }

        // 分配闭包对象
        self.emit_line("  li a0, 16")
        self.emit_line("  call minimbt_malloc")
        self.emit_line("  mv t2, a0  # 保存闭包对象指针")

        // 生成接受环境参数的函数（即使无捕获，调用约定保持一致）
        self.generate_function_expr_with_env(param_pairs, None, body, [])

        // 写入闭包对象：[0]=函数指针, [8]=NULL环境
        self.emit_line("  sd a0, 0(t2)")
        self.emit_line("  li t1, 0")
        self.emit_line("  sd t1, 8(t2)")
        self.emit_line("  mv a0, t2")
      }

      // 将闭包对象存储为局部变量
      self.stack_offset = self.stack_offset - 8
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")
      self.local_vars.set(name, self.stack_offset)
      self.closure_vars.set(name, true) // 标记为闭包对象

      // 重要：由于这是一个语句，我们需要保持闭包对象在a0中以供后续使用
      // 但是如果后面还有其他语句，闭包对象可能会被覆盖
      // 所以我们需要在需要时重新加载
    }
    @ast.LetTupleStmt(bindings, _type_annotation, expr) => {
      // 计算元组表达式
      self.generate_expression(expr)

      // 为每个绑定分配栈空间并存储值
      for i = 0; i < bindings.length(); i = i + 1 {
        match bindings[i] {
          @ast.Binding::Variable(name) => {
            // 如果是第一个元素，直接使用当前a0的值
            if i > 0 {
              // 对于后续元素，需要从元组中加载
              self.emit_line("  addi sp, sp, -8")
              self.emit_line("  sd a0, 0(sp)") // 保存元组指针
              self.emit_line("  ld a0, " + ((i + 1) * 8).to_string() + "(a0)") // 加载第i个元素
            }

            // 分配栈空间并保存值
            self.stack_offset = self.stack_offset - 8
            self.emit_line("  addi sp, sp, -8")
            self.emit_line("  sd a0, 0(sp)")
            self.local_vars.set(name, self.stack_offset)

            // 如果不是最后一个元素，恢复元组指针
            if i < bindings.length() - 1 {
              self.emit_line("  ld a0, 8(sp)") // 恢复元组指针
              self.emit_line("  addi sp, sp, 8")
            }
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

      // 记录变量位置（相对于fp）
      self.local_vars.set(name, self.stack_offset)
    }
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
        Some(param_offset) => {
          // 参数在当前函数栈上
          self.emit_line("  sd a0, " + param_offset.to_string() + "(fp)")
          // 更新闭包状态
          if self.is_closure_expression(expr) {
            self.closure_vars.set(name, true)
          } else {
            self.closure_vars.set(name, false)
          }
          return
        }
        None => ()
      }

      // 检查是否是局部变量
      match self.local_vars.get(name) {
        Some(var_offset) => {
          self.emit_line("  sd a0, " + var_offset.to_string() + "(fp)")
          // 更新闭包状态
          if self.is_closure_expression(expr) {
            self.closure_vars.set(name, true)
          } else {
            self.closure_vars.set(name, false)
          }
        }
        None => self.emit_line("  # 变量 " + name + " 未找到")
      }
    }
    @ast.ArrayAccess(array_lval, index) => {
      // 计算新值并保存
      self.generate_expression(expr)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 计算索引并保存
      self.generate_expression(index)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 计算数组地址
      self.generate_left_value_address(array_lval)

      // 恢复索引和值
      self.emit_line("  ld a1, 0(sp)") // 索引
      self.emit_line("  ld a2, 8(sp)") // 新值
      self.emit_line("  addi sp, sp, 16")

      // 根据C文档，数组没有长度前缀，所以不进行边界检查
      // 直接存储值：array[index] = value
      self.emit_line("  slli a1, a1, 2   # 索引 * 4")
      self.emit_line("  add a0, a0, a1")
      self.emit_line("  sw a2, 0(a0)     # 存储32位元素")
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
        Some(param_offset) => {
          // 参数在当前函数栈上
          self.emit_line("  addi a0, fp, " + param_offset.to_string())
          return
        }
        None => ()
      }

      // 检查是否是局部变量
      match self.local_vars.get(name) {
        Some(var_offset) =>
          self.emit_line("  addi a0, fp, " + var_offset.to_string())
        None => {
          self.emit_line("  # 变量 " + name + " 未找到")
          self.emit_line("  li a0, 0")
        }
      }
    }
    @ast.ArrayAccess(array_lval, index) => {
      // 计算索引并保存
      self.generate_expression(index)
      self.emit_line("  addi sp, sp, -8")
      self.emit_line("  sd a0, 0(sp)")

      // 计算数组地址
      self.generate_left_value_address(array_lval)

      // 恢复索引
      self.emit_line("  ld a1, 0(sp)")
      self.emit_line("  addi sp, sp, 8")

      // 计算最终地址
      self.emit_line("  slli a1, a1, 2   # 索引 * 4")
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
    Some(param_offset) => {
      // 参数保存在相对于fp的位置
      self.emit_line("  ld a0, " + param_offset.to_string() + "(fp)")
      return
    }
    None => ()
  }

  // 检查是否是局部变量
  match self.local_vars.get(name) {
    Some(var_offset) =>
      if var_offset == -999 {
        // 特殊标记：闭包捕获的变量，从全局变量加载
        self.emit_line("  # 加载捕获的全局变量: " + name)
        self.emit_line("  la a0, minimbt_capture_" + name)
        self.emit_line("  ld a0, 0(a0)")
      } else if var_offset <= -1000 {
        // 新的特殊标记：从环境中加载捕获的变量
        let env_index = -1000 - var_offset
        self.emit_line("  # 从环境加载捕获变量: " + name)
        self.emit_line("  ld t0, -8(fp)  # 加载环境指针")
        self.emit_line(
          "  ld a0, " +
          (env_index * 8).to_string() +
          "(t0)  # 从环境加载变量",
        )
      } else {
        // 普通局部变量保存在相对于fp的位置
        self.emit_line("  ld a0, " + var_offset.to_string() + "(fp)")
      }
    None => {
      // 可能是全局变量，尝试加载全局变量
      self.emit_line("  # 加载全局变量: " + name)
      self.emit_line("  la a0, minimbt_" + name)
      self.emit_line("  ld a0, 0(a0)")
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
  // 计算所有参数并保存到栈上
  for i = 0; i < args.length(); i = i + 1 {
    self.generate_expression(args[i])
    self.emit_line("  addi sp, sp, -8")
    self.emit_line("  sd a0, 0(sp)")
  }

  // 从栈恢复到寄存器（按顺序）
  for i = 0; i < args.length() && i < 8; i = i + 1 {
    let stack_pos = (args.length() - 1 - i) * 8
    self.emit_line(
      "  ld a" + i.to_string() + ", " + stack_pos.to_string() + "(sp)",
    )
  }

  // 清理栈空间
  if args.length() > 0 {
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

  // 存储变体索引（基于常见变体名的简化映射）
  let variant_index = match _variant {
    Some("Some") => 1
    Some("None") => 0
    Some("Ok") => 1
    Some("Err") => 0
    Some("Nil") => 0
    Some("Cons") => 1
    _ => 0 // 默认第一个变体
  }
  self.emit_line("  li t0, " + variant_index.to_string() + "  # 变体索引")
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

  // 简化处理：基于常见字段名映射到偏移
  let field_offset = match field_name {
    "x" => 0 // 第一个字段
    "y" => 8 // 第二个字段  
    "z" => 16 // 第三个字段
    "value" => 0
    "next" => 8
    "data" => 0
    "size" => 8
    _ => 0 // 默认第一个字段
  }
  self.emit_line(
    "  # 字段访问: " +
    field_name +
    " (偏移: " +
    field_offset.to_string() +
    ")",
  )
  self.emit_line("  ld a0, " + field_offset.to_string() + "(a0)")
}

///|
/// 生成模式匹配表达式
fn generate_match_expr(
  self : RiscVCodeGen,
  expr : @ast.Expr,
  arms : Array[@ast.MatchArm],
) -> Unit {
  // 计算匹配表达式并保存到栈
  self.generate_expression(expr)
  self.emit_line("  addi sp, sp, -8")
  self.emit_line("  sd a0, 0(sp)")
  let end_label = self.new_label("match_end")
  let arm_labels = Array::new()

  // 为每个分支生成标签
  for i = 0; i < arms.length(); i = i + 1 {
    arm_labels.push(self.new_label("match_arm"))
  }

  // 生成模式匹配逻辑
  for i = 0; i < arms.length(); i = i + 1 {
    let arm = arms[i]
    let next_label = if i + 1 < arms.length() {
      arm_labels[i + 1]
    } else {
      end_label
    }
    self.emit_line(arm_labels[i] + ":")

    // 简化的模式匹配：只处理整数字面量和通配符
    match arm.pattern {
      @ast.NumberPattern(value) => {
        self.emit_line("  ld a0, 0(sp)  # 加载匹配值")
        self.emit_line("  li a1, " + value.to_string())
        self.emit_line("  bne a0, a1, " + next_label)
      }
      @ast.BoolPattern(value) => {
        self.emit_line("  ld a0, 0(sp)  # 加载匹配值")
        let bool_val = if value { 1 } else { 0 }
        self.emit_line("  li a1, " + bool_val.to_string())
        self.emit_line("  bne a0, a1, " + next_label)
      }
      @ast.WildcardPattern | @ast.VariablePattern(_) =>
        // 通配符或变量模式，直接匹配
        ()
      _ =>
        // 其他模式（如枚举变体），简化处理
        ()
    }

    // 生成分支表达式
    self.generate_expression(arm.expr)
    self.emit_line("  j " + end_label)
  }
  self.emit_line(end_label + ":")
  // 清理栈上的匹配值
  self.emit_line("  addi sp, sp, 8")
}

///|
/// 输出一行汇编代码
fn emit_line(self : RiscVCodeGen, line : String) -> Unit {
  self.output = self.output + line + "\n"
}

///|
/// 生成运行时函数
fn emit_runtime_functions(self : RiscVCodeGen) -> Unit {
  // 根据测评平台文档，所有运行时函数都由环境提供
  // 我们只需要确保正确调用它们
  // 这里不需要实现具体的运行时函数，它们由测评环境提供

  // 添加一些说明注释
  self.emit_line("# 运行时函数由测评环境提供:")
  self.emit_line(
    "# minimbt_malloc, minimbt_create_array, minimbt_create_float_array",
  )
  self.emit_line(
    "# minimbt_print_int, minimbt_read_int, minimbt_print_char, minimbt_read_char",
  )
  self.emit_line(
    "# minimbt_print_endline, minimbt_int_of_float, minimbt_float_of_int",
  )
  self.emit_line("# minimbt_truncate, minimbt_floor, minimbt_abs_float")
  self.emit_line("# minimbt_sqrt, minimbt_sin, minimbt_cos, minimbt_atan")
  self.emit_line("")
}

///|
/// 生成函数表达式作为闭包（统一处理有无捕获变量的情况）
fn generate_function_expr_as_closure(
  self : RiscVCodeGen,
  params : Array[(String, @ast.Type?)],
  return_type : @ast.Type?,
  body : @ast.Expr,
) -> Unit {
  // 分析需要捕获的变量
  let captured_vars = Array::new()

  // 检查所有局部变量
  self.local_vars.each(fn(var_name, offset) {
    // 检查是否不是闭包函数的参数（避免参数名冲突）
    let mut is_param = false
    for j = 0; j < params.length(); j = j + 1 {
      if params[j].0 == var_name {
        is_param = true
        break
      }
    }
    if !is_param {
      captured_vars.push((var_name, offset))
    }
  })

  // 检查所有函数参数
  self.function_params.each(fn(var_name, offset) {
    // 检查是否不是闭包函数的参数（避免参数名冲突）
    let mut is_param = false
    for j = 0; j < params.length(); j = j + 1 {
      if params[j].0 == var_name {
        is_param = true
        break
      }
    }
    if !is_param {
      captured_vars.push((var_name, offset))
    }
  })
  if captured_vars.length() > 0 {
    // 有捕获变量，创建环境对象
    let env_size = captured_vars.length() * 8
    self.emit_line("  li a0, " + env_size.to_string())
    self.emit_line("  call minimbt_malloc")
    self.emit_line("  mv t1, a0  # 保存环境指针")

    // 将捕获的变量存储到环境中
    for i = 0; i < captured_vars.length(); i = i + 1 {
      let (_var_name, offset) = captured_vars[i]
      self.emit_line("  ld a0, " + offset.to_string() + "(fp)")
      self.emit_line("  sd a0, " + (i * 8).to_string() + "(t1)")
    }

    // 创建闭包对象：分配16字节（函数指针 + 环境指针）
    self.emit_line("  li a0, 16")
    self.emit_line("  call minimbt_malloc")
    self.emit_line("  mv t2, a0  # 保存闭包对象指针")

    // 生成闭包函数（会使用captured_vars信息）  
    self.generate_function_expr_with_env(
      params, return_type, body, captured_vars,
    )

    // 将函数地址和环境指针存储到闭包对象中
    self.emit_line("  sd a0, 0(t2)   # 存储函数指针")
    self.emit_line("  sd t1, 8(t2)   # 存储环境指针")
    self.emit_line("  mv a0, t2      # 返回闭包对象")
  } else {
    // 没有捕获变量，仍然创建闭包对象以保持一致性
    // 创建闭包对象：分配16字节（函数指针 + NULL环境指针）
    self.emit_line("  li a0, 16")
    self.emit_line("  call minimbt_malloc")
    self.emit_line("  mv t2, a0  # 保存闭包对象指针")

    // 生成接受环境参数的函数（即使无捕获，调用约定保持一致）
    self.generate_function_expr_with_env(params, return_type, body, [])

    // 将函数地址和NULL环境指针存储到闭包对象中
    self.emit_line("  sd a0, 0(t2)   # 存储函数指针")
    self.emit_line("  li t1, 0")
    self.emit_line("  sd t1, 8(t2)   # 存储NULL环境指针")
    self.emit_line("  mv a0, t2      # 返回闭包对象")
  }
}

///|
/// 检查表达式是否是闭包对象
fn is_closure_expression(self : RiscVCodeGen, expr : @ast.Expr) -> Bool {
  match expr {
    @ast.FunctionExpr(_, _, _) => true // 函数表达式总是创建闭包对象
    @ast.Identifier(name) =>
      // 检查是否是已知的闭包变量
      self.closure_vars.get(name) == Some(true)
    _ => false // 其他表达式不是闭包对象
  }
}

///|
/// 生成带环境的函数表达式（使用环境传递捕获变量）
fn generate_function_expr_with_env(
  self : RiscVCodeGen,
  params : Array[(String, @ast.Type?)],
  _return_type : @ast.Type?,
  body : @ast.Expr,
  captured_vars : Array[(String, Int)],
) -> Unit {
  // 生成闭包函数，接收环境作为隐式第一个参数
  let closure_name = "closure_" + self.label_counter.to_string()
  self.label_counter = self.label_counter + 1

  // 构建闭包函数代码（稍后添加到程序末尾）
  let closure_code = Array::new()
  closure_code.push("")
  closure_code.push("minimbt_" + closure_name + ":")
  closure_code.push("  # 闭包函数（带环境）")
  closure_code.push("  addi sp, sp, -16")
  closure_code.push("  sd ra, 8(sp)")
  closure_code.push("  sd fp, 0(sp)")
  closure_code.push("  mv fp, sp")

  // 保存环境指针（在a0中传入）
  closure_code.push("  addi sp, sp, -8")
  closure_code.push("  sd a0, 0(sp)  # 保存环境指针")

  // 保存其他参数到栈
  for i = 0; i < params.length() && i < 7; i = i + 1 { // 注意：a0被环境占用，所以从a1开始
    closure_code.push("  addi sp, sp, -8")
    closure_code.push("  sd a" + (i + 1).to_string() + ", 0(sp)")
  }

  // 使用临时代码生成器处理闭包体
  let temp_codegen = RiscVCodeGen::new()
  temp_codegen.stack_offset = 0
  temp_codegen.function_params.clear()
  temp_codegen.local_vars.clear()

  // 设置参数映射：闭包函数的参数在栈上（跳过环境指针）
  for i = 0; i < params.length() && i < 7; i = i + 1 {
    temp_codegen.function_params.set(params[i].0, -8 * (i + 2)) // 从-16开始（跳过环境）
  }

  // 设置捕获变量映射：从环境中加载
  for i = 0; i < captured_vars.length(); i = i + 1 {
    let (var_name, _offset) = captured_vars[i]
    // 使用特殊标记表示从环境加载，offset表示在环境中的索引
    temp_codegen.local_vars.set(var_name, -1000 - i)
  }
  temp_codegen.generate_expression(body)
  let body_lines = temp_codegen.output.split("\n")
  for line in body_lines {
    let trimmed = line.to_string()
    if trimmed != "" {
      closure_code.push(trimmed)
    }
  }

  // 清理栈并返回
  let total_stack_size = (params.length() + 1) * 8 // +1 for environment
  if total_stack_size > 0 {
    closure_code.push("  addi sp, sp, " + total_stack_size.to_string())
  }
  closure_code.push("  ld ra, 8(sp)")
  closure_code.push("  ld fp, 0(sp)")
  closure_code.push("  addi sp, sp, 16")
  closure_code.push("  ret")
  closure_code.push("")

  // 将闭包代码添加到closure_functions字段中
  for line in closure_code {
    self.closure_functions = self.closure_functions + line + "\n"
  }

  // 在当前位置返回闭包函数的地址
  self.emit_line("  la a0, minimbt_" + closure_name)
}

///|
/// 公共接口：生成程序汇编代码
pub fn generate_riscv_assembly(program : @ast.Program) -> String {
  let codegen = RiscVCodeGen::new()
  codegen.generate_program(program)
}
