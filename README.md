# myCPU: LoongArch 五级流水 CPU

## 项目简介

本项目实现了一个简化的 32 位 LoongArch 风格 CPU，采用经典五级流水结构：

- IF: 取指
- ID: 译码、读寄存器、分支判断、冒险检测
- EXE: 执行、访存地址计算、异常/中断处理、CSR 访问
- MEM: Load 数据选择与扩展
- WB: 写回寄存器堆并输出 debug trace

顶层模块为 `mycpu_top.v`。CPU 对外提供类 SRAM 的指令/数据接口，以及功能测试使用的写回调试接口。

当前版本已经支持 exp13 所需的 CSR、异常、中断、定时器和计数器相关功能，并已在 `F:\cdp_ede_local\output\exp13` 环境中通过完整功能仿真：

```text
Number 8'd58 Functional Test Point PASS!!!
Test end!
----PASS!!!
```

## 文件说明

- `mycpu_top.v`: CPU 顶层，连接五级流水、CSR/异常重定向和 debug 接口。
- `mycpu.vh`: 全局宏定义，包括流水总线宽度、中断位号等。
- `if_stage.v`: IF 级，维护 PC、发起取指、处理分支/异常/`ertn` 重定向，并检测取指地址错 ADEF。
- `id_stage.v`: ID 级，完成指令译码、寄存器读取、分支判断、数据前递、冒险阻塞和非法指令 INE 检测。
- `exe_stage.v`: EXE 级，执行 ALU 运算，生成访存控制，检测 ALE，处理 CSR、异常、中断和 `ertn`。
- `mem_stage.v`: MEM 级，根据访存类型完成 Load 数据选择、符号扩展或零扩展。
- `wb_stage.v`: WB 级，产生寄存器堆写回总线和 debug trace。
- `csr_regfile.v`: CSR 寄存器堆，包含异常现场、中断、定时器和稳定计数器支持。
- `alu.v`: 算术逻辑单元。
- `regfile.v`: 32 个 32 位通用寄存器，双读单写，`r0` 恒为 0。
- `decoder_*.v`: 多级译码器模块。
- `LoongArch-Vol1-v1.10-CN.pdf`: LoongArch 手册，用于查阅指令编码和 CSR 定义。

## 已支持的主要功能

### 基础指令

支持常见 LoongArch 整数指令，包括：

- 算术逻辑：`add.w`、`sub.w`、`slt`、`sltu`、`nor`、`and`、`or`、`xor`
- 立即数逻辑：`slti`、`sltui`、`andi`、`ori`、`xori`
- 移位：`slli.w`、`srli.w`、`srai.w`、`sll.w`、`srl.w`、`sra.w`
- 立即数/PC：`addi.w`、`lu12i.w`、`pcaddu12i`
- 乘除法：`mul.w`、`mulh.w`、`mulh.wu`、`div.w`、`div.wu`、`mod.w`、`mod.wu`
- 访存：`ld.b`、`ld.h`、`ld.w`、`ld.bu`、`ld.hu`、`st.b`、`st.h`、`st.w`
- 跳转分支：`jirl`、`b`、`bl`、`beq`、`bne`、`blt`、`bge`、`bltu`、`bgeu`

### CSR 和系统指令

支持以下 CSR/系统相关指令：

- `csrrd`
- `csrwr`
- `csrxchg`
- `ertn`
- `syscall`
- `rdcntvl.w`
- `rdcntvh.w`
- `rdcntid`

`rdcntid` 按 LoongArch 编码通过 `rdtimel.w r0, rj` 形式区分，目的寄存器为 `rj`；`rdcntvl.w` 和 `rdcntvh.w` 的目的寄存器为 `rd`。

### CSR 寄存器

`csr_regfile.v` 当前实现的主要 CSR 包括：

- `CRMD`: 当前模式与中断使能。
- `PRMD`: 异常前的模式与中断使能保存。
- `ECFG`: 中断局部使能配置。
- `ESTAT`: 异常状态、中断 pending 位、异常编码。
- `ERA`: 异常返回地址。
- `EENTRY`: 异常入口地址。
- `SAVE0` ~ `SAVE3`: 软件保存寄存器。
- `BADV`: 地址相关异常的出错虚地址。
- `TID`: 计时器编号。
- `TCFG`: 定时器配置。
- `TVAL`: 定时器当前值。
- `TICLR`: 定时器中断清除。

实现细节：

- `ECFG` 仅保留测试和手册要求的合法中断使能位，非法位写入被屏蔽。
- `BADV` 只在 ADEF/ALE 这类地址相关异常时更新，避免 `syscall` 等异常覆盖有效地址现场。
- 定时器中断位使用 `ESTAT.IS[11]`。
- `TICLR` 写 1 清除定时器中断 pending，避免清除后因 `TVAL == 0` 立即重新置位。

