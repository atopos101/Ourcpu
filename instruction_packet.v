`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// The only construction point for Decode -> Issue instruction packets.
module instruction_packet_pack(
    output [`ID_TO_EX1_BUS_WD-1:0] packet,
    input exception_valid, input [5:0] ecode, input [8:0] esubcode,
    input [31:0] inst, input inst_ll_w, input inst_sc_w,
    input inst_dbar, input inst_ibar, input inst_idle,
    input rdcntv, input rdcntv_hi, input rdcntid,
    input [2:0] tlb_op, input [4:0] invtlb_op,
    input inst_cacop, input [4:0] cacop_code,
    input [18:0] alu_op, input load_op, input [1:0] mem_size,
    input mem_unsigned, input src1_is_pc, input src2_is_imm,
    input src2_is_4, input dst_valid, input mem_we,
    input [4:0] dst_reg, input [31:0] immediate,
    input [31:0] rj_value, input [31:0] rkd_value,
    input [31:0] pc, input res_from_mem,
    input [1:0] csr_op, input [13:0] csr_num,
    input inst_syscall, input inst_ertn,
    input [31:0] seq_id, input lane_id, input [7:0] fetch_epoch,
    input [31:0] pc_next, input pred_valid, input pred_taken,
    input [31:0] pred_target, input [2:0] pred_type,
    input [15:0] pred_meta, input [2:0] src_valid,
    input [4:0] src0_reg, input [4:0] src1_reg, input [4:0] src2_reg,
    input [3:0] op_class, input [31:0] badv
);
assign packet[`INST_PKT_INST_ERTN_BIT] = inst_ertn;
assign packet[`INST_PKT_INST_SYSCALL_BIT] = inst_syscall;
assign packet[`INST_PKT_CSR_NUM_HI:`INST_PKT_CSR_NUM_LO] = csr_num;
assign packet[`INST_PKT_CSR_OP_HI:`INST_PKT_CSR_OP_LO] = csr_op;
assign packet[`INST_PKT_RES_FROM_MEM_BIT] = res_from_mem;
assign packet[`INST_PKT_PC_HI:`INST_PKT_PC_LO] = pc;
assign packet[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rkd_value;
assign packet[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] = rj_value;
assign packet[`INST_PKT_IMM_HI:`INST_PKT_IMM_LO] = immediate;
assign packet[`INST_PKT_DST_REG_HI:`INST_PKT_DST_REG_LO] = dst_reg;
assign packet[`INST_PKT_MEM_WE_BIT] = mem_we;
assign packet[`INST_PKT_DST_VALID_BIT] = dst_valid;
assign packet[`INST_PKT_SRC2_IS_4_BIT] = src2_is_4;
assign packet[`INST_PKT_SRC2_IS_IMM_BIT] = src2_is_imm;
assign packet[`INST_PKT_SRC1_IS_PC_BIT] = src1_is_pc;
assign packet[`INST_PKT_MEM_UNSIGNED_BIT] = mem_unsigned;
assign packet[`INST_PKT_MEM_SIZE_HI:`INST_PKT_MEM_SIZE_LO] = mem_size;
assign packet[`INST_PKT_LOAD_OP_BIT] = load_op;
assign packet[`INST_PKT_ALU_OP_HI:`INST_PKT_ALU_OP_LO] = alu_op;
assign packet[`INST_PKT_CACOP_CODE_HI:`INST_PKT_CACOP_CODE_LO] = cacop_code;
assign packet[`INST_PKT_CACOP_BIT] = inst_cacop;
assign packet[`INST_PKT_INVTLB_OP_HI:`INST_PKT_INVTLB_OP_LO] = invtlb_op;
assign packet[`INST_PKT_TLB_OP_HI:`INST_PKT_TLB_OP_LO] = tlb_op;
assign packet[`INST_PKT_RDCNTID_BIT] = rdcntid;
assign packet[`INST_PKT_RDCNTV_HI_BIT] = rdcntv_hi;
assign packet[`INST_PKT_RDCNTV_BIT] = rdcntv;
assign packet[`INST_PKT_IDLE_BIT] = inst_idle;
assign packet[`INST_PKT_IBAR_BIT] = inst_ibar;
assign packet[`INST_PKT_DBAR_BIT] = inst_dbar;
assign packet[`INST_PKT_SC_W_BIT] = inst_sc_w;
assign packet[`INST_PKT_LL_W_BIT] = inst_ll_w;
assign packet[`INST_PKT_INST_HI:`INST_PKT_INST_LO] = inst;
assign packet[`INST_PKT_ESUBCODE_HI:`INST_PKT_ESUBCODE_LO] = esubcode;
assign packet[`INST_PKT_ECODE_HI:`INST_PKT_ECODE_LO] = ecode;
assign packet[`INST_PKT_EXCEPTION_BIT] = exception_valid;
assign packet[`INST_PKT_SEQ_ID_HI:`INST_PKT_SEQ_ID_LO] = seq_id;
assign packet[`INST_PKT_LANE_ID_BIT] = lane_id;
assign packet[`INST_PKT_FETCH_EPOCH_HI:`INST_PKT_FETCH_EPOCH_LO] = fetch_epoch;
assign packet[`INST_PKT_PC_NEXT_HI:`INST_PKT_PC_NEXT_LO] = pc_next;
assign packet[`INST_PKT_PRED_VALID_BIT] = pred_valid;
assign packet[`INST_PKT_PRED_TAKEN_BIT] = pred_taken;
assign packet[`INST_PKT_PRED_TARGET_HI:`INST_PKT_PRED_TARGET_LO] = pred_target;
assign packet[`INST_PKT_PRED_TYPE_HI:`INST_PKT_PRED_TYPE_LO] = pred_type;
assign packet[`INST_PKT_PRED_META_HI:`INST_PKT_PRED_META_LO] = pred_meta;
assign packet[`INST_PKT_SRC_VALID_HI:`INST_PKT_SRC_VALID_LO] = src_valid;
assign packet[`INST_PKT_SRC0_REG_HI:`INST_PKT_SRC0_REG_LO] = src0_reg;
assign packet[`INST_PKT_SRC1_REG_HI:`INST_PKT_SRC1_REG_LO] = src1_reg;
assign packet[`INST_PKT_SRC2_REG_HI:`INST_PKT_SRC2_REG_LO] = src2_reg;
assign packet[`INST_PKT_OP_CLASS_HI:`INST_PKT_OP_CLASS_LO] = op_class;
assign packet[`INST_PKT_BADV_HI:`INST_PKT_BADV_LO] = badv;
endmodule

// Shared field access for every downstream consumer.  Named ports make
// omitted fields explicit and keep consumers independent of packet layout.
module instruction_packet_unpack(
    input [`ID_TO_EX1_BUS_WD-1:0] packet,
    output exception_valid, output [5:0] ecode, output [8:0] esubcode,
    output [31:0] inst, output inst_ll_w, output inst_sc_w,
    output inst_dbar, output inst_ibar, output inst_idle,
    output rdcntv, output rdcntv_hi, output rdcntid,
    output [2:0] tlb_op, output [4:0] invtlb_op,
    output inst_cacop, output [4:0] cacop_code,
    output [18:0] alu_op, output load_op, output [1:0] mem_size,
    output mem_unsigned, output src1_is_pc, output src2_is_imm,
    output src2_is_4, output dst_valid, output mem_we,
    output [4:0] dst_reg, output [31:0] immediate,
    output [31:0] rj_value, output [31:0] rkd_value,
    output [31:0] pc, output res_from_mem,
    output [1:0] csr_op, output [13:0] csr_num,
    output inst_syscall, output inst_ertn,
    output [31:0] seq_id, output lane_id, output [7:0] fetch_epoch,
    output [31:0] pc_next, output pred_valid, output pred_taken,
    output [31:0] pred_target, output [2:0] pred_type,
    output [15:0] pred_meta, output [2:0] src_valid,
    output [4:0] src0_reg, output [4:0] src1_reg, output [4:0] src2_reg,
    output [3:0] op_class, output [31:0] badv
);
assign inst_ertn = packet[`INST_PKT_INST_ERTN_BIT];
assign inst_syscall = packet[`INST_PKT_INST_SYSCALL_BIT];
assign csr_num = packet[`INST_PKT_CSR_NUM_HI:`INST_PKT_CSR_NUM_LO];
assign csr_op = packet[`INST_PKT_CSR_OP_HI:`INST_PKT_CSR_OP_LO];
assign res_from_mem = packet[`INST_PKT_RES_FROM_MEM_BIT];
assign pc = packet[`INST_PKT_PC_HI:`INST_PKT_PC_LO];
assign rkd_value = packet[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO];
assign rj_value = packet[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO];
assign immediate = packet[`INST_PKT_IMM_HI:`INST_PKT_IMM_LO];
assign dst_reg = packet[`INST_PKT_DST_REG_HI:`INST_PKT_DST_REG_LO];
assign mem_we = packet[`INST_PKT_MEM_WE_BIT];
assign dst_valid = packet[`INST_PKT_DST_VALID_BIT];
assign src2_is_4 = packet[`INST_PKT_SRC2_IS_4_BIT];
assign src2_is_imm = packet[`INST_PKT_SRC2_IS_IMM_BIT];
assign src1_is_pc = packet[`INST_PKT_SRC1_IS_PC_BIT];
assign mem_unsigned = packet[`INST_PKT_MEM_UNSIGNED_BIT];
assign mem_size = packet[`INST_PKT_MEM_SIZE_HI:`INST_PKT_MEM_SIZE_LO];
assign load_op = packet[`INST_PKT_LOAD_OP_BIT];
assign alu_op = packet[`INST_PKT_ALU_OP_HI:`INST_PKT_ALU_OP_LO];
assign cacop_code = packet[`INST_PKT_CACOP_CODE_HI:`INST_PKT_CACOP_CODE_LO];
assign inst_cacop = packet[`INST_PKT_CACOP_BIT];
assign invtlb_op = packet[`INST_PKT_INVTLB_OP_HI:`INST_PKT_INVTLB_OP_LO];
assign tlb_op = packet[`INST_PKT_TLB_OP_HI:`INST_PKT_TLB_OP_LO];
assign rdcntid = packet[`INST_PKT_RDCNTID_BIT];
assign rdcntv_hi = packet[`INST_PKT_RDCNTV_HI_BIT];
assign rdcntv = packet[`INST_PKT_RDCNTV_BIT];
assign inst_idle = packet[`INST_PKT_IDLE_BIT];
assign inst_ibar = packet[`INST_PKT_IBAR_BIT];
assign inst_dbar = packet[`INST_PKT_DBAR_BIT];
assign inst_sc_w = packet[`INST_PKT_SC_W_BIT];
assign inst_ll_w = packet[`INST_PKT_LL_W_BIT];
assign inst = packet[`INST_PKT_INST_HI:`INST_PKT_INST_LO];
assign esubcode = packet[`INST_PKT_ESUBCODE_HI:`INST_PKT_ESUBCODE_LO];
assign ecode = packet[`INST_PKT_ECODE_HI:`INST_PKT_ECODE_LO];
assign exception_valid = packet[`INST_PKT_EXCEPTION_BIT];
assign seq_id = packet[`INST_PKT_SEQ_ID_HI:`INST_PKT_SEQ_ID_LO];
assign lane_id = packet[`INST_PKT_LANE_ID_BIT];
assign fetch_epoch = packet[`INST_PKT_FETCH_EPOCH_HI:`INST_PKT_FETCH_EPOCH_LO];
assign pc_next = packet[`INST_PKT_PC_NEXT_HI:`INST_PKT_PC_NEXT_LO];
assign pred_valid = packet[`INST_PKT_PRED_VALID_BIT];
assign pred_taken = packet[`INST_PKT_PRED_TAKEN_BIT];
assign pred_target = packet[`INST_PKT_PRED_TARGET_HI:`INST_PKT_PRED_TARGET_LO];
assign pred_type = packet[`INST_PKT_PRED_TYPE_HI:`INST_PKT_PRED_TYPE_LO];
assign pred_meta = packet[`INST_PKT_PRED_META_HI:`INST_PKT_PRED_META_LO];
assign src_valid = packet[`INST_PKT_SRC_VALID_HI:`INST_PKT_SRC_VALID_LO];
assign src0_reg = packet[`INST_PKT_SRC0_REG_HI:`INST_PKT_SRC0_REG_LO];
assign src1_reg = packet[`INST_PKT_SRC1_REG_HI:`INST_PKT_SRC1_REG_LO];
assign src2_reg = packet[`INST_PKT_SRC2_REG_HI:`INST_PKT_SRC2_REG_LO];
assign op_class = packet[`INST_PKT_OP_CLASS_HI:`INST_PKT_OP_CLASS_LO];
assign badv = packet[`INST_PKT_BADV_HI:`INST_PKT_BADV_LO];
endmodule
