`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

// Four-entry queue between the instruction-return stage and Decode.
// The queue owns backpressure toward F2, so an occupied Decode stage no
// longer directly blocks an instruction response that has already returned.
module fetch_queue #(
    parameter DEPTH = 4,
    parameter PTR_W = 2,
    parameter PACKET_WD = `FS_TO_DS_BUS_WD
)(
    input                              clk,
    input                              reset,
    input                              flush,
    input                              in_valid,
    output                             in_ready,
    input  [PACKET_WD-1:0]             in_packet,
    output                             out_valid,
    input                              out_ready,
    output [PACKET_WD-1:0]             out_packet,
    output [PTR_W:0]                   occupancy
);

reg [PACKET_WD-1:0] entries [0:DEPTH-1];
reg [PTR_W-1:0] read_ptr;
reg [PTR_W-1:0] write_ptr;
reg [PTR_W:0]   count;

wire out_fire = out_valid && out_ready;
wire in_fire  = in_valid && in_ready;

assign out_valid  = (count != 0) && !flush;
assign out_packet = entries[read_ptr];
// Permit replacement in the same cycle that a full queue removes its head.
assign in_ready   = !flush && ((count < DEPTH) || out_fire);
assign occupancy  = count;

always @(posedge clk) begin
    if (reset || flush) begin
        read_ptr  <= {PTR_W{1'b0}};
        write_ptr <= {PTR_W{1'b0}};
        count     <= {(PTR_W+1){1'b0}};
    end
    else begin
        if (in_fire) begin
            entries[write_ptr] <= in_packet;
            write_ptr <= write_ptr + {{(PTR_W-1){1'b0}}, 1'b1};
        end

        if (out_fire)
            read_ptr <= read_ptr + {{(PTR_W-1){1'b0}}, 1'b1};

        case ({in_fire, out_fire})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
        endcase
    end
end

`ifndef SYNTHESIS
reg                              stalled_last;
reg [PACKET_WD-1:0]              payload_last;
always @(posedge clk) begin
    if (!reset && count > DEPTH)
        $error("fetch queue occupancy overflow");

    if (reset || flush) begin
        stalled_last <= 1'b0;
    end
    else begin
        if (stalled_last && (!out_valid || out_packet !== payload_last))
            $error("fetch queue payload changed while stalled");
        stalled_last <= out_valid && !out_ready;
        payload_last <= out_packet;
    end
end
`endif

endmodule

// Lane-shaped wrapper around the storage FIFO.  It is intentionally neutral
// about pairing policy; IF2 currently supplies slot0 only, while a later
// 64-bit fetch implementation can populate slot1 without changing the FIFO.
module fetch_packet_queue #(
    parameter DEPTH = 4,
    parameter PTR_W = 2
)(
    input clk,
    input reset,
    input flush,
    input in_valid,
    output in_ready,
    input slot0_in_valid,
    input [`FS_TO_DS_BUS_WD-1:0] slot0_in_packet,
    input slot1_in_valid,
    input [`FS_TO_DS_BUS_WD-1:0] slot1_in_packet,
    output out_valid,
    input out_ready,
    output slot0_out_valid,
    output [`FS_TO_DS_BUS_WD-1:0] slot0_out_packet,
    output slot1_out_valid,
    output [`FS_TO_DS_BUS_WD-1:0] slot1_out_packet,
    output [PTR_W:0] occupancy
);
wire [`FETCH_PACKET_WD-1:0] in_fetch_packet =
    {slot1_in_packet, slot0_in_packet, slot1_in_valid, slot0_in_valid};
wire [`FETCH_PACKET_WD-1:0] out_fetch_packet;

assign slot0_out_valid  = out_valid && out_fetch_packet[0];
assign slot1_out_valid  = out_valid && out_fetch_packet[1];
assign slot0_out_packet = out_fetch_packet[2 +: `FS_TO_DS_BUS_WD];
assign slot1_out_packet = out_fetch_packet[2+`FS_TO_DS_BUS_WD +: `FS_TO_DS_BUS_WD];

fetch_queue #(.DEPTH(DEPTH), .PTR_W(PTR_W), .PACKET_WD(`FETCH_PACKET_WD))
u_fetch_packet_storage(
    .clk(clk), .reset(reset), .flush(flush),
    .in_valid(in_valid), .in_ready(in_ready), .in_packet(in_fetch_packet),
    .out_valid(out_valid), .out_ready(out_ready),
    .out_packet(out_fetch_packet), .occupancy(occupancy)
);
endmodule
