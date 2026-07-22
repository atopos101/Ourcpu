`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// Ordered three-entry sliding issue queue.  Lane1 is a restricted companion lane:
// only two independent, exception-free scalar ALU operations may leave in
// parallel.  Every other bundle is split without changing program order.
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

reg valid0, valid1, valid2;
reg [`ID_TO_EX1_BUS_WD-1:0] packet0, packet1, packet2;

// Decode may have held an instruction while an older producer reached WB.
// At the accepting edge the register file still exposes its pre-NBA value,
// so refresh both incoming packets from the live producer set before the
// producer disappears.
wire [2:0] in_src_valid0, in_src_valid1;
wire [4:0] in_src00, in_src01, in_src02, in_src10, in_src11, in_src12;
wire [31:0] in_rj0, in_rkd0, in_rj1, in_rkd1;
wire [31:0] in_seq0, in_seq1;
instruction_packet_unpack u_in_unpack0(
    .packet(decode_packet[0 +: `ID_TO_EX1_BUS_WD]),
    .seq_id(in_seq0),
    .src_valid(in_src_valid0),
    .src0_reg(in_src00), .src1_reg(in_src01), .src2_reg(in_src02),
    .rj_value(in_rj0), .rkd_value(in_rkd0)
);
instruction_packet_unpack u_in_unpack1(
    .packet(decode_packet[`ID_TO_EX1_BUS_WD +: `ID_TO_EX1_BUS_WD]),
    .seq_id(in_seq1),
    .src_valid(in_src_valid1),
    .src0_reg(in_src10), .src1_reg(in_src11), .src2_reg(in_src12),
    .rj_value(in_rj1), .rkd_value(in_rkd1)
);
wire in_vv00, in_vv01, in_vv02, in_vv10, in_vv11, in_vv12;
wire [31:0] in_rv00, in_rv01, in_rv02, in_rv10, in_rv11, in_rv12;
producer_resolver in_r00(.src_valid(in_src_valid0[0]), .src_reg(in_src00),
    .consumer_seq_id(in_seq0),
    .regfile_value(in_rj0), .producers(producer_set),
    .value_valid(in_vv00), .value(in_rv00));
producer_resolver in_r01(.src_valid(in_src_valid0[1]), .src_reg(in_src01),
    .consumer_seq_id(in_seq0),
    .regfile_value(in_rkd0), .producers(producer_set),
    .value_valid(in_vv01), .value(in_rv01));
producer_resolver in_r02(.src_valid(in_src_valid0[2]), .src_reg(in_src02),
    .consumer_seq_id(in_seq0),
    .regfile_value(in_rkd0), .producers(producer_set),
    .value_valid(in_vv02), .value(in_rv02));
producer_resolver in_r10(.src_valid(in_src_valid1[0]), .src_reg(in_src10),
    .consumer_seq_id(in_seq1),
    .regfile_value(in_rj1), .producers(producer_set),
    .value_valid(in_vv10), .value(in_rv10));
producer_resolver in_r11(.src_valid(in_src_valid1[1]), .src_reg(in_src11),
    .consumer_seq_id(in_seq1),
    .regfile_value(in_rkd1), .producers(producer_set),
    .value_valid(in_vv11), .value(in_rv11));
producer_resolver in_r12(.src_valid(in_src_valid1[2]), .src_reg(in_src12),
    .consumer_seq_id(in_seq1),
    .regfile_value(in_rkd1), .producers(producer_set),
    .value_valid(in_vv12), .value(in_rv12));
reg [`ID_TO_EX1_BUS_WD-1:0] refreshed_decode0, refreshed_decode1;
always @(*) begin
    refreshed_decode0 = decode_packet[0 +: `ID_TO_EX1_BUS_WD];
    if (in_src_valid0[0] && in_vv00)
        refreshed_decode0[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] = in_rv00;
    if (in_src_valid0[1] && in_vv01)
        refreshed_decode0[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = in_rv01;
    else if (in_src_valid0[2] && in_vv02)
        refreshed_decode0[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = in_rv02;
    refreshed_decode1 = decode_packet[`ID_TO_EX1_BUS_WD +: `ID_TO_EX1_BUS_WD];
    if (in_src_valid1[0] && in_vv10)
        refreshed_decode1[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] = in_rv10;
    if (in_src_valid1[1] && in_vv11)
        refreshed_decode1[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = in_rv11;
    else if (in_src_valid1[2] && in_vv12)
        refreshed_decode1[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = in_rv12;
end

wire [2:0] src_valid0, src_valid1, src_valid2;
wire [4:0] src00, src01, src02, src10, src11, src12;
wire [4:0] src20, src21, src22;
wire [31:0] rj0, rkd0, rj1, rkd1, rj2, rkd2;
wire [31:0] seq0, seq1, seq2;
wire dst_valid0, dst_valid1;
wire [4:0] dst0, dst1;
wire [1:0] csr_op0;
wire [13:0] csr_num0;
wire ertn0;
wire [2:0] tlb_op0;
wire [3:0] op_class0, op_class1;
wire exception0, exception1;

instruction_packet_unpack u_unpack0(
    .packet(packet0), .exception_valid(exception0),
    .seq_id(seq0), .src_valid(src_valid0),
    .src0_reg(src00), .src1_reg(src01), .src2_reg(src02),
    .rj_value(rj0), .rkd_value(rkd0),
    .dst_valid(dst_valid0), .dst_reg(dst0),
    .csr_op(csr_op0), .csr_num(csr_num0), .inst_ertn(ertn0),
    .tlb_op(tlb_op0), .op_class(op_class0)
);
instruction_packet_unpack u_unpack1(
    .packet(packet1), .exception_valid(exception1),
    .seq_id(seq1), .src_valid(src_valid1),
    .src0_reg(src10), .src1_reg(src11), .src2_reg(src12),
    .rj_value(rj1), .rkd_value(rkd1),
    .dst_valid(dst_valid1), .dst_reg(dst1), .op_class(op_class1)
);
instruction_packet_unpack u_unpack2(
    .packet(packet2), .seq_id(seq2), .src_valid(src_valid2),
    .src0_reg(src20), .src1_reg(src21), .src2_reg(src22),
    .rj_value(rj2), .rkd_value(rkd2)
);

wire [`PRODUCER_PACKET_WD-1:0] queue0_producer;
wire [`PRODUCER_PACKET_WD-1:0] queue1_producer;
producer_packet_pack qprod0(.valid(valid0), .seq_id(seq0),
    .dst_valid(dst_valid0), .dst(dst0), .value_valid(1'b0),
    .value(32'b0), .packet(queue0_producer));
producer_packet_pack qprod1(.valid(valid1), .seq_id(seq1),
    .dst_valid(dst_valid1), .dst(dst1), .value_valid(1'b0),
    .value(32'b0), .packet(queue1_producer));
wire [12*`PRODUCER_PACKET_WD-1:0] slot2_producers =
    {producer_set, queue0_producer, queue1_producer};

wire [31:0] rv00, rv01, rv02, rv10, rv11, rv12;
wire vv00, vv01, vv02, vv10, vv11, vv12;
wire hit00, hit01, hit02, hit10, hit11, hit12;
wire [31:0] ps00, ps01, ps02, ps10, ps11, ps12;
wire [31:0] rv20, rv21, rv22;
wire vv20, vv21, vv22;
wire hit20, hit21, hit22;
wire [31:0] ps20, ps21, ps22;

producer_resolver r00(.src_valid(src_valid0[0]), .src_reg(src00),
    .consumer_seq_id(seq0),
    .regfile_value(rj0), .producers(producer_set), .hit(hit00),
    .value_valid(vv00), .value(rv00), .producer_seq_id(ps00));
producer_resolver r01(.src_valid(src_valid0[1]), .src_reg(src01),
    .consumer_seq_id(seq0),
    .regfile_value(rkd0), .producers(producer_set), .hit(hit01),
    .value_valid(vv01), .value(rv01), .producer_seq_id(ps01));
producer_resolver r02(.src_valid(src_valid0[2]), .src_reg(src02),
    .consumer_seq_id(seq0),
    .regfile_value(rkd0), .producers(producer_set), .hit(hit02),
    .value_valid(vv02), .value(rv02), .producer_seq_id(ps02));
producer_resolver r10(.src_valid(src_valid1[0]), .src_reg(src10),
    .consumer_seq_id(seq1),
    .regfile_value(rj1), .producers(producer_set), .hit(hit10),
    .value_valid(vv10), .value(rv10), .producer_seq_id(ps10));
producer_resolver r11(.src_valid(src_valid1[1]), .src_reg(src11),
    .consumer_seq_id(seq1),
    .regfile_value(rkd1), .producers(producer_set), .hit(hit11),
    .value_valid(vv11), .value(rv11), .producer_seq_id(ps11));
producer_resolver r12(.src_valid(src_valid1[2]), .src_reg(src12),
    .consumer_seq_id(seq1),
    .regfile_value(rkd1), .producers(producer_set), .hit(hit12),
    .value_valid(vv12), .value(rv12), .producer_seq_id(ps12));
producer_resolver #(.PRODUCER_COUNT(12)) r20(
    .src_valid(src_valid2[0]), .src_reg(src20),
    .consumer_seq_id(seq2),
    .regfile_value(rj2), .producers(slot2_producers), .hit(hit20),
    .value_valid(vv20), .value(rv20), .producer_seq_id(ps20));
producer_resolver #(.PRODUCER_COUNT(12)) r21(
    .src_valid(src_valid2[1]), .src_reg(src21),
    .consumer_seq_id(seq2),
    .regfile_value(rkd2), .producers(slot2_producers), .hit(hit21),
    .value_valid(vv21), .value(rv21), .producer_seq_id(ps21));
