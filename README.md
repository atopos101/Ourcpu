# myCPU：20 条 LoongArch 指令的五级流水线 CPU（不处理冲突）

## 1. 项目简介

本项目实现了一个简化的 32 位 LoongArch 风格 CPU，采用经典五级流水线结构：

- IF：取指（Instruction Fetch）
- ID：译码/读寄存器/分支决策（Instruction Decode）
- EXE：执行/地址计算（Execute）
- MEM：访存（Memory Access）
- WB：写回（Write Back）

本版本设计目标：

- 支持 20 条基础指令
- 不考虑流水线冲突处理（无前递、无停顿、无冲刷）
- 采用 valid/allowin 流水握手机制
- 对外提供类 SRAM 的指令/数据接口与写回调试接口

顶层模块：mycpu_top.v

## 2. 目录与文件说明

- mycpu_top.v：CPU 顶层，连接五级流水线
- mycpu.vh：全局宏定义（各级总线位宽）
- if_stage.v：IF 级
- id_stage.v：ID 级（指令译码、寄存器读取、分支判断）
- exe_stage.v：EXE 级（ALU 计算、Store 控制）
- mem_stage.v：MEM 级（Load 数据选择）
- wb_stage.v：WB 级（回写寄存器、输出调试信息）
- alu.v：算术逻辑单元
- regfile.v：32x32 寄存器堆（2 读 1 写）
- decoder_2_4.v / decoder_4_16.v / decoder_5_32.v / decoder_6_64.v：译码器模块

## 3. 五级流水线结构

### 3.1 IF 级（if_stage.v）

主要功能：

- 保存当前 PC
- 计算 nextpc：
  - 顺序执行：pc + 4
  - 分支跳转：来自 br_bus 的 br_target
- 访问指令存储器
- 向 ID 级发送 {inst, pc}

关键实现点：

- fs_ready_go 恒为 1
- fs_allowin 使用标准 allowin 公式
- 复位时 fs_pc 初始化为 0x1bfffffc，使下一拍 nextpc 为 0x1c000000

### 3.2 ID 级（id_stage.v）

主要功能：

- 锁存 IF 级传来的指令与 PC
- 通过多级译码器解析操作码字段
- 生成控制信号与立即数
- 读取寄存器堆操作数
- 在本级完成分支是否跳转判断与目标地址计算
- 打包 ds_to_es_bus 发送到 EXE 级

分支处理在 ID 级完成：

- beq/bne 在 ID 级比较寄存器值
- jirl/bl/b 直接在 ID 级给出跳转决策
- 输出 br_bus = {br_taken, br_target}

### 3.3 EXE 级（exe_stage.v）

主要功能：

- 锁存 ID 级总线
- 选择 ALU 两个输入源
- 执行 ALU 运算
- 生成 Store 写数据存储器控制信号
- 将结果打包到 es_to_ms_bus

存储写使能行为：

- data_sram_we 仅在有效 st.w 指令时输出 4'hf，否则为 4'h0

### 3.4 MEM 级（mem_stage.v）

主要功能：

- 锁存 EXE 级总线
- 选择最终结果：
  - Load 指令：取 data_sram_rdata
  - 非 Load 指令：取 ALU 结果
- 打包并发送到 WB 级

### 3.5 WB 级（wb_stage.v）

主要功能：

- 锁存 MEM 级总线
- 产生寄存器堆写回总线 ws_to_rf_bus
- 输出调试接口信号：
  - debug_wb_pc
  - debug_wb_rf_we
  - debug_wb_rf_wnum
  - debug_wb_rf_wdata

## 4. 流水线握手机制

各级都采用相同握手语义：

- stage_valid：当前级是否持有有效指令
- stage_ready_go：当前级内部是否可向下游发送（本实验中各级均恒为 1）
- stage_allowin：当前级是否可接收上游新指令
- stage_to_next_valid：当前级对下游的 valid

通用关系：

- allowin = !valid || (ready_go && next_allowin)
- to_next_valid = valid && ready_go

由于 ready_go 恒为 1，本实现是“始终就绪”流水线，不包含结构性停顿逻辑。

## 5. 级间总线与位宽定义

宏定义位于 mycpu.vh：

- BR_BUS_WD       = 33
- FS_TO_DS_BUS_WD = 64
- DS_TO_ES_BUS_WD = 152
- ES_TO_MS_BUS_WD = 71
- MS_TO_WS_BUS_WD = 70
- WS_TO_RF_BUS_WD = 38

