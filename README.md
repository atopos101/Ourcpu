# myCPU：20 条 LoongArch 指令的五级流水线 CPU（含阻塞冲突处理与数据前递）

## 1. 项目简介

本项目实现了一个简化的 32 位 LoongArch 风格 CPU，采用经典五级流水线结构：

- IF：取指（Instruction Fetch）
- ID：译码/读寄存器/分支决策（Instruction Decode）
- EXE：执行/地址计算（Execute）
- MEM：访存（Memory Access）
- WB：写回（Write Back）

本版本设计目标：

- 支持 20 条基础指令
- 支持数据相关冲突的基础处理：
  - RAW 数据前递（EXE/MEM/WB -> ID）
  - load-use 阻塞（stall）
  - 分支等待时对 IF 的阻塞控制
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

- fs_ready_go = ~br_taken（当本拍确定跳转时，IF 不向下游发送旧顺序指令）
- pre_if_ready_go = ~br_stall（分支相关且需要等待 load 数据时，暂停发起下一次取指）
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
- 输出 br_bus = {br_stall, br_taken, br_target}

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
- stage_ready_go：当前级内部是否可向下游发送
- stage_allowin：当前级是否可接收上游新指令
- stage_to_next_valid：当前级对下游的 valid

通用关系：

- allowin = !valid || (ready_go && next_allowin)
- to_next_valid = valid && ready_go

本实现中：

- IF 级 ready_go 受分支信号影响（~br_taken）
- ID 级 ready_go 受 load_stall 影响（~load_stall）
- EXE/MEM/WB 级当前均为始终就绪

## 5. 级间总线与位宽定义

宏定义位于 mycpu.vh：

- BR_BUS_WD       = 34
- FS_TO_DS_BUS_WD = 64
- DS_TO_ES_BUS_WD = 152
- ES_TO_MS_BUS_WD = 71
- MS_TO_WS_BUS_WD = 70
- WS_TO_RF_BUS_WD = 38

### 5.1 BR bus（ID -> IF）

- {br_stall[1], br_taken[1], br_target[32]}，共 34 位

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

算术逻辑运算类指令
21.slti
22.sltui
23.andi
24.ori
25.xori
26.sll
27.srl
28.sra
29.pcaddu12i。

乘除运算类指令
30.mul.w
31.mulh.w
32.mulh.wu
33.div.w
34.mod.w
35.div.wu
36.mod.wu

## 7. ALU 说明

ALU 控制信号宽度为 19 位（alu_op[18:0]），支持：

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

## 10. 阻塞冲突与数据前递信号说明

本实现在 ID 级完成相关检测，并通过跨级反馈信号实现“可前递时前递、不能前递时阻塞”。

### 10.1 顶层跨级冲突信息通道（mycpu_top.v）

- es_to_ds_dest[4:0]：EXE 级写回目的寄存器号，反馈给 ID 用于 RAW 相关判断
- ms_to_ds_dest[4:0]：MEM 级写回目的寄存器号，反馈给 ID 用于 RAW 相关判断
- ws_to_ds_dest[4:0]：WB 级写回目的寄存器号，反馈给 ID 用于 RAW 相关判断
- es_to_ds_load_op：EXE 级当前是否为 load 指令，用于判断是否需要 load-use 阻塞
- es_to_ds_result[31:0]：EXE 级可前递结果（ALU 结果）
- ms_to_ds_result[31:0]：MEM 级可前递结果（最终结果）
- ws_to_ds_result[31:0]：WB 级可前递结果（最终写回值）

### 10.2 ID 级相关检测信号（id_stage.v）

- rj_wait / rk_wait / rd_wait：当前指令源操作数是否与 EXE/MEM/WB 任一目的寄存器重名
- src_no_rj / src_no_rk / src_no_rd：当前指令是否实际使用对应源寄存器（避免误判）
- load_stall：load-use 阻塞条件信号

load_stall 判定逻辑为：

- EXE 级是 load（es_to_ds_load_op = 1）
- 且 ID 当前要读取的源寄存器命中 EXE 的目的寄存器

当 load_stall=1 时：

- ds_ready_go = ds_valid && ~load_stall 变为 0
- ID 不向 EXE 发送新指令（ds_to_es_valid 被抑制）
- IF 通过 ds_allowin 链路被背压，形成流水暂停

### 10.3 数据前递选择信号（id_stage.v）

ID 级读数优先级：EXE > MEM > WB > regfile。

- rj_value：当 rj_wait=1 时，从 es/ms/ws_to_ds_result 中按优先级选择；否则取 rf_rdata1
- rkd_value：对 rk 或 rd（取决于指令类型）采用同样的前递选择；否则取寄存器堆读值

该机制保证：

- 对于可由 EXE/MEM/WB 当拍提供的数据，直接前递，避免无谓停顿
- 仅在“EXE 为 load 且 ID 立即使用该结果”时停顿 1 拍

### 10.4 分支相关阻塞信号（id_stage.v + if_stage.v）

- br_stall：分支等待阻塞信号，定义为 load_stall & br_taken & ds_valid
- br_taken：分支是否成立
- br_target[31:0]：分支目标地址
- br_bus = {br_stall, br_taken, br_target}

IF 级使用方式：

- pre_if_ready_go = ~br_stall：遇到“分支成立但比较数依赖 load 未就绪”时，暂停取指
- fs_ready_go = ~br_taken：分支成立当拍不向下游发送旧顺序指令

### 10.5 仍未覆盖的冲突类型

- 当前实现未引入显式 flush 通路（通过阻塞与 PC 选择避免错误推进）
- 未实现异常/中断/CSR/TLB/MMU 等复杂控制冲突处理

## 11. 集成与使用建议

- 本目录提供可综合 Verilog 模块。
- 使用时将 mycpu_top.v 接入你的 SoC/仿真平台。
- 正确连接 resetn、指令/数据 SRAM 接口以及 debug 接口。
- 进行功能验证时，建议重点覆盖：
  - 普通 RAW 前递（EXE/MEM/WB -> ID）
  - load-use 阻塞 1 拍
  - 分支与 load-use 叠加场景（br_stall 生效）

## 12. 后续改进建议

若希望可稳定运行通用程序，建议按以下顺序增强：

1. 增加更完整的旁路网络（例如 ID/EXE 双向更细粒度前递）
2. 增加显式 flush 通路，统一处理跳转、异常等控制流改变
3. 扩展字节/半字访存与对齐检查
4. 增加异常与 CSR 支持
5. 增加 TLB/MMU 与虚拟内存支持

## 13. 许可说明

当前目录未包含 LICENSE 文件。若公开发布，建议补充许可证声明。
