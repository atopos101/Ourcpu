
`timescale 1ns/1ps
`default_nettype wire
`include "mycpu.vh"

module mem_stage(
    input                          clk,
    input                          reset,

    // valid/ready pipeline handshake
    input                          ms_to_ws_ready,
    output                         ex3_to_mem_ready,
    output                         ms_empty,

    // from Commit/EX3
    input                          ex3_to_mem_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] ex3_to_mem_bus,

    // to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus,

    // from data sram
    input                          data_sram_data_ok,
    input  [31:0]                  data_sram_rdata,

    // LL/SC retirement events
    output                         ll_commit_valid,
    output                         sc_commit_valid,
    output                         local_store_commit_valid,
    output [27:0]                  mem_commit_line,

    output [`PRODUCER_PACKET_WD-1:0] mem_producer_packet
);

reg         ms_valid;
wire        ms_operation_ready;

reg [`ES_TO_MS_BUS_WD -1:0] ex3_to_mem_bus_r;

//==========================================================
// bus decode
//==========================================================

wire        ms_res_from_mem;
wire        ms_mem_access;
wire        ms_inst_ll_w;
wire        ms_inst_sc_w;
wire        ms_sc_success;
wire        ms_access_cached;
wire [27:0] ms_mem_line;
wire [1:0]  ms_mem_size;
wire        ms_mem_unsigned;
wire        ms_gr_we;
wire [4:0]  ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
wire [31:0] ms_seq_id;
wire        ms_lane_id;

assign {
        ms_seq_id,
        ms_lane_id,
        ms_inst_ll_w,
        ms_inst_sc_w,
        ms_sc_success,
        ms_access_cached,
        ms_mem_line,
        ms_mem_access,   //74
        ms_res_from_mem, //73
        ms_mem_size,     //72:71
        ms_mem_unsigned, //70
        ms_gr_we,        //69
        ms_dest,         //68:64
        ms_alu_result,   //63:32
        ms_pc            //31:0
       } = ex3_to_mem_bus_r;

//==========================================================
// operation completion
//==========================================================

// load/store:
//     wait data_ok
//
// others:
//     pass directly

assign ms_operation_ready =
       !ms_mem_access
    || data_sram_data_ok;

//==========================================================
// upstream readiness
//==========================================================

assign ex3_to_mem_ready =
       !ms_valid
    || (ms_operation_ready && ms_to_ws_ready);

assign ms_empty = !ms_valid;

//==========================================================
// pipeline valid
//==========================================================

assign ms_to_ws_valid =
       ms_valid
    && ms_operation_ready;

always @(posedge clk) begin
    if(reset) begin
        ms_valid <= 1'b0;
    end
    else if(ex3_to_mem_ready) begin
        ms_valid <= ex3_to_mem_valid;
    end

    if(ex3_to_mem_valid && ex3_to_mem_ready) begin
        ex3_to_mem_bus_r <= ex3_to_mem_bus;
    end
end

//==========================================================
// load extract
//==========================================================

wire [7:0]  load_byte;
wire [15:0] load_half;

assign load_byte =
       (ms_alu_result[1:0] == 2'b00) ? data_sram_rdata[7:0]   :
       (ms_alu_result[1:0] == 2'b01) ? data_sram_rdata[15:8]  :
       (ms_alu_result[1:0] == 2'b10) ? data_sram_rdata[23:16] :
                                       data_sram_rdata[31:24];

assign load_half =
       ms_alu_result[1]
    ? data_sram_rdata[31:16]
    : data_sram_rdata[15:0];

//==========================================================
// mem result
//==========================================================

wire [31:0] mem_result;

assign mem_result =
       (ms_mem_size == 2'b00)
    ? {{24{~ms_mem_unsigned & load_byte[7]}}, load_byte}

    : (ms_mem_size == 2'b01)
    ? {{16{~ms_mem_unsigned & load_half[15]}}, load_half}

    : data_sram_rdata;

//==========================================================
// final result
//==========================================================

wire [31:0] ms_final_result;

assign ms_final_result =
       ms_inst_sc_w
    ? {31'b0, ms_sc_success}
    :  ms_res_from_mem
    ? mem_result
    : ms_alu_result;

wire ms_out_fire = ms_to_ws_valid && ms_to_ws_ready;
wire ms_in_fire  = ex3_to_mem_valid && ex3_to_mem_ready;
wire ms_commit = ms_out_fire;

assign ll_commit_valid = ms_commit && ms_inst_ll_w;
assign sc_commit_valid = ms_commit && ms_inst_sc_w;
assign local_store_commit_valid = ms_commit && ms_mem_access &&
                                  !ms_res_from_mem && !ms_inst_sc_w;
assign mem_commit_line = ms_mem_line;

//==========================================================
// to ws
//==========================================================

assign ms_to_ws_bus = {
        ms_seq_id,
        ms_lane_id,
        ms_gr_we,
        ms_dest,
        ms_final_result,
        ms_pc
};

//==========================================================
// forward
//==========================================================

// 注意：
// forwarding有效条件必须是
// ms_to_ws_valid
//
// 不能仅 ms_valid

// seq_id is carried in the lane sideband in the current single-lane MEM
// payload and is widened below when the canonical retirement packet is built.
// Until then producer order, not the numeric ID, selects this value.
producer_packet_pack u_mem_producer_packet(
    .valid(ms_valid), .seq_id(ms_seq_id), .dst_valid(ms_gr_we), .dst(ms_dest),
    .value_valid(ms_to_ws_valid && ms_gr_we), .value(ms_final_result),
    .packet(mem_producer_packet)
);

`ifndef SYNTHESIS
reg                        ms_stalled_last;
reg [`ES_TO_MS_BUS_WD-1:0] ms_payload_last;
always @(posedge clk) begin
    if (reset) begin
        ms_stalled_last <= 1'b0;
    end
    else begin
        if (ms_stalled_last && (!ms_to_ws_valid ||
                                ex3_to_mem_bus_r !== ms_payload_last))
            $error("MEM payload changed while stalled");
        ms_stalled_last <= ms_to_ws_valid && !ms_to_ws_ready;
        ms_payload_last <= ex3_to_mem_bus_r;
        if ((ll_commit_valid || sc_commit_valid || local_store_commit_valid) &&
            !ms_commit)
            $error("LL/SC/store reservation side effect fired without MEM commit");
    end
end
wire unused_ms_in_fire = ms_in_fire;
`endif

endmodule

