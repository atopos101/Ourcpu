# OurCPU LoongArch CPU RTL

本仓库是一套使用 Verilog 实现的 32 位 LoongArch 顺序单发 CPU 设计。当前核心按 RTL 命名边界采用十级流水，集成取指前端、Fetch Queue、Decode/Issue、执行、顺序提交、CSR/异常/中断、TLB 地址转换、ICache/DCache、LL/SC、Cache 维护、`DBAR`/`IBAR`、`IDLE` 以及 32 位 AXI 主接口。

当前 RTL 顶层为 `core_top`。集成到 Vivado 或仿真工程时，将本目录下全部 `.v` 和 `.vh` 文件加入工程即可。未提供 Difftest 模块时不要定义 `SIMU`。

## Pipeline

核心按当前 RTL 的命名边界属于**十级单发射流水**：

```text
IF1(F0/F1) -> IF2(F2) -> Fetch Queue -> Decode -> Issue[0]
           -> EX1 -> EX2 -> Commit(EX3) -> MEM -> GPR WB
```

这里的十级是在原八级流水基础上加入 Fetch Queue 和 Issue 两个寄存边界得到的。
RTL 中 `if1_stage` 暂时封装 F0/F1，`if2_stage` 对应 F2，历史命名
`ex3_stage` 对应 Commit。如果把 `if1_stage` 内部的 F0 和 F1 也分别作为逻辑级
统计，则可以描述为十一段逻辑结构。

Fetch Queue 是一个 4 项、每项两 slot 的 FIFO，而不是只能保存一条指令的传统流水寄存器，
因此“十级”主要用于描述从取指到写回所经过的 RTL 边界，并不表示每条指令
始终占用十个单项流水寄存器。Fetch Queue 将已经返回的指令与 Decode 解耦；
当前 IF2 只填充 slot0。Decode 只生成源/目的描述和寄存器堆快照；Issue 使用统一
producer packet 解析最新的 older producer、等待结果并覆盖最终操作数，同时处理
CSR/TLB/ERTN 串行化。Issue/Commit 均暴露两 lane 契约，但 lane1 被断言保持关闭。

各级之间统一使用 `valid/ready/fire` 握手；边界名称成对对应，例如
`ex1_to_ex2_valid/ex1_to_ex2_ready`，只有两者同时为 1 的 `fire` 周期才推进。
所有弹性寄存级都支持下游接收旧指令的同拍接收新指令，并在停顿期间保持
`valid` 和 payload 不变；仿真版本包含相应断言。

边界推进条件统一写成 `fire = valid && ready`。Decode、Issue、EX1、EX2、
Commit(EX3)、MEM 以及 Fetch Queue 的寄存状态只在输入 `fire`（或本级为空、
需要吸收新的 valid）时更新。CSR/TLB、异常/ERTN、LL/SC 和 GPR 写回等体系
结构副作用均由 Commit/退休 `fire` 派生，而不是由驻留的 `valid` 单独触发。
重定向统一汇总到取指前端，优先级为：

```text
ERTN > exception > IBAR > branch
```

### 取指前端

`if_stage.v` 包含 `if1_stage`、`if2_stage` 和兼容外部接口的 `if_stage` 包装；
`fetch_queue.v` 提供 F2 与 Decode 之间的 4 项队列。

当前 `if1_stage` 已加入轻量 IF1b 寄存缓冲，用于切断原来的组合关键路径：

```text
PC/req_pc -> inst_vaddr -> TLB 翻译 -> inst_paddr/inst_trans_ex -> IF1 控制
```

IF1a 负责选择请求 PC、处理 redirect、输出 `inst_vaddr`。IF1b 寄存 `{pc, paddr, ex, ecode, esubcode, cancel}`，再由 IF1b 驱动 `inst_sram_req`、`inst_sram_addr` 和 `if1_to_if2_bus`。redirect 到来时会清掉尚未发射的 IF1b 请求；已经进入 IF2 或等待 ICache 返回的数据继续由 IF2 的 cancel/pending 机制丢弃。

