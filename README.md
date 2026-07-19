# OurCPU：十级流水顺序双发射 LoongArch CPU

本项目是一套使用 Verilog 实现的 32 位 LoongArch CPU。当前 RTL 采用十级弹性流水线、顺序双发射和动态分支预测，集成双路组相联 ICache/DCache、CSR、精确异常与中断、TLB/MMU、LL/SC、Cache 维护、`DBAR`/`IBAR`、`IDLE` 以及 32 位 AXI 主接口。

设计采用保守的双发射策略：lane0 是完整功能主通路，lane1 是只执行普通整数 ALU 指令的 companion lane。满足配对条件时每拍最多发射、写回两条指令；不满足条件时在 Issue 中按程序顺序自动拆包，年轻指令随后转入 lane0，不丢失、不越序。

RTL 顶层为 `core_top`，复位入口 PC 为 `0x1c000000`。默认启用分支预测，可通过顶层参数 `ENABLE_BP=0` 关闭。未提供 Difftest 模块时不要定义 `SIMU`。

## 1. 总体结构

按当前 RTL 的模块边界，主流水线为：

```text
IF1 -> IF2 -> Fetch Queue -> Decode -> Issue
    -> EX1 -> EX2 -> Commit(EX3) -> MEM -> WB
```

这是十个从取指到写回的流水边界。`if1_stage` 内部包含 next-PC/地址翻译请求准备和 IF1b 请求描述寄存器；历史模块名 `ex3_stage` 在当前设计中承担 Commit 阶段。

```text
                         +---------------- Branch Predictor ----------------+
                         |                                                   |
                         v                                                   |
IF1 -> IF2 -> 4-entry Fetch Queue -> Decode x2 -> 2-slot Issue -> lane0 full pipe
                                                 |            \-> lane1 ALU pipe
                                                 |
                    EX1/EX2/EX3/MEM/WB x 2 producer forwarding
```

流水级之间使用 `valid/ready/fire` 握手。弹性寄存器在下游停顿时保持有效位和指令身份字段稳定，并支持在旧指令离开的同一拍接收新指令。异常、CSR/TLB 更新、LL/SC 状态、访存请求和 GPR 写回等副作用均由实际推进或提交事件触发。

## 2. 双字取指与双译码

取指前端支持每次返回两条连续的 32 位指令：

- ICache 返回 64 位数据、两位 `resp_word_valid`、请求 PC 和 4 位 fetch epoch。
- 当请求 PC 位于 8 字节块的低字时，顺序 next PC 为 `PC + 8`；位于高字时退化为单字取指并前进到 `PC + 4`。
- IF2 将返回值构造成两个各自携带 PC、异常和预测快照的 fetch slot。
- 若 slot0 被预测为 taken，则不会保留顺序路径上的 slot1。
- IF2 内有 4 项请求元数据队列和 4 项响应队列；其后还有 4 项、每项双 slot 的 Fetch Queue，用于隔离 ICache 返回与 Decode 反压。
- 两个 `id_stage` 实例同时译码 slot0/slot1，并分配连续的 `seq_id`；lane0 永远比同组 lane1 年老。

redirect 会递增 fetch epoch，并清空尚未进入后端的队列。旧 epoch 的 ICache 响应仍可返回，但会在 IF2 被识别并丢弃，从而避免错误路径指令重新进入流水线。

## 3. 顺序双发射策略

`issue_stage` 保存一个两槽 bundle，并统一完成数据相关检查、producer 解析、配对或拆包。

只有同时满足以下条件时，两条指令才会并发离开 Issue：

1. 两个 slot 都有效，且都是 `OP_CLASS_ALU` 普通整数 ALU 指令。
2. 两条指令都没有异常，也没有等待 CSR/TLB/ERTN 等串行化条件。
3. lane1 不读取 lane0 的目的寄存器，即组内无 RAW。
4. lane1 的源寄存器没有命中其他在途 producer；这是当前实现为 companion lane 采用的保守限制。
5. 两个执行通路都 ready，且两个操作数集合都已就绪。

不满足配对条件时只发射 lane0。若 bundle 中还有 slot1，Issue 会将其提升为下一拍的 lane0 指令，并保留已经解析出的最新操作数。

lane1 的边界与 lane0 锁步经过 EX1、EX2、EX3、MEM 和 WB，但只携带 ALU 结果、PC、指令、目的寄存器和顺序号。它不拥有访存、乘除法、分支恢复、CSR/TLB、系统指令、Cache/屏障或异常资源。因此：

- 满足条件的独立整数 ALU 序列峰值提交带宽为 2 IPC。
- 其他指令以及无法安全配对的 ALU 指令退化为顺序单发。
- lane0 发生异常或中断时，同组中更年轻的 lane1 会被取消。
- 同拍写同一 GPR 时，年轻的 lane1 写口优先；`r0` 始终保持为零。

## 4. 数据相关与前递

