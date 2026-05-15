`include "mycpu.vh"

module mycpu_top(
    input         clk,
    input         resetn,
    // 8 external hardware interrupt lines (tie to 0 if unused)
    input  [7:0]  hw_int_in,
    // inst sram interface
    output        inst_sram_en,
    output [ 3:0] inst_sram_we,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    // data sram interface
    output        data_sram_en,
    output [ 3:0] data_sram_we,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input  [31:0] data_sram_rdata,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

reg         reset;
always @(posedge clk) reset <= ~resetn;

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;
wire [4:0] es_to_ds_dest;
wire [4:0] ms_to_ds_dest;
wire [4:0] ws_to_ds_dest;
wire       es_to_ds_load_op;
wire [31:0] es_to_ds_result;
wire [31:0] ms_to_ds_result;
wire [31:0] ws_to_ds_result;

// exception interface
wire        flush;
wire [31:0] ex_entry;

// ertn interface
wire        ertn_flush;
wire [31:0] ertn_pc;

// csr hazard tracking
wire        es_csr_we;
wire [13:0] es_csr_num;
wire        es_is_ertn;

wire [7:0] hw_int_in_safe;
assign hw_int_in_safe = {
    (hw_int_in[7] === 1'b1),
    (hw_int_in[6] === 1'b1),
    (hw_int_in[5] === 1'b1),
    (hw_int_in[4] === 1'b1),
    (hw_int_in[3] === 1'b1),
    (hw_int_in[2] === 1'b1),
    (hw_int_in[1] === 1'b1),
    (hw_int_in[0] === 1'b1)
};

// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    // exception
    .flush          (flush          ),
    .ex_entry       (ex_entry       ),
    // ertn
    .ertn_flush     (ertn_flush     ),
    .ertn_pc        (ertn_pc        ),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_en   (inst_sram_en   ),
    .inst_sram_we   (inst_sram_we  ),
    .inst_sram_addr (inst_sram_addr ),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata)
);

// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .flush          (flush          ),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //hazard detect info
    .es_to_ds_dest  (es_to_ds_dest  ),
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ws_to_ds_dest  (ws_to_ds_dest  ),
    .es_to_ds_load_op(es_to_ds_load_op),
    .es_to_ds_result(es_to_ds_result),
    .ms_to_ds_result(ms_to_ds_result),
    .ws_to_ds_result(ws_to_ds_result),
    // csr hazard tracking
    .es_csr_we      (es_csr_we      ),
    .es_csr_num     (es_csr_num     ),
    .es_is_ertn     (es_is_ertn     ),
    .ertn_flush     (ertn_flush     )
);

// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    // data sram interface
    .data_sram_en   (data_sram_en   ),
    .data_sram_we   (data_sram_we  ),
    .data_sram_addr (data_sram_addr ),
    .data_sram_wdata(data_sram_wdata),
    // hazard detect info
    .es_to_ds_dest  (es_to_ds_dest  ),
    .es_to_ds_load_op(es_to_ds_load_op),
    .es_to_ds_result(es_to_ds_result),
    // exception interface
    .flush          (flush          ),
    .ex_entry       (ex_entry       ),
    // ertn interface
    .ertn_flush     (ertn_flush     ),
    .ertn_pc        (ertn_pc        ),
    // csr hazard tracking
    .es_csr_we      (es_csr_we      ),
    .es_csr_num     (es_csr_num     ),
    .es_is_ertn     (es_is_ertn     ),
    // interrupt / csr interface
    .hw_int_in      (hw_int_in_safe )
);

// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //from data-sram
    .data_sram_rdata(data_sram_rdata),
    // hazard detect info
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ms_to_ds_result(ms_to_ds_result)
);

// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    // hazard detect info
    .ws_to_ds_dest  (ws_to_ds_dest  ),
    .ws_to_ds_result(ws_to_ds_result),
    // trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

endmodule
