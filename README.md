# myCPU：46 条 LoongArch 指令的五级流水线 CPU

## 1. 项目简介

本项目实现了一个简化的 32 位 LoongArch 风格 CPU，采用经典五级流水线结构：

- IF：取指（Instruction Fetch）
- ID：译码/读寄存器/分支决策（Instruction Decode）
- EXE：执行/地址计算/Store 写控制（Execute）
- MEM：访存读数据处理（Memory Access）
- WB：写回（Write Back）

本版本设计目标：

- 支持 exp11 要求的 46 条用户态指令。
- 支持转移指令 `blt`、`bge`、`bltu`、`bgeu`。
- 支持字节/半字访存指令 `ld.b`、`ld.h`、`ld.bu`、`ld.hu`、`st.b`、`st.h`。
- 支持 RAW 数据前递、load-use 阻塞，以及分支等待 load 数据时的取指阻塞。
- 采用 valid/allowin 流水握手机制。
- 对外提供类 SRAM 的指令/数据接口与写回调试接口。

顶层模块：`mycpu_top.v`。

## 2. 目录与文件说明

- `mycpu_top.v`：CPU 顶层，连接五级流水线。
- `mycpu.vh`：全局宏定义，包含各级总线位宽。
- `if_stage.v`：IF 级，维护 PC、取指、处理分支重定向。
- `id_stage.v`：ID 级，完成译码、寄存器读取、分支判断、冒险检测和前递选择。
- `exe_stage.v`：EXE 级，执行 ALU 运算，生成 Store 写掩码和对齐后的写数据。
- `mem_stage.v`：MEM 级，按访存类型完成 Load 数据选择、符号扩展或零扩展。
- `wb_stage.v`：WB 级，写回寄存器堆并输出 debug trace 信号。
- `alu.v`：算术逻辑单元。
- `regfile.v`：32x32 寄存器堆（2 读 1 写）。
- `decoder_2_4.v` / `decoder_4_16.v` / `decoder_5_32.v` / `decoder_6_64.v`：译码器模块。
- `output/exp11/myCPU/`：exp11 验证环境使用的 CPU RTL 副本。
- `output/exp11/soc_verify/soc_bram/run_vivado/run_func_sim.tcl`：用于 Vivado xsim 跑 exp11 func 的 batch 脚本。

## 3. 五级流水线结构

### 3.1 IF 级（if_stage.v）

主要功能：

- 保存当前 PC。
- 计算 nextpc：
  - 顺序执行：`pc + 4`
  - 分支跳转：来自 `br_bus` 的 `br_target`
- 访问指令存储器。
- 向 ID 级发送 `{inst, pc}`。

关键实现点：

- `fs_ready_go = ~br_taken`：当本拍确定跳转时，IF 不向下游发送旧顺序指令。
- `pre_if_ready_go = ~br_stall`：分支依赖 load 且尚未取回数据时，暂停发起下一次取指。
- 复位时 `fs_pc` 初始化为 `32'h1bfffffc`，使下一拍 `nextpc` 为 `32'h1c000000`。

### 3.2 ID 级（id_stage.v）

主要功能：

- 锁存 IF 级传来的指令与 PC。
- 通过多级译码器解析操作码字段。
- 生成 ALU、访存、写回和分支控制信号。
- 读取寄存器堆并选择 EXE/MEM/WB 前递数据。
- 在本级完成分支是否跳转判断与目标地址计算。
- 打包 `ds_to_es_bus` 发送到 EXE 级。

分支处理在 ID 级完成：

- `beq` / `bne`：比较 `rj_value` 与 `rkd_value` 是否相等。
- `blt` / `bge`：按有符号数比较 `rj_value` 与 `rkd_value`。
- `bltu` / `bgeu`：按无符号数比较 `rj_value` 与 `rkd_value`。
- `jirl` / `bl` / `b`：直接给出跳转决策。
- 输出 `br_bus = {br_stall, br_taken, br_target}`。

### 3.3 EXE 级（exe_stage.v）

主要功能：

- 锁存 ID 级总线。
- 选择 ALU 两个输入源。
- 执行 ALU 运算，访存类指令用 ALU 结果作为有效地址。
- 根据 `mem_size` 生成 `st.b` / `st.h` / `st.w` 的字节写掩码。
- 根据地址低位对 Store 写数据进行移位或复制。
- 将结果和访存属性打包到 `es_to_ms_bus`。

Store 写使能行为：