Decode 读取寄存器堆快照，Issue 再从两个 lane 的五个流水位置收集共 10 个统一 producer packet：

```text
lane0/lane1 × {EX1, EX2, EX3, MEM, WB}
```

每个 producer packet 包含：

```text
{valid, seq_id, dst_valid, dst, value_valid, value}
```

`producer_resolver` 只选择 `seq_id` 小于消费者的 producer，并从所有同名在途结果中选择程序顺序上最新的 older producer。只有所选结果的 `value_valid` 为真时消费者才能发射；load、CSR、乘除法、SC 等结果尚未就绪时，指令会稳定停留在 Issue。

寄存器堆使用逻辑 4R2W 接口，支持两个 Decode lane 同时读取和两个 WB lane 同时写入。读端带双写口 write-through，以处理读取与退休发生在同一时钟边沿的情况。

## 5. 分支预测与重定向

分支预测器默认启用，并只在指令真实提交时训练：

- 256 项、2 路组相联 BTB（128 组）。
- 256 项 gshare BHT，每项为 2 位饱和计数器。
- 8 位提交态全局历史。
- 16 项返回地址栈 RAS。
- 支持条件分支、直接跳转、间接跳转、call 和 return 类型。

IF1 对当前请求 PC 做异步预测查询。预测快照随 instruction packet 一直传到执行和提交阶段；EX1 计算实际 taken/target，并比较方向和目标。Commit 只训练未被异常或 ERTN 取消的真实提交指令，错误 BTB 命中的非控制流指令会使对应表项失效。

所有恢复请求都携带目标地址、原因、`seq_id` 和源 fetch epoch。重定向先按程序年龄仲裁；同龄请求的优先级为：

```text
ERTN > exception > IBAR > branch
```

## 6. 执行、提交与精确状态

- **EX1**：普通 ALU 早期结果、分支解析、访存虚地址、store 数据和写掩码。
- **EX2**：地址转换、异常预判、CSR/TLB 访问准备、流水乘法和迭代除法等待。
- **Commit / EX3**：精确异常、`ertn`、CSR/TLB 副作用、访存请求、`CACOP`、`DBAR`/`IBAR` 和 `IDLE` 的顺序提交点。
- **MEM**：load 返回数据处理、符号/零扩展以及 LL/SC 退休事件。
- **WB**：GPR 写回和调试提交信息。

lane0 承担全部体系结构副作用。lane1 只在与 lane0 对应的锁步边界允许推进时前进，并最终通过第二写口完成 GPR 写回。

## 7. MMU、TLB 与异常

取指和数据访问使用相同的地址转换规则：

```text
CRMD.PG == 0                -> 直接地址模式，VA 作为 PA
CRMD.PG == 1 且 DMW 命中   -> DMW 直接映射
CRMD.PG == 1 且 DMW 未命中 -> 查询 TLB
```

核心实例化 32 项全相联 TLB，提供两个查询端口、一个读端口和一个写端口，支持 ASID、全局位 `G`、4KB 以及 PS=21/22 的大页匹配。`invtlb` 支持 op 0～6。

已实现的主要异常包括：

- 普通异常：`INT`、`ADEF`、`ALE`、`SYS`、`BRK`、`INE`、`IPE`
- MMU/TLB 异常：`TLBR`、`PIF`、`PIL`、`PIS`、`PME`、`PPI`

CSR 包括 `CRMD`、`PRMD`、`ECFG`、`ESTAT`、`ERA`、`BADV`、`EENTRY`、TLB 相关 CSR、`ASID`、`PGDL/PGDH/PGD`、`SAVE0～3`、定时器、`LLBCTL`、`TLBRENTRY` 和 `DMW0/1` 等。

## 8. Cache、LL/SC 与 AXI

ICache 和 DCache 均为：

- 2 路组相联；
- 256 组；
- 16 Byte Cache line；
- 每行 4 个 32 位 bank；
- 整行回填使用 4 拍 AXI burst。

DCache 采用写回策略。数据访问的 `MAT == 2'b00` 时走非缓存通路，其他访问进入 DCache。非缓存访问使用单拍 AXI 事务；Cache 回填和 DCache 写回使用 4 拍 burst。

`CACOP` 支持按索引和按命中地址维护。`IBAR` 的全局流程为：

```text
等待数据侧空闲
  -> clean 全部 DCache 行
  -> 等待写回结束
  -> invalidate 全部 ICache 行
  -> 重定向到 IBAR PC + 4
```

`llsc_unit` 维护 LL/SC reservation，并在本核 store、DCache line invalidation、SC、异常返回及相关 `LLBCTL` 操作时更新预约状态。

顶层 AXI 接口的数据宽度为 32 位、ID 宽度为 4 位。`sram_axi_bridge_2x1` 一次处理一个事务，仲裁顺序为：

```text
uncached access > DCache writeback > DCache refill > ICache refill
```

## 9. 支持的指令

