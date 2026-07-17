`timescale 1ns/1ps
`default_nettype none
`include "mycpu.vh"

module wb_stage(
    input  wire                     clk           ,
    input  wire                     reset         ,
    // valid/ready pipeline handshake; WB always retires in one cycle
    output wire                     ms_to_ws_ready,
    output wire                     ws_empty      ,
    //from ms
    input  wire                     ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD -1:0]  ms_to_ws_bus  ,
    //to rf: for write back
    output wire [`WS_TO_RF_BUS_WD -1:0]  ws_to_rf_bus  ,
    //trace debug interface
    output wire [31:0] debug_wb_pc     ,
    output wire [ 3:0] debug_wb_rf_we  ,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire [`PRODUCER_PACKET_WD-1:0] wb_producer_packet
);

reg         ws_valid;

reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
wire        ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
wire [31:0] ws_seq_id;
wire        ws_lane_id;
assign {ws_seq_id,
        ws_lane_id,
        ws_gr_we       ,  //69:69
        ws_dest        ,  //68:64
        ws_final_result,  //63:32
        ws_pc             //31:0
       } = ms_to_ws_bus_r;

wire        rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
reg  [31:0] debug_wb_pc_r;
wire        ws_pc_known;
wire        ws_debug_valid;
assign ws_to_rf_bus = {rf_we   ,  //37:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

wire ws_out_fire = ws_valid;
wire ws_in_fire  = ms_to_ws_valid && ms_to_ws_ready;
assign ms_to_ws_ready = 1'b1;
assign ws_empty    = !ws_valid;
always @(posedge clk) begin
    if (reset) begin
        ws_valid <= 1'b0;
    end
    else if (ms_to_ws_ready) begin
        ws_valid <= ms_to_ws_valid;
    end

    if (ws_in_fire) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end

assign rf_we    = ws_gr_we && ws_out_fire;
assign rf_waddr = ws_dest;
assign rf_wdata = ws_final_result;

// debug info generate
assign ws_pc_known    = (ws_pc === ws_pc);
assign ws_debug_valid = (ws_valid === 1'b1) && ws_pc_known;

always @(posedge clk) begin
    if (reset) begin
        debug_wb_pc_r <= 32'b0;
    end
    else if (ws_debug_valid) begin
        debug_wb_pc_r <= ws_pc;
    end
end

assign debug_wb_pc       = ws_debug_valid ? ws_pc : debug_wb_pc_r;
assign debug_wb_rf_we    = ws_debug_valid ? {4{rf_we}}      : 4'b0;
assign debug_wb_rf_wnum  = ws_debug_valid ? ws_dest         : 5'b0;
assign debug_wb_rf_wdata = ws_debug_valid ? ws_final_result : 32'b0;

producer_packet_pack u_wb_producer_packet(
    .valid(ws_valid), .seq_id(ws_seq_id), .dst_valid(ws_gr_we), .dst(ws_dest),
    .value_valid(ws_valid && ws_gr_we), .value(ws_final_result),
    .packet(wb_producer_packet)
);

wire unused_ws_out_fire = ws_out_fire;

`ifndef SYNTHESIS
always @(posedge clk) begin
    if (!reset && rf_we && !ws_out_fire)
        $error("GPR write fired without WB commit_fire");
end
`endif

endmodule