### 5.1 BR bus（ID -> IF）

- {br_taken[1], br_target[32]}，共 33 位

### 5.2 FS_TO_DS bus（IF -> ID）

- {fs_inst[32], fs_pc[32]}，共 64 位

### 5.3 DS_TO_ES bus（ID -> EXE）

字段打包顺序：

- alu_op[11:0]（12）
- load_op（1）
- src1_is_pc（1）
- src2_is_imm（1）
- src2_is_4（1）
- gr_we（1）
- mem_we（1）
- dest[4:0]（5）
- imm[31:0]（32）
- rj_value[31:0]（32）
- rkd_value[31:0]（32）
- ds_pc[31:0]（32）
- res_from_mem（1）

合计 152 位。

### 5.4 ES_TO_MS bus（EXE -> MEM）

字段打包顺序：

- res_from_mem（1）
- gr_we（1）
- dest[4:0]（5）
- alu_result[31:0]（32）
- es_pc[31:0]（32）

合计 71 位。

### 5.5 MS_TO_WS bus（MEM -> WB）

字段打包顺序：

- gr_we（1）
- dest[4:0]（5）
- final_result[31:0]（32）
- pc[31:0]（32）

合计 70 位。

### 5.6 WS_TO_RF bus（WB -> ID/regfile）

字段打包顺序：

- rf_we（1）
- rf_waddr[4:0]（5）
- rf_wdata[31:0]（32）

合计 38 位。

## 6. 已支持指令（共 20 条）

在 id_stage.v 中完成译码：

算术/逻辑类：

1. add.w
2. sub.w
3. slt
4. sltu
5. nor
6. and
7. or
8. xor

移位类：

9. slli.w
10. srli.w
11. srai.w

立即数/高位加载类：

12. addi.w
13. lu12i.w

访存类：

14. ld.w
15. st.w

跳转/分支类：

16. jirl
17. b
18. bl
19. beq
20. bne

## 7. ALU 说明

ALU 控制信号宽度为 12 位（alu_op[11:0]），支持：

- add/sub
- slt/sltu
- and/nor/or/xor
- sll/srl/sra
- lui（由立即数准备逻辑配合实现）

EXE 级输入选择：

- alu_src1 = src1_is_pc ? pc : rj_value
- alu_src2 = src2_is_imm ? imm : rkd_value

## 8. 寄存器堆说明

regfile.v 实现 32 个通用寄存器（每个 32 位）：

- 双读口（组合读）
- 单写口（时钟上升沿写）
- 0 号寄存器读出恒为 0

## 9. 对外接口说明

### 9.1 指令 SRAM 接口

输出：

- inst_sram_en
- inst_sram_we[3:0]（恒 0，仅取指）
- inst_sram_addr[31:0]
- inst_sram_wdata[31:0]（未使用，置 0）

输入：

- inst_sram_rdata[31:0]

### 9.2 数据 SRAM 接口

输出：

- data_sram_en（当前实现恒为 1）
- data_sram_we[3:0]（有效 store 时为 4'hf，否则 0）
- data_sram_addr[31:0]
- data_sram_wdata[31:0]

输入：

- data_sram_rdata[31:0]

### 9.3 回写调试接口

- debug_wb_pc
- debug_wb_rf_we
- debug_wb_rf_wnum
- debug_wb_rf_wdata

## 10. 当前实现限制（重点）

本项目明确不处理流水线冲突，因此存在如下限制：

- 无数据相关前递（forwarding）
- 无 load-use 停顿（stall）
- 无控制相关冲刷（flush）
- 无异常/中断/CSR/TLB/MMU 等机制

因此，在存在相关依赖的指令序列中，若软件不插入足够 nop，执行结果可能不正确。

## 11. 集成与使用建议

- 本目录提供可综合 Verilog 模块。
- 使用时将 mycpu_top.v 接入你的 SoC/仿真平台。
- 正确连接 resetn、指令/数据 SRAM 接口以及 debug 接口。
- 进行功能验证时，建议使用“无冲突测试程序”或手动插入 nop。

## 12. 后续改进建议

若希望可稳定运行通用程序，建议按以下顺序增强：

1. 增加 RAW 前递路径（EXE/MEM/WB -> ID/EXE）
2. 增加 load-use 相关检测与停顿控制
3. 增加分支跳转冲刷机制
4. 扩展字节/半字访存与对齐检查
5. 增加异常与 CSR 支持

## 13. 许可说明

当前目录未包含 LICENSE 文件。若公开发布，建议补充许可证声明。