### 执行与提交

- `EX1`：生成 ALU 早期结果、访存虚地址、store 数据和写掩码。
- `EX2`：执行 CSR/TLB 访问准备、地址转换、异常预判、乘法流水和迭代除法等待。
- `EX3`：作为特权状态提交点，最终发起异常、`ertn`、`ibar`、CSR/TLB 副作用、访存请求、`CACOP`、`DBAR`/`IBAR` 和 `IDLE`。
- `MEM`：处理 load 返回数据、符号/零扩展和 LL/SC 退休事件。
- `WB`：写回通用寄存器并输出 debug trace。

## File Overview

| 文件 | 说明 |
| --- | --- |
| `core_top.v` | 顶层 `core_top`、`mycpu_core`、SRAM-like 到 AXI bridge、Cache/Barrier/LLSC/Difftest 连接。 |
| `if_stage.v` | IF1/IF2 取指前端；IF1 内含 IF1b 翻译结果缓冲。 |
| `fetch_queue.v` | F2 到 Decode 的 4 项、两 slot fetch packet 队列，redirect 时清空。 |
| `id_stage.v` | 指令译码、源/目的描述生成和 lane 化寄存器堆读取。 |
| `issue_stage.v` | 两 lane 接口、lane0 弹性边界、统一 producer 解析和串行化判断；lane1 关闭。 |
| `instruction_packet.v` | 统一 instruction packet 的命名字段 pack/unpack 模块。 |
| `producer_packet.v` | 统一 producer packet 及 newest-older 选择器。 |
| `exe_stage.v` | EX1/EX2/EX3，包含执行、地址转换、CSR/TLB 和提交控制。 |
| `mem_stage.v` | load 数据处理、LL/SC 退休事件、MEM 到 WB 总线。 |
| `wb_stage.v` | 通用寄存器写回和 debug trace 输出。 |
| `csr_regfile.v` | CSR、异常入口、`ertn`、中断、定时器、DMW 和 TLB 相关 CSR。 |
| `tlb.v` | 参数化全相联 TLB，当前在 core 中以 32 项实例化。 |
| `icache.v` | 2 路组相联指令 Cache，256 组，16B 行。 |
| `dcache.v` | 2 路组相联数据 Cache，256 组，16B 行，写回策略。 |
| `barrier_ctrl.v` | `DBAR`/`IBAR` 控制器。 |
| `llsc_unit.v` | LL/SC reservation 状态维护。 |
| `alu.v` | ALU、流水乘法器和迭代除法器。 |
| `regfile.v` | 32 个 32 位通用寄存器及逻辑 4R2W lane wrapper；当前只启用 2R1W。 |
| `decoder_*.v` | 基础译码器模块。 |
| `mycpu.vh` | instruction packet 字段位号、流水总线宽度、重定向原因、异常码和中断位宏定义。 |

## Supported Features

主要支持的指令类型：

- 整数运算：`add.w`、`sub.w`、`slt`、`sltu`、`and`、`or`、`xor`、`nor`
- 立即数：`addi.w`、`slti`、`sltui`、`andi`、`ori`、`xori`、`lu12i.w`、`pcaddu12i`
- 移位：`slli.w`、`srli.w`、`srai.w`、`sll.w`、`srl.w`、`sra.w`
- 乘除法：`mul.w`、`mulh.w`、`mulh.wu`、`div.w`、`div.wu`、`mod.w`、`mod.wu`
- 访存：`ld.b`、`ld.h`、`ld.w`、`ld.bu`、`ld.hu`、`st.b`、`st.h`、`st.w`、`preld`
- 原子访存：`ll.w`、`sc.w`
- 分支跳转：`jirl`、`b`、`bl`、`beq`、`bne`、`blt`、`bge`、`bltu`、`bgeu`
- CSR/系统：`csrrd`、`csrwr`、`csrxchg`、`ertn`、`syscall`、`break`、`rdcntvl.w`、`rdcntvh.w`、`rdcntid`
- TLB：`tlbsrch`、`tlbrd`、`tlbwr`、`tlbfill`、`invtlb`
- Cache/同步：`cacop`、`dbar`、`ibar`、`idle`

