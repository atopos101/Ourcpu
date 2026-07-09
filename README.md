# OurCPU LoongArch CPU RTL

本仓库是一套使用 Verilog 实现的 32 位 LoongArch 顺序单发 CPU 设计。当前核心采用八级流水，集成取指前端、译码、执行、CSR/异常/中断、TLB 地址转换、ICache/DCache、LL/SC、Cache 维护、`DBAR`/`IBAR`、`IDLE` 以及 32 位 AXI 主接口。

当前 RTL 顶层为 `core_top`。集成到 Vivado 或仿真工程时，将本目录下全部 `.v` 和 `.vh` 文件加入工程即可。未提供 Difftest 模块时不要定义 `SIMU`。

## Pipeline

核心流水结构如下：

```text
IF1 -> IF2 -> ID -> EX1 -> EX2 -> EX3 -> MEM -> WB
取指   回包   译码   前执行 后执行 提交/访存 访存   写回
```

各级之间使用 `valid/allowin` 握手。重定向统一汇总到取指前端，优先级为：

```text
ERTN > exception > IBAR > branch
```

### 取指前端

`if_stage.v` 包含 `if1_stage`、`if2_stage` 和兼容外部接口的 `if_stage` 包装。

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
| `id_stage.v` | 指令译码、寄存器读取、分支判断、前递选择和冒险控制。 |
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
| `regfile.v` | 32 个 32 位通用寄存器。 |
| `decoder_*.v` | 基础译码器模块。 |
| `mycpu.vh` | 流水总线宽度、重定向原因、异常码和中断位宏定义。 |

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

ID 级观察 EX1、EX2、EX3、MEM、WB 五个 older producer，前递优先级为：

```text
EX1 > EX2 > EX3 > MEM > WB
```

只有 producer 的 `result_ready` 为真时才允许前递。load、CSR、乘除法、SC 等结果未就绪时会阻塞 ID。CSR 写后读、`ertn`、TLB 指令和异常状态相关操作会触发额外阻塞，避免 younger 指令提前观察特权状态变化。

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

本仓库当前不包含独立 testbench、SoC harness、镜像加载脚本或约束文件。建议最小检查流程：

```text
1. 将本目录全部 .v/.vh 文件加入 Vivado、iverilog 或 Verilator 工程。
2. 未提供 Difftest 模块时不要定义 SIMU。
3. 以 core_top 为顶层做语法分析、elaboration、综合和实现。
4. 在 SoC/testbench 中覆盖算术、分支、load/store、CSR、异常、中断、TLB、Cache、LL/SC、DBAR/IBAR、IDLE 和非缓存访问。
```

当前前端已经加入 IF1b 取指翻译缓冲，功能仿真已按顺序取指、redirect、ADEF、TLB 异常、IDLE/IBAR 等场景验证通过。55MHz 约束下，IF1/TLB/PC 组合闭环已不再是首要关键路径；后续提频需要继续针对新的 routed worst path 做局部优化。
