`include "mycpu.vh"

// Lane-0 issue boundary.  Decode currently performs the single-lane hazard
// decision; this elastic register makes that decision independent of EX1
// backpressure and provides the structural point where lane pairing is added.
module issue_stage(
    input                               clk,
    input                               reset,
    input                               kill,
    input                               decode_valid,
    output                              decode_ready,
    input  [`ID_TO_EX1_BUS_WD-1:0]      decode_packet,
    output                              lane0_valid,
    input                               lane0_ready,
    output [`ID_TO_EX1_BUS_WD-1:0]      lane0_packet,
    output [4:0]                        pending_dst,
    output                              pending_csr_we,
    output [13:0]                       pending_csr_num,
    output                              pending_ertn,
    output                              pending_tlb
);

reg                                issue_valid;
reg [`ID_TO_EX1_BUS_WD-1:0]        issue_packet;

wire [1:0] packet_csr_op = issue_packet[17:16];

assign decode_ready = !issue_valid || lane0_ready;
assign lane0_valid  = issue_valid;
assign lane0_packet = issue_packet;

// These fields describe the instruction while it is between Decode and EX1.
// Decode treats its destination as not-ready, preventing a younger consumer
// from overlooking this newly introduced pipeline boundary.
assign pending_dst     = (issue_valid && issue_packet[153]) ? issue_packet[151:147] : 5'b0;
assign pending_csr_we  = issue_valid && ((packet_csr_op == 2'b10) ||
                                         (packet_csr_op == 2'b11));
assign pending_csr_num = issue_packet[15:2];
assign pending_ertn    = issue_valid && issue_packet[0];
assign pending_tlb     = issue_valid && (issue_packet[193:191] != 3'b0);

always @(posedge clk) begin
    if (reset || kill) begin
        issue_valid <= 1'b0;
    end
    else if (decode_ready) begin
        issue_valid <= decode_valid;
        if (decode_valid)
            issue_packet <= decode_packet;
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
        if (stalled_last && (!issue_valid || issue_packet !== packet_last))
            $error("issue packet changed while stalled");
        stalled_last <= issue_valid && !lane0_ready;
        packet_last  <= issue_packet;
    end
end
`endif

endmodule
