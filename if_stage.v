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
    // IBAR completion redirect
    input                          ibar_flush     ,
    input  [31:0]                  ibar_target    ,
    // IDLE wait state
    input                          idle_wait      ,
    // address translation
    output [31:0]                  inst_vaddr     ,
    input  [31:0]                  inst_paddr     ,
    input                          inst_trans_ex  ,
    input  [ 5:0]                  inst_trans_ecode,
    input  [ 8:0]                  inst_trans_esubcode,
    //to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output        inst_sram_req    ,
    output        inst_sram_wr     ,
    output [ 1:0] inst_sram_size   ,
    output [ 3:0] inst_sram_wstrb  ,
    output [31:0] inst_sram_addr   ,
    output [31:0] inst_sram_wdata  ,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [31:0] inst_sram_rdata
);

reg         fs_valid;
reg         fs_req;
wire        to_fs_valid;

wire [31:0] seq_pc;

wire         br_taken;
wire [ 31:0] br_target;

wire br_stall;

assign {br_stall, br_taken, br_target} = br_bus;

reg  [31:0] fs_inst;
reg  [31:0] fs_pc;

reg  [31:0] fetch_pc;
reg  [31:0] req_pc;
reg         req_cancel;
reg         resp_pending;
reg  [31:0] resp_pc;
reg         resp_cancel;
reg         adef_pending;
reg         resp_ex;
reg  [ 5:0] resp_ecode;
reg  [ 8:0] resp_esubcode;
reg         fs_ex;
reg  [ 5:0] fs_ecode;
reg  [ 8:0] fs_esubcode;

wire        redirect;
wire [31:0] redirect_pc;
wire        inst_addr_hs;
wire        inst_data_hs;
wire        fs_handoff;
wire        fetch_ex;
wire [ 5:0] fetch_ecode;
wire [ 8:0] fetch_esubcode;

// ============================================================
// Fetch exception detection
// ============================================================
wire fetch_adef;
assign fetch_adef = fs_req && (req_pc[1:0] != 2'b00);
assign fetch_ex   = fetch_adef || (fs_req && inst_trans_ex);
assign fetch_ecode = fetch_adef ? `ECODE_ADEF : inst_trans_ecode;
assign fetch_esubcode = fetch_adef ? 9'h000 : inst_trans_esubcode;

// fs_to_ds_bus: {inst[31:0], pc[31:0], fs_ex, fs_ecode, fs_esubcode}
assign fs_to_ds_bus = {fs_inst,
                       fs_pc,
                       fs_ex,
                       fs_ecode,
                       fs_esubcode
                      };

// pre-IF stage
assign to_fs_valid  = ~reset;
assign redirect     = ertn_flush || flush || ibar_flush || br_taken;
assign redirect_pc  = ertn_flush ? ertn_pc  :
                      flush      ? ex_entry :
                      ibar_flush ? ibar_target :
                      br_target;

// IF stage
assign seq_pc         = fs_pc + 3'h4;
assign fs_to_ds_valid =  fs_valid;
assign fs_handoff     =  fs_to_ds_valid && ds_allowin;
assign inst_vaddr      = fs_req ? req_pc : fetch_pc;

assign inst_addr_hs   = fetch_ex || (inst_sram_req && inst_sram_addr_ok);
assign inst_data_hs   = resp_pending && inst_sram_data_ok;

assign inst_sram_req    = fs_req && !fetch_ex && !idle_wait;
assign inst_sram_wr     = 1'b0;
assign inst_sram_size   = 2'b10;
assign inst_sram_wstrb  = 4'b0000;
assign inst_sram_addr   = inst_paddr;
assign inst_sram_wdata  = 32'b0;

always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else begin
        if (fs_handoff || redirect) begin
            fs_valid <= 1'b0;
        end
        if ((inst_data_hs || adef_pending) && !resp_cancel && !redirect) begin
            fs_valid <= 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        fetch_pc <= 32'h1c000000;
        fs_pc    <= 32'h1c000000;
        fs_ex    <= 1'b0;
        fs_ecode <= 6'b0;
        fs_esubcode <= 9'b0;
    end
    else begin
        if (redirect) begin
            fetch_pc <= redirect_pc;
        end
        else if (fs_handoff) begin
            fetch_pc <= seq_pc;
        end

        if ((inst_data_hs || adef_pending) && !resp_cancel && !redirect) begin
            fs_pc <= resp_pc;
            fs_ex <= resp_ex;
            fs_ecode <= resp_ecode;
            fs_esubcode <= resp_esubcode;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        fs_req      <= 1'b0;
        req_pc      <= 32'b0;
        req_cancel  <= 1'b0;
        resp_pending <= 1'b0;
        resp_pc      <= 32'b0;
        resp_cancel  <= 1'b0;
        adef_pending <= 1'b0;
        resp_ex      <= 1'b0;
        resp_ecode   <= 6'b0;
        resp_esubcode <= 9'b0;
    end
    else begin
        if (inst_addr_hs) begin
            fs_req <= 1'b0;
            req_cancel <= 1'b0;
            resp_pending <= !fetch_ex;
            resp_pc <= req_pc;
            resp_cancel <= redirect || req_cancel;
            adef_pending <= fetch_ex;
            resp_ex <= fetch_ex;
            resp_ecode <= fetch_ecode;
            resp_esubcode <= fetch_esubcode;
        end

        if (inst_data_hs) begin
            resp_pending <= 1'b0;
            resp_cancel  <= 1'b0;
        end

        if (adef_pending) begin
            adef_pending <= 1'b0;
            resp_cancel  <= 1'b0;
        end

        if (redirect) begin
            resp_cancel <= resp_pending || (inst_addr_hs && !inst_sram_data_ok) || req_cancel;
            adef_pending <= 1'b0;
            if (fs_req && !inst_sram_addr_ok) begin
                fs_req <= 1'b1;
                req_cancel <= 1'b1;
            end
            else if (!fs_req && !resp_pending) begin
                fs_req <= 1'b1;
                req_pc <= redirect_pc;
                req_cancel <= 1'b0;
                resp_cancel <= 1'b0;
            end
        end
        else if (to_fs_valid && !idle_wait &&
                 !fs_req && !resp_pending && !fs_valid) begin
            fs_req <= 1'b1;
            req_pc <= fetch_pc;
            req_cancel <= 1'b0;
            resp_cancel <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (adef_pending && !resp_cancel && !redirect) begin
        fs_inst <= 32'b0;
    end
    if (inst_data_hs && !resp_cancel && !redirect) begin
        fs_inst <= inst_sram_rdata;
    end
end

endmodule