- `st.b`：`data_sram_we = 4'b0001 << addr[1:0]`。
- `st.h`：地址低位 `addr[1]` 为 0 时写低半字，为 1 时写高半字。
- `st.w`：`data_sram_we = 4'b1111`。
- 非有效 Store 指令：`data_sram_we = 4'b0000`。

### 3.4 MEM 级（mem_stage.v）

主要功能：

- 锁存 EXE 级总线。
- 对 Load 指令按地址低位选择字节、半字或字。
- `ld.b` / `ld.h` 做符号扩展。
- `ld.bu` / `ld.hu` 做零扩展。
- 非 Load 指令直接使用 ALU 结果作为最终结果。
- 打包并发送到 WB 级。

### 3.5 WB 级（wb_stage.v）

主要功能：

- 锁存 MEM 级总线。
- 产生寄存器堆写回总线 `ws_to_rf_bus`。
- 输出调试接口信号：
  - `debug_wb_pc`
  - `debug_wb_rf_we`
  - `debug_wb_rf_wnum`
  - `debug_wb_rf_wdata`

## 4. 流水线握手机制

各级都采用相同握手语义：

- `stage_valid`：当前级是否持有有效指令。
- `stage_ready_go`：当前级内部是否可向下游发送。
- `stage_allowin`：当前级是否可接收上游新指令。
- `stage_to_next_valid`：当前级对下游的 valid。

通用关系：

- `allowin = !valid || (ready_go && next_allowin)`
- `to_next_valid = valid && ready_go`

本实现中：

- IF 级 `ready_go` 受分支信号影响（`~br_taken`）。
- ID 级 `ready_go` 受 `load_stall` 影响（`~load_stall`）。
- EXE/MEM/WB 级当前均为始终就绪。

## 5. 级间总线与位宽定义

宏定义位于 `mycpu.vh`：

- `BR_BUS_WD       = 34`
- `FS_TO_DS_BUS_WD = 64`
- `DS_TO_ES_BUS_WD = 162`
- `ES_TO_MS_BUS_WD = 74`
- `MS_TO_WS_BUS_WD = 70`
- `WS_TO_RF_BUS_WD = 38`

### 5.1 BR bus（ID -> IF）

- `{br_stall[1], br_taken[1], br_target[32]}`，共 34 位。

### 5.2 FS_TO_DS bus（IF -> ID）

- `{fs_inst[32], fs_pc[32]}`，共 64 位。

### 5.3 DS_TO_ES bus（ID -> EXE）

字段打包顺序：

- `alu_op[18:0]`（19）
- `load_op`（1）
- `mem_size[1:0]`（2）
- `mem_unsigned`（1）
- `src1_is_pc`（1）
- `src2_is_imm`（1）
- `src2_is_4`（1）
- `gr_we`（1）
- `mem_we`（1）
- `dest[4:0]`（5）
- `imm[31:0]`（32）
- `rj_value[31:0]`（32）
- `rkd_value[31:0]`（32）
- `ds_pc[31:0]`（32）
- `res_from_mem`（1）

合计 162 位。

### 5.4 ES_TO_MS bus（EXE -> MEM）

字段打包顺序：

- `res_from_mem`（1）
- `mem_size[1:0]`（2）
- `mem_unsigned`（1）
- `gr_we`（1）
- `dest[4:0]`（5）
- `alu_result[31:0]`（32）
- `es_pc[31:0]`（32）

合计 74 位。

### 5.5 MS_TO_WS bus（MEM -> WB）

字段打包顺序：

- `gr_we`（1）
- `dest[4:0]`（5）
- `final_result[31:0]`（32）
- `pc[31:0]`（32）

合计 70 位。

### 5.6 WS_TO_RF bus（WB -> ID/regfile）

字段打包顺序：

- `rf_we`（1）
- `rf_waddr[4:0]`（5）
- `rf_wdata[31:0]`（32）

合计 38 位。

## 6. 已支持指令（共 46 条）

算术/逻辑类：

1. `add.w`
2. `sub.w`
3. `slt`
4. `sltu`
5. `nor`
6. `and`
7. `or`
8. `xor`
9. `slti`
10. `sltui`
11. `andi`
12. `ori`
13. `xori`

移位类：

14. `slli.w`
15. `srli.w`
16. `srai.w`
17. `sll.w`
18. `srl.w`
19. `sra.w`

立即数/PC 类：

20. `addi.w`
21. `lu12i.w`
22. `pcaddu12i`

乘除法类：

23. `mul.w`
24. `mulh.w`
25. `mulh.wu`
26. `div.w`
27. `div.wu`
28. `mod.w`
29. `mod.wu`

