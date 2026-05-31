`include "mycpu.vh"

module mycpu_top(
    input         aclk,
    input         aresetn,

    output [ 3:0] arid,
    output [31:0] araddr,
    output [ 7:0] arlen,
    output [ 2:0] arsize,
    output [ 1:0] arburst,
    output [ 1:0] arlock,
    output [ 3:0] arcache,
    output [ 2:0] arprot,
    output        arvalid,
    input         arready,
    input  [ 3:0] rid,
    input  [31:0] rdata,
    input  [ 1:0] rresp,
    input         rlast,
    input         rvalid,
    output        rready,

    output [ 3:0] awid,
    output [31:0] awaddr,
    output [ 7:0] awlen,
    output [ 2:0] awsize,
    output [ 1:0] awburst,
    output [ 1:0] awlock,
    output [ 3:0] awcache,
    output [ 2:0] awprot,
    output        awvalid,
    input         awready,
    output [ 3:0] wid,
    output [31:0] wdata,
    output [ 3:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready,

    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

wire        inst_sram_req;
wire        inst_sram_wr;
wire [ 1:0] inst_sram_size;
wire [ 3:0] inst_sram_wstrb;
wire [31:0] inst_sram_addr;
wire [31:0] inst_sram_wdata;
wire        inst_sram_addr_ok;
wire        inst_sram_data_ok;
wire [31:0] inst_sram_rdata;

wire        data_sram_req;
wire        data_sram_wr;
wire [ 1:0] data_sram_size;
wire [ 3:0] data_sram_wstrb;
wire [31:0] data_sram_addr;
wire [31:0] data_sram_wdata;
wire        data_sram_addr_ok;
wire        data_sram_data_ok;
wire [31:0] data_sram_rdata;

mycpu_core u_core(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .hw_int_in          (8'b0                ),
    .inst_sram_req      (inst_sram_req       ),
    .inst_sram_wr       (inst_sram_wr        ),
    .inst_sram_size     (inst_sram_size      ),
    .inst_sram_wstrb    (inst_sram_wstrb     ),
    .inst_sram_addr     (inst_sram_addr      ),
    .inst_sram_wdata    (inst_sram_wdata     ),
    .inst_sram_addr_ok  (inst_sram_addr_ok   ),
    .inst_sram_data_ok  (inst_sram_data_ok   ),
    .inst_sram_rdata    (inst_sram_rdata     ),
    .data_sram_req      (data_sram_req       ),
    .data_sram_wr       (data_sram_wr        ),
    .data_sram_size     (data_sram_size      ),
    .data_sram_wstrb    (data_sram_wstrb     ),
    .data_sram_addr     (data_sram_addr      ),
    .data_sram_wdata    (data_sram_wdata     ),
    .data_sram_addr_ok  (data_sram_addr_ok   ),
    .data_sram_data_ok  (data_sram_data_ok   ),
    .data_sram_rdata    (data_sram_rdata     ),
    .debug_wb_pc        (debug_wb_pc         ),
    .debug_wb_rf_we     (debug_wb_rf_we      ),
    .debug_wb_rf_wnum   (debug_wb_rf_wnum    ),
    .debug_wb_rf_wdata  (debug_wb_rf_wdata   )
);

sram_axi_bridge_2x1 u_sram_axi_bridge(
    .clk                (aclk                ),
    .resetn             (aresetn             ),
    .inst_sram_req      (inst_sram_req       ),
    .inst_sram_wr       (inst_sram_wr        ),
    .inst_sram_size     (inst_sram_size      ),
    .inst_sram_wstrb    (inst_sram_wstrb     ),
    .inst_sram_addr     (inst_sram_addr      ),
    .inst_sram_wdata    (inst_sram_wdata     ),
    .inst_sram_addr_ok  (inst_sram_addr_ok   ),
    .inst_sram_data_ok  (inst_sram_data_ok   ),
    .inst_sram_rdata    (inst_sram_rdata     ),
    .data_sram_req      (data_sram_req       ),
    .data_sram_wr       (data_sram_wr        ),
    .data_sram_size     (data_sram_size      ),
    .data_sram_wstrb    (data_sram_wstrb     ),
    .data_sram_addr     (data_sram_addr      ),
    .data_sram_wdata    (data_sram_wdata     ),
    .data_sram_addr_ok  (data_sram_addr_ok   ),
    .data_sram_data_ok  (data_sram_data_ok   ),
    .data_sram_rdata    (data_sram_rdata     ),
    .arid               (arid                ),
    .araddr             (araddr              ),
    .arlen              (arlen               ),
    .arsize             (arsize              ),
    .arburst            (arburst             ),
    .arlock             (arlock              ),
    .arcache            (arcache             ),
    .arprot             (arprot              ),
    .arvalid            (arvalid             ),
    .arready            (arready             ),
    .rid                (rid                 ),
    .rdata              (rdata               ),
    .rresp              (rresp               ),
    .rlast              (rlast               ),
    .rvalid             (rvalid              ),
    .rready             (rready              ),
    .awid               (awid                ),
    .awaddr             (awaddr              ),
    .awlen              (awlen               ),
    .awsize             (awsize              ),
    .awburst            (awburst             ),
    .awlock             (awlock              ),
    .awcache            (awcache             ),
    .awprot             (awprot              ),
    .awvalid            (awvalid             ),
    .awready            (awready             ),
    .wid                (wid                 ),
    .wdata              (wdata               ),
    .wstrb              (wstrb               ),
    .wlast              (wlast               ),
    .wvalid             (wvalid              ),
    .wready             (wready              ),
    .bid                (bid                 ),
    .bresp              (bresp               ),
    .bvalid             (bvalid              ),
    .bready             (bready              )
);

endmodule

module sram_axi_bridge_2x1(
    input         clk,
    input         resetn,

    input         inst_sram_req,
    input         inst_sram_wr,
    input  [ 1:0] inst_sram_size,
    input  [ 3:0] inst_sram_wstrb,
    input  [31:0] inst_sram_addr,
    input  [31:0] inst_sram_wdata,
    output        inst_sram_addr_ok,
    output        inst_sram_data_ok,
    output [31:0] inst_sram_rdata,

    input         data_sram_req,
    input         data_sram_wr,
    input  [ 1:0] data_sram_size,
    input  [ 3:0] data_sram_wstrb,
    input  [31:0] data_sram_addr,
    input  [31:0] data_sram_wdata,
    output        data_sram_addr_ok,
    output        data_sram_data_ok,
    output [31:0] data_sram_rdata,

    output [ 3:0] arid,
    output [31:0] araddr,
    output [ 7:0] arlen,
    output [ 2:0] arsize,
    output [ 1:0] arburst,
    output [ 1:0] arlock,
    output [ 3:0] arcache,
    output [ 2:0] arprot,
    output        arvalid,
    input         arready,
    input  [ 3:0] rid,
    input  [31:0] rdata,
    input  [ 1:0] rresp,
    input         rlast,
    input         rvalid,
    output        rready,

    output [ 3:0] awid,
    output [31:0] awaddr,
    output [ 7:0] awlen,
    output [ 2:0] awsize,
    output [ 1:0] awburst,
    output [ 1:0] awlock,
    output [ 3:0] awcache,
    output [ 2:0] awprot,
    output        awvalid,
    input         awready,
    output [ 3:0] wid,
    output [31:0] wdata,
    output [ 3:0] wstrb,
    output        wlast,
    output        wvalid,
    input         wready,
    input  [ 3:0] bid,
    input  [ 1:0] bresp,
    input         bvalid,
    output        bready
);

localparam ST_IDLE    = 3'd0;
localparam ST_RD_ADDR = 3'd1;
localparam ST_RD_RESP = 3'd2;
localparam ST_WR_ADDR = 3'd3;
localparam ST_WR_RESP = 3'd4;

reg [2:0] state;
reg       rd_sel_data;
reg       aw_done;
reg       w_done;
reg [31:0] rd_addr_r;
reg [ 1:0] rd_size_r;
reg [31:0] wr_data_r;
reg [ 3:0] wr_strb_r;
reg [31:0] wr_addr_r;
reg [ 1:0] wr_size_r;

wire sel_data = data_sram_req;
wire sel_inst = !data_sram_req && inst_sram_req;
wire sel_wr   = sel_data && data_sram_wr;
wire sel_rd   = sel_inst || (sel_data && !data_sram_wr);

wire [1:0] req_size = sel_data ? data_sram_size : inst_sram_size;
wire [31:0] req_addr = sel_data ? data_sram_addr : inst_sram_addr;

wire rd_addr_hs = arvalid && arready;
wire rd_data_hs = rvalid && rready;
wire aw_hs      = awvalid && awready;
wire w_hs       = wvalid && wready;
wire wr_addr_hs = (aw_done || aw_hs) && (w_done || w_hs);
wire wr_resp_hs = bvalid && bready;

always @(posedge clk) begin
    if (!resetn) begin
        state       <= ST_IDLE;
        rd_sel_data <= 1'b0;
        aw_done     <= 1'b0;
        w_done      <= 1'b0;
        rd_addr_r   <= 32'b0;
        rd_size_r   <= 2'b0;
        wr_data_r   <= 32'b0;
        wr_strb_r   <= 4'b0;
        wr_addr_r   <= 32'b0;
        wr_size_r   <= 2'b0;
    end
    else begin
        case (state)
        ST_IDLE: begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            if (sel_rd) begin
                rd_addr_r   <= req_addr;
                rd_size_r   <= req_size;
                rd_sel_data <= sel_data;
                state       <= ST_RD_ADDR;
            end
            else if (sel_wr) begin
                wr_data_r <= data_sram_wdata;
                wr_strb_r <= data_sram_wstrb;
                wr_addr_r <= data_sram_addr;
                wr_size_r <= data_sram_size;
                state     <= ST_WR_ADDR;
            end
        end
        ST_RD_ADDR: begin
            if (rd_addr_hs) begin
                state <= ST_RD_RESP;
            end
        end
        ST_RD_RESP: begin
            if (rd_data_hs) begin
                state <= ST_IDLE;
            end
        end
        ST_WR_ADDR: begin
            aw_done <= aw_done || aw_hs;
            w_done  <= w_done  || w_hs;
            if (wr_addr_hs) begin
                state   <= ST_WR_RESP;
                aw_done <= 1'b0;
                w_done  <= 1'b0;
            end
        end
        ST_WR_RESP: begin
            if (wr_resp_hs) begin
                state <= ST_IDLE;
            end
        end
        default: begin
            state <= ST_IDLE;
        end
        endcase
    end
end

assign arid     = rd_sel_data ? 4'd1 : 4'd0;
assign araddr   = rd_addr_r;
assign arlen    = 8'd0;
assign arsize   = {1'b0, rd_size_r};
assign arburst  = 2'b01;
assign arlock   = 2'b00;
assign arcache  = 4'b0000;
assign arprot   = 3'b000;
assign arvalid  = (state == ST_RD_ADDR);
assign rready   = (state == ST_RD_RESP);

assign awid     = 4'd1;
assign awaddr   = wr_addr_r;
assign awlen    = 8'd0;
assign awsize   = {1'b0, wr_size_r};
assign awburst  = 2'b01;
assign awlock   = 2'b00;
assign awcache  = 4'b0000;
assign awprot   = 3'b000;
assign awvalid  = (state == ST_WR_ADDR) && !aw_done;

assign wid      = 4'd1;
assign wdata    = wr_data_r;
assign wstrb    = wr_strb_r;
assign wlast    = 1'b1;
assign wvalid   = (state == ST_WR_ADDR) && !w_done;
assign bready   = (state == ST_WR_RESP);

assign inst_sram_addr_ok = (state == ST_IDLE) && sel_inst;
assign data_sram_addr_ok = (state == ST_IDLE) && sel_data;
assign inst_sram_data_ok = (state == ST_RD_RESP) && !rd_sel_data && rd_data_hs;
assign data_sram_data_ok = ((state == ST_RD_RESP) &&  rd_sel_data && rd_data_hs)
                         || ((state == ST_WR_RESP) && wr_resp_hs);
assign inst_sram_rdata = rdata;
assign data_sram_rdata = rdata;

endmodule

module mycpu_core(
    input         clk,
    input         resetn,
    // 8 external hardware interrupt lines (tie to 0 if unused)
    input  [7:0]  hw_int_in,
    // inst sram interface (bus-style)
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input  [31:0] inst_sram_rdata,
    // data sram interface (bus-style)
    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [ 3:0] data_sram_wstrb,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input         data_sram_addr_ok,
    input         data_sram_data_ok,
    input  [31:0] data_sram_rdata,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);

reg         reset;
always @(posedge clk) begin
    if (!resetn) begin
        reset <= 1'b1;
    end
    else begin
        reset <= 1'b0;
    end
end

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
wire       ms_to_ds_load_op;
wire [4:0] ms_to_ds_load_dest;
wire [31:0] es_to_ds_result;
wire [31:0] ms_to_ds_result;
wire [31:0] ws_to_ds_result;
wire [31:0] inst_vaddr;
wire [31:0] inst_paddr;
wire        inst_trans_ex;
wire [ 5:0] inst_trans_ecode;
wire [ 8:0] inst_trans_esubcode;

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
    // address translation
    .inst_vaddr     (inst_vaddr     ),
    .inst_paddr     (inst_paddr     ),
    .inst_trans_ex  (inst_trans_ex  ),
    .inst_trans_ecode(inst_trans_ecode),
    .inst_trans_esubcode(inst_trans_esubcode),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_req    (inst_sram_req   ),
    .inst_sram_wr     (inst_sram_wr    ),
    .inst_sram_size   (inst_sram_size  ),
    .inst_sram_wstrb  (inst_sram_wstrb ),
    .inst_sram_addr   (inst_sram_addr  ),
    .inst_sram_wdata  (inst_sram_wdata ),
    .inst_sram_addr_ok(inst_sram_addr_ok),
    .inst_sram_data_ok(inst_sram_data_ok),
    .inst_sram_rdata  (inst_sram_rdata )
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
    .ms_to_ds_load_op(ms_to_ds_load_op),
    .ms_to_ds_load_dest(ms_to_ds_load_dest),
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
    .data_sram_req    (data_sram_req   ),
    .data_sram_wr     (data_sram_wr    ),
    .data_sram_size   (data_sram_size  ),
    .data_sram_wstrb  (data_sram_wstrb ),
    .data_sram_addr   (data_sram_addr  ),
    .data_sram_wdata  (data_sram_wdata ),
    .data_sram_addr_ok(data_sram_addr_ok),
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata  (data_sram_rdata ),
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
    // instruction address translation
    .inst_vaddr     (inst_vaddr     ),
    .inst_paddr     (inst_paddr     ),
    .inst_trans_ex  (inst_trans_ex  ),
    .inst_trans_ecode(inst_trans_ecode),
    .inst_trans_esubcode(inst_trans_esubcode),
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
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata(data_sram_rdata),
    // hazard detect info
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ms_to_ds_load_op(ms_to_ds_load_op),
    .ms_to_ds_load_dest(ms_to_ds_load_dest),
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