主要 CSR：

```text
CRMD, PRMD, ECFG, ESTAT, ERA, BADV, EENTRY,
TLBIDX, TLBEHI, TLBELO0, TLBELO1, ASID,
PGDL, PGDH, PGD, CPUID,
SAVE0, SAVE1, SAVE2, SAVE3,
TID, TCFG, TVAL, TICLR, LLBCTL,
TLBRENTRY, DMW0, DMW1
```

## MMU and TLB

地址转换在 EX2 完成，取指和数据访存使用相同规则：

```text
CRMD.PG == 0              -> 直接地址模式，VA 作为 PA
CRMD.PG == 1 且 DMW 命中 -> 使用 DMW 直接映射窗口
CRMD.PG == 1 且 DMW 未命中 -> 查询 TLB
```

TLB 为全相联结构，core 中实例化 32 项，提供两个查询端口、一个读端口和一个写端口。支持 4KB、2MB、4MB 页面匹配，支持 ASID 和全局位 `G`。`tlbfill` 使用内部递增索引选择写入项，`invtlb` 支持 op 0 到 op 6。

已覆盖的异常类型包括：

- 普通异常：`INT`、`ADEF`、`ALE`、`SYS`、`BRK`、`INE`、`IPE`
- MMU/TLB 异常：`TLBR`、`PIF`、`PIL`、`PIS`、`PME`、`PPI`

## Cache and Memory

ICache 与 DCache 均为 2 路组相联、256 组、每行 16 Byte。每行由 4 个 32 位 bank 组成，通过 4 拍 AXI burst 完成整行回填。

DCache 使用写回策略。`MAT == 2'b00` 的数据访问走非缓存通路，其余访问走 DCache。非缓存访问在 AXI bridge 中以单拍事务发出；Cache miss、回填和写回使用 4 拍 burst。

`CACOP` 支持按索引和按命中地址维护。`IBAR` 由 `barrier_ctrl` 驱动，流程为：

```text
等待数据侧空闲 -> clean 全部 DCache 行 -> 等待写回完成 -> invalidate 全部 ICache 行 -> 重定向到 IBAR PC + 4
```

## Hazards and Forwarding

Issue 接收 EX1、EX2、Commit、MEM、WB 的统一 producer packet，按程序年龄从新到旧选择第一个同名 producer：

```text
EX1 > EX2 > EX3 > MEM > WB
```

只有 producer 的 `value_valid` 为真时才允许发射。load、CSR、乘除法、SC 等结果未就绪时，packet 稳定地停留在 Issue；Decode 可以与前端继续按 ready 条件解耦。CSR 写、`ertn` 和 TLB 状态改变由 Issue 的统一串行化输入阻塞 younger 指令。producer packet 携带 `seq_id`，仿真会检查所选 producer 必须比消费者更老。

## Integration

顶层接口在 `core_top.v`：

```verilog
module core_top(
    input aclk,
    input aresetn,
    ...
);
```

外部接口包括：

- 32 位 AXI 主接口，ID 宽度 4 位，数据宽度 32 位。
- 8 路硬件中断输入 `intrpt[7:0]`。
- debug trace 输出：`debug0_wb_pc`、`debug0_wb_rf_wen`、`debug0_wb_rf_wnum`、`debug0_wb_rf_wdata`。
- 调试读寄存器接口：`break_point`、`infor_flag`、`reg_num`、`ws_valid`、`rf_rdata`。

`sram_axi_bridge_2x1` 是单事务状态机，仲裁优先级为：

```text
uncached write/read > DCache writeback > DCache refill > ICache refill
```

## Verification and Timing Notes

