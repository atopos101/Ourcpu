`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// One canonical description for every in-flight GPR producer.
module producer_packet_pack(
    input         valid,
    input  [31:0] seq_id,
    input         dst_valid,
    input  [ 4:0] dst,
    input         value_valid,
    input  [31:0] value,
    output [`PRODUCER_PACKET_WD-1:0] packet
);
assign packet = {valid, seq_id, dst_valid, dst, value_valid, value};
endmodule

module producer_packet_unpack(
    input  [`PRODUCER_PACKET_WD-1:0] packet,
    output        valid,
    output [31:0] seq_id,
    output        dst_valid,
    output [ 4:0] dst,
    output        value_valid,
    output [31:0] value
);
assign valid       = packet[`PRODUCER_VALID_BIT];
assign seq_id      = packet[`PRODUCER_SEQ_HI:`PRODUCER_SEQ_LO];
assign dst_valid   = packet[`PRODUCER_DST_VALID_BIT];
assign dst         = packet[`PRODUCER_DST_HI:`PRODUCER_DST_LO];
assign value_valid = packet[`PRODUCER_VALUE_VALID_BIT];
assign value       = packet[`PRODUCER_VALUE_HI:`PRODUCER_VALUE_LO];
endmodule

// Producers are packed with producer 0 in the least-significant slice and
// must be supplied newest first.  Every producer visible from Issue is older
// than the Issue consumer, so the first matching packet is the required
// youngest producer.  Do not compare all 32-bit sequence IDs here: doing so
// creates a long cascaded maximum-selection carry chain on the Issue-to-fetch
// backpressure path.  seq_id remains in the interface for age assertions and
// redirect handling elsewhere in the core.
module producer_resolver #(
    parameter PRODUCER_COUNT = `PRODUCER_COUNT
)(
    input                            src_valid,
    input      [4:0]                 src_reg,
    input      [31:0]                consumer_seq_id,
    input      [31:0]                regfile_value,
    input      [PRODUCER_COUNT*`PRODUCER_PACKET_WD-1:0] producers,
    output reg                       hit,
    output reg                       value_valid,
    output reg [31:0]                value,
    output reg [31:0]                producer_seq_id
);
// This implementation is intentionally fixed at 10 producers.
// Producer slice 0 is newest and has the highest priority.
wire [9:0] match;
genvar g;
generate
    for (g = 0; g < 10; g = g + 1) begin : g_match
        wire [`PRODUCER_PACKET_WD-1:0] p =
            producers[g*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
        assign match[g] = src_valid && (src_reg != 5'b0) &&
                          p[`PRODUCER_VALID_BIT] &&
                          p[`PRODUCER_DST_VALID_BIT] &&
                          (p[`PRODUCER_DST_HI:`PRODUCER_DST_LO] == src_reg);
    end
endgenerate

wire [`PRODUCER_PACKET_WD-1:0] p0 = producers[0*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p1 = producers[1*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p2 = producers[2*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p3 = producers[3*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p4 = producers[4*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p5 = producers[5*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p6 = producers[6*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p7 = producers[7*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p8 = producers[8*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
wire [`PRODUCER_PACKET_WD-1:0] p9 = producers[9*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];

// Five-way selectors are evaluated in parallel. The final selector gives
// the newer group (0..4) priority over the older group (5..9).
reg [`PRODUCER_PACKET_WD-1:0] newest_group_packet;
reg [`PRODUCER_PACKET_WD-1:0] oldest_group_packet;
always @(*) begin
    casez (match[4:0])
        5'b????1: newest_group_packet = p0;
        5'b???10: newest_group_packet = p1;
        5'b??100: newest_group_packet = p2;
        5'b?1000: newest_group_packet = p3;
        5'b10000: newest_group_packet = p4;
        default:  newest_group_packet = {`PRODUCER_PACKET_WD{1'b0}};
    endcase
    casez (match[9:5])
        5'b????1: oldest_group_packet = p5;
        5'b???10: oldest_group_packet = p6;
        5'b??100: oldest_group_packet = p7;
        5'b?1000: oldest_group_packet = p8;
        5'b10000: oldest_group_packet = p9;
        default:  oldest_group_packet = {`PRODUCER_PACKET_WD{1'b0}};
    endcase
end

wire newest_group_hit = |match[4:0];
wire oldest_group_hit = |match[9:5];
wire [`PRODUCER_PACKET_WD-1:0] selected_packet =
    newest_group_hit ? newest_group_packet : oldest_group_packet;

always @(*) begin
    hit             = newest_group_hit || oldest_group_hit;
    value_valid     = hit ? selected_packet[`PRODUCER_VALUE_VALID_BIT] : 1'b1;
    value           = hit ? selected_packet[`PRODUCER_VALUE_HI:`PRODUCER_VALUE_LO]
                          : regfile_value;
    producer_seq_id = hit ? selected_packet[`PRODUCER_SEQ_HI:`PRODUCER_SEQ_LO]
                          : 32'b0;
end

// Kept intentionally as interface metadata; producer selection relies on the
// in-order stage ordering documented above.
wire unused_consumer_seq_id = ^consumer_seq_id;
endmodule
