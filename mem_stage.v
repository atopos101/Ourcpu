
`include "mycpu.vh"

module mem_stage(
    input                          clk,
    input                          reset,

    // allowin
    input                          ws_allowin,
    output                         ms_allowin,

    // from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus,

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

    // forward
    output [4:0]                   ms_to_ds_dest,
    output                         ms_to_ds_load_op,
    output [4:0]                   ms_to_ds_load_dest,
    output [31:0]                  ms_to_ds_result
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;

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

assign {
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
       } = es_to_ms_bus_r;

//==========================================================
// ready_go
//==========================================================

// load/store:
//     wait data_ok
//
// others:
//     pass directly

assign ms_ready_go =
       !ms_mem_access
    || data_sram_data_ok;

//==========================================================
// allowin
//==========================================================

assign ms_allowin =
       !ms_valid
    || (ms_ready_go && ws_allowin);

//==========================================================
// pipeline valid
//==========================================================

assign ms_to_ws_valid =
       ms_valid
    && ms_ready_go;

always @(posedge clk) begin
    if(reset) begin
        ms_valid <= 1'b0;
    end
    else if(ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if(es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r <= es_to_ms_bus;
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

wire ms_commit = ms_valid && ms_ready_go && ws_allowin;

assign ll_commit_valid = ms_commit && ms_inst_ll_w && ms_access_cached;
assign sc_commit_valid = ms_commit && ms_inst_sc_w;
assign local_store_commit_valid = ms_commit && ms_mem_access &&
                                  !ms_res_from_mem && !ms_inst_sc_w;
assign mem_commit_line = ms_mem_line;

//==========================================================
// to ws
//==========================================================

assign ms_to_ws_bus = {
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

assign ms_to_ds_dest =
       ms_dest
    & {5{ms_to_ws_valid}}
    & {5{ms_gr_we}};

assign ms_to_ds_load_op = ms_valid && (ms_res_from_mem || ms_inst_sc_w) && !ms_ready_go;
assign ms_to_ds_load_dest = ms_dest;

assign ms_to_ds_result = ms_final_result;

endmodule