访存类：

30. `ld.b`
31. `ld.h`
32. `ld.w`
33. `ld.bu`
34. `ld.hu`
35. `st.b`
36. `st.h`
37. `st.w`

跳转/分支类：

38. `jirl`
39. `b`
40. `bl`
41. `beq`
42. `bne`
43. `blt`
44. `bge`
45. `bltu`
46. `bgeu`

## 7. ALU 说明

ALU 控制信号宽度为 19 位（`alu_op[18:0]`），支持：

- 加减法和比较：`add` / `sub` / `slt` / `sltu`
- 逻辑运算：`and` / `nor` / `or` / `xor`
- 移位：`sll` / `srl` / `sra`
- 高位立即数装载：`lui`
- 乘除与取余：`mul` / `mulh` / `mulhu` / `div` / `divu` / `mod` / `modu`

EXE 级输入选择：

- `alu_src1 = src1_is_pc ? es_pc : rj_value`
- `alu_src2 = src2_is_imm ? imm : rkd_value`

## 8. 访存类型说明

ID 级生成的访存属性：

- `load_op`：当前指令是否为 Load。
- `mem_size`：
  - `2'b00`：字节访问。
  - `2'b01`：半字访问。
  - `2'b10`：字访问。
- `mem_unsigned`：Load 是否零扩展，仅对 `ld.bu` / `ld.hu` 有效。
- `mem_we`：当前指令是否为 Store。

EXE 级依据 `mem_size` 和地址低位生成 `data_sram_we` 与对齐后的 `data_sram_wdata`。MEM 级依据 `mem_size`、`mem_unsigned` 和地址低位生成写回寄存器的数据。

当前实现未增加未对齐异常检查，exp11 范围内按测试程序使用的合法地址完成访存。

## 9. 寄存器堆说明

`regfile.v` 实现 32 个通用寄存器（每个 32 位）：

- 双读口（组合读）。
- 单写口（时钟上升沿写）。
- 0 号寄存器读出恒为 0。

## 10. 对外接口说明

### 10.1 指令 SRAM 接口

输出：

- `inst_sram_en`
- `inst_sram_we[3:0]`：恒为 0，仅取指。
- `inst_sram_addr[31:0]`
- `inst_sram_wdata[31:0]`：未使用，置 0。

输入：

- `inst_sram_rdata[31:0]`

### 10.2 数据 SRAM 接口

输出：

- `data_sram_en`：当前实现恒为 1。
- `data_sram_we[3:0]`：按 `st.b` / `st.h` / `st.w` 生成字节写掩码。
- `data_sram_addr[31:0]`
- `data_sram_wdata[31:0]`：Store 数据按地址低位对齐后输出。

输入：

- `data_sram_rdata[31:0]`

### 10.3 回写调试接口

- `debug_wb_pc`
- `debug_wb_rf_we`
- `debug_wb_rf_wnum`
- `debug_wb_rf_wdata`

## 11. 阻塞冲突与数据前递信号说明

本实现在 ID 级完成相关检测，并通过跨级反馈信号实现“可前递时前递、不能前递时阻塞”。

### 11.1 顶层跨级冲突信息通道（mycpu_top.v）

- `es_to_ds_dest[4:0]`：EXE 级写回目的寄存器号，反馈给 ID 用于 RAW 相关判断。
- `ms_to_ds_dest[4:0]`：MEM 级写回目的寄存器号，反馈给 ID 用于 RAW 相关判断。
- `ws_to_ds_dest[4:0]`：WB 级写回目的寄存器号，反馈给 ID 用于 RAW 相关判断。
- `es_to_ds_load_op`：EXE 级当前是否为 Load 指令，用于判断是否需要 load-use 阻塞。
- `es_to_ds_result[31:0]`：EXE 级可前递结果（ALU 结果）。
- `ms_to_ds_result[31:0]`：MEM 级可前递结果（最终结果）。
- `ws_to_ds_result[31:0]`：WB 级可前递结果（最终写回值）。

### 11.2 ID 级相关检测信号（id_stage.v）

- `rj_wait` / `rk_wait` / `rd_wait`：当前指令源操作数是否与 EXE/MEM/WB 任一目的寄存器重名。
- `src_no_rj` / `src_no_rk` / `src_no_rd`：当前指令是否实际使用对应源寄存器，避免误判。
- `load_stall`：load-use 阻塞条件信号。

`load_stall` 判定逻辑：