producer_resolver #(.PRODUCER_COUNT(12)) r22(
    .src_valid(src_valid2[2]), .src_reg(src22),
    .consumer_seq_id(seq2),
    .regfile_value(rkd2), .producers(slot2_producers), .hit(hit22),
    .value_valid(vv22), .value(rv22), .producer_seq_id(ps22));

wire operands0_ready = (!src_valid0[0] || vv00) &&
                       (!src_valid0[1] || vv01) &&
                       (!src_valid0[2] || vv02);
wire operands1_ready = (!src_valid1[0] || vv10) &&
                       (!src_valid1[1] || vv11) &&
                       (!src_valid1[2] || vv12);
wire lane1_reads_lane0 =
    dst_valid0 && (dst0 != 5'b0) &&
    ((src_valid1[0] && src10 == dst0) ||
     (src_valid1[1] && src11 == dst0) ||
     (src_valid1[2] && src12 == dst0));
wire pair_static = valid0 && valid1 &&
                   (op_class0 == `OP_CLASS_ALU) &&
                   (op_class1 == `OP_CLASS_ALU) &&
                   // A dependency on slot 0 still requires ordered split
                   // issue.  Dependencies on older instructions are legal
                   // when the producer network marks their values ready;
                   // resolved1 below carries those bypassed values.
                   !exception0 && !exception1 && !lane1_reads_lane0 &&
                   !serialize_pending;

reg [`ID_TO_EX1_BUS_WD-1:0] resolved0, resolved1, refreshed2;
always @(*) begin
    resolved0 = packet0;
    if (src_valid0[0] && vv00)
        resolved0[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] = rv00;
    if (src_valid0[1] && vv01)
        resolved0[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rv01;
    else if (src_valid0[2] && vv02)
        resolved0[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rv02;
    resolved1 = packet1;
    if (src_valid1[0] && vv10)
        resolved1[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] = rv10;
    if (src_valid1[1] && vv11)
        resolved1[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rv11;
    else if (src_valid1[2] && vv12)
        resolved1[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rv12;
    refreshed2 = packet2;
    if (src_valid2[0] && vv20)
        refreshed2[`INST_PKT_RJ_VALUE_HI:`INST_PKT_RJ_VALUE_LO] = rv20;
    if (src_valid2[1] && vv21)
        refreshed2[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rv21;
    else if (src_valid2[2] && vv22)
        refreshed2[`INST_PKT_RKD_VALUE_HI:`INST_PKT_RKD_VALUE_LO] = rv22;
end

wire lane0_offer = valid0 && operands0_ready && !serialize_pending;
wire lane1_offer = lane0_offer && pair_static && operands1_ready;
wire fire0 = lane0_offer && issue_lane_ready[0];
wire pair_fire = fire0 && lane1_offer && issue_lane_ready[1];
wire [1:0] issue_count = pair_fire ? 2'd2 : fire0 ? 2'd1 : 2'd0;
wire [1:0] queue_count = valid2 ? 2'd3 : valid1 ? 2'd2 :
                         valid0 ? 2'd1 : 2'd0;
wire [1:0] remaining_count = queue_count - issue_count;
wire [2:0] free_after_issue = 3 - remaining_count;
wire [1:0] incoming_count = decode_valid[1] ? 2'd2 :
                            decode_valid[0] ? 2'd1 : 2'd0;
wire decode_space_ok = (incoming_count == 0) ||
                       (free_after_issue >= incoming_count);

assign decode_ready = {2{decode_space_ok}};
assign issue_lane_valid = {lane1_offer, lane0_offer};
assign issue_lane_packet = {resolved1, resolved0};
assign stall_data = valid0 && (!operands0_ready ||
                    (pair_static && !operands1_ready));
assign stall_struct = valid0 && operands0_ready &&
                      (serialize_pending ||
                       (pair_static && !issue_lane_ready[1]));

assign pending_dst = valid0 && dst_valid0 ? dst0 : 5'b0;
assign pending_csr_we = valid0 && (csr_op0 == 2'b10 || csr_op0 == 2'b11);
assign pending_csr_num = csr_num0;
assign pending_ertn = valid0 && ertn0;
assign pending_tlb = valid0 && (tlb_op0 != 3'b0);

producer_packet_pack u_issue_producer(
    .valid(valid0), .seq_id(seq0), .dst_valid(dst_valid0), .dst(dst0),
    .value_valid(1'b0), .value(32'b0), .packet(producer_packet)
);

wire decode_fire = decode_valid[0] && decode_space_ok;
reg next_valid0, next_valid1, next_valid2;
reg [`ID_TO_EX1_BUS_WD-1:0] next_packet0, next_packet1, next_packet2;
reg [1:0] next_count;
always @(*) begin
    // First compact the surviving oldest instructions.
    next_packet0 = resolved0;
    next_packet1 = resolved1;
    next_packet2 = refreshed2;
    case (issue_count)
        2'd1: begin
            next_packet0 = resolved1;
            next_packet1 = refreshed2;
        end
        2'd2: begin
            next_packet0 = refreshed2;
        end
        default: begin end
    endcase

    next_count = remaining_count;
    if (decode_fire) begin
        case (remaining_count)
            2'd0: begin
                next_packet0 = refreshed_decode0;
                if (decode_valid[1])
                    next_packet1 = refreshed_decode1;
            end
            2'd1: begin
                next_packet1 = refreshed_decode0;
                if (decode_valid[1])
                    next_packet2 = refreshed_decode1;
            end
            2'd2: begin
                next_packet2 = refreshed_decode0;
            end
            default: begin end
        endcase
        next_count = remaining_count + incoming_count;
    end
    next_valid0 = next_count >= 1;
    next_valid1 = next_count >= 2;
    next_valid2 = next_count >= 3;
end

always @(posedge clk) begin
    if (reset || kill) begin
        valid0 <= 1'b0;
        valid1 <= 1'b0;
        valid2 <= 1'b0;
    end
    else begin
        valid0 <= next_valid0;
        valid1 <= next_valid1;
        valid2 <= next_valid2;
        packet0 <= next_packet0;
        packet1 <= next_packet1;
        packet2 <= next_packet2;
    end
end

`ifndef SYNTHESIS
always @(posedge clk) begin
    if (!reset && valid1 && !(seq0 < seq1))
        $error("issue bundle sequence order is not lane0 < lane1");
    if (!reset && valid2 && !(seq1 < seq2))
        $error("issue queue sequence order is not slot1 < slot2");
    if (!reset && pair_fire && (lane1_reads_lane0 ||
        op_class0 != `OP_CLASS_ALU || op_class1 != `OP_CLASS_ALU))
        $error("illegal lane1 pairing");
    if (!reset && valid0 &&
        ((hit00 && !(ps00 < seq0)) || (hit01 && !(ps01 < seq0)) ||
         (hit02 && !(ps02 < seq0))))
        $error("lane0 selected a non-older producer");
    if (!reset && valid1 &&
        ((hit10 && !(ps10 < seq1)) || (hit11 && !(ps11 < seq1)) ||
         (hit12 && !(ps12 < seq1))))
        $error("lane1 selected a non-older producer");
    if (!reset && valid2 &&
        ((hit20 && !(ps20 < seq2)) || (hit21 && !(ps21 < seq2)) ||
         (hit22 && !(ps22 < seq2))))
        $error("issue slot2 selected a non-older producer");
end
`endif
endmodule
