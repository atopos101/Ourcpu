`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// Restricted lane1 data path.  It carries only scalar ALU instructions and
// advances on exactly the same elastic boundaries as the paired lane0 token.
module companion_lane(
    input clk,
    input reset,
    input kill_execute,
    input issue_valid,
    input [`ID_TO_EX1_BUS_WD-1:0] issue_packet,
    input issue_to_ex1_ready,
    input lane0_ex1_valid,
    input ex1_to_ex2_ready,
    input lane0_ex2_valid,
    input ex2_to_ex3_ready,
    input lane0_ex3_valid,
    input ex3_to_mem_ready,
    input lane0_mem_valid,
    input mem_to_wb_ready,
    output [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus,
    output [`PRODUCER_PACKET_WD-1:0] ex1_producer,
    output [`PRODUCER_PACKET_WD-1:0] ex2_producer,
    output [`PRODUCER_PACKET_WD-1:0] ex3_producer,
    output [`PRODUCER_PACKET_WD-1:0] mem_producer,
    output [`PRODUCER_PACKET_WD-1:0] wb_producer,
    output wb_valid,
    output [31:0] wb_pc,
    output [31:0] wb_instr,
    output wb_rf_we,
    output [4:0] wb_rf_waddr,
    output [31:0] wb_rf_wdata
);

wire [18:0] in_alu_op;
wire in_src1_pc, in_src2_imm;
wire [31:0] in_pc, in_inst, in_rj, in_rkd, in_imm, in_seq;
wire in_dst_valid;
wire [4:0] in_dst;
instruction_packet_unpack u_unpack(
    .packet(issue_packet), .alu_op(in_alu_op),
    .inst(in_inst),
    .src1_is_pc(in_src1_pc), .src2_is_imm(in_src2_imm),
    .pc(in_pc), .rj_value(in_rj), .rkd_value(in_rkd),
    .immediate(in_imm), .seq_id(in_seq),
    .dst_valid(in_dst_valid), .dst_reg(in_dst)
);
wire [31:0] in_result;
alu u_lane1_alu(
    .alu_op(in_alu_op),
    .alu_src1(in_src1_pc ? in_pc : in_rj),
    .alu_src2(in_src2_imm ? in_imm : in_rkd),
    .alu_result(in_result)
);

localparam SIDE_WD = 134; // {seq,inst,dst_valid,dst,result,pc}
wire [SIDE_WD-1:0] in_side =
    {in_seq, in_inst, in_dst_valid, in_dst, in_result, in_pc};
reg [SIDE_WD-1:0] ex1_side, ex2_side, ex3_side, mem_side, wb_side;
reg ex1_valid, ex2_valid, ex3_valid, mem_valid, ws_valid;

always @(posedge clk) begin
    if (reset || kill_execute) begin
        ex1_valid <= 1'b0;
        ex2_valid <= 1'b0;
        ex3_valid <= 1'b0;
    end
    else begin
        if (issue_to_ex1_ready) begin
            ex1_valid <= issue_valid;
            if (issue_valid)
                ex1_side <= in_side;
        end
        if (ex1_to_ex2_ready) begin
            ex2_valid <= ex1_valid && lane0_ex1_valid;
            if (ex1_valid && lane0_ex1_valid)
                ex2_side <= ex1_side;
        end
        if (ex2_to_ex3_ready) begin
            ex3_valid <= ex2_valid && lane0_ex2_valid;
            if (ex2_valid && lane0_ex2_valid)
                ex3_side <= ex2_side;
        end
    end

    if (reset) begin
        mem_valid <= 1'b0;
        ws_valid <= 1'b0;
    end
    else begin
        if (ex3_to_mem_ready) begin
            // A lane0 exception/interrupt kills its younger paired lane1
            // instruction.  Preserve older MEM/WB work, but do not let the
            // old EX3 valid value cross into MEM on the flush edge.
            mem_valid <= !kill_execute && ex3_valid && lane0_ex3_valid;
            if (!kill_execute && ex3_valid && lane0_ex3_valid)
                mem_side <= ex3_side;
        end
        if (mem_to_wb_ready) begin
            ws_valid <= mem_valid && lane0_mem_valid;
            if (mem_valid && lane0_mem_valid)
                wb_side <= mem_side;
        end
    end
end

wire [31:0] ex1_seq, ex2_seq, ex3_seq, mem_seq, ws_seq;
wire [31:0] ex1_inst, ex2_inst, ex3_inst, mem_inst, ws_inst;
wire ex1_we, ex2_we, ex3_we, mem_we, ws_we;
wire [4:0] ex1_dst, ex2_dst, ex3_dst, mem_dst, ws_dst;
wire [31:0] ex1_result, ex2_result, ex3_result, mem_result, ws_result;
wire [31:0] ex1_pc, ex2_pc, ex3_pc, mem_pc, ws_pc;
assign {ex1_seq, ex1_inst, ex1_we, ex1_dst, ex1_result, ex1_pc} = ex1_side;
assign {ex2_seq, ex2_inst, ex2_we, ex2_dst, ex2_result, ex2_pc} = ex2_side;
assign {ex3_seq, ex3_inst, ex3_we, ex3_dst, ex3_result, ex3_pc} = ex3_side;
assign {mem_seq, mem_inst, mem_we, mem_dst, mem_result, mem_pc} = mem_side;
assign {ws_seq, ws_inst, ws_we, ws_dst, ws_result, ws_pc} = wb_side;

producer_packet_pack p_ex1(.valid(ex1_valid), .seq_id(ex1_seq),
    .dst_valid(ex1_we), .dst(ex1_dst), .value_valid(ex1_valid && ex1_we),
    .value(ex1_result), .packet(ex1_producer));
producer_packet_pack p_ex2(.valid(ex2_valid), .seq_id(ex2_seq),
    .dst_valid(ex2_we), .dst(ex2_dst), .value_valid(ex2_valid && ex2_we),
    .value(ex2_result), .packet(ex2_producer));
producer_packet_pack p_ex3(.valid(ex3_valid), .seq_id(ex3_seq),
    .dst_valid(ex3_we), .dst(ex3_dst), .value_valid(ex3_valid && ex3_we),
    .value(ex3_result), .packet(ex3_producer));
producer_packet_pack p_mem(.valid(mem_valid), .seq_id(mem_seq),
    .dst_valid(mem_we), .dst(mem_dst), .value_valid(mem_valid && mem_we),
    .value(mem_result), .packet(mem_producer));
producer_packet_pack p_wb(.valid(ws_valid), .seq_id(ws_seq),
    .dst_valid(ws_we), .dst(ws_dst), .value_valid(ws_valid && ws_we),
    .value(ws_result), .packet(wb_producer));

assign ws_to_rf_bus = {ws_valid && ws_we, ws_dst, ws_result};
assign wb_valid = ws_valid;
assign wb_pc = ws_pc;
assign wb_instr = ws_inst;
assign wb_rf_we = ws_valid && ws_we;
assign wb_rf_waddr = ws_dst;
assign wb_rf_wdata = ws_result;

wire unused_pc = ^{ex1_pc, ex2_pc, ex3_pc, mem_pc, ws_pc};
endmodule