在 PowerShell 中运行全部架构回归和 `core_top` elaboration：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_regression.ps1
```

当前回归包含：

- instruction packet 字段往返；
- EX1 分支 predicted/actual 解析和年龄优先 redirect；
- Fetch Queue 顺序/flush、epoch 旧响应丢弃和 payload-stable；
- producer 优先级、未就绪阻塞、Issue 唤醒与串行化；
- 两 slot Fetch Queue、4R2W wrapper 的 younger-WAW-wins；
- M0/M1/M2 乘法流水、符号高位结果；
- Decode→Issue→EX1 连续独立 packet 的稳定 1 IPC；
- 随机 source/sink backpressure 下不丢失、不重复、不乱序；
- `core_top` 完整 elaboration。

这些测试不替代 SoC 指令回归或 Difftest。完整系统仍需覆盖 load/store、CSR、异常、中断、TLB、Cache、LL/SC、DBAR/IBAR、IDLE 和非缓存访问。未提供 Difftest 模块时不要定义 `SIMU`。

当前前端已经加入 IF1b 取指翻译缓冲、4 位 fetch epoch 和 4 项 Fetch Queue。
取指请求及 ICache 返回均携带 epoch，IF2 只接收当前世代的响应，redirect 会
递增世代并逻辑清空队列。core/ICache 返回接口已预留为 64 位数据、两位
`word_valid`、响应 PC 和 epoch；当前保守地只返回 slot0（`word_valid=01`），
因此跨行、跨页和双指令 packet 不会引入额外异常处理。

后端增加双 lane 形状、只启用 lane0 的 Issue 边界，EX3 明确作为 Commit。
`tests/target_arch_tb.v` 覆盖 Fetch Queue 顺序/flush、redirect 后旧 ICache
响应丢弃、当前 epoch 响应入队、停顿期间 payload 稳定性以及 Issue
backpressure。Decode 已
通过统一 pack 模块生成 instruction packet，Issue/EX1/EX2/EX3 使用同一
unpack 模块；fetch epoch 和分支预测快照会写入 packet，并一直携带到 EX1/Commit。

控制流解析已统一移动到 EX1：条件分支、`B`/`BL` 和 `JIRL` 都从已寄存的
instruction packet 操作数计算 `actual_taken`、`actual_target` 与 fall-through PC，
再与 `pred_taken`/`pred_target` 比较方向和目标是否失配。所有恢复请求携带 target、
reason、`seq_id` 和源 fetch epoch，先按年龄、同龄再按
`ERTN > exception > IBAR > branch` 仲裁，并寄存一拍后送入 F0。Commit 会为真实提交的
控制流指令产生 predictor update，异常、ERTN 和未提交指令不会训练；`tests/redirect_branch_tb.v` 覆盖方向失配、
目标失配、JIRL 目标、年龄仲裁、同龄优先级和 redirect 单拍脉冲。
较老的 exception/ERTN/IBAR 会同时禁止 EX1 产生年轻恢复请求并 kill resolve 寄存器，
避免下一拍二次 redirect。非控制流指令若被 BTB 错误预测为 taken，EX1 会恢复到
`pc_next`，提交时以 `PRED_TYPE_NONE` 更新通知未来 BTB 使该项失效。

乘法器已切分为 M0 输入寄存、M1 DSP 乘积寄存和 M2 结果寄存。AXI
`arlen/awlen` 及内部长度寄存器统一为 8 位。核心内提供 `cycle_count`、
`commit_count`、前端/Issue stall、branch/mispredict 和 I/D Cache miss 等 64 位
性能计数器，可由仿真层次、ILA 或后续 CSR 映射读取。

当前已默认启用 256 项两路组相联 BTB、256 项两位计数器 gshare BHT、8 位提交态
全局历史和 16 项 RAS；`ENABLE_BP=0` 时仍可回退到静态不跳。专项回归命令为
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_branch_prediction.ps1`，
完整设计与实施说明见 `BRANCH_PREDICTION_PLAN.md`。lane1 仍永久无效，双发射配对
尚未实现。100 MHz routed setup 尚未达标，作为已知限制保留。
