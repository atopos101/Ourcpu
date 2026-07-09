`ifndef MYCPU_H
`define MYCPU_H

`define BR_BUS_WD       34

// Seven-stage pipeline bus widths. Phase 1 keeps the existing five-stage
// datapath intact and exposes these names as the migration boundary.
`define IF1_TO_IF2_BUS_WD 49    // {pc[31:0], req_cancel, ex, ecode[5:0], esubcode[8:0]}
`define IF2_TO_ID_BUS_WD  80    // {inst[31:0], pc[31:0], ex, ecode[5:0], esubcode[8:0]}
`define ID_TO_EX1_BUS_WD  250   // DS_TO_ES payload + instruction for aligned Difftest sideband
`define EX1_TO_EX2_BUS_WD 350   // {alu_result, mem_addr, store_wdata, store_wstrb, ID_TO_EX1 payload}
`define EX2_TO_EX3_BUS_WD 658   // {EX2 sideband, EX1_TO_EX2 payload}
`define EX3_TO_MEM_BUS_WD 107   // EX3_TO_MEM payload, same layout as ES_TO_MS
`define EX2_TO_MEM_BUS_WD 107   // legacy payload width

`define FS_TO_DS_BUS_WD 80    // {inst[31:0], pc[31:0], fs_ex, fs_ecode, fs_esubcode}
`define DS_TO_ES_BUS_WD 250   // previous fields + LL.W/SC.W + DBAR/IBAR + IDLE + instruction
`define ES_TO_MS_BUS_WD 107   // previous fields + LL/SC metadata
`define MS_TO_WS_BUS_WD 70    // unchanged
`define WS_TO_RF_BUS_WD 38    // unchanged

// Pipeline redirect causes, ordered by architectural priority in core_top.
`define REDIRECT_CAUSE_BRANCH 2'd0
`define REDIRECT_CAUSE_IBAR   2'd1
`define REDIRECT_CAUSE_EXCP   2'd2
`define REDIRECT_CAUSE_ERTN   2'd3

// Exception codes — LoongArch Vol1 §7.4.6 Table 7-8
`define ECODE_INT      6'h00
`define ECODE_PIL      6'h01
`define ECODE_PIS      6'h02
`define ECODE_PIF      6'h03
`define ECODE_PME      6'h04
`define ECODE_PPI      6'h07
`define ECODE_ADEF     6'h08  // ADEF, EsubCode=1 (non-TLB)
`define ECODE_ALE      6'h09  // ALE,  EsubCode=1 (non-TLB)
`define ECODE_SYSCALL  6'h0b
`define ECODE_BRK      6'h0c
`define ECODE_INE      6'h0d
`define ECODE_IPE      6'h0e
`define ECODE_TLBR     6'h3f

// Interrupt bit positions in ESTAT.IS / ECFG.LIE
`define INT_SWI0    0
`define INT_SWI1    1
`define INT_HWI0    2
`define INT_HWI7    9
`define INT_TI     11

`endif
