`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// Common EX1 branch semantics.  Decode supplies registered operands and the
// prediction placeholder carried by the instruction packet.
module branch_resolver(
    input  [31:0] inst,
    input  [31:0] pc,
    input  [31:0] pc_next,
    input  [31:0] rj_value,
    input  [31:0] rkd_value,
    input         pred_valid,
    input         pred_taken,
    input  [31:0] pred_target,
    output        is_control_flow,
    output        actual_taken,
    output [31:0] actual_target,
    output [31:0] fallthrough_pc,
    output        direction_miss,
    output        target_miss,
    output        false_btb_hit,
    output        mispredict,
    output [31:0] recovery_target
);
wire inst_jirl = inst[31:26] == 6'h13;
wire inst_b    = inst[31:26] == 6'h14;
wire inst_bl   = inst[31:26] == 6'h15;
wire inst_beq  = inst[31:26] == 6'h16;
wire inst_bne  = inst[31:26] == 6'h17;
wire inst_blt  = inst[31:26] == 6'h18;
wire inst_bge  = inst[31:26] == 6'h19;
wire inst_bltu = inst[31:26] == 6'h1a;
wire inst_bgeu = inst[31:26] == 6'h1b;

wire [31:0] i16_offs = {{14{inst[25]}}, inst[25:10], 2'b0};
wire [25:0] i26      = {inst[9:0], inst[25:10]};
wire [31:0] i26_offs = {{4{i26[25]}}, i26, 2'b0};
wire        rj_eq    = rj_value == rkd_value;
wire        rj_lt    = $signed(rj_value) < $signed(rkd_value);
wire        rj_ltu   = rj_value < rkd_value;
wire        predicted_taken = pred_valid && pred_taken;

assign is_control_flow = inst_jirl || inst_b || inst_bl || inst_beq ||
                         inst_bne || inst_blt || inst_bge || inst_bltu ||
                         inst_bgeu;
assign actual_taken = inst_jirl || inst_b || inst_bl ||
                      (inst_beq  &&  rj_eq) ||
                      (inst_bne  && !rj_eq) ||
                      (inst_blt  &&  rj_lt) ||
                      (inst_bge  && !rj_lt) ||
                      (inst_bltu &&  rj_ltu) ||
                      (inst_bgeu && !rj_ltu);
assign actual_target = inst_jirl ? (rj_value + i16_offs) :
                       (inst_b || inst_bl) ? (pc + i26_offs) :
                       (is_control_flow ? (pc + i16_offs) : pc_next);
assign fallthrough_pc = pc_next;
assign direction_miss = is_control_flow && (actual_taken != predicted_taken);
assign target_miss = is_control_flow && actual_taken && predicted_taken &&
                     (actual_target != pred_target);
assign false_btb_hit = predicted_taken && !is_control_flow;
assign mispredict = direction_miss || target_miss || false_btb_hit;
assign recovery_target = actual_taken ? actual_target : fallthrough_pc;
endmodule

// Small EX1 resolve boundary.  It cuts branch compare/target arithmetic away
// from the privileged redirect arbiter and its wide registered packet.
module branch_resolve_register(
    input  wire        clk,
    input  wire        reset,
    input  wire        kill,
    input  wire        in_valid,
    input  wire [31:0] in_target,
    input  wire [31:0] in_seq_id,
    input  wire [`FETCH_EPOCH_WD-1:0] in_epoch,
    output reg         out_valid,
    output reg  [31:0] out_target,
    output reg  [31:0] out_seq_id,
    output reg  [`FETCH_EPOCH_WD-1:0] out_epoch
);
always @(posedge clk) begin
    if (reset || kill)
        out_valid <= 1'b0;
    else begin
        out_valid <= in_valid;
        if (in_valid) begin
            out_target <= in_target;
            out_seq_id <= in_seq_id;
            out_epoch <= in_epoch;
        end
    end
end
endmodule

// Age-first redirect arbitration followed by a register.  Reason priority is
// used only when two requests belong to the same instruction age.
module redirect_register(
    input clk,
    input reset,
    input branch_valid, input [31:0] branch_target,
    input [31:0] branch_seq_id,
    input [`FETCH_EPOCH_WD-1:0] branch_epoch,
    input ibar_valid, input [31:0] ibar_target,
    input [31:0] ibar_seq_id,
    input [`FETCH_EPOCH_WD-1:0] ibar_epoch,
    input exception_valid, input [31:0] exception_target,
    input [31:0] exception_seq_id,
    input [`FETCH_EPOCH_WD-1:0] exception_epoch,
    input ertn_valid, input [31:0] ertn_target,
    input [31:0] ertn_seq_id,
    input [`FETCH_EPOCH_WD-1:0] ertn_epoch,
    output reg redirect_valid,
    output reg [`REDIRECT_PACKET_WD-1:0] redirect_packet
);
reg select_valid;
reg [31:0] select_target;
reg [1:0] select_reason;
reg [31:0] select_seq_id;
reg [`FETCH_EPOCH_WD-1:0] select_epoch;

always @(*) begin
    select_valid  = 1'b0;
    select_target = 32'b0;
    select_reason = `REDIRECT_CAUSE_BRANCH;
    select_seq_id = 32'hffff_ffff;
    select_epoch  = {`FETCH_EPOCH_WD{1'b0}};
    if (branch_valid) begin
        select_valid = 1'b1; select_target = branch_target;
        select_reason = `REDIRECT_CAUSE_BRANCH;
        select_seq_id = branch_seq_id; select_epoch = branch_epoch;
    end
    if (ibar_valid && (!select_valid || ibar_seq_id < select_seq_id ||
        (ibar_seq_id == select_seq_id && `REDIRECT_CAUSE_IBAR > select_reason))) begin
        select_valid = 1'b1; select_target = ibar_target;
        select_reason = `REDIRECT_CAUSE_IBAR;
        select_seq_id = ibar_seq_id; select_epoch = ibar_epoch;
    end
    if (exception_valid && (!select_valid || exception_seq_id < select_seq_id ||
        (exception_seq_id == select_seq_id && `REDIRECT_CAUSE_EXCP > select_reason))) begin
        select_valid = 1'b1; select_target = exception_target;
        select_reason = `REDIRECT_CAUSE_EXCP;
        select_seq_id = exception_seq_id; select_epoch = exception_epoch;
    end
    if (ertn_valid && (!select_valid || ertn_seq_id < select_seq_id ||
        (ertn_seq_id == select_seq_id && `REDIRECT_CAUSE_ERTN > select_reason))) begin
        select_valid = 1'b1; select_target = ertn_target;
        select_reason = `REDIRECT_CAUSE_ERTN;
        select_seq_id = ertn_seq_id; select_epoch = ertn_epoch;
    end
end

always @(posedge clk) begin
    if (reset) begin
        redirect_valid  <= 1'b0;
        redirect_packet <= {`REDIRECT_PACKET_WD{1'b0}};
    end
    else begin
        redirect_valid <= select_valid;
        if (select_valid)
            redirect_packet <= {select_target, select_reason,
                                select_seq_id, select_epoch};
    end
end
endmodule
