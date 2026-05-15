`include "mycpu.vh"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    //allowin
    input                          ds_allowin     ,
    //brbus
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    // exception interface
    input                          flush          ,
    input  [31:0]                  ex_entry       ,
    // ertn interface
    input                          ertn_flush     ,
    input  [31:0]                  ertn_pc        ,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output        inst_sram_en   ,
    output [ 3:0] inst_sram_we  ,
    output [31:0] inst_sram_addr ,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;

wire         br_taken;
wire [ 31:0] br_target;

wire br_stall;
wire pre_if_ready_go;

assign {br_stall, br_taken, br_target} = br_bus;

wire [31:0] fs_inst;
reg  [31:0] fs_pc;

// ============================================================
// ADEF detection: fetch address not 4-byte aligned
// ============================================================
wire fs_adef;
assign fs_adef = fs_valid && (fs_pc[1:0] != 2'b00);

// fs_to_ds_bus: {inst[31:0], pc[31:0], fs_ex}
assign fs_to_ds_bus = {fs_inst,
                       fs_pc,
                       fs_adef   // ADEF flag
                      };

// pre-IF stage
assign to_fs_valid  = ~reset;
assign pre_if_ready_go = ~br_stall && !flush && !ertn_flush;

assign seq_pc       = fs_pc + 3'h4;
assign nextpc       = ertn_flush ? ertn_pc  :
                      flush      ? ex_entry :
                      br_taken   ? br_target : seq_pc;

// IF stage
assign fs_ready_go    = ~br_taken && !flush && !ertn_flush;
assign fs_allowin     = !fs_valid || fs_ready_go && ds_allowin;
assign fs_to_ds_valid =  fs_valid && fs_ready_go;

always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        fs_pc <= 32'h1bfffffc;     //trick: to make nextpc be 0x1c000000 during reset
    end
    else if (to_fs_valid && (fs_allowin || br_taken || flush || ertn_flush)) begin
        fs_pc <= nextpc;
    end
end

assign inst_sram_en    = to_fs_valid && (fs_allowin || br_taken || flush || ertn_flush);
assign inst_sram_we   = 4'h0;
assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;

assign fs_inst         = inst_sram_rdata;

endmodule
