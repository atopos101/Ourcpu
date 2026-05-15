`ifndef MYCPU_H
`define MYCPU_H

`define BR_BUS_WD       34
`define FS_TO_DS_BUS_WD 65    // {inst[31:0], pc[31:0], fs_ex}
`define DS_TO_ES_BUS_WD 199   // 180 + ds_ex + ds_ecode + ds_esubcode + rdcnt fields
`define ES_TO_MS_BUS_WD 74    // unchanged
`define MS_TO_WS_BUS_WD 70    // unchanged
`define WS_TO_RF_BUS_WD 38    // unchanged

// Exception codes — LoongArch Vol1 §7.4.6 Table 7-8
`define ECODE_INT      6'h00
`define ECODE_ADEF     6'h08  // ADEF, EsubCode=1 (non-TLB)
`define ECODE_ALE      6'h09  // ALE,  EsubCode=1 (non-TLB)
`define ECODE_SYSCALL  6'h0b
`define ECODE_BRK      6'h0c
`define ECODE_INE      6'h0d

// Interrupt bit positions in ESTAT.IS / ECFG.LIE
`define INT_SWI0    0
`define INT_SWI1    1
`define INT_HWI0    2
`define INT_HWI7    9
`define INT_TI     11

`endif