当前 Decode 覆盖的主要指令如下：

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

## 10. 顶层接口与工程集成

```verilog
module core_top #(
    parameter integer ENABLE_BP = 1
)(
    input aclk,
    input aresetn,
    input [7:0] intrpt,
    // 32-bit AXI master
    // debug/trace
    ...
);
```

主要接口：

- 32 位 AXI 主接口，4 位 ID，`arlen/awlen` 为 8 位，并保留 `wid` 和 2 位 `lock` 等工程接口信号。
- 8 路硬件中断 `intrpt[7:0]`。
- lane0 提交 trace：`debug0_wb_*`。
- 定义 `CPU_2CMT` 后提供 lane1 提交 trace：`debug1_wb_*`。
- 调试寄存器读取接口：`break_point`、`infor_flag`、`reg_num`、`ws_valid`、`rf_rdata`。

集成到仿真或 Vivado 工程时，应加入根目录下全部 `.v` 和 `.vh` 文件，包括 `branch_predictor.v`、`instruction_packet.v`、`producer_packet.v` 和 `companion_lane.v`。Vivado OOC/DCP 的使用方式见 `SYNTHESIS.md`。

## 11. 文件说明

| 文件 | 作用 |
| --- | --- |
| `core_top.v` | `core_top`、`mycpu_core`、Cache/Barrier/LLSC/Difftest 集成和 SRAM-like 到 AXI bridge |
| `if_stage.v` | IF1/IF2、预测 next PC、双字响应构造和 epoch 过滤 |
| `fetch_queue.v` | 4 项双 slot Fetch Queue |
| `branch_predictor.v` | BTB、gshare BHT、RAS 和提交训练逻辑 |
| `id_stage.v` | LoongArch 指令译码、源/目的描述和双写回寄存器快照 |
| `issue_stage.v` | 两槽顺序 Issue、producer 解析、配对、拆包和串行化 |
| `companion_lane.v` | 受限 lane1 ALU 锁步流水及其 producer/WB 输出 |
| `instruction_packet.v` | 统一 instruction packet 的 pack/unpack |
| `producer_packet.v` | producer packet、年龄过滤和 newest-older 选择 |
| `exe_stage.v` | EX1、EX2、Commit/EX3、分支解析、MMU、特权状态和提交 |
| `mem_stage.v` | load 数据处理及 LL/SC 退休事件 |
| `wb_stage.v` | lane0 GPR 写回和 debug trace |
| `regfile.v` | 基础寄存器堆和逻辑 4R2W 双 lane wrapper |
| `csr_regfile.v` | CSR、异常/中断、定时器、DMW 和 TLB CSR |
| `tlb.v` | 参数化全相联 TLB |
| `icache.v` / `dcache.v` | 双路组相联指令/数据 Cache |
| `barrier_ctrl.v` | `DBAR`/`IBAR` 控制 |
| `llsc_unit.v` | LL/SC reservation 管理 |
| `alu.v` | 整数 ALU、流水乘法器和迭代除法器 |
| `mycpu.vh` | 流水总线、packet 字段、操作类别、重定向与异常宏 |

## 12. 验证

环境需要 Icarus Verilog（`iverilog` 和 `vvp`）。

双发射专项测试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_dual_issue.ps1
```

该测试检查独立 ALU 双发射，以及 lane1 对 lane0 存在 RAW 时自动拆包且年轻指令不丢失。

分支预测与顶层 elaboration：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_branch_prediction.ps1
```

该脚本验证 BTB 两路分配、gshare BHT、RAS、BTB 失效，并分别在 `ENABLE_BP=1` 和 `ENABLE_BP=0` 下 elaboration `core_top`。

这些单元测试和 elaboration 不能替代完整 SoC 指令回归或 Difftest。系统级验证仍应重点覆盖：

- 连续独立 ALU 的稳定 2 IPC；
- 跨 8 字节边界取指、taken slot0 对 slot1 的取消；
- 组内 RAW 拆包、跨周期 RAW/WAW、load-use 和乘除法等待；
- 分支错误预测、异常、中断和 redirect 时 lane1 的取消；
- CSR/TLB、Cache miss、非缓存访问、LL/SC、`CACOP`、`DBAR/IBAR` 和 `IDLE`；
- 随机 backpressure 下不丢失、不重复、不乱序。

## 13. 当前限制

- lane1 仅支持无异常、固定延迟的普通整数 ALU 指令，不执行分支、访存、乘除法或特权/系统操作。

- slot1 使用顺序取指信息，不进行独立的 BTB/BHT/RAS 查询；slot0 预测 taken 时直接抑制 slot1。

- 双发射配对策略刻意保守：lane1 源寄存器命中任意在途 producer 时都会拆包，即使结果已经可以前递。

- 当前仓库中的专项测试主要覆盖 Issue 配对和分支预测，完整体系结构正确性仍需依赖 SoC 回归或 Difftest。

  
