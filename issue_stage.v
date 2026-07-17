`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// Lane-0 issue boundary.  Decode currently performs the single-lane hazard
// decision; this elastic register makes that decision independent of EX1
// backpressure and provides the structural point where lane pairing is added.
module issue_stage(
    input                               clk,
    input                               reset,
    input                               kill,
    input  [`ARCH_LANE_COUNT-1:0]       decode_valid,
    output [`ARCH_LANE_COUNT-1:0]       decode_ready,
    input  [`ARCH_LANE_COUNT*`ID_TO_EX1_BUS_WD-1:0] decode_packet,
    output [`ARCH_LANE_COUNT-1:0]       issue_lane_valid,
    input  [`ARCH_LANE_COUNT-1:0]       issue_lane_ready,
    output [`ARCH_LANE_COUNT*`ID_TO_EX1_BUS_WD-1:0] issue_lane_packet,
    input  [`PRODUCER_SET_WD-1:0]       producer_set,
    input                               serialize_pending,
    output [`PRODUCER_PACKET_WD-1:0]    producer_packet,
    output                              stall_data,
    output                              stall_struct,
    output [4:0]                        pending_dst,
    output                              pending_csr_we,
    output [13:0]                       pending_csr_num,
    output                              pending_ertn,
    output                              pending_tlb
);

reg                                issue_valid;
reg [`ID_TO_EX1_BUS_WD-1:0]        issue_packet;

wire [1:0] packet_csr_op;
wire       packet_dst_valid;
wire [4:0] packet_dst_reg;
wire [13:0] packet_csr_num;
wire       packet_ertn;
wire [2:0] packet_tlb_op;
wire [31:0] packet_seq_id;
wire [2:0]  packet_src_valid;
wire [4:0]  packet_src0_reg;
wire [4:0]  packet_src1_reg;
wire [4:0]  packet_src2_reg;
wire [31:0] packet_rj_value;
wire [31:0] packet_rkd_value;

instruction_packet_unpack u_instruction_packet_unpack(
    .packet(issue_packet),
    .seq_id(packet_seq_id),
    .src_valid(packet_src_valid), .src0_reg(packet_src0_reg),
    .src1_reg(packet_src1_reg), .src2_reg(packet_src2_reg),
    .rj_value(packet_rj_value), .rkd_value(packet_rkd_value),
    .dst_valid(packet_dst_valid), .dst_reg(packet_dst_reg),
    .csr_op(packet_csr_op), .csr_num(packet_csr_num),
    .inst_ertn(packet_ertn), .tlb_op(packet_tlb_op)
);

wire lane0_decode_valid = decode_valid[0];
wire [`ID_TO_EX1_BUS_WD-1:0] lane0_decode_packet =
    decode_packet[0 +: `ID_TO_EX1_BUS_WD];
wire lane0_ready = issue_lane_ready[0];

wire rj_hit;
wire rk_hit;
wire rd_hit;
wire rj_value_valid;
wire rk_value_valid;
wire rd_value_valid;
wire [31:0] resolved_rj_value;
wire [31:0] resolved_rk_value;
wire [31:0] resolved_rd_value;
wire [31:0] rj_producer_seq;
wire [31:0] rk_producer_seq;
wire [31:0] rd_producer_seq;

producer_resolver u_issue_rj_resolver(
    .src_valid(packet_src_valid[0]), .src_reg(packet_src0_reg),
    .regfile_value(packet_rj_value), .producers(producer_set),
    .hit(rj_hit), .value_valid(rj_value_valid), .value(resolved_rj_value),
    .producer_seq_id(rj_producer_seq)
);
producer_resolver u_issue_rk_resolver(
    .src_valid(packet_src_valid[1]), .src_reg(packet_src1_reg),
    .regfile_value(packet_rkd_value), .producers(producer_set),
    .hit(rk_hit), .value_valid(rk_value_valid), .value(resolved_rk_value),
    .producer_seq_id(rk_producer_seq)
);
producer_resolver u_issue_rd_resolver(
    .src_valid(packet_src_valid[2]), .src_reg(packet_src2_reg),
    .regfile_value(packet_rkd_value), .producers(producer_set),
    .hit(rd_hit), .value_valid(rd_value_valid), .value(resolved_rd_value),
    .producer_seq_id(rd_producer_seq)
);

wire operands_ready = (!packet_src_valid[0] || rj_value_valid) &&
                      (!packet_src_valid[1] || rk_value_valid) &&
                      (!packet_src_valid[2] || rd_value_valid);
wire issue_operation_ready = operands_ready && !serialize_pending;
wire [31:0] resolved_rkd_value = packet_src_valid[1] ? resolved_rk_value :
                                 packet_src_valid[2] ? resolved_rd_value :
                                                       packet_rkd_value;
