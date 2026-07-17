`timescale 1ns/1ps
`default_nettype wire
module regfile(
    input  wire        clk,
    // READ PORT 1
    input  wire [ 4:0] raddr1,
    output wire [31:0] rdata1,
    // READ PORT 2
    input  wire [ 4:0] raddr2,
    output wire [31:0] rdata2,
    // WRITE PORT
    input  wire        we,       //write enable, HIGH valid
    input  wire [ 4:0] waddr,
    input  wire [31:0] wdata
);
reg [31:0] rf[31:0];

//WRITE
always @(posedge clk) begin
    if (we) rf[waddr] <= wdata;
end

//READ OUT 1
assign rdata1 = (raddr1==5'b0) ? 32'b0 :
                (we && (waddr == raddr1)) ? wdata : rf[raddr1];

//READ OUT 2
assign rdata2 = (raddr2==5'b0) ? 32'b0 :
                (we && (waddr == raddr2)) ? wdata : rf[raddr2];

endmodule

// Logical 4R2W wrapper used by the lane-shaped frontend/backend interfaces.
// The current core drives only lane0/wb0.  wb1 is nevertheless fully defined
// now so enabling a younger lane later does not change architectural conflict
// semantics: when both writes target the same GPR, wb1 wins.
module regfile_lane_wrapper(
    input         clk,
    input  [4:0]  lane0_raddr0,
    output [31:0] lane0_rdata0,
    input  [4:0]  lane0_raddr1,
    output [31:0] lane0_rdata1,
    input  [4:0]  lane1_raddr0,
    output [31:0] lane1_rdata0,
    input  [4:0]  lane1_raddr1,
    output [31:0] lane1_rdata1,
    input         wb0_valid,
    input  [4:0]  wb0_addr,
    input  [31:0] wb0_data,
    input         wb1_valid,
    input  [4:0]  wb1_addr,
    input  [31:0] wb1_data
);
reg [31:0] rf[31:0];

// Write-through keeps a decode snapshot coherent when register-file reads and
// retirement of the same register occur on one clock edge.  Port 1 has the
// same priority as the sequential writes below.
assign lane0_rdata0 = (lane0_raddr0 == 5'b0) ? 32'b0 :
                      (wb1_valid && (wb1_addr == lane0_raddr0)) ? wb1_data :
                      (wb0_valid && (wb0_addr == lane0_raddr0)) ? wb0_data :
                                                                  rf[lane0_raddr0];
assign lane0_rdata1 = (lane0_raddr1 == 5'b0) ? 32'b0 :
                      (wb1_valid && (wb1_addr == lane0_raddr1)) ? wb1_data :
                      (wb0_valid && (wb0_addr == lane0_raddr1)) ? wb0_data :
                                                                  rf[lane0_raddr1];
assign lane1_rdata0 = (lane1_raddr0 == 5'b0) ? 32'b0 :
                      (wb1_valid && (wb1_addr == lane1_raddr0)) ? wb1_data :
                      (wb0_valid && (wb0_addr == lane1_raddr0)) ? wb0_data :
                                                                  rf[lane1_raddr0];
assign lane1_rdata1 = (lane1_raddr1 == 5'b0) ? 32'b0 :
                      (wb1_valid && (wb1_addr == lane1_raddr1)) ? wb1_data :
                      (wb0_valid && (wb0_addr == lane1_raddr1)) ? wb0_data :
                                                                  rf[lane1_raddr1];

always @(posedge clk) begin
    if (wb0_valid && (wb0_addr != 5'b0))
        rf[wb0_addr] <= wb0_data;
    if (wb1_valid && (wb1_addr != 5'b0))
        rf[wb1_addr] <= wb1_data;
end
endmodule
