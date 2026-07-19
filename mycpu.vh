`ifndef MYCPU_H
`define MYCPU_H

// Seven-stage pipeline bus widths. Phase 1 keeps the existing five-stage
// datapath intact and exposes these names as the migration boundary.
`define FETCH_EPOCH_WD      4
`define FETCH_PRED_SNAPSHOT_WD 85 // {pc_next,pred_valid,taken,target,type,meta}
`define IF1_TO_IF2_BUS_WD 137    // request metadata plus prediction snapshot
`define IF2_TO_ID_BUS_WD  169    // legacy alias; full fetch packet
// Canonical instruction packet.  Keep every field position here: pipeline
// stages must use instruction_packet_pack/unpack instead of anonymous
// concatenations or numeric bit selects.
`define INST_PKT_INST_ERTN_BIT       0
`define INST_PKT_INST_SYSCALL_BIT    1
`define INST_PKT_CSR_NUM_HI         15
`define INST_PKT_CSR_NUM_LO          2
`define INST_PKT_CSR_OP_HI          17
`define INST_PKT_CSR_OP_LO          16
`define INST_PKT_RES_FROM_MEM_BIT   18
`define INST_PKT_PC_HI              50
`define INST_PKT_PC_LO              19
`define INST_PKT_RKD_VALUE_HI       82
`define INST_PKT_RKD_VALUE_LO       51
`define INST_PKT_RJ_VALUE_HI       114
`define INST_PKT_RJ_VALUE_LO        83
`define INST_PKT_IMM_HI            146
`define INST_PKT_IMM_LO            115
`define INST_PKT_DST_REG_HI        151
`define INST_PKT_DST_REG_LO        147
`define INST_PKT_MEM_WE_BIT        152
`define INST_PKT_DST_VALID_BIT     153
`define INST_PKT_SRC2_IS_4_BIT     154
`define INST_PKT_SRC2_IS_IMM_BIT   155
`define INST_PKT_SRC1_IS_PC_BIT    156
`define INST_PKT_MEM_UNSIGNED_BIT  157
`define INST_PKT_MEM_SIZE_HI       159
`define INST_PKT_MEM_SIZE_LO       158
`define INST_PKT_LOAD_OP_BIT       160
`define INST_PKT_ALU_OP_HI         179
`define INST_PKT_ALU_OP_LO         161
`define INST_PKT_CACOP_CODE_HI     184
`define INST_PKT_CACOP_CODE_LO     180
`define INST_PKT_CACOP_BIT         185
`define INST_PKT_INVTLB_OP_HI      190
`define INST_PKT_INVTLB_OP_LO      186
`define INST_PKT_TLB_OP_HI         193
`define INST_PKT_TLB_OP_LO         191
`define INST_PKT_RDCNTID_BIT       194
`define INST_PKT_RDCNTV_HI_BIT     195
`define INST_PKT_RDCNTV_BIT        196
`define INST_PKT_IDLE_BIT          197
`define INST_PKT_IBAR_BIT          198
`define INST_PKT_DBAR_BIT          199
`define INST_PKT_SC_W_BIT          200
`define INST_PKT_LL_W_BIT          201
`define INST_PKT_INST_HI           233
`define INST_PKT_INST_LO           202
`define INST_PKT_ESUBCODE_HI       242
`define INST_PKT_ESUBCODE_LO       234
`define INST_PKT_ECODE_HI          248
`define INST_PKT_ECODE_LO          243
`define INST_PKT_EXCEPTION_BIT     249
`define INST_PKT_SEQ_ID_HI         281
`define INST_PKT_SEQ_ID_LO         250
`define INST_PKT_LANE_ID_BIT       282
`define INST_PKT_FETCH_EPOCH_HI    290
`define INST_PKT_FETCH_EPOCH_LO    283
`define INST_PKT_PC_NEXT_HI        322
`define INST_PKT_PC_NEXT_LO        291
`define INST_PKT_PRED_VALID_BIT    323
`define INST_PKT_PRED_TAKEN_BIT    324
`define INST_PKT_PRED_TARGET_HI    356
`define INST_PKT_PRED_TARGET_LO    325
`define INST_PKT_PRED_TYPE_HI      359
`define INST_PKT_PRED_TYPE_LO      357
`define INST_PKT_PRED_META_HI      375
`define INST_PKT_PRED_META_LO      360
`define INST_PKT_SRC_VALID_HI      378
`define INST_PKT_SRC_VALID_LO      376
`define INST_PKT_SRC0_REG_HI       383
`define INST_PKT_SRC0_REG_LO       379
`define INST_PKT_SRC1_REG_HI       388
`define INST_PKT_SRC1_REG_LO       384
`define INST_PKT_SRC2_REG_HI       393
`define INST_PKT_SRC2_REG_LO       389
`define INST_PKT_OP_CLASS_HI       397
`define INST_PKT_OP_CLASS_LO       394
`define INST_PKT_BADV_HI           429
`define INST_PKT_BADV_LO           398

`define PRED_TYPE_NONE             3'd0
`define PRED_TYPE_CONDITIONAL      3'd1
`define PRED_TYPE_DIRECT           3'd2
`define PRED_TYPE_INDIRECT         3'd3
`define PRED_TYPE_RETURN           3'd4
`define PRED_TYPE_CALL             3'd5
`define OP_CLASS_ALU               4'd0
`define OP_CLASS_BRANCH            4'd1
`define OP_CLASS_MEMORY            4'd2
`define OP_CLASS_MULDIV            4'd3
`define OP_CLASS_CSR               4'd4
`define OP_CLASS_TLB               4'd5
`define OP_CLASS_SYSTEM            4'd6
`define OP_CLASS_BARRIER           4'd7

`define ID_TO_EX1_BUS_WD  430
`define BRANCH_RESULT_WD 35      // {is_control,taken,target,mispredict}
`define EX1_TO_EX2_BUS_WD (`ID_TO_EX1_BUS_WD + 100 + `BRANCH_RESULT_WD)
`define EX2_TO_EX3_BUS_WD (`EX1_TO_EX2_BUS_WD + 397)
`define EX3_PRIV_COMMIT_BUS_WD 306 // EX3 -> CSR/TLB architectural commit payload
`define EX3_TO_MEM_BUS_WD 140   // {seq_id,lane_id, legacy EX3/MEM payload}
`define EX2_TO_MEM_BUS_WD 140   // legacy alias

`define FS_TO_DS_BUS_WD 169   // instruction/fetch exception plus prediction snapshot
// Two-slot fetch packet.  Current IF2 sets only slot0_valid; slot1 remains a
// structural reservation until 64-bit fetch/decode consumption is enabled.
`define FETCH_PACKET_WD (2 + 2*`FS_TO_DS_BUS_WD)
`define DS_TO_ES_BUS_WD `ID_TO_EX1_BUS_WD
`define ES_TO_MS_BUS_WD 140   // canonical EX3/Commit -> MEM packet
`define MS_TO_WS_BUS_WD 103   // {seq_id,lane_id,GPR result packet}
`define WS_TO_RF_BUS_WD 38    // unchanged

// Canonical in-flight GPR producer description.  Producer packets are
// ordered newest-to-oldest when presented to Decode/Issue.  Keeping the age
// and readiness in one shape avoids adding another set of stage-specific
// hazard ports when lane1 is enabled later.
// {valid, seq_id, dst_valid, dst, value_valid, value}
`define PRODUCER_PACKET_WD       72
`define PRODUCER_VALUE_LO         0
`define PRODUCER_VALUE_HI        31
`define PRODUCER_VALUE_VALID_BIT 32
`define PRODUCER_DST_LO          33
`define PRODUCER_DST_HI          37
`define PRODUCER_DST_VALID_BIT   38
`define PRODUCER_SEQ_LO          39
`define PRODUCER_SEQ_HI          70
`define PRODUCER_VALID_BIT       71
// Five forwarding points for each architectural lane (EX1..WB).
`define PRODUCER_COUNT            10
`define PRODUCER_SET_WD (`PRODUCER_COUNT * `PRODUCER_PACKET_WD)

// Two architectural lane positions are exposed even though lane1 is held
// invalid in the static-not-taken single-issue baseline.
`define ARCH_LANE_COUNT 2

// Pipeline redirect causes, ordered by architectural priority in core_top.
`define REDIRECT_CAUSE_BRANCH 2'd0
`define REDIRECT_CAUSE_IBAR   2'd1
`define REDIRECT_CAUSE_EXCP   2'd2
`define REDIRECT_CAUSE_ERTN   2'd3

// Registered redirect packet: {target, reason, seq_id, source_epoch}.
// redirect_valid is kept separate so an invalid payload is a don't-care.
`define REDIRECT_PACKET_WD       (32 + 2 + 32 + `FETCH_EPOCH_WD)
`define REDIRECT_EPOCH_LO        0
`define REDIRECT_EPOCH_HI        (`FETCH_EPOCH_WD-1)
`define REDIRECT_SEQ_LO          `FETCH_EPOCH_WD
`define REDIRECT_SEQ_HI          (`FETCH_EPOCH_WD+31)
`define REDIRECT_REASON_LO       (`FETCH_EPOCH_WD+32)
`define REDIRECT_REASON_HI       (`FETCH_EPOCH_WD+33)
`define REDIRECT_TARGET_LO       (`FETCH_EPOCH_WD+34)
`define REDIRECT_TARGET_HI       (`FETCH_EPOCH_WD+65)

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