reg [`ID_TO_EX1_BUS_WD-1:0] resolved_issue_packet;
always @(*) begin
    resolved_issue_packet = issue_packet;
    resolved_issue_packet[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] =
        resolved_rj_value;
    resolved_issue_packet[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] =
        resolved_rkd_value;
end

assign decode_ready[0] = !issue_valid || (issue_operation_ready && lane0_ready);
// lane1 is architecturally present but closed; no instruction may enter it.
assign decode_ready[1] = 1'b0;
assign issue_lane_valid = {1'b0, issue_valid && issue_operation_ready};
assign issue_lane_packet = {{`ID_TO_EX1_BUS_WD{1'b0}}, resolved_issue_packet};
wire decode_fire = lane0_decode_valid && decode_ready[0];
wire lane0_fire  = issue_valid && issue_operation_ready && lane0_ready;
assign stall_data = issue_valid && !operands_ready;
assign stall_struct = issue_valid && operands_ready && serialize_pending;

// These fields describe the instruction while it is between Decode and EX1.
// Decode treats its destination as not-ready, preventing a younger consumer
// from overlooking this newly introduced pipeline boundary.
assign pending_dst     = (issue_valid && packet_dst_valid) ? packet_dst_reg : 5'b0;
assign pending_csr_we  = issue_valid && ((packet_csr_op == 2'b10) ||
                                         (packet_csr_op == 2'b11));
assign pending_csr_num = packet_csr_num;
assign pending_ertn    = issue_valid && packet_ertn;
assign pending_tlb     = issue_valid && (packet_tlb_op != 3'b0);

producer_packet_pack u_issue_producer_packet(
    .valid(issue_valid),
    .seq_id(packet_seq_id),
    .dst_valid(packet_dst_valid),
    .dst(packet_dst_reg),
    .value_valid(1'b0),
    .value(32'b0),
    .packet(producer_packet)
);

always @(posedge clk) begin
    if (reset || kill) begin
        issue_valid <= 1'b0;
    end
    else if (decode_ready[0]) begin
        issue_valid <= lane0_decode_valid;
        if (decode_fire)
            issue_packet <= lane0_decode_packet;
    end
    else if (issue_valid) begin
        // A packet may wait for one source (for example store data from a
        // load) after another source has already become forwardable.  Retain
        // each forwarded operand as soon as it is ready; otherwise its
        // producer can retire and disappear from producer_set, exposing the
        // stale register-file snapshot taken in Decode.
        if (packet_src_valid[0] && rj_hit && rj_value_valid)
            issue_packet[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO]
                <= resolved_rj_value;
        if (packet_src_valid[1] && rk_hit && rk_value_valid)
            issue_packet[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO]
                <= resolved_rk_value;
        else if (packet_src_valid[2] && rd_hit && rd_value_valid)
            issue_packet[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO]
                <= resolved_rd_value;
    end
end

`ifndef SYNTHESIS
reg                                stalled_last;
reg [`ID_TO_EX1_BUS_WD-1:0]        packet_last;
always @(posedge clk) begin
    if (reset || kill) begin
        stalled_last <= 1'b0;
    end
    else begin
        // Operand snapshots are intentionally allowed to absorb forwarding
        // results while stalled.  All instruction identity/control fields
        // around those two adjacent value slots must remain stable.
        if (stalled_last &&
            (!issue_valid ||
             issue_packet[`ID_TO_EX1_BUS_WD-1:`INST_PKT_RJ_VALUE_HI+1] !==
                 packet_last[`ID_TO_EX1_BUS_WD-1:`INST_PKT_RJ_VALUE_HI+1] ||
             issue_packet[`INST_PKT_RKD_VALUE_LO-1:0] !==
                 packet_last[`INST_PKT_RKD_VALUE_LO-1:0]))
            $error("issue packet changed while stalled");
        stalled_last <= issue_valid && !(issue_operation_ready && lane0_ready);
        packet_last  <= issue_packet;
    end
end
`endif

wire unused_lane0_fire = lane0_fire;

`ifndef SYNTHESIS
always @(posedge clk) begin
    if (!reset && decode_valid[1])
        $error("lane1 must remain disabled in the single-issue baseline");
    if (!reset && issue_valid &&
        ((rj_hit && !(rj_producer_seq < packet_seq_id)) ||
         (rk_hit && !(rk_producer_seq < packet_seq_id)) ||
         (rd_hit && !(rd_producer_seq < packet_seq_id))))
        $error("Issue selected a producer that is not older than its consumer");
end
`endif

endmodule
