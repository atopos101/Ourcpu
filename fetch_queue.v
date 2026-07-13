`include "mycpu.vh"

// Four-entry queue between the instruction-return stage and Decode.
// The queue owns backpressure toward F2, so an occupied Decode stage no
// longer directly blocks an instruction response that has already returned.
module fetch_queue #(
    parameter DEPTH = 4,
    parameter PTR_W = 2
)(
    input                              clk,
    input                              reset,
    input                              flush,
    input                              in_valid,
    output                             in_ready,
    input  [`FS_TO_DS_BUS_WD-1:0]      in_packet,
    output                             out_valid,
    input                              out_ready,
    output [`FS_TO_DS_BUS_WD-1:0]      out_packet,
    output [PTR_W:0]                   occupancy
);

reg [`FS_TO_DS_BUS_WD-1:0] entries [0:DEPTH-1];
reg [PTR_W-1:0] read_ptr;
reg [PTR_W-1:0] write_ptr;
reg [PTR_W:0]   count;

wire pop  = out_valid && out_ready;
wire push = in_valid && in_ready;

assign out_valid  = (count != 0) && !flush;
assign out_packet = entries[read_ptr];
// Permit replacement in the same cycle that a full queue removes its head.
assign in_ready   = !flush && ((count < DEPTH) || pop);
assign occupancy  = count;

always @(posedge clk) begin
    if (reset || flush) begin
        read_ptr  <= {PTR_W{1'b0}};
        write_ptr <= {PTR_W{1'b0}};
        count     <= {(PTR_W+1){1'b0}};
    end
    else begin
        if (push) begin
            entries[write_ptr] <= in_packet;
            write_ptr <= write_ptr + {{(PTR_W-1){1'b0}}, 1'b1};
        end

        if (pop)
            read_ptr <= read_ptr + {{(PTR_W-1){1'b0}}, 1'b1};

        case ({push, pop})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
        endcase
    end
end

`ifndef SYNTHESIS
always @(posedge clk) begin
    if (!reset && count > DEPTH)
        $error("fetch queue occupancy overflow");
end
`endif

endmodule