- EXE 级是 Load（`es_to_ds_load_op = 1`）。
- ID 当前要读取的源寄存器命中 EXE 的目的寄存器。

当 `load_stall = 1` 时：

- `ds_ready_go = ds_valid && ~load_stall` 变为 0。
- ID 不向 EXE 发送新指令（`ds_to_es_valid` 被抑制）。
- IF 通过 `ds_allowin` 链路被背压，形成流水暂停。

### 11.3 数据前递选择信号（id_stage.v）

ID 级读数优先级：EXE > MEM > WB > regfile。

- `rj_value`：当 `rj_wait = 1` 时，从 `es/ms/ws_to_ds_result` 中按优先级选择；否则取 `rf_rdata1`。
- `rkd_value`：对 `rk` 或 `rd`（取决于指令类型）采用同样的前递选择；否则取 `rf_rdata2`。

该机制保证：

- 对于可由 EXE/MEM/WB 当拍提供的数据，直接前递，避免无谓停顿。
- 仅在“EXE 为 Load 且 ID 立即使用该结果”时停顿 1 拍。

### 11.4 分支相关阻塞信号（id_stage.v + if_stage.v）

- `br_stall`：分支等待阻塞信号，定义为 `load_stall & br_taken & ds_valid`。
- `br_taken`：分支是否成立。
- `br_target[31:0]`：分支目标地址。
- `br_bus = {br_stall, br_taken, br_target}`。

IF 级使用方式：

- `pre_if_ready_go = ~br_stall`：遇到“分支成立但比较数依赖 Load 未就绪”时，暂停取指。
- `fs_ready_go = ~br_taken`：分支成立当拍不向下游发送旧顺序指令。

### 11.5 仍未覆盖的冲突类型

- 当前实现未引入显式 flush 通路，通过阻塞与 PC 选择避免错误推进。
- 未实现异常、中断、CSR、TLB、MMU 等复杂控制逻辑。

## 12. exp11 func 验证说明

exp11 的 testbench 默认从 `output/exp11/myCPU/` 读取 CPU RTL。完成 RTL 修改后，需要将根目录 `*.v` / `*.vh` 同步到该目录。

本次验证使用 Vivado 2019.1 xsim，因 Windows 长路径与 IP 仿真模型问题，对 exp11 环境做了以下兼容处理：

- 将 exp11 环境复制到短路径 `C:\tmp\ourcpu_exp11` 运行 Vivado batch，避免 Vivado 2019.1 对 `Documents` 路径规范化异常。
- 在 Vivado 仿真文件集中加入 `testbench/sync_ram.v`，作为 `inst_ram` / `data_ram` 的仿真模型。
- 修正 `sync_ram.v` 中 Vivado 不接受的数组范围与端口方向写法。

已观察到 exp11 func 的 n1~n46 均通过，xsim 日志包含：

```text
Number 8'd46 Functional Test Point PASS!!!
Test end!
----PASS!!!
$finish called at time : 1161315 ns
```

程序到达 `test_finish` 后会执行 `1c000110: b 0` 自旋。如果日志里后续持续看到 `debug_wb_pc = 0x1c000110`，这是测试结束后的停车循环；判断是否通过应以 `Test end!` 和 `----PASS!!!` 为准。

## 13. 集成与使用建议

- 本目录提供可综合 Verilog 模块。
- 使用时将 `mycpu_top.v` 接入 SoC/仿真平台。
- 正确连接 `resetn`、指令/数据 SRAM 接口以及 debug 接口。
- 进行功能验证时，建议重点覆盖：
  - 普通 RAW 前递（EXE/MEM/WB -> ID）。
  - load-use 阻塞 1 拍。
  - 分支与 load-use 叠加场景（`br_stall` 生效）。
  - `blt` / `bge` / `bltu` / `bgeu` 的有符号和无符号边界比较。
  - `ld.b` / `ld.h` 的符号扩展和 `ld.bu` / `ld.hu` 的零扩展。
  - `st.b` / `st.h` 在不同地址低位下的写掩码和写数据对齐。

## 14. 后续改进建议

若希望可稳定运行更完整的系统程序，建议按以下顺序增强：

1. 增加更完整的旁路网络，例如 ID/EXE 双向更细粒度前递。
2. 增加显式 flush 通路，统一处理跳转、异常等控制流改变。
3. 增加访存未对齐异常检查。
4. 增加异常与 CSR 支持。
5. 增加 TLB/MMU 与虚拟内存支持。

## 15. 许可说明

当前目录未包含 LICENSE 文件。若公开发布，建议补充许可证声明。