## 异常和中断

当前支持的异常：

- ADEF: 取指地址错。
- ALE: 访存地址非对齐。
- INE: 指令不存在。
- BRK: 断点异常。
- SYS: `syscall` 系统调用异常。

当前支持的中断：

- 2 个软件中断位。
- 8 个硬件中断输入。
- 1 个定时器中断。

异常/中断处理流程：

1. EXE 级统一选择当前最高优先级异常或中断。
2. 写入 `ESTAT.Ecode` / `ESTAT.EsubCode`、`ERA`，必要时写入 `BADV`。
3. 将 `CRMD.PLv` / `CRMD.IE` 保存到 `PRMD`，并关闭当前中断使能。
4. 冲刷流水线并重定向到 `EENTRY`。
5. `ertn` 从 `ERA` 返回，并从 `PRMD` 恢复 `CRMD` 中的权限级和中断使能。

`mycpu_top.v` 包含 `hw_int_in[7:0]` 外部中断输入。为了兼容部分测试 SoC 未连接该端口的情况，内部会对该输入做 X 安全处理，避免未连接信号把中断逻辑污染成未知值。

## 流水线和冒险处理

各级采用 valid/allowin 握手机制：

```verilog
allowin       = !valid || (ready_go && next_allowin);
to_next_valid = valid && ready_go;
```

ID 级完成主要冒险检测和前递选择：

- EXE/MEM/WB 到 ID 的 RAW 数据前递。
- Load-use 冒险阻塞。
- 分支依赖 Load 结果时，通过 `br_stall` 阻止 IF 继续发起错误取指。
- CSR 相关写后读和 `ertn` 相关控制冒险会触发必要阻塞。

分支判断在 ID 级完成，支持有符号和无符号比较分支。

## 访存行为

访存类型由 ID 级产生，EXE/MEM 级配合完成：

- `mem_size = 2'b00`: 字节访问。
- `mem_size = 2'b01`: 半字访问。
- `mem_size = 2'b10`: 字访问。
- `mem_unsigned`: 控制 `ld.bu` / `ld.hu` 零扩展。

Store 写掩码：

- `st.b`: 根据 `addr[1:0]` 选择 1 个 byte lane。
- `st.h`: 根据 `addr[1]` 选择低半字或高半字。
- `st.w`: 写 4 个 byte lane。

ALE 检测会抑制异常指令的实际数据 SRAM 写使能。

## 顶层接口

### 指令 SRAM 接口

- `inst_sram_en`
- `inst_sram_we[3:0]`
- `inst_sram_addr[31:0]`
- `inst_sram_wdata[31:0]`
- `inst_sram_rdata[31:0]`

### 数据 SRAM 接口

- `data_sram_en`
- `data_sram_we[3:0]`
- `data_sram_addr[31:0]`
- `data_sram_wdata[31:0]`
- `data_sram_rdata[31:0]`

### debug trace 接口

- `debug_wb_pc`
- `debug_wb_rf_we`
- `debug_wb_rf_wnum`
- `debug_wb_rf_wdata`

## exp13 验证说明

本仓库根目录的 RTL 已同步到：

```text
F:\cdp_ede_local\output\exp13\myCPU
```

使用 Vivado 2023.2 xsim 运行：

```powershell
F:\xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source C:\Users\aaljl\Desktop\CPU\run_exp13_sim.tcl
```

最近一次完整验证结果：

```text
----[1757575 ns] Number 8'd58 Functional Test Point PASS!!!
==============================================================
Test end!
----PASS!!!
```

验证过程中重点修复过的问题：

- 未连接 `hw_int_in` 导致 CSR 写回数据出现 `X`。
- CSR 写入信号在异常/`ertn` 冲刷时未正确屏蔽。
- 定时器中断位应落在 `ESTAT.IS[11]`。
- `TICLR` 清 pending 后不应在 `TVAL == 0` 时立即重新置位。
- `ECFG` 非法位需要屏蔽。
- `BADV` 不应被非地址异常覆盖。
- `rdcntid` 的解码和目的寄存器选择需要按手册编码处理。

## 后续改进建议

- 将异常优先级和 flush 控制进一步集中化，降低 EXE 级控制逻辑复杂度。
- 为 CSR 和计时器补充更细的单元级测试。
- 若后续实验引入 TLB/MMU，需要扩展异常类型、地址翻译和 CSR 集合。

## 许可说明

当前目录未包含 `LICENSE` 文件。若需要公开发布，建议补充许可证声明。
