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
// must be supplied newest first.  In an in-order pipeline the first matching
// packet is necessarily the youngest older producer.  seq_id remains in the
// packet for assertions, redirect age comparison and future two-lane logic.
module producer_resolver #(
    parameter PRODUCER_COUNT = `PRODUCER_COUNT
)(
    input                            src_valid,
    input      [4:0]                 src_reg,
    input      [31:0]                regfile_value,
    input      [PRODUCER_COUNT*`PRODUCER_PACKET_WD-1:0] producers,
    output reg                       hit,
    output reg                       value_valid,
    output reg [31:0]                value,
    output reg [31:0]                producer_seq_id
);
integer i;
reg found;
reg [`PRODUCER_PACKET_WD-1:0] candidate;
always @(*) begin
    hit             = 1'b0;
    value_valid     = 1'b1;
    value           = regfile_value;
    producer_seq_id = 32'b0;
    found           = 1'b0;
    candidate       = {`PRODUCER_PACKET_WD{1'b0}};
    for (i = 0; i < PRODUCER_COUNT; i = i + 1) begin
        candidate = producers[i*`PRODUCER_PACKET_WD +: `PRODUCER_PACKET_WD];
        if (!found && src_valid && (src_reg != 5'b0) &&
            candidate[`PRODUCER_VALID_BIT] &&
            candidate[`PRODUCER_DST_VALID_BIT] &&
            (candidate[`PRODUCER_DST_HI:`PRODUCER_DST_LO] == src_reg)) begin
            found           = 1'b1;
            hit             = 1'b1;
            value_valid     = candidate[`PRODUCER_VALUE_VALID_BIT];
            value           = candidate[`PRODUCER_VALUE_HI:`PRODUCER_VALUE_LO];
            producer_seq_id = candidate[`PRODUCER_SEQ_HI:`PRODUCER_SEQ_LO];
        end
    end
end
endmodule
